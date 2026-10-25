"""Copy a locally built pack into the desktop app's pack folder (`build <code> --desktop`).

The app lists every `{id}.sqlite` in `{app support dir}/courses/` (LocalPackSource), so a pack that
must not be bundled (a restricted course, see restricted.py) can be dropped there. On Windows that folder is
`%APPDATA%\\linguaperta\\tosk\\courses`. The pack is also registered in the folder's
`packs.json`, so app builds from before the folder scan list it too. The user's own app data is no
repository, so this does not publish anything.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sqlite3
import sys
from pathlib import Path

SAFE_COURSE_ID = re.compile(r"\A[a-z][a-z0-9_-]{0,39}(\.[a-z0-9][a-z0-9_-]{0,39})?\Z")
WINDOWS_DEVICE_NAMES = {"con", "prn", "aux", "nul", *(f"com{i}" for i in range(10)), *(f"lpt{i}" for i in range(10))}


def desktop_courses_dir() -> Path | None:
    if sys.platform == "win32" and os.environ.get("APPDATA"):
        return Path(os.environ["APPDATA"]) / "linguaperta" / "tosk" / "courses"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "org.linguaperta.tosk" / "courses"
    if sys.platform.startswith("linux"):
        return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share") / "org.linguaperta.tosk" / "courses"
    return None


def install_desktop(pack: Path, dest: Path | None = None) -> Path:
    dest = dest or desktop_courses_dir()
    if dest is None:
        raise SystemExit("unknown platform: copy the pack into the app's courses/ folder by hand (docs/data-layer.md, packs copied in by hand)")
    dest.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(f"file:{pack}?mode=ro", uri=True)
    try:
        meta = dict(con.execute("SELECT key, value FROM meta"))
    finally:
        con.close()
    cid = meta["course_id"]
    # The id names the file: the app's rule (app/lib/core/course_id.dart), never a path.
    if not SAFE_COURSE_ID.match(cid) or cid.split(".")[0] in WINDOWS_DEVICE_NAMES:
        raise SystemExit(f"{pack}: meta.course_id {cid!r} is not a valid course id")
    target = dest / f"{cid}.sqlite"
    shutil.copyfile(pack, target)
    mp = dest / "packs.json"
    manifest = json.loads(mp.read_text(encoding="utf-8")) if mp.exists() else {"packs": {}}
    manifest.setdefault("packs", {})[cid] = {
        "version": meta["version"], "title": json.loads(meta["title"]), "origin": "local",
        "schemaVersion": int(str(meta["schema_version"]).split(".")[0]), "unverified": meta.get("unverified") == "1"}
    mp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return target
