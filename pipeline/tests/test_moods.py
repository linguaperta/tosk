"""Italian moods (pack 1.3): imperative, conditional, subjunctive, passato remoto; pronominal verbs;
attached pronouns; the generic pack keys they use (tense_persons, tense_groups, recognition skills,
required_translations) and the new feature detectors."""
import json
import sqlite3

import yaml

from pipeline import features, query
from pipeline.align import Aligner
from pipeline.compile import compile_pack, facets_for
from pipeline.content import load_pack, required_translations
from pipeline.lang import get_lang
from pipeline.tokens import tokenize
from pipeline.validate import validate

IT = get_lang("it")
P = ["io", "tu", "lui/lei", "noi", "voi", "loro"]
IMP = ["tu", "lui/lei", "noi", "voi"]


def item(iid, pos, freq, **kw):
    return {"id": iid, "lemma": kw.pop("lemma", iid.split(":", 1)[1]), "pos": pos, "freq": freq,
            "tr": {"en": [kw.pop("en", "x")]}, **kw}


def tab(persons, forms):
    return dict(zip(persons, forms))


def aligner():
    items = [item("it:essere", "verb", 1), item("it:avere", "verb", 2), item("it:pensare", "verb", 20),
             item("it:sapere", "verb", 21), item("it:parlare", "verb", 22, en="to speak"),
             item("it:dire", "verb", 23, en="to say"), item("it:alzarsi", "verb", 300, en="to get up"),
             item("it:sorprendere", "verb", 400), item("it:sorpreso", "adj", 500, inflections=["sorpresa", "sorpresi", "sorprese"]),
             item("it:che", "conj", 5), item("it:tu", "pron", 6), item("it:io", "pron", 7), item("it:noi", "pron", 8),
             item("it:mi", "pron", 9), item("it:se", "conj", 10), item("it:bene", "adv", 11),
             item("it:italiano", "noun", 12), item("it:non", "adv", 13), item("it:la", "det", 14),
             item("it:verità", "noun", 15), item("it:tardi", "adv", 16), item("it:piano", "adv", 17),
             item("it:più", "adv", 18), item("it:a", "prep", 19), item("it:ora", "noun", 24)]
    verbs = {
        "it:essere": {"id": "it:essere", "auxiliary": "essere", "forms": {
            "infinitive": {"_": "essere"}, "participle": {"_": "stato"},
            "presente": tab(P, ["sono", "sei", "è", "siamo", "siete", "sono"]),
            "imperativo": tab(IMP, ["sii", "sia", "siamo", "siate"])}},
        "it:avere": {"id": "it:avere", "auxiliary": "avere", "forms": {
            "infinitive": {"_": "avere"}, "participle": {"_": "avuto"},
            "presente": tab(P, ["ho", "hai", "ha", "abbiamo", "avete", "hanno"])}},
        "it:pensare": {"id": "it:pensare", "auxiliary": "avere", "forms": {
            "infinitive": {"_": "pensare"}, "presente": tab(P, ["penso", "pensi", "pensa", "pensiamo", "pensate", "pensano"])}},
        "it:sapere": {"id": "it:sapere", "auxiliary": "avere", "forms": {
            "infinitive": {"_": "sapere"}, "presente": tab(P, ["so", "sai", "sa", "sappiamo", "sapete", "sanno"])}},
        "it:parlare": {"id": "it:parlare", "auxiliary": "avere", "forms": {
            "infinitive": {"_": "parlare"}, "gerund": {"_": "parlando"}, "participle": {"_": "parlato"},
            "presente": tab(P, ["parlo", "parli", "parla", "parliamo", "parlate", "parlano"]),
            "congiuntivo_presente": tab(P, ["parli", "parli", "parli", "parliamo", "parliate", "parlino"]),
            "imperativo": tab(IMP, ["parla", "parli", "parliamo", "parlate"]),
            "condizionale": tab(P, ["parlerei", "parleresti", "parlerebbe", "parleremmo", "parlereste", "parlerebbero"])}},
        "it:dire": {"id": "it:dire", "auxiliary": "avere", "forms": {
            "infinitive": {"_": "dire"}, "presente": tab(P, ["dico", "dici", "dice", "diciamo", "dite", "dicono"]),
            "imperativo": {"tu": {"form": "di'", "alts": ["dì"]}, "lui/lei": "dica", "noi": "diciamo", "voi": "dite"}}},
        "it:alzarsi": {"id": "it:alzarsi", "auxiliary": "essere", "forms": {
            "infinitive": {"_": "alzarsi"}, "participle": {"_": "alzatosi"},
            "presente": tab(P, ["mi alzo", "ti alzi", "si alza", "ci alziamo", "vi alzate", "si alzano"]),
            "imperativo": tab(IMP, ["alzati", "si alzi", "alziamoci", "alzatevi"]),
            "passato_prossimo": {"io": {"form": "mi sono alzato", "alts": ["mi sono alzata"]}}}},
        "it:sorprendere": {"id": "it:sorprendere", "auxiliary": "avere", "forms": {
            "infinitive": {"_": "sorprendere"}, "participle": {"_": "sorpreso"},
            "presente": tab(P, ["sorprendo", "sorprendi", "sorprende", "sorprendiamo", "sorprendete", "sorprendono"]),
            "passato_remoto": tab(P, ["sorpresi", "sorprendesti", "sorprese", "sorprendemmo", "sorprendeste", "sorpresero"])}},
    }
    return Aligner(IT, items, verbs)


