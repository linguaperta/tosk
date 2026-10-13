"""Filesystem locations: repo root, content root, download cache, app assets."""
from __future__ import annotations

import os
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent          # pipeline/pipeline
PIPELINE_DIR = PKG_DIR.parent                       # pipeline/
REPO_ROOT = PIPELINE_DIR.parent                     # tosk repo (or worktree) root
SCHEMA_DIR = REPO_ROOT / "schema"
DDL_PATH = SCHEMA_DIR / "course_db.sql"
APP_COURSES_DIR = REPO_ROOT / "app" / "assets" / "courses"

DEFAULT_DATA_REPO = Path("C:/Users/timo/Repositories/tosk-data")


def data_repo_root(content_root: str | os.PathLike | None = None) -> Path:
    """The tosk-data checkout (parent of content/ and dist/)."""
    return content_dir(content_root).parent


def content_dir(content_root: str | os.PathLike | None = None) -> Path:
    """Resolve the content root (the folder holding it/, nl/, ...).

    Order: explicit argument, $TOSK_CONTENT, ../tosk-data/content next to the repo
    root, then the fixed default checkout location (useful from git worktrees).
    """
    if content_root:
        return Path(content_root).resolve()
    env = os.environ.get("TOSK_CONTENT")
    if env:
        return Path(env).resolve()
    rel = (REPO_ROOT.parent / "tosk-data" / "content")
    if rel.exists():
        return rel.resolve()
    return DEFAULT_DATA_REPO / "content"


def cache_dir() -> Path:
    env = os.environ.get("TOSK_CACHE")
    if env:
        p = Path(env)
    else:
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / ".cache")
        p = Path(base) / "tosk-cache"
    p.mkdir(parents=True, exist_ok=True)
    return p
