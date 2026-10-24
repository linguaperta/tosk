"""Keep restricted course content out of every published location.

Some courses are built from sources whose licence forbids redistribution (all rights reserved).
Their JSONL source, ids, samples and compiled `{code}.sqlite` may only be written below a local
folder that is never published (`local_root()`): never into the public content repository, never
into `app/assets/` (which would ship it in every app build) and never anywhere else inside the
public repositories. `publish`, `mirror` and `build --install` refuse these courses outright.

Compiled packs of restricted courses also carry `meta.restricted = 1` (stamped by `compile.py`), so
`publish`, `mirror` and `build --install` refuse such a pack whatever its course id or file name
(`refuse_restricted_pack`), and CI fails if a tracked `*.sqlite` carries it (`check_tracked_packs`).

A course is restricted when it is listed in `BUILTIN_RESTRICTED`, in `$TOSK_RESTRICTED_COURSES`
(comma-separated), or by a private pipeline plugin (`plugins.py`). The list stays here, in the
public code, so the protection holds also when the private plugin is not installed.
"""
from __future__ import annotations

import os
from pathlib import Path

from .paths import APP_COURSES_DIR, DEFAULT_DATA_REPO, REPO_ROOT

# Course codes (languages) whose packs are built from all-rights-reserved sources. No source
# content lives in the public code; the importers are private plugins.
BUILTIN_RESTRICTED = frozenset({"hns"})
# Kept for callers that read the constant; prefer restricted_courses(), which adds the plugins.
RESTRICTED_COURSES = BUILTIN_RESTRICTED


class RestrictedContentError(RuntimeError):
    pass


def restricted_courses() -> set[str]:
    out = set(BUILTIN_RESTRICTED)
    env = os.environ.get("TOSK_RESTRICTED_COURSES", "")
    out |= {c.strip() for c in env.split(",") if c.strip()}
    from .plugins import load_plugins
    out |= {code for code, c in load_plugins().courses.items() if c.restricted}
    return out


def is_restricted(course: str) -> bool:
    return course in restricted_courses()


def main_checkout_root(repo_root: Path = REPO_ROOT) -> Path:
    """The main checkout, also when running from a git worktree in .claude/worktrees/."""
    parts = repo_root.resolve().parts
    for i in range(len(parts) - 1):
        if parts[i] == ".claude" and parts[i + 1] == "worktrees":
            return Path(*parts[:i])
    return repo_root.resolve()


def local_root(course: str | None = None) -> Path:
    """Where restricted content may be written.

    Order: `$TOSK_LOCAL`, the `local_root` a private plugin declares for `course`, then
    `<main checkout>/local` (git-ignored).
    """
    env = os.environ.get("TOSK_LOCAL")
    if env:
        return Path(env).resolve()
    if course is not None:
        from .plugins import course_plugin
        plugin = course_plugin(course)
        if plugin is not None and plugin.local_root is not None:
            return Path(plugin.local_root).resolve()
    return main_checkout_root() / "local"


def local_content_root(course: str | None = None) -> Path:
    return local_root(course) / "content"


def local_dist(course: str | None = None) -> Path:
    return local_root(course) / "dist"


