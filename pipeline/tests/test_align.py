from pipeline.align import Aligner
from pipeline.lang import get_lang
from pipeline.tokens import tokenize

IT_P = ["io", "tu", "lui/lei", "noi", "voi", "loro"]
NL_P = ["ik", "jij", "hij/zij", "wij", "jullie", "zij"]


def item(iid, pos, freq, **kw):
    return {"id": iid, "lemma": iid.split(":", 1)[1], "pos": pos, "freq": freq, "tr": {"en": ["x"]}, **kw}


def verb(iid, persons, present, participle, aux, tense="presente", infinitive=None, extra=None):
    forms = {"infinitive": {"_": infinitive or iid.split(":", 1)[1]}, "participle": {"_": participle},
             tense: dict(zip(persons, present))}
    forms.update(extra or {})
    return {"id": iid, "auxiliary": aux, "forms": forms}


def it_aligner():
    items = [item("it:essere", "verb", 1), item("it:avere", "verb", 2), item("it:il", "det", 3,
             inflections=["la", "lo", "l'", "i", "gli", "le"]),
             item("it:io", "pron", 4), item("it:noi", "pron", 5), item("it:mangiare", "verb", 20),
             item("it:andare", "verb", 10), item("it:portare", "verb", 40), item("it:porta", "noun", 60),
             item("it:pizza", "noun", 70), item("it:libro", "noun", 80), item("it:uomo", "noun", 50),
             item("it:stanco", "adj", 90, inflections=["stanca", "stanchi", "stanche"]),
             item("it:lui", "pron", 6), item("it:che", "conj", 7), item("it:li", "pron", 8),
             item("it:casa", "noun", 30), item("it:a", "prep", 9)]
    verbs = {v["id"]: v for v in [
        verb("it:essere", IT_P, ["sono", "sei", "è", "siamo", "siete", "sono"], "stato", "essere"),
        verb("it:avere", IT_P, ["ho", "hai", "ha", "abbiamo", "avete", "hanno"], "avuto", "avere"),
        verb("it:mangiare", IT_P, ["mangio", "mangi", "mangia", "mangiamo", "mangiate", "mangiano"], "mangiato", "avere"),
        verb("it:andare", IT_P, ["vado", "vai", "va", "andiamo", "andate", "vanno"], "andato", "essere"),
        verb("it:portare", IT_P, ["porto", "porti", "porta", "portiamo", "portate", "portano"], "portato", "avere"),
    ]}
    return Aligner(get_lang("it"), items, verbs)


def nl_aligner():
    items = [item("nl:zijn", "verb", 1), item("nl:hebben", "verb", 2), item("nl:ik", "pron", 3),
             item("nl:jij", "pron", 4), item("nl:hij", "pron", 5), item("nl:wij", "pron", 6),
             item("nl:werken", "verb", 30), item("nl:lopen", "verb", 40), item("nl:gaan", "verb", 10),
             item("nl:willen", "verb", 20), item("nl:waar", "adv", 15), item("nl:waren", "verb", 900),
             item("nl:huis", "noun", 50), item("nl:naar", "prep", 12), item("nl:vandaag", "adv", 60)]
    T = "tegenwoordige_tijd"
    verbs = {v["id"]: v for v in [
        verb("nl:zijn", NL_P, ["ben", "bent", "is", "zijn", "zijn", "zijn"], "geweest", "zijn", T),
        verb("nl:hebben", NL_P, ["heb", "hebt", "heeft", "hebben", "hebben", "hebben"], "gehad", "hebben", T),
        verb("nl:werken", NL_P, ["werk", "werkt", "werkt", "werken", "werken", "werken"], "gewerkt", "hebben", T),
        verb("nl:lopen", NL_P, ["loop", "loopt", "loopt", "lopen", "lopen", "lopen"], "gelopen", "zijn|hebben", T),
        verb("nl:gaan", NL_P, ["ga", "gaat", "gaat", "gaan", "gaan", "gaan"], "gegaan", "zijn", T),
        verb("nl:willen", NL_P, ["wil", "wilt", "wil", "willen", "willen", "willen"], "gewild", "hebben", T),
        verb("nl:waren", NL_P, ["waar", "waart", "waart", "waren", "waren", "waren"], "gewaard", "hebben", T),
    ]}
    return Aligner(get_lang("nl"), items, verbs)


