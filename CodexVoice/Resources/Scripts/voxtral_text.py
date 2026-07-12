import re


MAX_STREAM_TEXT_SEGMENT_CHARS = 650


def split_stream_text(text: str) -> list[str]:
    """Keep each model generation bounded without dropping any spoken text."""
    sentences = re.split(r"(?<=[.!?…])\s+", text.strip())
    segments: list[str] = []
    current = ""

    def append_bounded(unit: str) -> None:
        remaining = unit.strip()
        while len(remaining) > MAX_STREAM_TEXT_SEGMENT_CHARS:
            boundary = remaining.rfind(" ", 0, MAX_STREAM_TEXT_SEGMENT_CHARS + 1)
            if boundary <= 0:
                boundary = MAX_STREAM_TEXT_SEGMENT_CHARS
            segments.append(remaining[:boundary].strip())
            remaining = remaining[boundary:].strip()
        if remaining:
            segments.append(remaining)

    for sentence in sentences:
        sentence = sentence.strip()
        if not sentence:
            continue
        if len(sentence) > MAX_STREAM_TEXT_SEGMENT_CHARS:
            if current:
                segments.append(current)
                current = ""
            append_bounded(sentence)
            continue
        if current and len(current) + 1 + len(sentence) > MAX_STREAM_TEXT_SEGMENT_CHARS:
            segments.append(current)
            current = sentence
        else:
            current = f"{current} {sentence}".strip()

    if current:
        segments.append(current)
    return segments or [text.strip()]
