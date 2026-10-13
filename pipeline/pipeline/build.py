"""`python -m pipeline build it nl [--install]`: validate + compile + report + dist/index.json.

Works offline from the committed JSONL source packs.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import sys
from pathlib import Path

from .compile import COURSE_DB_SCHEMA_VERSION, compile_pack
from .content import load_pack
from .paths import APP_COURSES_DIR, content_dir
from .report import build_report, format_report
from .validate import validate


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _validate(langs, root: Path) -> tuple[dict, bool]:
    packs = {}
    ok = True
    for code in langs:
        pack = load_pack(root / code)
        errors = validate(pack)
        if errors:
            ok = False
            print(f"[{code}] VALIDATION FAILED ({len(errors)} errors):", file=sys.stderr)
            for e in errors[:200]:
                print("  " + e, file=sys.stderr)
            if len(errors) > 200:
                print(f"  ... {len(errors) - 200} more", file=sys.stderr)
        else:
            print(f"[{code}] validation passed", file=sys.stderr)
        packs[code] = pack
    return packs, ok


def validate_only(langs, content_root=None) -> int:
    _, ok = _validate(langs, content_dir(content_root))
    return 0 if ok else 1


def write_index(dist: Path, entries: dict[str, dict]) -> Path:
    path = dist / "index.json"
    existing = {}
    if path.exists():
        try:
            for e in json.loads(path.read_text(encoding="utf-8")).get("courses", []):
                existing[e["id"]] = e
        except ValueError:
            pass
    existing.update(entries)
    doc = {
        "schema_version": COURSE_DB_SCHEMA_VERSION,
        "note": "url is relative to this index.json; replace with the release/download URL when publishing",
        "courses": [existing[k] for k in sorted(existing)],
    }
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return path


def build(langs, content_root=None, install: bool = False, quiet: bool = False) -> int:
    root = content_dir(content_root)
    packs, ok = _validate(langs, root)
    if not ok:
        return 1
    dist = root.parent / "dist"
    entries = {}
    for code, pack in packs.items():
        out = dist / f"{code}.sqlite"
        stats = compile_pack(pack, out)
        print(f"[{code}] compiled {out} ({out.stat().st_size // 1024} KB): {stats['items']} items, "
              f"{stats['verbs']} verbs, {stats['verb_forms']} forms, {stats['sentences']} sentences, "
              f"{stats['tokens']} tokens, {stats['facets']} skill facets", file=sys.stderr)
        print(format_report(build_report(pack), verbose=not quiet))
        entries[code] = {
            "id": code,
            "version": pack.course["version"],
            "title": pack.course["title"],
            "sha256": sha256(out),
            "size": out.stat().st_size,
            "schema_version": COURSE_DB_SCHEMA_VERSION,
            "url": f"{code}.sqlite",
        }
        if install:
            APP_COURSES_DIR.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(out, APP_COURSES_DIR / f"{code}.sqlite")
            print(f"[{code}] installed -> {APP_COURSES_DIR / f'{code}.sqlite'}", file=sys.stderr)
    idx = write_index(dist, entries)
    print(f"wrote {idx}", file=sys.stderr)
    return 0
