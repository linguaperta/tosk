"""`python -m pipeline build it nl [--install]`: validate + compile + report + dist/index.json.

Works offline from the committed JSONL source packs.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import sys
from pathlib import Path

from .compile import COURSE_DB_SCHEMA_MINOR, COURSE_DB_SCHEMA_VERSION, compile_pack
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


def _roots(langs, content_root, local: bool) -> dict[str, Path]:
    """Content root per course. Restricted courses always use the local root, unless an
    explicit --content-root is given (which the safeguard then checks)."""
    from .restricted import check_destination, local_content_root, restricted_courses
    restricted = restricted_courses()
    out = {}
    for code in langs:
        if content_root:
            root = content_dir(content_root)
        elif code in restricted:
            root = local_content_root(code)
        elif local:
            root = local_content_root()
        else:
            root = content_dir(None)
        check_destination(code, root / code)
        out[code] = root
    return out


def _validate(langs, roots: dict[str, Path]) -> tuple[dict, bool]:
    packs = {}
    ok = True
    for code in langs:
        pack = load_pack(roots[code] / code)
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


def validate_only(langs, content_root=None, local: bool = False) -> int:
    _, ok = _validate(langs, _roots(langs, content_root, local))
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


def build(langs, content_root=None, install: bool = False, quiet: bool = False, local: bool = False,
          desktop: bool = False) -> int:
    from .restricted import RestrictedContentError, check_destination, restricted_courses
    bad = sorted(restricted_courses() & set(langs))
    if install and bad:
        raise RestrictedContentError(
            f"refusing --install for {bad}: restricted content must not be bundled into app/assets "
            "(load it from a file instead: build --desktop, or 'Add course from file' in the app)")
    roots = _roots(langs, content_root, local)
    packs, ok = _validate(langs, roots)
    if not ok:
        return 1
    entries_by_dist: dict[Path, dict] = {}
    for code, pack in packs.items():
        dist = roots[code].parent / "dist"
        out = check_destination(code, dist / f"{code}.sqlite")
        entries = entries_by_dist.setdefault(dist, {})
        stats = compile_pack(pack, out)
        print(f"[{code}] compiled {out} ({out.stat().st_size // 1024} KB): {stats['items']} items, "
              f"{stats['verbs']} verbs, {stats['verb_forms']} forms, {stats['sentences']} sentences, "
              f"{stats['tokens']} tokens, {stats['facets']} skill facets, {stats['stories']} stories "
              f"({stats['story_sentences']} sentences, {stats['story_questions']} questions)", file=sys.stderr)
        print(format_report(build_report(pack), verbose=not quiet))
        entries[code] = {
            "id": code,
            "version": pack.course["version"],
            "title": pack.course["title"],
            "sha256": sha256(out),
            "size": out.stat().st_size,
            "schema_version": COURSE_DB_SCHEMA_VERSION,
            "schema_minor": COURSE_DB_SCHEMA_MINOR,   # 1: inflection tables (facet kind infl)
            "url": f"{code}.sqlite",
        }
        if install:
            APP_COURSES_DIR.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(out, APP_COURSES_DIR / f"{code}.sqlite")
            print(f"[{code}] installed -> {APP_COURSES_DIR / f'{code}.sqlite'}", file=sys.stderr)
        if desktop:
            from .install import install_desktop
            print(f"[{code}] copied to the desktop app: {install_desktop(out)}", file=sys.stderr)
    for dist, entries in entries_by_dist.items():
        idx = write_index(dist, entries)
        print(f"wrote {idx}", file=sys.stderr)
    return 0
