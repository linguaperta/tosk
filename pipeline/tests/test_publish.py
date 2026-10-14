"""`python -m pipeline publish`: the release index (fields, checksums, URLs), the gh commands, and
the safeguard that keeps restricted courses (hns) out of every release. Never touches the network."""
import hashlib
import json
import sqlite3
import subprocess

import pytest

from pipeline import publish as pub
from pipeline.__main__ import main
from pipeline.compile import compile_pack
from pipeline.content import load_pack
from pipeline.hns.safeguard import RestrictedContentError


def _fake_pack(path, cid, version="1.2.0", **extra):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.unlink(missing_ok=True)
    con = sqlite3.connect(path)
    meta = {"schema_version": "1", "course_id": cid, "version": version, "target": cid,
            "title": json.dumps({"en": cid.upper(), "nl": cid.upper() + "-nl"}),
            "translations": json.dumps(["en", "nl"]), "unverified": "0", **extra}
    con.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
    con.executemany("INSERT INTO meta VALUES (?, ?)", meta.items())
    con.commit()
    con.close()
    return path


@pytest.fixture
def data_repo(tmp_path):
    root = tmp_path / "tosk-data"
    (root / "content").mkdir(parents=True)
    _fake_pack(root / "dist" / "it.sqlite", "it", description=json.dumps({"en": "Learn Italian"}))
    _fake_pack(root / "dist" / "nl.sqlite", "nl", version="1.1.0")
    return root


def test_index_fields_checksums_and_urls(data_repo):
    dist = data_repo / "dist"
    doc = pub.build_index(dist, ["nl", "it"], "packs-20261014", generated_at="2026-10-14T00:00:00Z")
    assert doc["index_version"] == 1
    assert doc["generated_at"] == "2026-10-14T00:00:00Z"
    assert doc["tag"] == "packs-20261014"
    assert [c["id"] for c in doc["courses"]] == ["it", "nl"]
    it = doc["courses"][0]
    data = (dist / "it.sqlite").read_bytes()
    assert it == {
        "id": "it",
        "version": "1.2.0",
        "title": {"en": "IT", "nl": "IT-nl"},
        "description": {"en": "Learn Italian"},
        "target": "it",
        "sources": ["en", "nl"],
        "unverified": False,
        "schema_version": "1",
        "min_app_version": "0.3.0",
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
        "url": "https://github.com/timoverlaan/tosk-data/releases/download/packs-20261014/it.sqlite",
    }
    assert doc["courses"][1]["description"] == {}
    assert pub.stable_index_url() == \
        "https://github.com/timoverlaan/tosk-data/releases/latest/download/index.json"


def test_min_app_version_from_meta_wins(data_repo):
    _fake_pack(data_repo / "dist" / "it.sqlite", "it", min_app_version="0.5.0")
    doc = pub.build_index(data_repo / "dist", ["it", "nl"], "t", min_app_version="0.4.1")
    assert [c["min_app_version"] for c in doc["courses"]] == ["0.5.0", "0.4.1"]


def test_index_of_a_real_compiled_pack(mini_pack_dir, tmp_path):
    out = tmp_path / "dist" / "it.sqlite"
    compile_pack(load_pack(mini_pack_dir), out)
    e = pub.index_entry(out, "packs-x")
    assert e["id"] == "it" and e["schema_version"] == "1" and e["target"] == "it"
    assert e["size"] == out.stat().st_size and len(e["sha256"]) == 64


def test_misnamed_or_missing_packs_are_refused(data_repo):
    dist = data_repo / "dist"
    _fake_pack(dist / "es.sqlite", "it")
    with pytest.raises(ValueError, match="it.sqlite"):
        pub.build_index(dist, ["es"], "t")
    with pytest.raises(FileNotFoundError, match="pipeline build fr"):
        pub.build_index(dist, ["fr"], "t")


def test_hns_is_never_published(data_repo, capsys):
    _fake_pack(data_repo / "dist" / "hns.sqlite", "hns")
    with pytest.raises(RestrictedContentError, match="hns"):
        pub.build_index(data_repo / "dist", ["it", "hns"], "t")
    # A pack that claims another name but holds hns is refused as well.
    _fake_pack(data_repo / "dist" / "xx.sqlite", "hns")
    with pytest.raises((RestrictedContentError, ValueError)):
        pub.index_entry(data_repo / "dist" / "xx.sqlite", "t")
    calls = []
    with pytest.raises(RestrictedContentError):
        pub.publish(["hns"], content_root=str(data_repo / "content"), run=lambda c: calls.append(c))
    assert calls == []
    assert main(["publish", "it", "hns", "--dry-run", "--content-root", str(data_repo / "content")]) == 2
    assert "refusing to publish ['hns']" in capsys.readouterr().err
    assert not (data_repo / "dist" / "index.json").exists()


def test_dry_run_writes_the_index_and_prints_the_commands(data_repo, capsys):
    rc = main(["publish", "it", "nl", "--tag", "packs-20261014", "--dry-run",
               "--content-root", str(data_repo / "content")])
    assert rc == 0
    out = capsys.readouterr().out.splitlines()
    assert out[0] == "gh auth status"
    assert out[1].startswith("gh release create packs-20261014 ")
    assert "it.sqlite" in out[1] and "nl.sqlite" in out[1] and "index.json" in out[1]
    assert "--repo timoverlaan/tosk-data" in out[1] and "--latest" in out[1]
    assert "hns" not in out[1]
    doc = json.loads((data_repo / "dist" / "index.json").read_text(encoding="utf-8"))
    assert doc["tag"] == "packs-20261014" and len(doc["courses"]) == 2


def test_publish_runs_gh_and_stops_when_not_logged_in(data_repo):
    calls = []

    def run(cmd):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 0)

    assert pub.publish(["it"], tag="packs-1", content_root=str(data_repo / "content"), run=run) == 0
    assert calls[0] == ["gh", "auth", "status"]
    create = calls[1]
    assert create[:4] == ["gh", "release", "create", "packs-1"]
    assert create[4].endswith("it.sqlite") and create[5].endswith("index.json")

    calls.clear()
    assert pub.publish(["it"], tag="packs-1", content_root=str(data_repo / "content"),
                       run=lambda c: (calls.append(c), subprocess.CompletedProcess(c, 1))[1]) == 1
    assert len(calls) == 1  # no release without a login


def test_default_tag():
    from datetime import datetime, timezone
    assert pub.default_tag(datetime(2026, 10, 14, tzinfo=timezone.utc)) == "packs-20261014"
