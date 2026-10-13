import json

import yaml

from pipeline.content import read_jsonl
from pipeline.ids import IdRegistry
from pipeline.importer import run_import


def test_registry_assigns_and_reuses(tmp_path):
    p = tmp_path / "ids.tsv"
    r = IdRegistry("it", p)
    assert r.get("casa", "noun") == "it:casa"
    assert r.get("fine", "adj") == "it:fine"
    assert r.get("fine", "noun") == "it:fine.2"          # homograph with another POS
    assert r.get("per favore", "phrase") == "it:per_favore"
    assert r.get("casa", "noun") == "it:casa"            # same key, same id
    r.save()
    r2 = IdRegistry("it", p)
    assert r2.get("fine", "noun") == "it:fine.2"
    assert r2.get("fine", "adj") == "it:fine"
    assert r2.added == 0
    # a new homograph never takes a used number, even if the earlier word is gone from the pack
    assert r2.get("fine", "adv") == "it:fine.3"


def test_ids_are_never_reused_after_removal(tmp_path):
    p = tmp_path / "ids.tsv"
    r = IdRegistry("it", p)
    r.get("vecchio", "adj")
    r.save()
    text = p.read_text(encoding="utf-8")
    r2 = IdRegistry("it", p)
    r2.get("nuovo", "adj")
    r2.save()
    assert p.read_text(encoding="utf-8").startswith(text)   # append-only
    assert "it:vecchio" in p.read_text(encoding="utf-8")


def _lexicon(root):
    out = {}
    for f in sorted((root / "lexicon").glob("*.jsonl")):
        for _, rec in read_jsonl(f):
            out[(rec["lemma"], rec["pos"])] = rec
    return out


def test_importer_is_stable_across_runs(import_env):
    root = import_env / "it"
    run_import("it", str(import_env))
    ids1 = (root / "ids.tsv").read_text(encoding="utf-8")
    lex1 = _lexicon(root)
    sents1 = sorted((root / "sentences").glob("*.jsonl"))
    assert lex1, "importer wrote no lexicon"
    assert any(rec.get("unit") for rec in lex1.values())
    assert sents1, "importer wrote no sentences"

    run_import("it", str(import_env))
    assert (root / "ids.tsv").read_text(encoding="utf-8") == ids1          # nothing new
    assert _lexicon(root) == lex1                                         # identical output

    # add a curated word: old ids stay, the new one is appended
    seed = yaml.safe_load((root / "seed.yaml").read_text(encoding="utf-8"))
    removed = seed["items"].pop(4)        # casa
    assert removed["lemma"] == "casa"
    seed["items"].append({"lemma": "acqua", "pos": "noun", "tags": ["things"], "nl": ["water"]})
    (root / "seed.yaml").write_text(yaml.safe_dump(seed, allow_unicode=True), encoding="utf-8")
    run_import("it", str(import_env))
    ids3 = (root / "ids.tsv").read_text(encoding="utf-8")
    assert ids3.startswith(ids1)
    assert "it:acqua\tacqua\tnoun" in ids3
    lex3 = _lexicon(root)
    for key, rec in lex1.items():
        if key in lex3:
            assert lex3[key]["id"] == rec["id"]


def test_importer_output_content(import_env):
    root = import_env / "it"
    run_import("it", str(import_env))
    lex = _lexicon(root)
    assert lex[("ciao", "intj")]["tr"] == {"en": ["hi", "bye"], "nl": ["hoi", "doei"]}
    assert lex[("ciao", "intj")]["tr_src"] == {"en": "claude", "nl": "claude"}
    assert lex[("ciao", "intj")]["unit"] == "u1"
    assert lex[("pizza", "noun")]["article"] == "la"
    assert lex[("uomo", "noun")]["article"] == "l'"
    assert lex[("pizza", "noun")]["unit"] == "u2"
    verbs = {}
    for f in (root / "verbs").glob("*.jsonl"):
        for _, rec in read_jsonl(f):
            verbs[rec["id"]] = rec
    m = verbs[lex[("mangiare", "verb")]["id"]]
    assert m["class"] == "are" and m["auxiliary"] == "avere"
    assert m["forms"]["presente"]["noi"] == {"form": "mangiamo", "stem": "mang", "ending": "iamo"}
    assert m["forms"]["passato_prossimo"]["io"] == {"form": "ho mangiato"}
    a = verbs[lex[("andare", "verb")]["id"]]
    assert a["forms"]["passato_prossimo"]["noi"] == {"form": "siamo andati", "alts": ["siamo andate"]}
    assert "presente" in a["irregular_in"]
    sents = {}
    for f in (root / "sentences").glob("*.jsonl"):
        for _, rec in read_jsonl(f):
            sents[rec["id"]] = rec
    s1 = sents["s:1"]
    assert s1["tr"] == {"en": "I eat the pizza.", "nl": "Ik eet de pizza."}
    assert s1["src"] == "tatoeba:1" and s1["tr_src"]["en"] == "tatoeba:101"
    assert "s:10" not in sents                      # duplicate text of s:1
    assert "s:11" not in sents                      # no English translation
    forms = [(t["t"], t.get("form")) for t in sents["s:3"]["tokens"]]
    assert ("mangiato", "passato_prossimo.lui/lei") in forms
