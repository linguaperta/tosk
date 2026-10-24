"""Restricted courses (built from all-rights-reserved sources, e.g. `hns`): the pipeline must refuse
to write them anywhere public (the content repo, app/assets) and only write below the local folder.
Also the private course plugin point (plugins.py) and the desktop pack copy (install.py)."""
import json
import sqlite3
import sys
import textwrap

import pytest

from pipeline import plugins, restricted
from pipeline.__main__ import main
from pipeline.build import build
from pipeline.install import install_desktop
from pipeline.paths import APP_COURSES_DIR, DEFAULT_DATA_REPO, REPO_ROOT
from pipeline.restricted import RestrictedContentError, check_destination


@pytest.fixture
def local(tmp_path, monkeypatch):
    monkeypatch.setenv("TOSK_LOCAL", str(tmp_path / "local"))
    monkeypatch.delenv("TOSK_CONTENT", raising=False)
    return tmp_path / "local"


def test_restricted_may_only_go_below_local(local, tmp_path):
    assert check_destination("hns", local / "content" / "hns") == (local / "content" / "hns").resolve()
    assert check_destination("hns", local / "dist" / "hns.sqlite")
    with pytest.raises(RestrictedContentError, match="tosk-data"):
        check_destination("hns", DEFAULT_DATA_REPO / "content" / "hns")
    with pytest.raises(RestrictedContentError, match="tosk-data"):
        check_destination("hns", DEFAULT_DATA_REPO / "dist" / "hns.sqlite")
    with pytest.raises(RestrictedContentError, match="app"):
        check_destination("hns", APP_COURSES_DIR / "hns.sqlite")
    with pytest.raises(RestrictedContentError, match="local folder"):
        check_destination("hns", REPO_ROOT / "pipeline" / "hns.sqlite")
    with pytest.raises(RestrictedContentError, match="local folder"):
        check_destination("hns", tmp_path / "elsewhere" / "hns.sqlite")


def test_local_inside_a_public_repo_is_still_refused(tmp_path, monkeypatch):
    monkeypatch.setenv("TOSK_LOCAL", str(DEFAULT_DATA_REPO / "local"))
    with pytest.raises(RestrictedContentError, match="tosk-data"):
        check_destination("hns", DEFAULT_DATA_REPO / "local" / "content" / "hns")


def test_other_courses_are_unrestricted(local):
    assert check_destination("it", DEFAULT_DATA_REPO / "content" / "it")
    assert check_destination("nl", APP_COURSES_DIR / "nl.sqlite")


def test_extra_restricted_courses_from_the_environment(local, monkeypatch):
    monkeypatch.setenv("TOSK_RESTRICTED_COURSES", "xx, yy")
    assert {"hns", "xx", "yy"} <= restricted.restricted_courses()
    with pytest.raises(RestrictedContentError):
        check_destination("xx", APP_COURSES_DIR / "xx.sqlite")


def test_build_refuses_to_bundle_or_publish_restricted(local, monkeypatch):
    with pytest.raises(RestrictedContentError, match="install"):
        build(["hns"], install=True)
    with pytest.raises(RestrictedContentError):
        build(["hns"], content_root=str(DEFAULT_DATA_REPO / "content"))


def test_main_checkout_root_from_a_worktree(tmp_path):
    wt = tmp_path / "tosk" / ".claude" / "worktrees" / "agent-x"
    wt.mkdir(parents=True)
    assert restricted.main_checkout_root(wt) == (tmp_path / "tosk").resolve()
    assert restricted.main_checkout_root(tmp_path / "tosk") == (tmp_path / "tosk").resolve()


# ------------------------------------------------------------------------------- plugin point
def test_no_plugins_means_no_restricted_import(capsys):
    assert plugins.load_plugins().courses == {}
    assert main(["import", "hns"]) == 2
    assert "private course plugin" in capsys.readouterr().err
    assert main(["fetch", "hns"]) == 2


def _fake_plugin(root, code="zz", restricted_=True):
    pkg = root / "pipeline_private" / "fake_course"
    pkg.mkdir(parents=True)
    (pkg / "__init__.py").write_text("", encoding="utf-8")
    (pkg / "tosk_plugin.py").write_text(textwrap.dedent(f'''
        from pathlib import Path
        CALLS = []

        def register(reg):
            reg.course("{code}", fetch=lambda force=False: CALLS.append(("fetch", force)),
                       import_=lambda content_root=None: CALLS.append(("import", content_root)),
                       restricted={restricted_}, local_root=Path(__file__).parents[2] / "local",
                       description="a fake course")
    '''), encoding="utf-8")
    return pkg


