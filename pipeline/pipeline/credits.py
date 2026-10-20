"""Credits of a pack (pack format 1.0, docs/pack-format.md "Licence, attribution and authors").

course.yaml may declare `license` (SPDX identifier), `authors` (names or {name, role, url, email})
and `data_sources` ({id, title, author, url, license, note}). The compiler copies them into
`meta.license`, `meta.authors` and `meta.data_sources` (JSON), and a pack that declares any of them
but no `attribution` gets an attribution text generated from them instead of the official
tosk-data text (compile.attribution_text), which would be wrong for anyone else's pack.
"""
from __future__ import annotations

import json


def _j(v) -> str:
    return json.dumps(v, ensure_ascii=False, separators=(",", ":"))


def authors_list(course: dict) -> list[dict]:
    return [a if isinstance(a, dict) else {"name": str(a)} for a in course.get("authors") or []]


def has_credits(course: dict) -> bool:
    return bool(course.get("license") or course.get("authors") or course.get("data_sources"))


def credits_meta(course: dict) -> dict[str, str]:
    """The meta rows for the declared credits (none for packs that declare nothing)."""
    out: dict[str, str] = {}
    if course.get("license"):
        out["license"] = str(course["license"])
    if course.get("authors"):
        out["authors"] = _j(authors_list(course))
    if course.get("data_sources"):
        out["data_sources"] = _j(list(course["data_sources"]))
    return out


def generic_attribution(course: dict) -> str:
    """Attribution text from the declared credits."""
    title = course.get("title") or {}
    if isinstance(title, dict):
        name = title.get("en") or next(iter(title.values()), course.get("id", "?"))
    else:
        name = str(title)
    lines = [f"Course '{course.get('id')}' ({name}) {course.get('version')}"
             + (f", content licensed {course['license']}." if course.get("license") else ".")]
    authors = authors_list(course)
    if authors:
        lines.append("Authors: " + ", ".join(
            a["name"] + (f" ({a['role']})" if a.get("role") else "") for a in authors) + ".")
    sources = course.get("data_sources") or []
    if sources:
        lines.append("Sources:")
        for s in sources:
            bits = [s["title"]]
            if s.get("author"):
                bits.append(s["author"])
            if s.get("url"):
                bits.append(s["url"])
            line = "- " + ", ".join(bits)
            if s.get("license"):
                line += f" — {s['license']}"
            lines.append(line)
    return "\n".join(lines)
