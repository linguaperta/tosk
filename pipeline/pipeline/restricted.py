"""Keep restricted course content out of every published location.

Some courses are built from sources whose licence forbids redistribution (all rights reserved).
Their JSONL source, ids, samples and compiled `{code}.sqlite` may only be written below a local
folder that is never published (`local_root()`): never into the public content repository, never
into `app/assets/` (which would ship it in every app build) and never anywhere else inside the
public repositories. `publish`, `mirror` and `build --install` refuse these courses outright.

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

    Order: `$TOSK_LOCAL` (or the older `$TOSK_LOCAL`), the `local_root` a private plugin
    declares for `course`, then `<main checkout>/local` (git-ignored).
    """
    env = os.environ.get("TOSK_LOCAL") or os.environ.get("TOSK_LOCAL")
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
             (REPO_ROOT.parent / "tosk-data", "the public tosk-data repository"),
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