def al(a, text, en=None):
    return [(t["t"], t["lex"], t["form"], bool(t.get("unsure"))) for t in a.align(tokenize(text, "it"), translation=en)
            if t["is_word"]]


def form_of(rows, word):
    return next((lex, form, unsure) for t, lex, form, unsure in rows if t == word)


def test_lang_reads_moods_from_wiktionary_tags():
    assert IT.slot(["conditional", "first-person", "singular"]) == ("condizionale", "io")
    assert IT.slot(["present", "second-person", "singular", "subjunctive"]) == ("congiuntivo_presente", "tu")
    assert IT.slot(["imperfect", "plural", "subjunctive", "third-person"]) == ("congiuntivo_imperfetto", "loro")
    assert IT.slot(["historic", "indicative", "past", "singular", "third-person"]) == ("passato_remoto", "lui/lei")
    assert IT.slot(["imperative", "second-person", "singular"]) == ("imperativo", "tu")
    # the formal Lei imperative is the lui/lei row; Loro, io and the negative tu form are not kept
    assert IT.slot(["formal", "imperative", "second-person-semantically", "singular", "third-person"]) == ("imperativo", "lui/lei")
    assert IT.slot(["formal", "imperative", "plural", "second-person-semantically", "third-person"]) is None
    assert IT.slot(["imperative", "negative", "second-person", "singular"]) is None
    assert IT.slot(["indicative", "present", "first-person", "singular"]) == ("presente", "io")
    assert IT.persons_of("imperativo") == IMP and IT.persons_of("presente") == P


def test_pronominal_verbs():
    assert IT.pronominal("alzarsi") == ("alzare", "si")
    assert IT.pronominal("andarsene") == ("andare", "sene")
    assert IT.pronominal("volerci") == ("volere", "ci")
    assert IT.pronominal("farcela") == ("fare", "cela")
    assert IT.pronominal("parlare") is None
    assert IT.base_participle("alzatosi") == "alzato" and IT.base_participle("andatosene") == "andato"
    assert IT.pronominal_compound({"io": "sono", "noi": "siamo"}, "alzato", "io", "si") == ("mi sono alzato", ["mi sono alzata"])
    assert IT.pronominal_compound({"io": "sono", "noi": "siamo"}, "andato", "noi", "sene") == ("ce ne siamo andati", ["ce ne siamo andate"])
    forms = {"presente": tab(P, ["mi alzo", "ti alzi", "si alza", "ci alziamo", "vi alzate", "si alzano"]),
             "imperfetto": tab(P, ["mi alzavo", "ti alzavi", "si alzava", "ci alzavamo", "vi alzavate", "si alzavano"]),
             "participle": {"_": "alzatosi"}}
    assert IT.verb_class("alzarsi", forms, "") == "are"
    assert IT.irregular_in("alzarsi", "are", forms) == []          # 'alzo' is regular, so is 'mi alzo'


