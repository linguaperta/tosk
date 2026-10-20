"""Web packs (v0.7): deterministic gzip, the optional index fields, the Pages mirror and
`publish --gz`. Never touches the network (the mirror's fetch is faked)."""
import gzip
import hashlib
import json
import shutil
import sqlite3

import pytest

from pipeline import publish as pub
from pipeline import webpacks
from pipeline.hns.safeguard import RestrictedContentError



def _fake_pack(path, cid, version="1.2.0"):
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(path)
    meta = {"schema_version": "1", "course_id": cid, "version": version, "target": cid,
            "title": json.dumps({"en": cid.upper()}), "translations": json.dumps(["en"]), "unverified": "0"}
    con.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
    con.executemany("INSERT INTO meta VALUES (?, ?)", meta.items())
    con.commit()
    con.close()
    return path


def _sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def test_gzip_is_deterministic_and_round_trips(tmp_path):
    src = _fake_pack(tmp_path / "it.sqlite", "it")
    a = webpacks.gzip_pack(src, tmp_path / "a" / "it.sqlite.gz")
    b = webpacks.gzip_pack(src, tmp_path / "b" / "it.sqlite.gz")
    assert a.read_bytes() == b.read_bytes()
    assert gzip.decompress(a.read_bytes()) == src.read_bytes()
    f = webpacks.web_fields(a, "it.sqlite.gz")
    assert f == {"web_url": "it.sqlite.gz", "gz_sha256": _sha(a), "gz_size": a.stat().st_size}


def _release(tmp_path):
    rel = tmp_path / "release"
    it = _fake_pack(rel / "it.sqlite", "it")
    nl = _fake_pack(rel / "nl.sqlite", "nl", version="1.1.0")
    doc = pub.build_index(rel, ["it", "nl"], "packs-20261020", generated_at="2026-10-20T00:00:00Z")
    (rel / "index.json").write_text(json.dumps(doc))
    return rel, {"it": it, "nl": nl}, doc


def test_mirror_downloads_verifies_and_adds_web_fields(tmp_path):
    rel, files, doc = _release(tmp_path)
    fetched = []

    def fetch(url, dst):
        fetched.append(url)
        name = url.rsplit("/", 1)[-1]
        shutil.copy(rel / name, dst)

    out = tmp_path / "site" / "packs"
    got = webpacks.mirror(out, "https://example.test/releases/latest/download/index.json", fetch=fetch)
    assert fetched[0].endswith("/index.json")
    assert {f.rsplit("/", 1)[-1] for f in fetched[1:]} == {"it.sqlite", "nl.sqlite"}
    written = json.loads((out / "index.json").read_text(encoding="utf-8"))
    assert written == got
    assert sorted(p.name for p in out.iterdir()) == ["index.json", "it.sqlite.gz", "nl.sqlite.gz"]
    for c in written["courses"]:
        gz = out / c["web_url"]
        assert c["gz_sha256"] == _sha(gz) and c["gz_size"] == gz.stat().st_size
        # The uncompressed checksum stays the one the app verifies after decompressing.
        assert hashlib.sha256(gzip.decompress(gz.read_bytes())).hexdigest() == c["sha256"]
        # Native downloads are unchanged.
        assert c["url"] == next(x["url"] for x in doc["courses"] if x["id"] == c["id"])
    assert written["tag"] == "packs-20261020"


def test_mirror_refuses_a_corrupt_download_and_restricted_courses(tmp_path):
    rel, files, doc = _release(tmp_path)

    def bad_fetch(url, dst):
        if url.endswith("index.json"):
            shutil.copy(rel / "index.json", dst)
        else:
            dst.write_bytes(b"not a pack")

    with pytest.raises(ValueError, match="does not match"):
        webpacks.mirror(tmp_path / "out", "https://example.test/index.json", fetch=bad_fetch)

    doc["courses"][0]["id"] = "hns"
    (rel / "index.json").write_text(json.dumps(doc))
    with pytest.raises(RestrictedContentError):
        webpacks.mirror(tmp_path / "out2", str(rel / "index.json"))


def test_publish_gz_adds_fields_and_assets(tmp_path):
    rel, files, _ = _release(tmp_path)
    doc = pub.build_index(rel, ["it", "nl"], "packs-20261020", gz=True)
    for c in doc["courses"]:
        assert c["web_url"] == f"https://github.com/timoverlaan/tosk-data/releases/download/packs-20261020/{c['id']}.sqlite.gz"
        assert c["gz_sha256"] == _sha(rel / f"{c['id']}.sqlite.gz")
    cmd = pub.gh_commands(rel, doc)[1]
    assert str(rel / "it.sqlite.gz") in cmd and str(rel / "nl.sqlite.gz") in cmd
    plain = pub.build_index(rel, ["it"], "packs-20261020")
    assert "web_url" not in plain["courses"][0]
