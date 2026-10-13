import json

import yaml

from pipeline.content import load_pack, read_jsonl, write_jsonl
from pipeline.validate import find_cycle, validate


def edit_course(root, fn):
    p = root / "course.yaml"
    c = yaml.safe_load(p.read_text(encoding="utf-8"))
    fn(c)
    p.write_text(yaml.safe_dump(c, allow_unicode=True, sort_keys=False), encoding="utf-8")


def edit_jsonl(path, fn):
    recs = [r for _, r in read_jsonl(path)]
    recs = fn(recs)
    write_jsonl(path, recs)


def skill(c, sid):
    for u in c["units"]:
        for s in u["skills"]:
            if s["id"] == sid:
                return s
    raise KeyError(sid)


def errors(root):
    return validate(load_pack(root))


def test_fixture_is_valid(mini_pack_dir):
    assert errors(mini_pack_dir) == []


def test_find_cycle():
    assert find_cycle({"a": ["b"], "b": ["c"], "c": []}) is None
    cyc = find_cycle({"a": ["b"], "b": ["c"], "c": ["a"]})
    assert cyc and cyc[0] == cyc[-1] and set(cyc) == {"a", "b", "c"}


def test_detects_prerequisite_cycle(mini_pack_dir):
    edit_course(mini_pack_dir, lambda c: skill(c, "greetings").__setitem__("requires", ["passato"]))
    errs = errors(mini_pack_dir)
    assert any("prerequisite cycle" in e for e in errs), errs


def test_detects_dangling_prerequisite(mini_pack_dir):
    edit_course(mini_pack_dir, lambda c: skill(c, "articles").__setitem__("requires", ["nope"]))
    assert any("unknown skill 'nope'" in e for e in errors(mini_pack_dir))


def test_detects_dangling_token(mini_pack_dir):
    def f(recs):
        recs[0]["tokens"][3]["lex"] = "it:pizzaa"
        return recs
    edit_jsonl(mini_pack_dir / "sentences" / "u1.jsonl", f)
    errs = errors(mini_pack_dir)
    assert any("unknown lex it:pizzaa" in e for e in errs), errs


def test_detects_token_form_missing_from_table(mini_pack_dir):
    def f(recs):
        recs[0]["tokens"][1]["form"] = "imperfetto.io"
        return recs
    edit_jsonl(mini_pack_dir / "sentences" / "u1.jsonl", f)
    assert any("has no form imperfetto.io" in e for e in errors(mini_pack_dir))


def test_detects_tokens_not_rendering_text(mini_pack_dir):
    def f(recs):
        recs[0]["tokens"][1]["pre"] = ""
        return recs
    edit_jsonl(mini_pack_dir / "sentences" / "u1.jsonl", f)
    assert any("tokens render" in e for e in errors(mini_pack_dir))


def test_detects_incomplete_tables(mini_pack_dir):
    def f(recs):
        for r in recs:
            if r["id"] == "it:guardare":
                del r["forms"]["presente"]["voi"]
        return recs
    edit_jsonl(mini_pack_dir / "verbs" / "u1.jsonl", f)
    errs = errors(mini_pack_dir)
    assert any("skill present-are has 2 verbs with complete tables for presente, needs at least 3" in e for e in errs), errs


def test_detects_missing_table_for_listed_verb(mini_pack_dir):
    def f(recs):
        for r in recs:
            if r["id"] == "it:parlare":
                del r["forms"]["passato_prossimo"]["loro"]
        return recs
    edit_jsonl(mini_pack_dir / "verbs" / "u1.jsonl", f)
    errs = errors(mini_pack_dir)
    assert any("skill passato: no complete passato_prossimo table for ['parlare']" in e for e in errs), errs


def test_detects_bad_split(mini_pack_dir):
    def f(recs):
        recs[0]["forms"]["presente"]["io"]["ending"] = "a"
        return recs
    edit_jsonl(mini_pack_dir / "verbs" / "u1.jsonl", f)
    assert any("stem+ending" in e for e in errors(mini_pack_dir))


def test_detects_missing_translation_on_skill_item(mini_pack_dir):
    def f(recs):
        del recs[0]["tr"]["nl"]
        return recs
    edit_jsonl(mini_pack_dir / "lexicon" / "u1.jsonl", f)
    errs = errors(mini_pack_dir)
    assert any("it:ciao has no translation for ['nl']" in e for e in errs), errs


def test_detects_duplicate_ids_and_schema_errors(mini_pack_dir):
    edit_jsonl(mini_pack_dir / "lexicon" / "u1.jsonl", lambda recs: recs + [recs[0]])
    assert any("duplicate item id it:ciao" in e for e in errors(mini_pack_dir))
    edit_jsonl(mini_pack_dir / "lexicon" / "u1.jsonl", lambda recs: recs + [{"id": "it:x", "lemma": "x"}])
    errs = errors(mini_pack_dir)
    assert any("schema" in e and "u1.jsonl" in e for e in errs), errs


def test_detects_too_few_items_and_missing_notes(mini_pack_dir):
    edit_course(mini_pack_dir, lambda c: skill(c, "articles")["items"].__setitem__("min", 5))
    (mini_pack_dir / "grammar" / "passato.nl.md").unlink()
    errs = errors(mini_pack_dir)
    assert any("skill articles has 3 items, needs at least 5" in e for e in errs), errs
    assert any("grammar skill passato has no 'nl' grammar note" in e for e in errs), errs


def test_detects_item_used_before_its_unit(mini_pack_dir):
    def f(recs):
        for r in recs:
            if r["id"] == "it:mangiare":
                r["unit"] = "u2"
        return recs
    edit_jsonl(mini_pack_dir / "lexicon" / "u1.jsonl", f)
    assert any("introduced later in u2" in e for e in errors(mini_pack_dir))


def test_detects_ids_tsv_mismatch(mini_pack_dir):
    p = mini_pack_dir / "ids.tsv"
    p.write_text(p.read_text(encoding="utf-8").replace("it:zio\tzio\tnoun", "it:zio\tzia\tnoun"), encoding="utf-8")
    assert any("ids.tsv says zia/noun" in e for e in errors(mini_pack_dir))