def test_regular_moods_and_spelling_changes():
    reg = {"condizionale": tab(P, ["cercherei", "cercheresti", "cercherebbe", "cercheremmo", "cerchereste", "cercherebbero"]),
           "congiuntivo_presente": tab(P, ["cerchi", "cerchi", "cerchi", "cerchiamo", "cerchiate", "cerchino"]),
           "passato_remoto": tab(P, ["cercai", "cercasti", "cercò", "cercammo", "cercaste", "cercarono"]),
           "imperativo": tab(IMP, ["cerca", "cerchi", "cerchiamo", "cercate"]),
           "presente": tab(P, ["cerco", "cerchi", "cerca", "cerchiamo", "cercate", "cercano"]),
           "participle": {"_": "cercato"}}
    assert IT.irregular_in("cercare", "are", reg) == []
    assert "passato_remoto" in IT.irregular_in("prendere", "ere", {
        "passato_remoto": tab(P, ["presi", "prendesti", "prese", "prendemmo", "prendeste", "presero"]),
        "presente": tab(P, ["prendo", "prendi", "prende", "prendiamo", "prendete", "prendono"]), "participle": {"_": "preso"}})
    # -ere passato remoto in -etti is regular too
    assert "passato_remoto" not in IT.irregular_in("credere", "ere", {
        "passato_remoto": tab(P, ["credetti", "credesti", "credette", "credemmo", "credeste", "credettero"]),
        "presente": tab(P, ["credo", "credi", "crede", "crediamo", "credete", "credono"]), "participle": {"_": "creduto"}})
    assert IT.split("parlare", "are", "imperativo", "tu", "parla", True) == ("parl", "a")
    assert IT.split("parlare", "are", "condizionale", "noi", "parleremmo", True) == ("parl", "eremmo")


def test_mood_of_homographs_follows_the_context():
    a = aligner()
    # after a trigger + che: the subjunctive
    assert form_of(al(a, "Penso che tu parli bene."), "parli")[1] == "congiuntivo_presente.tu"
    # ... and right after a trigger that drops 'che' ('Penso parli bene'), not after a comma
    assert form_of(al(a, "Penso tu parli bene."), "parli")[1] == "congiuntivo_presente.tu"
    assert not (form_of(al(a, "Penso, tu parli bene."), "parli")[1] or "").startswith("congiuntivo")
    # a subjunctive singular without a subject: the person stays open (io, tu or lui/lei)
    assert form_of(al(a, "Penso che parli bene."), "parli")[1] is None
    # 'che' after a verb of knowing: indicative or subjunctive? the sentence is not used
    assert form_of(al(a, "So che parli italiano."), "parli")[2] is True
    # no context: the indicative
    assert form_of(al(a, "Parli italiano?", "Do you speak Italian?"), "Parli")[1] == "presente.tu"
    # an imperative context: the imperative
    assert form_of(al(a, "Parla più piano!", "Speak more slowly!"), "Parla")[1] == "imperativo.tu"
    assert form_of(al(a, "Parli più piano!", "Speak more slowly!"), "Parli")[1] == "imperativo.lui/lei"
    assert form_of(al(a, "Parliamo!", "We're talking!"), "Parliamo")[1] == "presente.noi"   # a subject in English
    # a pronoun that is no subject of that person ('tutti') keeps the imperative
    assert form_of(al(a, "Non parlate tutti insieme!", "Don't all talk at once!"), "parlate")[1] == "imperativo.voi"
    assert form_of(al(a, "Parli tu?", "Do you speak?"), "Parli")[1] == "presente.tu"
    # essere/avere: the noi imperative only with a "Let's" translation
    assert form_of(al(a, "Siamo pronti!", "We're ready!"), "Siamo")[1] == "presente.noi"
    assert form_of(al(a, "Siamo seri!", "Let's be serious!"), "Siamo")[1] == "imperativo.noi"
    # a unique form keeps its mood anywhere
    assert form_of(al(a, "Parlerei con lui."), "Parlerei")[1] == "condizionale.io"
    # an interrogative 'che' calls for no subjunctive ('A che ora ...?')
    assert form_of(al(a, "A che ora parli?", "What time do you speak?"), "parli") == ("it:parlare", "presente.tu", False)


def test_stress_marks_of_wiktionary_monosyllables_are_dropped():
    assert IT.spelling("se ne và", "se") == "se ne va"
    assert IT.spelling("me ne vàdo", "me") == "me ne vado"
    assert IT.spelling("ce n'è", "ce") == "ce n'è"


def test_elative_links_the_adjective():
    a = aligner()
    a.lemma_index.setdefault("bello", []).append("it:sorpreso")   # any adjective item stands in for bello
    assert form_of(al(a, "Mi alzo bellissimo."), "bellissimo")[0] == "it:sorpreso"


