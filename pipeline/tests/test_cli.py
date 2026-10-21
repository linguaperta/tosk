"""The `pack` toolkit CLI (pipeline/cli.py, docs/pack-format.md): new -> validate -> build -> info in a
temp dir, the catalog, publish's explicit flags, and the packaging of the console script. Offline;
nothing is ever published."""
import json
import re
import sqlite3
import tomllib
from pathlib import Path, PurePosixPath

import pytest
import yaml

from pipeline import cli
from pipeline import publish as pub
from pipeline.content import load_pack, read_jsonl, write_jsonl
from pipeline.validate import validate

PIPELINE_DIR = Path(__file__).resolve().parents[1]


@pytest.fixture
def scaffolded(tmp_path):
    d = tmp_path / "packs" / "xx"
    assert cli.main(["new", "xx", str(d), "--title", "Demo course", "--author", "Ada"]) == 0
    return d


def test_round_trip_new_validate_build_info(scaffolded, tmp_path, capsys):
    assert cli.main(["validate", str(scaffolded)]) == 0
    out = tmp_path / "dist" / "xx.sqlite"
    assert cli.main(["build", str(scaffolded), "-o", str(out)]) == 0
    assert out.is_file()
    capsys.readouterr()
    assert cli.main(["info", str(out), "--json"]) == 0
    info = json.loads(capsys.readouterr().out)
    assert info["course_id"] == "xx" and info["version"] == "0.1.0" and info["target"] == "xx"
    assert info["title"] == {"en": "Demo course"}
    assert info["translations"] == ["en"]
    assert info["schema_version"] == "1" and info["user_version"] == 1
    assert info["unverified"] is True
    assert info["license"] == "CC-BY-SA-4.0"
    assert info["authors"] == [{"name": "Ada", "role": "author"}]
    assert info["data_sources"][0]["title"] == "Written by the course authors"
    # a pack with its own credits gets an attribution from them, not the tosk-data text
    assert "Ada" in info["attribution"] and "tosk" not in info["attribution"]
    # the starter shows every facet kind
    assert set(info["facets"]) == {"rec", "prod", "form", "article", "infl"}
    c = info["counts"]
    assert c["units"] == 2 and c["skills"] == 5 and c["items"] == 17 and c["verbs"] == 2
    assert c["sentences"] == 6 and c["inflections"] == 6 and c["notes"] == 3
    # the text output names the licence too
    assert cli.main(["info", str(out)]) == 0
    assert "CC-BY-SA-4.0" in capsys.readouterr().out


def test_template_topic_example_builds(scaffolded, tmp_path):
    """The starter's commented-out topic (pack format 1.2) validates and builds once uncommented."""
    p = scaffolded / "course.yaml"
    lines = p.read_text(encoding="utf-8").split("\n")
    start = lines.index("# topics:")
    lines[start:] = [ln[2:] if ln.startswith("# ") else ln for ln in lines[start:]]
    p.write_text("\n".join(lines), encoding="utf-8")
    assert yaml.safe_load(p.read_text(encoding="utf-8"))["topics"][0]["id"] == "market"
    assert validate(load_pack(scaffolded)) == []
    out = tmp_path / "xx.sqlite"
    assert cli.main(["build", str(scaffolded), "-o", str(out)]) == 0
    con = sqlite3.connect(out)
    assert con.execute("SELECT id, anchor FROM topics").fetchall() == [("market", "things")]
    assert dict(con.execute("SELECT key, value FROM meta"))["schema_minor"] == "3"


def test_compiled_pack_follows_the_contract(scaffolded, tmp_path):
    out = tmp_path / "xx.sqlite"
    assert cli.main(["build", str(scaffolded), "-o", str(out)]) == 0
    con = sqlite3.connect(out)
    meta = dict(con.execute("SELECT key, value FROM meta"))
    for key in ("schema_version", "course_id", "version", "title", "target", "translations", "persons",
                "tenses", "tense_labels", "articles", "unverified", "built_at", "attribution"):
        assert key in meta, key
    assert json.loads(meta["base_features"]) == ["tense:present"]
    assert meta["min_app_version"] == "0.4.0"     # trains an inflection table
    facets = {r[0] for r in con.execute("SELECT facet_id FROM skill_facets")}
    assert {"xx:salo#rec", "xx:salo#prod", "xx:kantar#form:present", "xx:kantar#form:past",
            "xx:mela#article", "xx:mela#infl:number"} <= facets
    assert ("ex:6", "tense:past") in set(con.execute("SELECT sentence_id, feature FROM sentence_features"))
    con.close()


def test_new_refuses_bad_ids_and_non_empty_dirs(tmp_path, capsys):
    assert cli.main(["new", "Italian", str(tmp_path / "a")]) == 2
    assert "2-3 lower-case letters" in capsys.readouterr().err
    d = tmp_path / "b"
    d.mkdir()
    (d / "notes.txt").write_text("mine", encoding="utf-8")
    assert cli.main(["new", "xx", str(d)]) == 2
    assert "not empty" in capsys.readouterr().err
    assert cli.main(["new", "xx", str(d), "--force"]) == 0
    assert (d / "notes.txt").read_text(encoding="utf-8") == "mine"


@pytest.mark.parametrize("code", ["eo", "it", "nl"])
def test_template_validates_with_and_without_language_rules(tmp_path, code):
    d = tmp_path / code
    cli.scaffold(code, d)
    assert validate(load_pack(d)) == []


