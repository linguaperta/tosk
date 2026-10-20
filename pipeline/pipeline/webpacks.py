"""Gzipped packs for the web app (v0.7).

The web app is served from GitHub Pages with a pack mirror on the same origin (no CORS problem
with GitHub's release-asset redirects). Packs there are gzipped (`gzip -9`: ~19 MB -> ~5 MB) and
the index gets three optional fields per course, which older apps ignore:

    "web_url":   "it.sqlite.gz"   gzipped pack, absolute or relative to the index URL
    "gz_sha256": "..."            sha256 of the .gz file
    "gz_size":   5123456          size of the .gz file in bytes

`sha256` and `size` stay those of the uncompressed .sqlite, which the app checks after
decompressing, as for a native download. Native apps keep downloading `url` (GitHub Releases).

* `python -m pipeline mirror --out site/packs` (used by the Pages workflow): reads the release
  index (default: the stable `releases/latest/download/index.json`), downloads every pack,
  verifies it, writes `<id>.sqlite.gz` and an `index.json` with the web fields (relative
  `web_url`). Standard library only.
* `python -m pipeline publish ... --gz` also writes `dist/<id>.sqlite.gz`, adds the web fields
  (absolute release URLs) and uploads the .gz files with the release.
"""
from __future__ import annotations

import gzip
import hashlib
import json
import shutil
import sys
import urllib.request
from pathlib import Path
from typing import Callable

from .hns.safeguard import RESTRICTED_COURSES, RestrictedContentError

STABLE_INDEX_URL = "https://github.com/timoverlaan/tosk-data/releases/latest/download/index.json"


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def gzip_pack(src: Path, dst: Path) -> Path:
    """Deterministic `gzip -9` (no file name, mtime 0), so the same pack gives the same bytes."""
    dst = Path(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    with open(src, "rb") as fin, open(dst, "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as gz:
            shutil.copyfileobj(fin, gz, 1 << 20)
    return dst


def web_fields(gz_path: Path, web_url: str) -> dict:
    gz_path = Path(gz_path)
    return {"web_url": web_url, "gz_sha256": _sha256(gz_path), "gz_size": gz_path.stat().st_size}


def _download(url: str, dst: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "tosk-pipeline"})
    with urllib.request.urlopen(req, timeout=120) as r, open(dst, "wb") as f:
        shutil.copyfileobj(r, f, 1 << 20)


def _read_index(source: str, fetch: Callable[[str, Path], None], tmp: Path) -> dict:
    p = Path(source)
    if not source.startswith(("http://", "https://")) and p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    dst = tmp / "index.source.json"
    fetch(source, dst)
    return json.loads(dst.read_text(encoding="utf-8"))


def mirror(out: Path, index: str = STABLE_INDEX_URL,
           fetch: Callable[[str, Path], None] = _download) -> dict:
    """Builds the web pack mirror in [out]: `<id>.sqlite.gz` per course plus `index.json`."""
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    tmp = out / ".download"
    tmp.mkdir(exist_ok=True)
    try:
        local = not index.startswith(("http://", "https://"))
        doc = _read_index(index, fetch, tmp)
        courses = []
        for c in doc.get("courses", []):
            cid = c["id"]
            if cid in RESTRICTED_COURSES:
                raise RestrictedContentError(f"refusing to mirror {cid}: restricted content")
            raw = tmp / f"{cid}.sqlite"
            src = c["url"]
            beside = Path(index).parent / Path(src).name if local else None
            if beside is not None and beside.exists():
                # A local index (tests, `publish --dry-run` in dist/): use the packs next to it.
                raw = beside
            elif not src.startswith(("http://", "https://")):
                raise FileNotFoundError(f"{cid}: {src} not found next to {index}")
            else:
                fetch(src, raw)
            if _sha256(raw) != c["sha256"] or raw.stat().st_size != c["size"]:
                raise ValueError(f"{cid}: downloaded pack does not match the index (sha256/size)")
            gz = gzip_pack(raw, out / f"{cid}.sqlite.gz")
            courses.append({**c, **web_fields(gz, gz.name)})
            print(f"  {cid} {c['version']}: {c['size']:>10} -> {gz.stat().st_size:>9} bytes", file=sys.stderr)
        doc = {**doc, "courses": courses}
        (out / "index.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n",
                                        encoding="utf-8", newline="\n")
        return doc
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
