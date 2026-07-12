# Codex Voice

> An unofficial local voice companion for Codex on macOS.

Codex Voice watches local Codex transcripts and reads useful assistant updates aloud. It keeps the native Codex interface intact while adding an ambient, interruptible audio layer.

![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-black) ![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon-black) ![Privacy](https://img.shields.io/badge/privacy-local--first-brightgreen)

## Install with Codex

Copy and paste this prompt into Codex to install the app on another Mac:

```text
Install the latest Codex Voice release from:
https://github.com/sebdef123/codex-voice

1. Confirm that this Mac uses Apple Silicon.
2. Download the latest release ZIP, extract it, and move Codex Voice 2.app to /Applications.
3. Start with macOS TTS only. Do not prepare or install Voxtral yet.
4. Launch the app and tell me which macOS permissions I need to approve, including Input Monitoring. If Gatekeeper blocks the first launch, explain the safe manual step I need to take.
5. Do not modify my existing Codex configuration. Do not enable or install Voxtral without asking me first.
```

## Highlights

- **Two local engines:** macOS TTS for instant response, or local Voxtral Streaming for a more natural voice.
- **Interruptible by design:** a new Codex request, right Option, or an engine switch immediately stops active speech.
- **Voice navigation:** use left and right arrows while Codex is frontmost to replay nearby assistant blocks.
- **Local privacy:** no cloud API is used by the app. Diagnostic logs exclude spoken text unless explicitly enabled.
- **Resource-aware Voxtral:** the local server starts on demand, is released when switching back to macOS TTS, and records latency/resource metrics.
- **Portable pronunciation dictionary:** macOS-only corrections live in a small external CSV that can be imported or exported between Macs.
- **System-language menus:** the app uses French on French systems and English everywhere else.

## Requirements

- macOS 12 or later.
- Apple Silicon (the current release is built for `arm64`).
- Codex installed locally, with transcripts available under `~/.codex/sessions`.
- Voxtral Streaming is optional. It requires internet on first setup, `uv`, and enough disk/memory for the local model.

## Install

1. Download the latest `Codex Voice` release ZIP.
2. Move `Codex Voice 2.app` to `/Applications`.
3. Open the app and grant **Input Monitoring** if macOS asks for it.
4. macOS TTS is ready immediately.

To enable Voxtral Streaming, install `uv` and run `Preparer Voxtral.command` included in the release once. The script fetches the pinned audio dependency and the model locally.

## Privacy

Codex Voice reads local transcript files so it can speak assistant responses. It does not upload those transcripts or contact a remote TTS API.

The diagnostic log records timings, engine, voice, interruptions, and resource use. Spoken text is **off by default** and can only be included for a deliberate debugging session from the app menu. `Effacer les logs audio` clears the local audio and server logs.

## Voxtral model notice

The app does not include or redistribute model weights. Voxtral weights are downloaded separately to the user’s machine. Voxtral TTS is licensed under **CC BY-NC 4.0**, so the Voxtral feature is for non-commercial use only. See [MODEL_LICENSES.md](MODEL_LICENSES.md).

## Development

```sh
./test-codex-voice.sh
./build-codex-voice.sh
./create-distribution.sh
```

`build-codex-voice.sh` builds and installs the app into `/Applications`. `create-distribution.sh` also creates a personal transfer ZIP in `Distribution/out`.

## Status

`v1.0.1` is the first public maintenance release. The focus is comfort, natural voice quality, interruption behavior, and small operational surface area rather than a full replacement for Codex.

## Disclaimer

Codex Voice is an independent project and is not affiliated with or endorsed by OpenAI. “Codex” is used only to describe compatibility with the local Codex application.

## License

The source code is available under the [Apache License 2.0](LICENSE). Model weights and third-party dependencies retain their own licenses.
