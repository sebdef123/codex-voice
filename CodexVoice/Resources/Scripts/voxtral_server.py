#!/usr/bin/env python3
"""Lazy local HTTP bridge for mlx-audio Voxtral TTS.

``/speak`` remains the complete-WAV baseline. ``/speak/stream`` emits chunked binary
float32 PCM frames so the macOS client can begin playback before final generation.
"""
import argparse
import io
import json
import resource
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import numpy as np
import soundfile as sf
import mlx.core as mx
from mlx_audio.utils import load_model
from voxtral_text import split_stream_text

MODEL_ID = "mlx-community/Voxtral-4B-TTS-2603-mlx-4bit"
SAMPLE_RATE = 24_000
STREAMING_INTERVAL_SECONDS = 0.8
_model = None
_generation_lock = threading.Lock()
_request_lock = threading.Lock()
_request_id = 0


def model():
    global _model
    if _model is None:
        print("Loading Voxtral 4B TTS 4bit...", flush=True)
        _model = load_model(MODEL_ID)
        print("Voxtral model ready.", flush=True)
    return _model


def resource_snapshot() -> dict:
    usage = resource.getrusage(resource.RUSAGE_SELF)
    return {
        "max_rss_bytes": int(usage.ru_maxrss),
        "mlx_active_memory_bytes": int(mx.get_active_memory()),
        "mlx_peak_memory_bytes": int(mx.get_peak_memory()),
    }


def generate_wav(text: str, voice: str) -> tuple[bytes, dict]:
    chunks = []
    cpu_started = time.process_time()
    with _generation_lock:
        mx.reset_peak_memory()
        for result in model().generate(text=text, voice=voice):
            audio = np.asarray(result.audio, dtype=np.float32)
            if audio.size:
                chunks.append(audio)
    if not chunks:
        raise RuntimeError("Voxtral generated no audio")
    buffer = io.BytesIO()
    sf.write(buffer, np.concatenate(chunks), SAMPLE_RATE, format="WAV")
    report = resource_snapshot()
    report["cpu_seconds"] = time.process_time() - cpu_started
    return buffer.getvalue(), report


