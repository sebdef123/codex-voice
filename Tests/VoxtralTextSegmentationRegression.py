import sys
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1] / "CodexVoice" / "Resources" / "Scripts"
sys.path.insert(0, str(SCRIPTS))

from voxtral_text import MAX_STREAM_TEXT_SEGMENT_CHARS, split_stream_text


def normalized(text: str) -> str:
    return " ".join(text.split())


text = " ".join(
    [
        "La premiere phrase introduit le diagnostic.",
        "La deuxieme phrase garde les details importants sans les perdre.",
        "The third sentence keeps the English section readable and complete.",
    ]
    * 16
)
segments = split_stream_text(text)

assert len(segments) > 1
assert all(0 < len(segment) <= MAX_STREAM_TEXT_SEGMENT_CHARS for segment in segments)
assert normalized(" ".join(segments)) == normalized(text)

paragraph_one = " ".join(["premier"] * 110)
paragraph_two = " ".join(["second"] * 120)
paragraph_segments = split_stream_text(f"{paragraph_one}\n\n{paragraph_two}")
assert paragraph_segments == [paragraph_one, paragraph_two]

oversized_sentence = " ".join(["continu"] * 250) + "."
oversized_segments = split_stream_text(oversized_sentence)
assert len(oversized_segments) > 1
assert all(0 < len(segment) <= MAX_STREAM_TEXT_SEGMENT_CHARS for segment in oversized_segments)
assert normalized(" ".join(oversized_segments)) == normalized(oversized_sentence)

print("VoxtralTextSegmentationRegression: ok")
