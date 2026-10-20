"""`python -m pipeline publish it nl [--tag packs-YYYYMMDD] [--dry-run]`: publish built packs.

Takes the packs `python -m pipeline build` wrote to the tosk-data `dist/` folder, writes the
release index `dist/index.json` (absolute download URLs) and creates one GitHub Release on
`linguaperta/tosk-data` with every pack plus the index as assets, marked "latest".

The app reads the index from a stable URL, GitHub's redirect to the newest release's asset:

    https://github.com/linguaperta/tosk-data/releases/latest/download/index.json

and each pack from the `url` in the index (the asset of the release it was published in):

    https://github.com/linguaperta/tosk-data/releases/download/<tag>/<id>.sqlite

Restricted courses (all rights reserved, see restricted.py) are refused, always. Needs the GitHub CLI
(`gh`), logged in once with `gh auth login`. `--dry-run` writes the index and prints the commands.
See docs/release.md, "Publishing course packs".
"""
from __future__ import annotations

import json
import shlex
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from .build import sha256
from .paths import content_dir

DATA_REPO_SLUG = "linguaperta/tosk-data"
INDEX_VERSION = 1
# The oldest app that can use today's packs (schema 1 with the v0.3 tables: grammar gating,
# generated sentences). A pack that needs newer app code (e.g. a new exercise type or table the
# older app would ignore wrongly) is published with a higher --min-app-version, or a
# `min_app_version` key in the pack's meta.
DEFAULT_MIN_APP_VERSION = "0.3.0"


def stable_index_url(repo: str = DATA_REPO_SLUG) -> str:
    return f"https://github.com/{repo}/releases/latest/download/index.json"


def asset_url(tag: str, course_id: str, repo: str = DATA_REPO_SLUG, suffix: str = ".sqlite") -> str:
    return f"https://github.com/{repo}/releases/download/{tag}/{course_id}{suffix}"


def default_tag(now: datetime | None = None) -> str:
    return "packs-" + (now or datetime.now(timezone.utc)).strftime("%Y%m%d")


def _refuse_restricted(langs) -> None:
    from .restricted import refuse_restricted
    refuse_restricted(langs, "publish")


def read_pack_meta(path: Path) -> dict[str, str]:
    con = sqlite3.connect(f"file:{Path(path).as_posix()}?mode=ro", uri=True)
    try:
        return dict(con.execute("SELECT key, value FROM meta").fetchall())
    finally:
        con.close()


def _json(meta: dict[str, str], key: str, default):
    v = meta.get(key)
    return json.loads(v) if v else default


def index_entry(path: Path, tag: str, repo: str = DATA_REPO_SLUG,
                min_app_version: str = DEFAULT_MIN_APP_VERSION, gz: bool = False) -> dict:
    """One course of the release index, read from the compiled pack itself."""
    path = Path(path)
    meta = read_pack_meta(path)
    cid = meta.get("course_id")
    if cid != path.stem:
        raise ValueError(f"{path.name} holds course {cid!r}; the file must be named {cid}.sqlite")
    _refuse_restricted([cid])
    for key in ("version", "title", "schema_version", "target"):
        if not meta.get(key):
            raise ValueError(f"{path.name}: meta.{key} is missing")
    entry = {
        "id": cid,
        "version": meta["version"],
        "title": _json(meta, "title", {}),
        "description": _json(meta, "description", {}),
        "target": meta["target"],
        "sources": _json(meta, "translations", []),
        "unverified": meta.get("unverified") == "1",
        "schema_version": meta["schema_version"],
        "min_app_version": meta.get("min_app_version") or min_app_version,
        "sha256": sha256(path),
        "size": path.stat().st_size,
        "url": asset_url(tag, cid, repo),
    }
    # optional credits (pack format 1.0, credits.py); apps ignore fields they don't know
    if meta.get("license"):
        entry["license"] = meta["license"]
    if meta.get("authors"):
        entry["authors"] = _json(meta, "authors", [])
    if gz:
        # Web fields (docs/release.md, "Web packs"): a gzipped copy next to the pack.
        from .webpacks import gzip_pack, web_fields
        gz_path = gzip_pack(path, path.with_name(path.name + ".gz"))
        entry.update(web_fields(gz_path, asset_url(tag, cid, repo, ".sqlite.gz")))
    return entry


