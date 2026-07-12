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
    * 8
)
segments = split_stream_text(text)

assert len(segments) > 1
assert all(0 < len(segment) <= MAX_STREAM_TEXT_SEGMENT_CHARS for segment in segments)
assert normalized(" ".join(segments)) == normalized(text)

print("VoxtralTextSegmentationRegression: ok")