def _inside(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def forbidden_roots() -> list[tuple[Path, str]]:
    roots = [(DEFAULT_DATA_REPO, "the public tosk-data repository"),
             (REPO_ROOT.parent / "tosk-data", "the public tosk-data repository"),
             # a checkout under the repository's name from before the rename (split so a
             # repo-wide rename never touches it)
             (REPO_ROOT.parent / ("due" "lingo-data"), "the public tosk-data repository"),
             (APP_COURSES_DIR, "app/assets/courses (bundled into every app build)"),
             (REPO_ROOT / "app", "the app folder (bundled into app builds)"),
             (main_checkout_root() / "app", "the app folder (bundled into app builds)")]
    env = os.environ.get("TOSK_CONTENT")
    if env:
        roots.append((Path(env).parent, "the configured public content repository ($TOSK_CONTENT)"))
    return roots


def check_destination(course: str, path: str | os.PathLike) -> Path:
    """Raise RestrictedContentError unless `path` may receive content of `course`."""
    p = Path(path).resolve()
    if not is_restricted(course):
        return p
    for root, what in forbidden_roots():
        if _inside(p, root):
            raise RestrictedContentError(
                f"refusing to write '{course}' content to {p}: that is inside {what}. Its sources are "
                f"all rights reserved; keep it under {local_root(course)}.")
    if not _inside(p, local_root(course)):
        raise RestrictedContentError(
            f"refusing to write '{course}' content to {p}: it must stay below the local folder "
            f"{local_root(course)} (set $TOSK_LOCAL to move it).")
    return p


def refuse_restricted(langs, action: str) -> None:
    """Raise for any restricted course in `langs` (publish, mirror, --install)."""
    bad = sorted(restricted_courses() & set(langs))
    if bad:
        raise RestrictedContentError(
            f"refusing to {action} {bad}: restricted content (all rights reserved) must never be "
            "uploaded or bundled anywhere public; it stays local")


# ------------------------------------------------------------------ compiled packs (meta.restricted)
RESTRICTED_META_KEY = "restricted"


def read_meta(path: str | os.PathLike) -> dict[str, str]:
    """The `meta` table of a compiled pack ({} when it has none or isn't a database)."""
    import sqlite3
    try:
        con = sqlite3.connect(f"file:{Path(path).resolve().as_posix()}?mode=ro", uri=True)
    except sqlite3.Error:
        return {}
    try:
        return {str(k): str(v) for k, v in con.execute("SELECT key, value FROM meta")}
    except sqlite3.Error:
        return {}
    finally:
        con.close()


def pack_restriction(path: str | os.PathLike) -> str | None:
    """Why the compiled pack at `path` is restricted, or None: `meta.restricted` is set, or its
    `course_id` is a restricted course."""
    meta = read_meta(path)
    if meta.get(RESTRICTED_META_KEY, "").strip() not in ("", "0"):
        return f"meta.{RESTRICTED_META_KEY} = {meta[RESTRICTED_META_KEY]}"
    cid = meta.get("course_id")
    if cid and is_restricted(cid):
        return f"course_id {cid!r} is a restricted course"
    return None


def refuse_restricted_pack(path: str | os.PathLike, action: str) -> None:
    """Raise unless the compiled pack at `path` may be published, mirrored or bundled."""
    why = pack_restriction(path)
    if why:
        raise RestrictedContentError(
            f"refusing to {action} {Path(path).name}: {why}. Restricted content (all rights reserved) "
            "must never be uploaded or bundled anywhere public; it stays local")


def check_tracked_packs(repo: str | os.PathLike = REPO_ROOT) -> list[str]:
    """Problems with the files git tracks in `repo` (for CI): a `*.sqlite` that is a restricted pack,
    and any path with a folder or file named after a restricted course."""
    import subprocess
    files = subprocess.run(["git", "ls-files", "-z"], cwd=repo, capture_output=True, check=True)
    problems = []
    codes = restricted_courses()
    for name in files.stdout.decode("utf-8").split("\0"):
        if not name:
            continue
        path = Path(name)
        hit = sorted(codes & ({p.lower() for p in path.parts[:-1]} | {path.name.split(".")[0].lower()}))
        if hit:
            problems.append(f"{name}: the path names restricted course {hit[0]!r}")
        if name.lower().endswith(".sqlite"):
            why = pack_restriction(Path(repo) / name)
            if why:
                problems.append(f"{name}: {why}")
    return problems


def main() -> int:
    """`python -m pipeline.restricted`: the CI check over the tracked files (exit 1 on a problem)."""
    import sys
    problems = check_tracked_packs()
    for p in problems:
        print(f"error: {p}", file=sys.stderr)
    if not problems:
        print("ok: no restricted content is tracked", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
