"""Optional private course plugins: `fetch` / `import` for courses whose importers are not public.

Importers aimed at one copyrighted source stay out of the public code (docs/VISION.md). They plug
in here when present; without them the public pipeline works unchanged and simply does not offer
`fetch` / `import` for those courses.

Discovery (both are optional, in this order):

1. `$TOSK_PRIVATE_PIPELINE`: one or more folders (separated by `os.pathsep`). A folder that has a
   `pipeline_private/` subfolder means that subfolder. The folder is put on `sys.path`, and every
   package in it with a `tosk_plugin.py` module is a plugin (`<package>.tosk_plugin`).
2. Installed packages that declare an entry point in the group `tosk.pipeline_plugins`, pointing
   at a module (or a callable) like the above.

A plugin module defines `register(registry)` and calls `registry.course(...)` once per course:

    def register(reg):
        reg.course("xx", fetch=fetch, import_=run_import, restricted=True,
                   local_root=Path(__file__).parents[2] / "local", description="...")

`fetch(force: bool)` downloads into the cache; `import_(content_root: str | None)` writes the
JSONL source pack. `restricted=True` adds the course to `restricted.restricted_courses()`, and
`local_root` is where its content may be written (see restricted.local_root).
"""
from __future__ import annotations

import importlib
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

ENV_VAR = "TOSK_PRIVATE_PIPELINE"
ENTRY_POINT_GROUP = "tosk.pipeline_plugins"
PLUGIN_MODULE = "tosk_plugin"
entry_points_enabled = True   # the public tests switch installed plugins off


@dataclass
class CoursePlugin:
    code: str
    fetch: Callable[..., object] | None = None
    import_: Callable[..., object] | None = None
    restricted: bool = False
    local_root: Path | None = None
    description: str = ""
    origin: str = ""


@dataclass
class Registry:
    courses: dict[str, CoursePlugin] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    _origin: str = ""

    def course(self, code: str, *, fetch=None, import_=None, restricted: bool = False,
               local_root: str | os.PathLike | None = None, description: str = "") -> CoursePlugin:
        if code in self.courses:
            raise ValueError(f"course '{code}' registered twice ({self.courses[code].origin}, {self._origin})")
        c = CoursePlugin(code, fetch, import_, restricted, Path(local_root) if local_root else None,
                         description, self._origin)
        self.courses[code] = c
        return c


_loaded: Registry | None = None


def plugin_dirs() -> list[Path]:
    out = []
    for raw in (os.environ.get(ENV_VAR) or "").split(os.pathsep):
        if not raw.strip():
            continue
        p = Path(raw.strip()).expanduser().resolve()
        if (p / "pipeline_private").is_dir():
            p = p / "pipeline_private"
        out.append(p)
    return out


def _register_module(reg: Registry, target, origin: str) -> None:
    reg._origin = origin
    fn = getattr(target, "register", None) or (target if callable(target) else None)
    if fn is None:
        reg.errors.append(f"{origin}: no register(registry) function")
        return
    fn(reg)


def _discover() -> Registry:
    reg = Registry()
    seen: set[str] = set()      # a plugin both on the path and pip-installed registers once
    for d in plugin_dirs():
        if not d.is_dir():
            reg.errors.append(f"${ENV_VAR}: {d} is not a folder")
            continue
        if str(d) not in sys.path:
            sys.path.insert(0, str(d))
        for pkg in sorted(d.iterdir()):
            if (pkg / "__init__.py").is_file() and (pkg / f"{PLUGIN_MODULE}.py").is_file():
                name = f"{pkg.name}.{PLUGIN_MODULE}"
                seen.add(name)
                try:
                    _register_module(reg, importlib.import_module(name), name)
                except Exception as e:   # a broken plugin must not break the public commands
                    reg.errors.append(f"{name}: {type(e).__name__}: {e}")
    eps = []
    if entry_points_enabled:
        from importlib.metadata import entry_points
        eps = entry_points(group=ENTRY_POINT_GROUP)
    for ep in eps:
        if ep.value.split(":")[0] in seen:
            continue
        seen.add(ep.value.split(":")[0])
        try:
            _register_module(reg, ep.load(), f"entry point {ep.name}")
        except Exception as e:
            reg.errors.append(f"entry point {ep.name}: {type(e).__name__}: {e}")
    for e in reg.errors:
        print(f"warning: pipeline plugin: {e}", file=sys.stderr)
    return reg


def load_plugins() -> Registry:
    """The registered course plugins (discovered once per process)."""
    global _loaded
    if _loaded is None:
        _loaded = _discover()
    return _loaded


def reset() -> None:
    """Forget the discovered plugins (tests, or after changing $TOSK_PRIVATE_PIPELINE)."""
    global _loaded
    _loaded = None


def course_plugin(code: str) -> CoursePlugin | None:
    return load_plugins().courses.get(code)


def describe() -> str:
    """One line per plugin course, for --help texts."""
    cs = load_plugins().courses
    if not cs:
        return f"no private course plugins (set ${ENV_VAR} to add some)"
    return "private course plugins: " + "; ".join(
        f"{c.code} ({c.description or c.origin})" for c in cs.values())
