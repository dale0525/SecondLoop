from __future__ import annotations

import re

SECRET_LINE_RE = re.compile(r"(?i)(api[_-]?key|token|secret|password)")
LONG_SECRET_RE = re.compile(r"(?<![A-Za-z0-9])[A-Za-z0-9_\-]{24,}(?![A-Za-z0-9])")


def _sanitize_text(text: str, *, max_len: int = 1200) -> str:
    lines: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if not line:
            continue
        if SECRET_LINE_RE.search(line):
            line = "[redacted sensitive line]"
        else:
            line = LONG_SECRET_RE.sub("[redacted]", line)
        lines.append(line)

    sanitized = "\n".join(lines).strip()
    if len(sanitized) > max_len:
        sanitized = sanitized[:max_len].rstrip() + "..."
    return sanitized


def _extract_release_notes_section(body: str) -> str:
    if not body.strip():
        return ""

    pattern = re.compile(
        r"(?ims)^#{1,6}\s*release\s*notes?\s*$\n(?P<section>.*?)(?:^#{1,6}\s+|\Z)"
    )
    match = pattern.search(body)
    if match:
        return _sanitize_text(match.group("section"))
    return _sanitize_text(body)
