"""`pack`: the pack toolkit (docs/pack-format.md), a thin front-end over the pipeline.

    pack new <code> [DIR]            scaffold a pack source that validates (pack_template/)
    pack validate <dir>              validate a pack source directory (anywhere on disk)
    pack build <dir> [-o out.sqlite] validate + compile into a course.sqlite
    pack info <file.sqlite>          meta, counts and licence of a compiled pack
    pack index <file.sqlite>... --base-url URL [-o index.json]
                                     a catalog (index.json) for packs you host yourself
    pack publish <id>... (--dry-run | --yes)
                                     the official GitHub Release (wraps `python -m pipeline publish`)

Installed as the console script `pack` (pipeline/pyproject.toml); `python -m pipeline.cli` works
too, and so does the older `python -m pipeline ...` CLI. Exit codes: 0 ok, 1 invalid pack or failed
step, 2 bad usage or refused.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
import sys
import urllib.request
from pathlib import Path

PACK_FORMAT_VERSION = "1.1"
TEMPLATE_DIR = Path(__file__).resolve().parent / "pack_template"
COURSE_ID_RE = re.compile(r"^[a-z]{2,3}$")
COUNT_TABLES = ("units", "skills", "notes", "items", "verbs", "verb_forms", "inflections", "sentences",
                "tokens", "skill_items", "skill_facets", "sentence_features", "stories", "story_questions")


def _err(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)


def _schema_check() -> bool:
    from .paths import DDL_PATH, SCHEMA_DIR
    if SCHEMA_DIR.is_dir() and DDL_PATH.is_file():
        return True
    _err(f"the pack schemas are missing ({SCHEMA_DIR}); install the toolkit from a tosk checkout "
         "with `pip install -e pipeline` (docs/pack-format.md, Open issues)")
    return False


# ------------------------------------------------------------------------------------------- new
def scaffold(code: str, dest: Path, title: str | None = None, author: str | None = None,
             force: bool = False) -> list[Path]:
    """Copy pack_template/ to `dest`, filling in the course id, title and author."""
    if not COURSE_ID_RE.match(code):
        raise ValueError(f"course id {code!r} must be 2-3 lower-case letters (a language code, e.g. 'eo')")
    dest = Path(dest)
    if dest.exists() and any(dest.iterdir()) and not force:
        raise FileExistsError(f"{dest} exists and is not empty (use --force to write into it)")
    subst = {
        "{{code}}": code,
        "{{title}}": json.dumps(title or f"New course ({code})", ensure_ascii=False),
        "{{author}}": json.dumps(author or "Your name", ensure_ascii=False),
    }
    written = []
    for src in sorted(TEMPLATE_DIR.rglob("*")):
        if src.is_dir() or src.name.startswith(".") or "__pycache__" in src.parts:
            continue
        rel = src.relative_to(TEMPLATE_DIR)
        out = dest / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        text = src.read_text(encoding="utf-8")
        for k, v in subst.items():
            text = text.replace(k, v)
        out.write_text(text, encoding="utf-8", newline="\n")
        written.append(out)
    return written


def cmd_new(a) -> int:
    dest = Path(a.dir) if a.dir else Path.cwd() / a.code
    try:
        files = scaffold(a.code, dest, a.title, a.author, a.force)
    except (ValueError, FileExistsError) as e:
        _err(str(e))
        return 2
    print(f"created pack '{a.code}' in {dest} ({len(files)} files). Next:")
    print(f"  pack validate {dest}")
    print(f"  pack build {dest} -o {a.code}.sqlite")
    return 0


# -------------------------------------------------------------------------------------- validate
def _load(dir_: str):
    from .content import load_pack
    root = Path(dir_)
    if not (root / "course.yaml").is_file():
        raise FileNotFoundError(f"{root} has no course.yaml (is it a pack source directory?)")
    return load_pack(root)


def _validate(pack, max_errors: int) -> bool:
    from .validate import validate
    errors = validate(pack)
    code = pack.course.get("id", "?")
    if errors:
        print(f"[{code}] VALIDATION FAILED ({len(errors)} errors):", file=sys.stderr)
        for e in errors[:max_errors]:
            print("  " + e, file=sys.stderr)
        if len(errors) > max_errors:
            print(f"  ... {len(errors) - max_errors} more", file=sys.stderr)
        return False
    print(f"[{code}] validation passed ({len(pack.items)} items, {len(pack.verbs)} verbs, "
          f"{len(pack.sentences)} sentences, {len(pack.stories)} stories)", file=sys.stderr)
    return True


def cmd_validate(a) -> int:
    if not _schema_check():
        return 2
    try:
        pack = _load(a.dir)
    except (FileNotFoundError, ValueError) as e:
        _err(str(e))
        return 1
    return 0 if _validate(pack, a.max_errors) else 1


# ----------------------------------------------------------------------------------------- build
def cmd_build(a) -> int:
    if not _schema_check():
        return 2
    from .compile import compile_pack
    from .hns.safeguard import check_destination
    try:
        pack = _load(a.dir)
    except (FileNotFoundError, ValueError) as e:
        _err(str(e))
        return 1
    if not _validate(pack, a.max_errors):
        return 1
    code = pack.code
    out = Path(a.out) if a.out else Path.cwd() / f"{code}.sqlite"
    out = check_destination(code, out)
    stats = compile_pack(pack, out)
    print(f"[{code}] compiled {out} ({out.stat().st_size // 1024} KB): {stats['items']} items, "
          f"{stats['verbs']} verbs, {stats['sentences']} sentences, {stats['facets']} skill facets, "
          f"{stats['stories']} stories", file=sys.stderr)
    if out.name != f"{code}.sqlite":
        print(f"note: name the file {code}.sqlite before sharing or hosting it (the app and catalogs "
              "expect {course_id}.sqlite)", file=sys.stderr)
    if a.report:
        from .report import build_report, format_report
        print(format_report(build_report(pack), verbose=True))
    return 0


# ------------------------------------------------------------------------------------------ info
def _ro(path: Path) -> sqlite3.Connection:
    return sqlite3.connect("file:" + urllib.request.pathname2url(str(Path(path).resolve())) + "?mode=ro", uri=True)


def pack_info(path: str | Path) -> dict:
    """Meta, counts and credits of a compiled pack (read-only)."""
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f"{path} not found")
    con = _ro(path)
    try:
        try:
            meta = dict(con.execute("SELECT key, value FROM meta").fetchall())
        except sqlite3.DatabaseError as e:
            raise ValueError(f"{path} is no course pack ({e})") from None
        tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        counts = {t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0] for t in COUNT_TABLES if t in tables}
        facets = {}
        if "skill_facets" in tables:
            facets = dict(con.execute("SELECT kind, COUNT(DISTINCT facet_id) FROM skill_facets GROUP BY kind"))
        generated = 0
        if "sentences" in tables:
            generated = con.execute("SELECT COUNT(*) FROM sentences WHERE src LIKE 'claude%'").fetchone()[0]
        user_version = con.execute("PRAGMA user_version").fetchone()[0]
    finally:
        con.close()

    def js(key, default):
        try:
            return json.loads(meta[key]) if meta.get(key) else default
        except ValueError:
            return meta[key]

    return {
        "file": str(path), "size": path.stat().st_size,
        "course_id": meta.get("course_id"), "version": meta.get("version"), "title": js("title", {}),
        "description": js("description", {}), "target": meta.get("target"),
        "translations": js("translations", []),
        "schema_version": meta.get("schema_version"), "schema_minor": meta.get("schema_minor", "0"),
        "user_version": user_version, "min_app_version": meta.get("min_app_version"),
        "unverified": meta.get("unverified") == "1", "built_at": meta.get("built_at"),
        "license": meta.get("license"), "authors": js("authors", []), "data_sources": js("data_sources", []),
        "attribution": meta.get("attribution", ""),
        "counts": counts, "facets": facets, "generated_sentences": generated,
        "meta_keys": sorted(meta),
    }


def format_info(i: dict) -> str:
    title = i["title"] if isinstance(i["title"], dict) else {"": i["title"]}
    lines = [
        f"{i['course_id']} {i['version']}  {' / '.join(title.values())}",
        f"  file             {i['file']} ({i['size'] // 1024} KB)",
        f"  target           {i['target']}; translations {', '.join(i['translations'])}",
        f"  schema           {i['schema_version']}.{i['schema_minor']} (user_version {i['user_version']}); "
        f"min app {i['min_app_version'] or '-'}",
        f"  built            {i['built_at']}{'; UNVERIFIED (not checked by a speaker)' if i['unverified'] else ''}",
        f"  license          {i['license'] or '(not declared; see attribution)'}",
    ]
    if i["authors"]:
        lines.append("  authors          " + ", ".join(
            a.get("name", "?") + (f" ({a['role']})" if a.get("role") else "") if isinstance(a, dict) else str(a)
            for a in i["authors"]))
    for s in i["data_sources"] or []:
        if isinstance(s, dict):
            lines.append(f"  source           {s.get('title')}" + (f" — {s['license']}" if s.get("license") else ""))
    c = i["counts"]
    lines.append("  counts           " + ", ".join(f"{k} {v}" for k, v in c.items()))
    if i["facets"]:
        lines.append("  facets           " + ", ".join(f"{k} {v}" for k, v in sorted(i["facets"].items())))
    if c.get("sentences"):
        lines.append(f"  generated        {i['generated_sentences']} of {c['sentences']} sentences have src claude-*")
    if i["attribution"]:
        lines.append("  attribution")
        lines += ["    " + x for x in i["attribution"].splitlines()]
    return "\n".join(lines)


def cmd_info(a) -> int:
    try:
        info = pack_info(a.file)
    except (FileNotFoundError, ValueError) as e:
        _err(str(e))
        return 1
    print(json.dumps(info, ensure_ascii=False, indent=2) if a.json else format_info(info))
    return 0


# ----------------------------------------------------------------------------------------- index
def build_catalog(files: list[str | Path], base_url: str, tag: str | None = None,
                  min_app_version: str | None = None, gz: bool = False) -> dict:
    """index.json (index_version 1) for packs hosted at `base_url` + '/' + file name."""
    from . import publish as pub
    from datetime import datetime, timezone
    courses = []
    for f in files:
        p = Path(f)
        e = pub.index_entry(p, tag or "", min_app_version=min_app_version or pub.DEFAULT_MIN_APP_VERSION)
        e["url"] = base_url.rstrip("/") + "/" + p.name
        if gz:
            # Web copy (section 14): <id>.sqlite.gz next to the pack.
            from .webpacks import gzip_pack, web_fields
            g = gzip_pack(p, p.with_name(p.name + ".gz"))
            e.update(web_fields(g, base_url.rstrip("/") + "/" + g.name))
        courses.append(e)
    ids = [c["id"] for c in courses]
    dup = sorted({x for x in ids if ids.count(x) > 1})
    if dup:
        raise ValueError(f"the catalog lists {dup} more than once")
    doc = {"index_version": pub.INDEX_VERSION,
           "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")}
    if tag:
        doc["tag"] = tag
    doc["courses"] = sorted(courses, key=lambda c: c["id"])
    return doc


def cmd_index(a) -> int:
    try:
        doc = build_catalog(a.files, a.base_url, a.tag, a.min_app_version, gz=a.gz)
    except (FileNotFoundError, ValueError) as e:
        _err(str(e))
        return 1
    out = Path(a.out)
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {out} ({len(doc['courses'])} courses)", file=sys.stderr)
    return 0


# --------------------------------------------------------------------------------------- publish
def cmd_publish(a) -> int:
    if not a.dry_run and not a.yes:
        _err("pack publish creates a public GitHub Release; pass --dry-run to preview it "
             "or --yes to publish for real")
        return 2
    from . import publish as pub
    return pub.publish(a.ids, tag=a.tag, dry_run=a.dry_run, content_root=a.content_root,
                       repo=a.repo or pub.DATA_REPO_SLUG,
                       min_app_version=a.min_app_version or pub.DEFAULT_MIN_APP_VERSION, gz=a.gz)


# ------------------------------------------------------------------------------------------ main
def parser() -> argparse.ArgumentParser:
    from .compile import COURSE_DB_SCHEMA_MINOR, COURSE_DB_SCHEMA_VERSION
    ap = argparse.ArgumentParser(
        prog="pack", description="Make, check and build language packs (pack format "
                                 f"{PACK_FORMAT_VERSION}, docs/pack-format.md).")
    ap.add_argument("--version", action="version",
                    version=f"pack (pack format {PACK_FORMAT_VERSION}, course.sqlite schema "
                            f"{COURSE_DB_SCHEMA_VERSION}.{COURSE_DB_SCHEMA_MINOR})")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("new", help="scaffold a pack source that validates")
    p.add_argument("code", help="course id = target language code, 2-3 lower-case letters")
    p.add_argument("dir", nargs="?", help="where to create it (default ./<code>)")
    p.add_argument("--title", help="English course title")
    p.add_argument("--author", help="your name (course.yaml authors)")
    p.add_argument("--force", action="store_true", help="write into a non-empty directory")
    p.set_defaults(fn=cmd_new)

    p = sub.add_parser("validate", help="validate a pack source directory")
    p.add_argument("dir")
    p.add_argument("--max-errors", type=int, default=200, help="errors to print (default 200)")
    p.set_defaults(fn=cmd_validate)

    p = sub.add_parser("build", help="validate and compile a pack source into a course.sqlite")
    p.add_argument("dir")
    p.add_argument("-o", "--out", help="output file (default ./<course_id>.sqlite)")
    p.add_argument("--report", action="store_true", help="print the per-skill content report")
    p.add_argument("--max-errors", type=int, default=200)
    p.set_defaults(fn=cmd_build)

    p = sub.add_parser("info", help="meta, counts and licence of a compiled pack")
    p.add_argument("file")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    p.set_defaults(fn=cmd_info)

    p = sub.add_parser("index", help="write a catalog index.json for packs you host yourself")
    p.add_argument("files", nargs="+", help="compiled packs, each named <course_id>.sqlite")
    p.add_argument("--base-url", required=True, help="URL of the folder the packs are served from")
    p.add_argument("-o", "--out", default="index.json")
    p.add_argument("--tag", help="optional release tag recorded in the index")
    p.add_argument("--min-app-version", help="default min_app_version for packs that don't set one")
    p.add_argument("--gz", action="store_true",
                   help="also write <id>.sqlite.gz next to each pack and add web_url/gz_sha256/gz_size")
    p.set_defaults(fn=cmd_index)

    p = sub.add_parser("publish", help="the official GitHub Release of built packs (tosk-data)")
    p.add_argument("ids", nargs="+", help="course ids whose dist/<id>.sqlite to publish")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--dry-run", action="store_true", help="write dist/index.json and print the gh commands only")
    g.add_argument("--yes", action="store_true", help="really create the release")
    p.add_argument("--tag", help="release tag (default packs-YYYYMMDD, UTC)")
    p.add_argument("--repo", help="GitHub repository (default linguaperta/tosk-data)")
    p.add_argument("--min-app-version", help="oldest app version that can use these packs (default 0.3.0)")
    p.add_argument("--content-root", help="the content/ folder whose sibling dist/ holds the packs")
    p.add_argument("--gz", action="store_true",
                   help="also upload <id>.sqlite.gz for web apps and add web_url/gz_sha256/gz_size")
    p.set_defaults(fn=cmd_publish)
    return ap


def main(argv: list[str] | None = None) -> int:
    a = parser().parse_args(argv)
    from .hns.safeguard import RestrictedContentError
    try:
        return a.fn(a)
    except RestrictedContentError as e:
        _err(str(e))
        return 2


if __name__ == "__main__":
    sys.exit(main())