def run(aligner, text, lang):
    out = aligner.align(tokenize(text, lang))
    return {t["t"]: (t["lex"], t["form"]) for t in out if t["is_word"]}


def test_italian_present_and_articles():
    r = run(it_aligner(), "Noi mangiamo la pizza.", "it")
    assert r["mangiamo"] == ("it:mangiare", "presente.noi")
    assert r["la"] == ("it:il", None)
    assert r["pizza"] == ("it:pizza", None)
    assert r["Noi"] == ("it:noi", None)


def test_italian_elision_lookup():
    r = run(it_aligner(), "L'uomo mangia.", "it")
    assert r["L'"] == ("it:il", None)
    assert r["uomo"] == ("it:uomo", None)
    assert r["mangia"] == ("it:mangiare", "presente.lui/lei")


def test_italian_compound_with_avere():
    r = run(it_aligner(), "Io ho mangiato la pizza.", "it")
    assert r["ho"] == ("it:avere", "presente.io")
    assert r["mangiato"] == ("it:mangiare", "passato_prossimo.io")


def test_italian_compound_with_essere_agreement():
    r = run(it_aligner(), "Sono andate a casa.", "it")
    assert r["Sono"] == ("it:essere", "presente.loro")
    assert r["andate"] == ("it:andare", "passato_prossimo.loro")
    r = run(it_aligner(), "Lui è andato a casa.", "it")
    assert r["andato"] == ("it:andare", "passato_prossimo.lui/lei")


def test_italian_avere_participle_agrees_only_after_clitic():
    r = run(it_aligner(), "Li ho mangiati.", "it")
    assert r["mangiati"] == ("it:mangiare", "passato_prossimo.io")


def test_italian_sono_io_or_loro():
    assert run(it_aligner(), "Sono stanco.", "it")["Sono"] == ("it:essere", "presente.io")
    assert run(it_aligner(), "Sono stanchi.", "it")["Sono"] == ("it:essere", "presente.loro")


def test_noun_vs_verb():
    assert run(it_aligner(), "La porta è chiusa.", "it")["porta"] == ("it:porta", None)
    assert run(it_aligner(), "Lui porta il libro.", "it")["porta"] == ("it:portare", "presente.lui/lei")


def test_name_subject_without_third_person_form_gets_no_form():
    # subjunctive 'che Tom mangi': only the tu-form matches, so the person stays unset
    r = run(it_aligner(), "Penso che Tom mangi.", "it")
    assert r["mangi"] == ("it:mangiare", None)


def test_unknown_words_stay_unlinked():
    r = run(it_aligner(), "Mangio il xyzzy.", "it")
    assert r["xyzzy"] == (None, None)
    assert r["Mangio"] == ("it:mangiare", "presente.io")


def test_dutch_perfectum():
    a = nl_aligner()
    r = run(a, "Ik heb gewerkt.", "nl")
    assert r["heb"] == ("nl:hebben", "tegenwoordige_tijd.ik")
    assert r["gewerkt"] == ("nl:werken", "perfectum.ik")
    r = run(a, "Hij is naar huis gegaan.", "nl")
    assert r["is"] == ("nl:zijn", "tegenwoordige_tijd.hij/zij")
    assert r["gegaan"] == ("nl:gaan", "perfectum.hij/zij")
    r = run(a, "Heeft hij vandaag gewerkt?", "nl")
    assert r["gewerkt"] == ("nl:werken", "perfectum.hij/zij")


def test_dutch_inversion_and_plural_and_infinitive():
    a = nl_aligner()
    assert run(a, "Werk jij vandaag?", "nl")["Werk"] == ("nl:werken", None)
    assert run(a, "Werkt hij vandaag?", "nl")["Werkt"] == ("nl:werken", "tegenwoordige_tijd.hij/zij")
    assert run(a, "Wij lopen.", "nl")["lopen"] == ("nl:lopen", "tegenwoordige_tijd.wij")
    r = run(a, "Ik wil lopen.", "nl")
    assert r["wil"] == ("nl:willen", "tegenwoordige_tijd.ik")
    assert r["lopen"] == ("nl:lopen", "infinitive._")


def test_dutch_ik_form_without_ik_is_not_a_verb():
    r = run(nl_aligner(), "Waar is hij?", "nl")
    assert r["Waar"] == ("nl:waar", None)
    assert r["is"] == ("nl:zijn", "tegenwoordige_tijd.hij/zij")
