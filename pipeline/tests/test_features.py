"""Grammar gating (pipeline/features.py): sentence features, skill features, home-skill rule,
and how the validator, compiler and importer use them."""
import bz2
import sqlite3

import yaml

from pipeline.compile import compile_pack
from pipeline.content import load_pack, read_jsonl
from pipeline.features import FeatureTagger, SkillGraph, build
from pipeline.validate import validate


def tok(t, lex=None, form=None, pre=" "):
    return {"t": t, "pre": pre, "lex": lex, "form": form}


def punct(t):
    return {"t": t, "is_word": False}


def table(forms: dict, persons) -> dict:
    return {p: {"form": f} for p, f in zip(persons, forms)}


IT_P = ["io", "tu", "lui/lei", "noi", "voi", "loro"]
NL_P = ["ik", "jij", "hij/zij", "wij", "jullie", "zij"]


def it_data():
    def verb(vid, aux, pres, imp, fut, part, irr=()):
        return {"id": vid, "class": "are", "irregular_in": list(irr), "auxiliary": aux, "forms": {
            "infinitive": {"_": {"form": vid[3:]}}, "participle": {"_": {"form": part}},
            "presente": table(pres, IT_P), "imperfetto": table(imp, IT_P), "futuro": table(fut, IT_P)}}
    verbs = {
        "it:avere": verb("it:avere", "avere", "ho hai ha abbiamo avete hanno".split(),
                         "avevo avevi aveva avevamo avevate avevano".split(),
                         "avrò avrai avrà avremo avrete avranno".split(), "avuto", ["presente", "futuro"]),
        "it:essere": verb("it:essere", "essere", "sono sei è siamo siete sono".split(),
                          "ero eri era eravamo eravate erano".split(),
                          "sarò sarai sarà saremo sarete saranno".split(), "stato", ["presente", "futuro"]),
        "it:andare": verb("it:andare", "essere", "vado vai va andiamo andate vanno".split(),
                          "andavo andavi andava andavamo andavate andavano".split(),
                          "andrò andrai andrà andremo andrete andranno".split(), "andato", ["presente", "futuro"]),
        "it:parlare": verb("it:parlare", "avere", "parlo parli parla parliamo parlate parlano".split(),
                           "parlavo parlavi parlava parlavamo parlavate parlavano".split(),
                           "parlerò parlerai parlerà parleremo parlerete parleranno".split(), "parlato"),
        "it:potere": verb("it:potere", "avere", "posso puoi può possiamo potete possono".split(),
                          "potevo potevi poteva potevamo potevate potevano".split(),
                          "potrò potrai potrà potremo potrete potranno".split(), "potuto", ["presente", "futuro"]),
    }
    items = [{"id": v, "lemma": v[3:], "pos": "verb", "freq": i + 1, "tr": {"en": ["x"]}} for i, v in enumerate(verbs)]
    items += [{"id": "it:nel", "lemma": "nel", "pos": "prep", "freq": 50, "tr": {"en": ["in the"]}},
              {"id": "it:casa", "lemma": "casa", "pos": "noun", "freq": 60, "tr": {"en": ["house"]}, "tags": ["home"]}]
    return items, verbs


IT_COURSE = {
    "id": "it", "persons": IT_P, "tenses": ["presente", "imperfetto", "futuro", "passato_prossimo"],
    "base_features": ["tense:presente"],
    "feature_detectors": {
        "aux:essere": {"type": "compound_aux", "aux": "essere"},
        "modal": {"type": "modal_infinitive", "verbs": ["potere"],
                  "infinitive_pattern": "[a-z]+(are|ere|ire|(ar|er|ir)(lo|la|mi|ti))"},
        "prep:articulated": {"type": "words", "words": ["nel", "nella", "nell'"]},
        "irregular:futuro": {"type": "irregular_tense", "tense": "futuro"},
    },
    "units": [
        {"id": "u1", "skills": [
            {"id": "home", "kind": "vocab", "items": {"tags": ["home"]}},
            {"id": "present", "kind": "grammar", "requires": ["home"], "verbs": {"tense": "presente", "lemmas": ["parlare"]}},
            {"id": "preps", "kind": "grammar", "requires": ["home"], "items": {"lemmas": ["nel"]},
             "introduces": ["prep:articulated"]},
        ]},
        {"id": "u2", "skills": [
            {"id": "pp", "kind": "grammar", "requires": ["present"], "verbs": {"tense": "passato_prossimo", "lemmas": ["parlare"]}},
            {"id": "pp-essere", "kind": "grammar", "requires": ["pp"], "introduces": ["aux:essere"],
             "verbs": {"tense": "passato_prossimo", "lemmas": ["andare"]}},
            {"id": "futuro", "kind": "grammar", "requires": ["present"], "verbs": {"tense": "futuro", "lemmas": ["parlare"]}},
        ]},
    ],
}