def test_pronominal_forms_align_on_every_word():
    a = aligner()
    rows = al(a, "Mi alzo tardi.")
    assert rows[0][1:3] == ("it:alzarsi", "presente.io") and rows[1][1:3] == ("it:alzarsi", "presente.io")
    rows = al(a, "Mi sono alzato tardi.")
    assert {r[1:3] for r in rows[:3]} == {("it:alzarsi", "passato_prossimo.io")}
    # 'mi alzi' is no form of alzarsi in the present: not taken for one (subjunctive outside a context)
    assert form_of(al(a, "Alzati!", "Get up!"), "Alzati")[1] == "imperativo.tu"
    # a form that is only an imperative is one anywhere ('Siamo in ritardo, alziamoci!')
    assert form_of(al(a, "Siamo tardi, alziamoci!", "We're late, let's get up!"), "alziamoci")[1] == "imperativo.noi"
    # a subject pronoun that does not fit the cell: no pronominal form ('Penso che tu mi alzi')
    assert form_of(al(a, "Noi ti alzi.", "x"), "ti")[0] != "it:alzarsi"


def test_attached_pronouns_link_the_verb():
    a = aligner()
    assert form_of(al(a, "Dimmi la verità!", "Tell me the truth!"), "Dimmi")[:2] == ("it:dire", "imperativo.tu")
    assert form_of(al(a, "Non parlarmi!", "Don't talk to me!"), "parlarmi")[:2] == ("it:parlare", "infinitive._")
    assert form_of(al(a, "Sto parlandoti."), "parlandoti")[:2] == ("it:parlare", "gerund._")


def test_rare_tense_homograph_reads_as_the_adjective():
    a = aligner()
    assert form_of(al(a, "Siamo sorpresi."), "sorpresi")[:2] == ("it:sorpreso", None)
    assert form_of(al(a, "Io sorpresi tutti."), "sorpresi")[1] == "passato_remoto.io"
    # without a copula or a determiner before it, the form is the verb
    assert form_of(al(a, "Mi sorprese molto.", "It surprised me a lot."), "sorprese")[1] == "passato_remoto.lui/lei"
    assert form_of(al(a, "Sono sorprese."), "sorprese")[:2] == ("it:sorpreso", None)

def _tagger(detectors, verbs=None, items=None):
    course = {"id": "it", "persons": P, "tenses": ["presente"], "units": [], "feature_detectors": detectors}
    return features.FeatureTagger(course, items or [], verbs or {})


def toks(*words, **kw):
    out = []
    for w in words:
        t, _, lex = w.partition("/")
        lex, _, form = lex.partition("[")
        d = {"t": t, "pre": " " if out else "", "is_word": t not in ".!?,", "lex": lex or None}
        if form:
            d["form"] = form.rstrip("]")
        out.append(d)
    return out


def test_pattern_words_and_enclitic_detectors():
    verbs = {"it:dire": {"forms": {"imperativo": {"tu": {"form": "di'", "alts": ["dì"]}}}},
             "it:alzarsi": {"forms": {"imperativo": {"tu": "alzati"}}}}
    tg = _tagger({"comparative": {"type": "pattern", "pattern": r"\bpiù\s+\w+\s+(di|che)\b"},
                  "pronoun:combined": {"type": "words", "words": ["glielo", "me lo"]},
                  "imperative:pronoun": {"type": "enclitic", "tense": "imperativo"}}, verbs)
    assert "comparative" in tg.tag(toks("È", "più", "alto", "di", "me", "."))
    assert "pronoun:combined" in tg.tag(toks("Me", "lo", "dai", "?"))
    assert "pronoun:combined" not in tg.tag(toks("Dai", "lo", "a", "me", "."))
    assert "imperative:pronoun" in tg.tag(toks("Dimmi/it:dire[imperativo.tu]", "!"))
    assert "imperative:pronoun" not in tg.tag(toks("Alzati/it:alzarsi[imperativo.tu]", "!"))
    neg = _tagger({"neg": {"type": "pattern", "annotate": True,
                           "pattern": r"(^|[.!?]\s*)non\{\}\s+((ti|mi)\{\}\s*)*\S+\{infinitive\._\}"}}, verbs)
    assert "neg" in neg.tag(toks("Non", "ti", "preoccupare/it:preoccupare[infinitive._]", "!"))
    assert "neg" not in neg.tag(toks("Non", "ti", "diverti/it:divertire[presente.tu]", "?"))