def test_validate_reports_errors(scaffolded, capsys):
    p = scaffolded / "lexicon" / "u1.jsonl"
    recs = [r for _, r in read_jsonl(p)]
    recs[0]["tr"] = {"nl": ["hallo"]}           # no English gloss for a taught word
    write_jsonl(p, recs)
    assert cli.main(["validate", str(scaffolded)]) == 1
    assert "xx:salo has no translation for ['en']" in capsys.readouterr().err
    assert cli.main(["build", str(scaffolded), "-o", str(scaffolded.parent / "xx.sqlite")]) == 1
    assert not (scaffolded.parent / "xx.sqlite").exists()


def test_validate_needs_a_pack_dir(tmp_path, capsys):
    assert cli.main(["validate", str(tmp_path)]) == 1
    assert "no course.yaml" in capsys.readouterr().err


def test_stories_without_language_rules_are_an_error_not_a_crash(scaffolded, capsys):
    (scaffolded / "stories").mkdir()
    (scaffolded / "stories" / "u1.yaml").write_text(yaml.safe_dump([{
        "id": "u1-hello", "unit": "u1", "title": {"xx": "Salo", "en": "Hello"},
        "sentences": [{"xx": "Salo.", "en": "Hello."}] * 5,
        "questions": [{"q": {"en": "?"}, "options": ["a", "b", "c"], "answer": 0}] * 3}]), encoding="utf-8")
    assert cli.main(["validate", str(scaffolded)]) == 1
    assert "needs the pipeline's language rules" in capsys.readouterr().err


def test_old_cli_still_validates_a_scaffold(scaffolded):
    from pipeline.__main__ import main as old_main
    assert old_main(["validate", "xx", "--content-root", str(scaffolded.parent)]) == 0


def test_catalog_for_self_hosting(scaffolded, tmp_path):
    out = tmp_path / "site" / "xx.sqlite"
    assert cli.main(["build", str(scaffolded), "-o", str(out)]) == 0
    idx = tmp_path / "site" / "index.json"
    assert cli.main(["index", str(out), "--base-url", "https://example.org/packs/", "-o", str(idx)]) == 0
    doc = json.loads(idx.read_text(encoding="utf-8"))
    assert doc["index_version"] == 1 and "generated_at" in doc and "tag" not in doc
    [c] = doc["courses"]
    assert c["url"] == "https://example.org/packs/xx.sqlite"
    assert c["id"] == "xx" and c["version"] == "0.1.0" and c["sources"] == ["en"]
    assert c["schema_version"] == "1" and c["min_app_version"] == "0.4.0"
    assert c["size"] == out.stat().st_size and len(c["sha256"]) == 64
    assert c["license"] == "CC-BY-SA-4.0" and c["authors"] == [{"name": "Ada", "role": "author"}]


def test_catalog_needs_id_named_files(scaffolded, tmp_path, capsys):
    out = tmp_path / "demo.sqlite"
    assert cli.main(["build", str(scaffolded), "-o", str(out)]) == 0
    assert "name the file xx.sqlite" in capsys.readouterr().err
    assert cli.main(["index", str(out), "--base-url", "https://example.org", "-o", str(tmp_path / "i.json")]) == 1
    assert "must be named xx.sqlite" in capsys.readouterr().err


def test_publish_needs_an_explicit_flag(monkeypatch, capsys):
    def boom(*a, **k):
        raise AssertionError("publish must not run without --dry-run or --yes")
    monkeypatch.setattr(pub, "publish", boom)
    assert cli.main(["publish", "xx"]) == 2
    assert "--dry-run" in capsys.readouterr().err


def test_publish_dry_run_only_prints(scaffolded, tmp_path, capsys):
    content = tmp_path / "data" / "content"
    content.mkdir(parents=True)
    assert cli.main(["build", str(scaffolded), "-o", str(tmp_path / "data" / "dist" / "xx.sqlite")]) == 0
    assert cli.main(["publish", "xx", "--dry-run", "--tag", "packs-test", "--content-root", str(content)]) == 0
    out = capsys.readouterr().out
    assert "gh release create packs-test" in out
    doc = json.loads((tmp_path / "data" / "dist" / "index.json").read_text(encoding="utf-8"))
    assert doc["courses"][0]["url"].endswith("/releases/download/packs-test/xx.sqlite")


def test_publish_refuses_restricted_courses(capsys):
    assert cli.main(["publish", "hns", "--dry-run"]) == 2
    assert "restricted" in capsys.readouterr().err


def test_spec_worked_example_is_the_template(tmp_path):
    """docs/pack-format.md section 18 shows `pack new xx --title "Demo course" --author Ada` verbatim."""
    doc = (PIPELINE_DIR.parent / "docs" / "pack-format.md").read_text(encoding="utf-8")
    blocks = dict(re.findall(r"<!-- example: (\S+) -->\n[^\n]*\n\n```[a-z]*\n(.*?)```\n", doc, re.S))
    d = tmp_path / "xx"
    cli.scaffold("xx", d, "Demo course", "Ada")
    files = {p.relative_to(d).as_posix(): p.read_text(encoding="utf-8") for p in d.rglob("*") if p.is_file()}
    assert blocks == files


def test_console_script_and_template_are_packaged():
    meta = tomllib.loads((PIPELINE_DIR / "pyproject.toml").read_text(encoding="utf-8"))
    assert meta["project"]["scripts"]["pack"] == "pipeline.cli:main"
    patterns = meta["tool"]["setuptools"]["package-data"]["pipeline"]
    files = [p.relative_to(cli.TEMPLATE_DIR.parent).as_posix()
             for p in cli.TEMPLATE_DIR.rglob("*") if p.is_file() and "__pycache__" not in p.parts]
    assert files
    for f in files:
        assert any(len(PurePosixPath(f).parts) == len(PurePosixPath(pat).parts) and PurePosixPath(f).match(pat)
                   for pat in patterns), f"{f} is not in the package data"