def build_index(dist: Path, langs, tag: str, repo: str = DATA_REPO_SLUG,
                min_app_version: str = DEFAULT_MIN_APP_VERSION, generated_at: str | None = None,
                gz: bool = False) -> dict:
    _refuse_restricted(langs)
    courses = []
    for code in sorted(set(langs)):
        path = Path(dist) / f"{code}.sqlite"
        if not path.exists():
            raise FileNotFoundError(f"{path} not found: run `python -m pipeline build {code}` first")
        courses.append(index_entry(path, tag, repo, min_app_version, gz=gz))
    return {
        "index_version": INDEX_VERSION,
        "generated_at": generated_at or datetime.now(timezone.utc).replace(microsecond=0)
        .isoformat().replace("+00:00", "Z"),
        "tag": tag,
        "courses": courses,
    }


def write_index(dist: Path, doc: dict) -> Path:
    path = Path(dist) / "index.json"
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return path


def release_notes(doc: dict) -> str:
    """One line (so the printed dry-run commands stay one per line)."""
    parts = [f"{c['title'].get('en') or c['id']} ({c['id']}) {c['version']}, {c['size'] / 1e6:.1f} MB"
             for c in doc["courses"]]
    return ("tosk course packs (compiled SQLite, CC BY-SA 4.0, see ATTRIBUTION.md): " + "; ".join(parts)
            + ". Checksums are in index.json; the app reads releases/latest/download/index.json.")


def gh_commands(dist: Path, doc: dict, repo: str = DATA_REPO_SLUG) -> list[list[str]]:
    """The commands that publish [doc]: an auth check, then one release with every asset."""
    tag = doc["tag"]
    assets = [str(Path(dist) / f"{c['id']}.sqlite") for c in doc["courses"]]
    assets += [str(Path(dist) / f"{c['id']}.sqlite.gz") for c in doc["courses"] if c.get("web_url")]
    assets.append(str(Path(dist) / "index.json"))
    return [
        ["gh", "auth", "status"],
        ["gh", "release", "create", tag, *assets, "--repo", repo, "--title", f"Course packs {tag}",
         "--notes", release_notes(doc), "--latest"],
    ]


def publish(langs, tag: str | None = None, dry_run: bool = False, content_root=None,
            repo: str = DATA_REPO_SLUG, min_app_version: str = DEFAULT_MIN_APP_VERSION,
            run: Callable[..., subprocess.CompletedProcess] = subprocess.run, gz: bool = False) -> int:
    _refuse_restricted(langs)
    dist = content_dir(content_root).parent / "dist"
    tag = tag or default_tag()
    doc = build_index(dist, langs, tag, repo, min_app_version, gz=gz)
    idx = write_index(dist, doc)
    print(f"wrote {idx} ({len(doc['courses'])} courses, tag {tag})", file=sys.stderr)
    for c in doc["courses"]:
        print(f"  {c['id']} {c['version']}  {c['size']:>10} bytes  {c['url']}", file=sys.stderr)
    print(f"stable index URL: {stable_index_url(repo)}", file=sys.stderr)
    cmds = gh_commands(dist, doc, repo)
    if dry_run:
        for cmd in cmds:
            print(shlex.join(cmd))
        return 0
    for cmd in cmds:
        r = run(cmd)
        if r.returncode != 0:
            hint = " (log in once with `gh auth login`)" if cmd[1] == "auth" else ""
            print(f"error: `{' '.join(cmd[:4])} ...` failed with exit code {r.returncode}{hint}", file=sys.stderr)
            return r.returncode or 1
    print(f"published {tag}; commit dist/index.json in tosk-data", file=sys.stderr)
    return 0