def test_reflexive_detector_unbound_and_verbs():
    items = [{"id": "it:mangiare", "lemma": "mangiare", "pos": "verb"}, {"id": "it:andare", "lemma": "andare", "pos": "verb"},
             {"id": "it:alzarsi", "lemma": "alzarsi", "pos": "verb"}]
    verbs = {"it:mangiare": {"forms": {}}, "it:andare": {"forms": {}}, "it:alzarsi": {"forms": {}}}
    tg = _tagger({"si": {"type": "reflexive", "pronouns": {"si": ["lui/lei", "loro"]}, "unbound": True},
                  "ci": {"type": "reflexive", "pronouns": {"ci": ["io", "tu", "lui/lei", "voi", "loro"]},
                         "unbound": True, "verbs": ["andare"]}}, verbs, items)
    assert "si" in tg.tag(toks("Qui", "si/it:si", "mangia/it:mangiare[presente.lui/lei]", "."))
    assert "si" not in tg.tag(toks("Si/it:alzarsi[presente.lui/lei]", "alza/it:alzarsi[presente.lui/lei]", "."))
    assert "ci" in tg.tag(toks("Ci/it:ci", "vado/it:andare[presente.io]", "."))
    assert "ci" not in tg.tag(toks("Ci/it:ci", "mangia/it:mangiare[presente.lui/lei]", "."))


def test_tense_persons_make_an_imperative_table_complete():
    persons = query.Persons(P, {"imperativo": IMP})
    v = {"forms": {"imperativo": tab(IMP, ["parla", "parli", "parliamo", "parlate"])}}
    assert query.complete_tense(v, "imperativo", persons)
    assert not query.complete_tense(v, "imperativo", P)
    assert required_translations({"translations": ["en", "nl"], "required_translations": ["en"]}) == ["en"]
    assert required_translations({"translations": ["en", "nl"]}) == ["en", "nl"]


def test_recognition_skill_items_train_rec_only():
    skill = {"id": "read", "kind": "vocab", "recognition": True, "items": {"tags": ["x"]}}
    assert [f[2] for f in facets_for(skill, ["it:a", "it:b"])] == ["rec", "rec"]


def _gated_pack(mini_pack_dir, edit):
    c = yaml.safe_load(open(mini_pack_dir / "course.yaml", encoding="utf-8"))
    edit(c)
    (mini_pack_dir / "course.yaml").write_text(yaml.safe_dump(c, allow_unicode=True, sort_keys=False), encoding="utf-8")
    return load_pack(mini_pack_dir)


def test_moods_meta_and_recognition_compile(mini_pack_dir, tmp_path):
    def edit(c):
        c["tense_groups"] = {"passato_prossimo": "past"}
        c["tense_person_labels"] = {"presente": {"lui/lei": {"en": "Lei (you, formal)"}}}
        c["required_translations"] = ["en"]
        for u in c["units"]:
            for s in u["skills"]:
                if "verbs" in s and s["verbs"]["tense"] == "passato_prossimo":
                    s["recognition"] = True
                    s["equivalent_tense"] = "presente"
                    s["exercises"] = ["multiple_choice"]
    pack = _gated_pack(mini_pack_dir, edit)
    assert validate(pack) == []
    out = tmp_path / "it.sqlite"
    compile_pack(pack, out, built_at="2026-10-20T00:00:00Z")
    meta = dict(sqlite3.connect(out).execute("SELECT key, value FROM meta"))
    assert meta["schema_minor"] == "2" and meta["min_app_version"] == "0.7.3"
    rec = json.loads(meta["recognition_skills"])
    assert list(rec.values()) == [{"equivalent_tense": "presente"}]
    assert json.loads(meta["tense_groups"]) == {"passato_prossimo": "past"}
    assert json.loads(meta["tense_person_labels"])["presente"]["lui/lei"]["en"].startswith("Lei")


def test_validator_checks_the_new_keys(mini_pack_dir):
    def edit(c):
        c["tense_persons"] = {"imperativo": ["tu"]}           # undeclared tense
        c["required_translations"] = ["de"]                    # not a translation
        c["units"][0]["skills"][0]["equivalent_tense"] = "presente"   # not a recognition verbs skill
    errs = "\n".join(validate(_gated_pack(mini_pack_dir, edit)))
    assert "tense_persons names undeclared tense 'imperativo'" in errs
    assert "required translation 'de' is not one of translations" in errs
    assert "equivalent_tense needs a recognition verbs skill" in errs