def it_tagger():
    items, verbs = it_data()
    return FeatureTagger(IT_COURSE, items, verbs), items, verbs


def test_compound_form_tags_its_tense_not_the_auxiliary_present():
    t, _, _ = it_tagger()
    s = [tok("Ho", "it:avere", "presente.io", ""), tok("parlato", "it:parlare", "passato_prossimo.io"), punct(".")]
    assert t.tag(s) == {"tense:passato_prossimo"}
    s = [tok("Parlo", "it:parlare", "presente.io", ""), punct(".")]
    assert t.tag(s) == {"tense:presente"}


def test_aux_essere_and_participle_without_auxiliary():
    t, _, _ = it_tagger()
    s = [tok("Sono", "it:essere", "presente.io", ""), tok("andato", "it:andare", "passato_prossimo.io"), punct(".")]
    assert t.tag(s) == {"tense:passato_prossimo", "aux:essere"}
    s = [tok("Ho", "it:avere", "presente.io", ""), tok("parlato", "it:parlare", "passato_prossimo.io")]
    assert "aux:essere" not in t.tag(s)
    # a participle alone (adjectival/passive) is gated with the compound tense
    assert t.tag([tok("parlato", "it:parlare", "participle._", "")]) == {"tense:passato_prossimo"}


def test_unaligned_form_is_looked_up_by_spelling():
    t, _, _ = it_tagger()
    assert t.tag([tok("parlavo", "it:parlare", None, "")]) == {"tense:imperfetto"}
    assert t.tag([tok("parlo", "it:parlare", None, "")]) == set()          # present spelling: nothing new
    assert t.tag([tok("parlare", "it:parlare", None, "")]) == set()        # infinitive


def test_irregular_tense_modal_and_word_detectors():
    t, _, _ = it_tagger()
    assert t.tag([tok("Andrò", "it:andare", "futuro.io", "")]) == {"tense:futuro", "irregular:futuro"}
    assert t.tag([tok("Parlerò", "it:parlare", "futuro.io", "")]) == {"tense:futuro"}
    s = [tok("Posso", "it:potere", "presente.io", ""), tok("parlare", "it:parlare", "infinitive._")]
    assert t.tag(s) == {"tense:presente", "modal"}
    s = [tok("Posso", "it:potere", "presente.io", ""), tok("farlo")]                # unaligned clitic infinitive
    assert "modal" in t.tag(s)
    assert "modal" not in t.tag([tok("Posso", "it:potere", "presente.io", ""), tok("casa", "it:casa")])
    assert "prep:articulated" in t.tag([tok("nella", "it:nel", None, ""), tok("casa", "it:casa")])


def test_dutch_separable_split_and_whole():
    def verb(vid, pres, past, part, irr=()):
        return {"id": vid, "class": "strong", "irregular_in": list(irr), "auxiliary": "zijn", "forms": {
            "infinitive": {"_": {"form": vid[3:]}}, "participle": {"_": {"form": part}},
            "tegenwoordige_tijd": table(pres, NL_P), "verleden_tijd": table(past, NL_P)}}
    verbs = {
        "nl:komen": verb("nl:komen", "kom komt komt komen komen komen".split(), "kwam kwam kwam kwamen kwamen kwamen".split(),
                         "gekomen", ["verleden_tijd", "perfectum"]),
        "nl:terugkomen": verb("nl:terugkomen", ["kom terug", "komt terug", "komt terug", "komen terug", "komen terug",
                                                "komen terug"], ["kwam terug"] * 3 + ["kwamen terug"] * 3, "teruggekomen"),
        "nl:zijn": verb("nl:zijn", "ben bent is zijn zijn zijn".split(), "was was was waren waren waren".split(), "geweest"),
    }
    items = [{"id": v, "lemma": v[3:], "pos": "verb", "freq": i + 1, "tr": {"en": ["x"]}} for i, v in enumerate(verbs)]
    course = {"id": "nl", "persons": NL_P, "tenses": ["tegenwoordige_tijd", "verleden_tijd", "perfectum"],
              "feature_detectors": {"separable": {"type": "separable", "particles": ["terug", "op"]},
                                    "past:strong": {"type": "irregular_tense", "tense": "verleden_tijd"}},
              "units": []}
    t = FeatureTagger(course, items, verbs)
    s = [tok("Hij", None, None, ""), tok("komt", "nl:komen", "tegenwoordige_tijd.hij/zij"), tok("morgen"), tok("terug"), punct(".")]
    assert t.tag(s) == {"tense:tegenwoordige_tijd", "separable"}
    s = [tok("Hij", None, None, ""), tok("komt", "nl:komen", "tegenwoordige_tijd.hij/zij"), tok("terug"), tok("naar"), tok("huis"),
         punct(".")]
    assert "separable" not in t.tag(s)                                       # particle not clause-final
    s = [tok("Hij", None, None, ""), tok("is", "nl:zijn", "tegenwoordige_tijd.hij/zij"),
         tok("teruggekomen", "nl:terugkomen", "perfectum.hij/zij"), punct(".")]
    assert t.tag(s) == {"tense:perfectum", "separable"}
    # inverted strong past without a form: looked up by spelling
    assert t.tag([tok("Kwam", "nl:komen", None, ""), tok("je")]) == {"tense:verleden_tijd", "past:strong"}


