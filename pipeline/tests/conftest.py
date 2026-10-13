"""Shared fixtures. All tests run offline on files in tests/fixtures."""
from __future__ import annotations

import bz2
import shutil
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture
def mini_pack_dir(tmp_path) -> Path:
    """A writable copy of the tiny hand-written Italian course."""
    dst = tmp_path / "content" / "it"
    shutil.copytree(FIXTURES / "mini" / "it", dst)
    return dst


@pytest.fixture
def import_env(tmp_path, monkeypatch) -> Path:
    """Cache + content root for an offline importer run; returns the content root."""
    cache = tmp_path / "cache"
    shutil.copytree(FIXTURES / "cache", cache)
    tdir = cache / "tatoeba"
    tdir.mkdir()
    for src in (FIXTURES / "tatoeba").glob("*.tsv"):
        with open(src, "rb") as f, bz2.open(tdir / (src.name + ".bz2"), "wb") as out:
            out.write(f.read())
    monkeypatch.setenv("TOSK_CACHE", str(cache))
    content = tmp_path / "content"
    shutil.copytree(FIXTURES / "import_content", content)
    return content
