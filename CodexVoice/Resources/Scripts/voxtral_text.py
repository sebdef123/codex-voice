import re


MAX_STREAM_TEXT_SEGMENT_CHARS = 1_000


def split_stream_text(text: str) -> list[str]:
    """Bound model generations while preferring paragraph and sentence boundaries."""
    cleaned = text.strip()
    if not cleaned:
        return [cleaned]

    paragraphs = [part.strip() for part in re.split(r"\n\s*\n+", cleaned) if part.strip()]
    segments: list[str] = []
    current = ""

    def append_hard_bounded(unit: str) -> None:
        remaining = unit.strip()
        while len(remaining) > MAX_STREAM_TEXT_SEGMENT_CHARS:
            boundary = remaining.rfind(" ", 0, MAX_STREAM_TEXT_SEGMENT_CHARS + 1)
            if boundary <= 0:
                boundary = MAX_STREAM_TEXT_SEGMENT_CHARS
            segments.append(remaining[:boundary].strip())
            remaining = remaining[boundary:].strip()
        if remaining:
            segments.append(remaining)

    def append_paragraph(paragraph: str) -> None:
        nonlocal current
        sentences = re.split(r"(?<=[.!?…])\s+", paragraph)
        for sentence in sentences:
            sentence = sentence.strip()
            if not sentence:
                continue
            if len(sentence) > MAX_STREAM_TEXT_SEGMENT_CHARS:
                if current:
                    segments.append(current)
                    current = ""
                append_hard_bounded(sentence)
            elif current and len(current) + 1 + len(sentence) > MAX_STREAM_TEXT_SEGMENT_CHARS:
                segments.append(current)
                current = sentence
            else:
                current = f"{current} {sentence}".strip()

    for paragraph in paragraphs:
        if current and len(current) + 2 + len(paragraph) > MAX_STREAM_TEXT_SEGMENT_CHARS:
            segments.append(current)
            current = ""
        append_paragraph(paragraph)

    if current:
        segments.append(current)
    return segments or [cleaned]