def test_skill_graph_home_and_allowed():
    items, verbs = it_data()
    tagger, g = build(IT_COURSE, items, verbs)
    assert g.introduces["pp-essere"] == {"tense:passato_prossimo", "aux:essere"}
    assert g.allowed["pp-essere"] == {"tense:presente", "tense:passato_prossimo", "aux:essere"}
    assert "prep:articulated" not in g.allowed["futuro"]          # not a prerequisite
    ok = [tok("Sono", "it:essere", "presente.io", ""), tok("andato", "it:andare", "passato_prossimo.io")]
    assert g.home(ok, tagger.tag(ok)) == "pp-essere" and g.problems(ok, tagger.tag(ok)) == []
    # the future skill does not know articulated prepositions: home = futuro, not allowed
    bad = [tok("Parlerò", "it:parlare", "futuro.io", ""), tok("nella", "it:nel"), tok("casa", "it:casa")]
    assert g.home(bad, tagger.tag(bad)) == "futuro"
    assert g.problems(bad, tagger.tag(bad)) == ["home skill futuro does not allow ['prep:articulated']"]
    # a feature no skill introduces
    fut_irr = [tok("Andrò", "it:andare", "futuro.io", "")]
    assert "introduced by no skill" in g.problems(fut_irr, tagger.tag(fut_irr))[0]


def _set_base(root, base, **extra):
    p = root / "course.yaml"
    c = yaml.safe_load(p.read_text(encoding="utf-8"))
    c["base_features"] = base
    c.update(extra)
    p.write_text(yaml.safe_dump(c, allow_unicode=True, sort_keys=False), encoding="utf-8")


def test_validator_checks_gating(mini_pack_dir):
    assert validate(load_pack(mini_pack_dir)) == []          # no base_features: not enforced
    _set_base(mini_pack_dir, [])
    errs = validate(load_pack(mini_pack_dir))
    assert any("s:1" in e and "does not allow ['tense:presente']" in e for e in errs), errs
    _set_base(mini_pack_dir, ["tense:presente"])
    assert validate(load_pack(mini_pack_dir)) == []          # 'Noi abbiamo parlato.' is home in 'passato'
    _set_base(mini_pack_dir, ["tense:presente", "tense:typo"])
    assert any("tense:typo" in e for e in validate(load_pack(mini_pack_dir)))


def test_compiler_writes_feature_tables(mini_pack_dir, tmp_path):
    _set_base(mini_pack_dir, ["tense:presente"])
    out = tmp_path / "it.sqlite"
    compile_pack(load_pack(mini_pack_dir), out, built_at="2026-01-01T00:00:00Z")
    con = sqlite3.connect(out)
    try:
        sf = set(con.execute("SELECT sentence_id, feature FROM sentence_features"))
        assert sf == {("s:1", "tense:presente"), ("s:2", "tense:passato_prossimo")}
        kf = set(con.execute("SELECT skill_id, feature FROM skill_features"))
        assert kf == {("present-are", "tense:presente"), ("passato", "tense:passato_prossimo")}
        assert con.execute("SELECT value FROM meta WHERE key='base_features'").fetchone()[0] == '["tense:presente"]'
    finally:
        con.close()