def test_plugin_discovery_and_dispatch(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(sys, "path", list(sys.path))
    _fake_plugin(tmp_path)
    monkeypatch.setenv(plugins.ENV_VAR, str(tmp_path))   # the repo root: pipeline_private/ is found
    plugins.reset()
    c = plugins.course_plugin("zz")
    assert c is not None and c.restricted and c.origin == "fake_course.tosk_plugin"
    assert "zz" in restricted.restricted_courses()
    assert restricted.local_root("zz") == (tmp_path / "local").resolve()
    assert check_destination("zz", tmp_path / "local" / "content" / "zz")
    with pytest.raises(RestrictedContentError):
        check_destination("zz", APP_COURSES_DIR / "zz.sqlite")
    assert main(["fetch", "zz", "--force"]) == 0
    assert main(["import", "zz", "--content-root", "somewhere"]) == 0
    import fake_course.tosk_plugin as fp
    assert fp.CALLS == [("fetch", True), ("import", "somewhere")]
    with pytest.raises(SystemExit):
        main(["import", "--help"])
    assert "zz (a fake course)" in capsys.readouterr().out
    monkeypatch.setenv("TOSK_LOCAL", str(tmp_path / "elsewhere"))
    assert restricted.local_root("zz") == (tmp_path / "elsewhere").resolve()


def test_broken_plugin_only_warns(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(sys, "path", list(sys.path))
    pkg = tmp_path / "broken_course"
    pkg.mkdir()
    (pkg / "__init__.py").write_text("", encoding="utf-8")
    (pkg / "tosk_plugin.py").write_text("raise ImportError('missing dependency')\n", encoding="utf-8")
    monkeypatch.setenv(plugins.ENV_VAR, str(tmp_path))
    plugins.reset()
    assert plugins.load_plugins().courses == {}
    assert "missing dependency" in capsys.readouterr().err


# ------------------------------------------------------------------------------ desktop install
def test_install_desktop(tmp_path):
    pack = tmp_path / "x.sqlite"
    con = sqlite3.connect(pack)
    con.execute("CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)")
    con.executemany("INSERT INTO meta VALUES (?, ?)", [("course_id", "hns"), ("version", "0.2.0"),
                    ("title", '{"nl":"Sarnami"}'), ("schema_version", "1"), ("unverified", "1")])
    con.commit()
    con.close()
    dest = tmp_path / "appdata" / "courses"
    dest.mkdir(parents=True)
    (dest / "packs.json").write_text('{"packs": {"it": {"version": "1.0.0", "title": {"en": "Italian"}, '
                                     '"origin": "bundled", "schemaVersion": 1, "unverified": false}}}', encoding="utf-8")
    target = install_desktop(pack, dest)
    assert target == dest / "hns.sqlite" and target.exists()
    m = json.loads((dest / "packs.json").read_text(encoding="utf-8"))["packs"]
    assert set(m) == {"it", "hns"}
    assert m["hns"] == {"version": "0.2.0", "title": {"nl": "Sarnami"}, "origin": "local", "schemaVersion": 1,
                        "unverified": True}


def test_install_desktop_refuses_a_path_as_course_id(tmp_path):
    pack = _meta_pack(tmp_path / "evil.sqlite", "../progress")
    with pytest.raises(SystemExit, match="course id"):
        install_desktop(pack, tmp_path / "courses")
    assert not (tmp_path / "progress.sqlite").exists()


# --------------------------------------------------------------- meta.restricted (stamped packs)
def _meta_pack(path, cid, **extra):
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(path)
    meta = {"schema_version": "1", "course_id": cid, "version": "1.0.0", "target": cid,
            "title": json.dumps({"en": cid}), "translations": json.dumps(["en"]), "unverified": "0", **extra}
    con.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
    con.executemany("INSERT INTO meta VALUES (?, ?)", meta.items())
    con.commit()
    con.close()
    return path


def test_compile_stamps_restricted_courses(mini_pack_dir, tmp_path, monkeypatch):
    from pipeline.compile import compile_pack
    from pipeline.content import load_pack
    pack = load_pack(mini_pack_dir)
    compile_pack(pack, tmp_path / "open" / "it.sqlite")
    assert restricted.read_meta(tmp_path / "open" / "it.sqlite").get("restricted") is None
    monkeypatch.setenv("TOSK_RESTRICTED_COURSES", pack.code)
    compile_pack(pack, tmp_path / "closed" / "it.sqlite")
    assert restricted.read_meta(tmp_path / "closed" / "it.sqlite")["restricted"] == "1"


def test_a_stamped_pack_is_refused_under_any_id(tmp_path):
    import hashlib

    from pipeline import publish as pub
    from pipeline import webpacks
    # A restricted pack rebuilt (or renamed) as an ordinary course id.
    dist = tmp_path / "dist"
    _meta_pack(dist / "it.sqlite", "it", restricted="1")
    with pytest.raises(RestrictedContentError, match="meta.restricted"):
        pub.build_index(dist, ["it"], "packs-x")
    assert restricted.pack_restriction(_meta_pack(tmp_path / "ok" / "it.sqlite", "it")) is None
    assert "restricted course" in restricted.pack_restriction(_meta_pack(tmp_path / "h" / "x.sqlite", "hns"))

    # The mirror checks the downloaded pack itself, not just the index id.
    rel = tmp_path / "rel"
    _meta_pack(rel / "it.sqlite", "it", restricted="1")
    data = (rel / "it.sqlite").read_bytes()
    doc = {"index_version": 1, "courses": [{"id": "it", "version": "1.0.0", "url": "it.sqlite",
                                            "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}]}
    (rel / "index.json").write_text(json.dumps(doc), encoding="utf-8")
    with pytest.raises(RestrictedContentError, match="mirror"):
        webpacks.mirror(tmp_path / "site", str(rel / "index.json"))


def test_build_install_refuses_a_stamped_pack(mini_pack_dir, tmp_path, monkeypatch):
    # A stamped pack under an ordinary id (e.g. a restricted course's copy built as "it"):
    # --install refuses the compiled output itself.
    import shutil

    from pipeline import build as build_mod
    real = build_mod.compile_pack

    def stamped(pack, out, built_at=None):
        stats = real(pack, out, built_at)
        con = sqlite3.connect(out)
        con.execute("INSERT OR REPLACE INTO meta VALUES ('restricted', '1')")
        con.commit()
        con.close()
        return stats

    monkeypatch.setattr(build_mod, "compile_pack", stamped)
    installed = tmp_path / "assets"
    monkeypatch.setattr(build_mod, "APP_COURSES_DIR", installed)
    content = tmp_path / "data" / "content"
    shutil.copytree(mini_pack_dir, content / "it")
    with pytest.raises(RestrictedContentError, match="--install"):
        build_mod.build(["it"], content_root=str(content), install=True, quiet=True)
    assert not installed.exists()


def _vcs(repo, *args):
    import subprocess
    subprocess.run(["gi" "t", *args], cwd=repo, check=True, capture_output=True)


def test_tracked_files_check(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    _vcs(repo, "init", "-q")
    _meta_pack(repo / "app" / "assets" / "courses" / "it.sqlite", "it")
    (repo / "docs").mkdir()
    (repo / "docs" / "hns_notes.md").write_text("only the name mentions it", encoding="utf-8")
    _vcs(repo, "add", "-A")
    assert restricted.check_tracked_packs(repo) == []
    _meta_pack(repo / "app" / "assets" / "courses" / "es.sqlite", "es", restricted="1")
    _meta_pack(repo / "x" / "nl.sqlite", "hns")
    (repo / "content" / "hns").mkdir(parents=True)
    (repo / "content" / "hns" / "course.yaml").write_text("id: hns\n", encoding="utf-8")
    _vcs(repo, "add", "-A")
    problems = restricted.check_tracked_packs(repo)
    assert any("es.sqlite" in p and "meta.restricted" in p for p in problems)
    assert any("nl.sqlite" in p and "restricted course" in p for p in problems)
    assert any("content/hns/course.yaml" in p for p in problems)
    assert len(problems) == 3


def test_this_repository_tracks_no_restricted_content():
    assert restricted.check_tracked_packs() == []
