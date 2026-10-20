import json

import pytest
from jsonschema import Draft202012Validator

from pipeline.content import load_pack
from pipeline.paths import SCHEMA_DIR
from pipeline.validate import schema_validator

SCHEMAS = ["course", "lexicon", "verbs", "sentences"]


@pytest.mark.parametrize("name", SCHEMAS)
def test_schema_files_are_valid_json_schema(name):
    schema = json.loads((SCHEMA_DIR / f"{name}.schema.json").read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)


def test_fixture_pack_validates_against_schemas(mini_pack_dir):
    pack = load_pack(mini_pack_dir)
    assert list(schema_validator("course").iter_errors(pack.course)) == []
    for kind, rel, n, rec in pack.raw_lines:
        errs = list(schema_validator(kind).iter_errors(rec))
        assert errs == [], f"{rel}:{n}: {errs[0].message if errs else ''}"


def _errors(name, rec):
    return [e.message for e in schema_validator(name).iter_errors(rec)]


def test_lexicon_schema_rejects_bad_records():
    ok = {"id": "it:casa", "lemma": "casa", "pos": "noun", "tr": {"en": ["house"]}}
    assert _errors("lexicon", ok) == []
    assert _errors("lexicon", {**ok, "tr": {}})                       # needs a translation
    assert _errors("lexicon", {**ok, "tr": {"en": []}})               # non-empty gloss list
    assert _errors("lexicon", {**ok, "id": "casa"})                   # course prefix
    assert _errors("lexicon", {**ok, "id": "it:casa#rec"})            # '#' is reserved for facets
    assert _errors("lexicon", {**ok, "pos": "thing"})
    assert _errors("lexicon", {**ok, "gender": "x"})
    assert _errors("lexicon", {**ok, "unknown": 1})                   # no stray fields
    assert _errors("lexicon", {**ok, "tr_src": {"en": "somewhere"}})


def test_verbs_schema_split_and_forms():
    rec = {"id": "it:parlare", "forms": {"presente": {"io": {"form": "parlo", "stem": "parl", "ending": "o"}},
                                          "infinitive": {"_": "parlare"}}}
    assert _errors("verbs", rec) == []
    bad = {"id": "it:parlare", "forms": {"presente": {"io": {"form": "parlo", "stem": "parl"}}}}
    assert _errors("verbs", bad)                                       # stem without ending
    assert _errors("verbs", {"id": "it:x", "forms": {"Presente": {"io": "x"}}})
    assert _errors("verbs", {**rec, "auxiliary": "avere||essere"})
    # Dutch 'ik werk' = werk + '' (empty ending allowed)
    assert _errors("verbs", {"id": "nl:werken", "forms": {"tegenwoordige_tijd": {"ik": {"form": "werk", "stem": "werk", "ending": ""}}}}) == []


def test_sentences_schema():
    rec = {"id": "s:1", "text": "Ciao!", "tr": {"en": "Hi!"},
           "tokens": [{"t": "Ciao", "lex": "it:ciao"}, {"t": "!", "is_word": False}]}
    assert _errors("sentences", rec) == []
    assert _errors("sentences", {**rec, "tr": {}})
    assert _errors("sentences", {**rec, "tokens": [{"t": "Ciao", "form": "presente.io"}]})   # form needs lex
    assert _errors("sentences", {**rec, "tokens": [{"t": "Ciao", "lex": "it:ciao", "form": "presente"}]})
    assert _errors("sentences", {**rec, "tokens": [{"t": "Ciao", "pre": "x"}]})              # pre is whitespace


def test_course_schema_skill_needs_exactly_one_query(mini_pack_dir):
    pack = load_pack(mini_pack_dir)
    c = json.loads(json.dumps(pack.course))
    assert _errors("course", c) == []
    del c["units"][0]["skills"][0]["items"]
    assert _errors("course", c)
    c = json.loads(json.dumps(pack.course))
    c["units"][0]["skills"][0]["verbs"] = {"tense": "presente"}      # vocab skill with verbs + items
    assert _errors("course", c)
    c = json.loads(json.dumps(pack.course))
    c["units"][0]["skills"][1]["exercises"] = ["listen_pick"]          # allowed since pack format 1.1
    assert _errors("course", c) == []
    c["units"][0]["skills"][1]["exercises"] = ["dictation"]            # no such exercise type
    assert _errors("course", c)