def test_importer_drops_sentences_with_unintroduced_features(import_env, monkeypatch):
    import pipeline.importer as imp
    # the fixture teaches few words; lift the unknown-word caps to test the feature rule alone
    monkeypatch.setattr(imp, "MAX_NEVER_KNOWN", 99)
    monkeypatch.setattr(imp, "MAX_UNKNOWN", 99)
    monkeypatch.setattr(imp, "MAX_UNKNOWN_GRAMMAR", 99)
    root = import_env / "it"
    # one more Tatoeba pair: an essere compound
    tdir = import_env.parent / "cache" / "tatoeba"
    for name, line in (("ita_sentences.tsv.bz2", "12\tita\tNoi siamo andati.\n"),
                       ("eng_sentences.tsv.bz2", "112\teng\tWe went.\n"), ("ita-eng_links.tsv.bz2", "12\t112\n")):
        with bz2.open(tdir / name, "rt", encoding="utf-8") as f:
            text = f.read()
        with bz2.open(tdir / name, "wt", encoding="utf-8") as f:
            f.write(text + line)
    detectors = {"aux:essere": {"type": "compound_aux", "aux": "essere"}}
    _set_base(root, ["tense:presente"], feature_detectors=detectors)
    imp.run_import("it", str(import_env))

    def texts():
        return {rec["text"] for f in (root / "sentences").glob("*.jsonl") for _, rec in read_jsonl(f)}
    got = texts()
    assert "Lui ha mangiato la pizza." in got                 # passato prossimo: introduced by 'passato'
    assert "Noi siamo andati." not in got                     # aux:essere: introduced by no skill
    c = yaml.safe_load((root / "course.yaml").read_text(encoding="utf-8"))
    c["units"][1]["skills"][1]["introduces"] = ["aux:essere"]
    (root / "course.yaml").write_text(yaml.safe_dump(c, allow_unicode=True, sort_keys=False), encoding="utf-8")
    imp.run_import("it", str(import_env))
    assert "Noi siamo andati." in texts()
    gating = [e for e in validate(load_pack(root), check_notes=False) if "does not allow" in e or "no skill" in e]
    assert gating == []


def test_course_without_language_rules_is_tagged_from_forms():
    course = {"id": "xx", "persons": ["1s"], "tenses": ["pres", "past"], "units": []}
    verbs = {"xx:go": {"id": "xx:go", "forms": {"pres": {"1s": {"form": "go"}}, "past": {"1s": {"form": "went"}}}}}
    items = [{"id": "xx:go", "lemma": "go", "pos": "verb", "freq": 1, "tr": {"en": ["to go"]}}]
    t = FeatureTagger(course, items, verbs)
    assert t.tag([tok("went", "xx:go", "past.1s", "")]) == {"tense:past"}
    assert t.tag([tok("went", "xx:go", None, "")]) == {"tense:past"}


def test_sentence_dedupe_ignores_punctuation_and_case():
    from pipeline.importer import dedupe_key
    assert dedupe_key("Grazie mille!") == dedupe_key("grazie mille.") == dedupe_key("Grazie  mille")
    assert dedupe_key("L’acqua è fredda.") == dedupe_key("L'acqua è fredda!")
    assert dedupe_key("Grazie mille, Tom.") != dedupe_key("Grazie mille.")


def test_clean_text_drops_invisible_characters():
    from pipeline.importer import clean_text
    assert clean_text("Ze draagt ​​een oranje jurk.") == "Ze draagt een oranje jurk."
    assert clean_text(" Ciao, Tom!﻿ ") == "Ciao, Tom!"


def test_italian_irregular_imperfetto_and_futuro():
    from pipeline.lang import get_lang
    it = get_lang("it")

    def forms(pres, imp, fut, part):
        return {"presente": dict(zip(IT_P, pres.split())), "imperfetto": dict(zip(IT_P, imp.split())),
                "futuro": dict(zip(IT_P, fut.split())), "participle": {"_": part}}
    cercare = forms("cerco cerchi cerca cerchiamo cercate cercano", "cercavo cercavi cercava cercavamo cercavate cercavano",
                    "cercherò cercherai cercherà cercheremo cercherete cercheranno", "cercato")
    assert it.irregular_in("cercare", "are", cercare) == []
    mangiare = forms("mangio mangi mangia mangiamo mangiate mangiano",
                     "mangiavo mangiavi mangiava mangiavamo mangiavate mangiavano",
                     "mangerò mangerai mangerà mangeremo mangerete mangeranno", "mangiato")
    assert it.irregular_in("mangiare", "are", mangiare) == []
    vedere = forms("vedo vedi vede vediamo vedete vedono", "vedevo vedevi vedeva vedevamo vedevate vedevano",
                   "vedrò vedrai vedrà vedremo vedrete vedranno", "visto")
    assert it.irregular_in("vedere", "ere", vedere) == ["futuro", "passato_prossimo"]
    fare = forms("faccio fai fa facciamo fate fanno", "facevo facevi faceva facevamo facevate facevano",
                 "farò farai farà faremo farete faranno", "fatto")
    assert it.irregular_in("fare", "are", fare) == ["presente", "imperfetto", "futuro", "passato_prossimo"]