def next_request_id() -> int:
    global _request_id
    with _request_lock:
        _request_id += 1
        return _request_id


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path not in {"/health", "/metrics"}:
            self.send_error(404)
            return
        self.send_response(200)
        body = json.dumps({"ok": True, "modelLoaded": _model is not None, **resource_snapshot()}).encode("utf-8")
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def do_POST(self):
        if self.path == "/speak":
            self.handle_wav_request()
        elif self.path == "/speak/stream":
            self.handle_stream_request()
        else:
            self.send_error(404)

    def request_payload(self) -> tuple[str, str]:
        size = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(size))
        text = str(payload.get("text", "")).strip()
        voice = str(payload.get("voice", "fr_male")).strip() or "fr_male"
        if not text:
            raise ValueError("empty text")
        return text, voice

    def handle_wav_request(self):
        try:
            text, voice = self.request_payload()
            request_id = next_request_id()
            started = time.monotonic()
            print(f"REQUEST start id={request_id} voice={voice} chars={len(text)}", flush=True)
            wav, report = generate_wav(text, voice)
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(wav)))
            self.send_header("X-Server-CPU-Seconds", f"{report['cpu_seconds']:.6f}")
            self.send_header("X-Server-Max-RSS-Bytes", str(report["max_rss_bytes"]))
            self.send_header("X-MLX-Active-Memory-Bytes", str(report["mlx_active_memory_bytes"]))
            self.send_header("X-MLX-Peak-Memory-Bytes", str(report["mlx_peak_memory_bytes"]))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(wav)
            self.close_connection = True
            print(f"REQUEST done id={request_id} seconds={time.monotonic() - started:.3f} cpu={report['cpu_seconds']:.3f} rss={report['max_rss_bytes']} mlxPeak={report['mlx_peak_memory_bytes']} bytes={len(wav)}", flush=True)
        except BrokenPipeError:
            print("REQUEST client_disconnected", flush=True)
        except Exception as error:
            print(f"Voxtral error: {error}", flush=True)
            self.send_error(500, str(error))

    def write_stream_frame(self, frame_type: int, payload: bytes):
        frame = bytes([frame_type]) + len(payload).to_bytes(4, "big") + payload
        self.wfile.write(f"{len(frame):X}\r\n".encode("ascii"))
        self.wfile.write(frame)
        self.wfile.write(b"\r\n")
        self.wfile.flush()

    def finish_chunked_response(self):
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()

    def handle_stream_request(self):
        headers_sent = False
        request_id = None
        started = time.monotonic()
        try:
            text, voice = self.request_payload()
            request_id = next_request_id()
            segments = split_stream_text(text)
            print(
                f"STREAM start id={request_id} voice={voice} chars={len(text)} segments={len(segments)}",
                flush=True,
            )
            self.send_response(200)
            self.send_header("Content-Type", "application/x-local-voice-lab-pcm")
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("X-Audio-Sample-Rate", str(SAMPLE_RATE))
            self.send_header("X-Audio-Format", "float32le")
            self.send_header("X-Audio-Channels", "1")
            # The bridge is deliberately single-request. Close after each response so an
            # idle HTTP/1.1 keep-alive connection cannot block the next generation.
            self.send_header("Connection", "close")
            self.end_headers()
            headers_sent = True

            cpu_started = time.process_time()
            total_samples = 0
            chunk_count = 0
            with _generation_lock:
                mx.reset_peak_memory()
                for segment in segments:
                    for result in model().generate(
                        text=segment,
                        voice=voice,
                        stream=True,
                        streaming_interval=STREAMING_INTERVAL_SECONDS,
                    ):
                        audio = np.asarray(result.audio, dtype=np.float32)
                        if not audio.size:
                            continue
                        self.write_stream_frame(1, audio.tobytes())
                        total_samples += audio.size
                        chunk_count += 1

            report = resource_snapshot()
            report["cpu_seconds"] = time.process_time() - cpu_started
            generation_seconds = time.monotonic() - started
            metadata = {
                "audioSeconds": total_samples / SAMPLE_RATE,
                "generationSeconds": generation_seconds,
                "chunkCount": chunk_count,
                "segmentCount": len(segments),
                "streamingIntervalSeconds": STREAMING_INTERVAL_SECONDS,
                "serverCPUSeconds": report["cpu_seconds"],
                "serverMaxRSSBytes": report["max_rss_bytes"],
                "mlxActiveMemoryBytes": report["mlx_active_memory_bytes"],
                "mlxPeakMemoryBytes": report["mlx_peak_memory_bytes"],
            }
            self.write_stream_frame(2, json.dumps(metadata).encode("utf-8"))
            self.finish_chunked_response()
            self.close_connection = True
            print(
                f"STREAM done id={request_id} seconds={generation_seconds:.3f} "
                f"chunks={chunk_count} segments={len(segments)} audio={metadata['audioSeconds']:.3f} "
                f"interval={STREAMING_INTERVAL_SECONDS:.1f} "
                f"cpu={report['cpu_seconds']:.3f} rss={report['max_rss_bytes']} "
                f"mlxPeak={report['mlx_peak_memory_bytes']}",
                flush=True,
            )
        except (BrokenPipeError, ConnectionResetError):
            elapsed = time.monotonic() - started
            print(f"STREAM cancelled id={request_id} seconds={elapsed:.3f} client_disconnected", flush=True)
        except Exception as error:
            print(f"Voxtral stream error: {error}", flush=True)
            if not headers_sent:
                self.send_error(500, str(error))

    def log_message(self, format, *args):
        print(format % args, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--preload", action="store_true")
    args = parser.parse_args()
    if args.preload:
        model()
    print(f"Voxtral bridge: http://127.0.0.1:{args.port}", flush=True)
    HTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
