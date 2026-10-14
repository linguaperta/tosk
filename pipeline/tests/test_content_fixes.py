"""Content fixes from the sample review: Dutch adjective before a copula ('dat ik laat ben'),
Italian imperatives, the Dutch perfect with a double infinitive, translation checks,
uncountable nouns and ambiguous articles."""
from pipeline.align import Aligner
from pipeline.features import FeatureTagger
from pipeline.lang import get_lang
from pipeline.tokens import tokenize

from test_align import IT_P, NL_P, item, nl_aligner, run, verb
from test_features import punct, table, tok


def test_dutch_adjective_before_a_copula_is_not_a_verb():
    a = nl_aligner()
    r = run(a, "Sorry dat ik laat ben.", "nl")
    assert r["laat"] == ("nl:laat", None)
    assert r["ben"] == ("nl:zijn", "tegenwoordige_tijd.ik")
    assert run(a, "Ik weet dat het laat is.", "nl")["laat"] == ("nl:laat", None)
    assert run(a, "Ik laat het huis zien.", "nl")["laat"] == ("nl:laten", "tegenwoordige_tijd.ik")
    assert run(a, "Ik laat zijn huis zien.", "nl")["laat"] == ("nl:laten", "tegenwoordige_tijd.ik")


def it_imperative_aligner():
    items = [item("it:chiedere", "verb", 20, tr={"en": ["to ask"]}), item("it:andare", "verb", 10, tr={"en": ["to go"]}),
             item("it:essere", "verb", 1, tr={"en": ["to be"]}), item("it:tu", "pron", 4), item("it:a", "prep", 9),
             item("it:un", "det", 3), item("it:non", "adv", 5), item("it:casa", "noun", 30), item("it:bravo", "adj", 40)]
    verbs = {v["id"]: v for v in [
        verb("it:chiedere", IT_P, ["chiedo", "chiedi", "chiede", "chiediamo", "chiedete", "chiedono"], "chiesto", "avere"),
        verb("it:andare", IT_P, ["vado", "vai", "va", "andiamo", "andate", "vanno"], "andato", "essere"),
        verb("it:essere", IT_P, ["sono", "sei", "è", "siamo", "siete", "sono"], "stato", "essere"),
    ]}
    return Aligner(get_lang("it"), items, verbs)


def test_italian_imperatives_get_no_present_form():
    a = it_imperative_aligner()

    def form(text, word, tr=None):
        out = a.align(tokenize(text, "it"), tr)
        return next(t["form"] for t in out if t["t"] == word)

    assert form("Chiedi a un poliziotto!", "Chiedi") is None                   # exclamation, no subject
    assert form("Non chiedete!", "chiedete") is None
    assert form("Andiamo a casa.", "Andiamo", "Let's go home.") is None       # translation: imperative
    assert form("Chiedi a un poliziotto.", "Chiedi", "Ask a policeman.") is None
    assert form("Chiedi a un poliziotto.", "Chiedi", "Please ask a policeman.") is None
    assert form("Chiedi a un poliziotto.", "Chiedi", "You ask a policeman.") == "presente.tu"
    assert form("Tu chiedi a un poliziotto!", "chiedi") == "presente.tu"      # subject pronoun
    assert form("Chiedi tu!", "Chiedi") == "presente.tu"
    assert form("Sei bravo!", "Sei") == "presente.tu"                         # essere has its own imperative
    assert form("Chiedo a un poliziotto!", "Chiedo") == "presente.io"         # io has no imperative
    assert form("Andiamo a casa.", "Andiamo", "We go home.") == "presente.noi"
    assert form("Domani chiedi a casa!", "chiedi") == "presente.tu"                  # not clause-initial


def nl_ipp_tagger():
    def v(vid, pres, part, aux="hebben"):
        return {"id": vid, "class": "strong", "irregular_in": [], "auxiliary": aux, "forms": {
            "infinitive": {"_": {"form": vid[3:]}}, "participle": {"_": {"form": part}},
            "tegenwoordige_tijd": table(pres, NL_P)}}
    verbs = {
        "nl:hebben": v("nl:hebben", "heb hebt heeft hebben hebben hebben".split(), "gehad"),
        "nl:zijn": v("nl:zijn", "ben bent is zijn zijn zijn".split(), "geweest", "zijn"),
        "nl:willen": v("nl:willen", "wil wilt wil willen willen willen".split(), "gewild"),
        "nl:zien": v("nl:zien", "zie ziet ziet zien zien zien".split(), "gezien"),
        "nl:vallen": v("nl:vallen", "val valt valt vallen vallen vallen".split(), "gevallen", "zijn"),
        "nl:leren": v("nl:leren", "leer leert leert leren leren leren".split(), "geleerd"),
        "nl:gaan": v("nl:gaan", "ga gaat gaat gaan gaan gaan".split(), "gegaan", "zijn"),
    }
    items = [{"id": x, "lemma": x[3:], "pos": "verb", "freq": i + 1, "tr": {"en": ["x"]}} for i, x in enumerate(verbs)]
    course = {"id": "nl", "persons": NL_P, "tenses": ["tegenwoordige_tijd", "verleden_tijd", "perfectum"],
              "feature_detectors": {"aux:zijn": {"type": "compound_aux", "aux": "zijn"},
                                    "modal": {"type": "modal_infinitive", "verbs": ["willen"]}},
              "units": []}
    return FeatureTagger(course, items, verbs)


def test_dutch_perfect_with_double_infinitive():
    t = nl_ipp_tagger()
    T = "tegenwoordige_tijd"
    inf = "infinitive._"
    s = [tok("Ik", None, None, ""), tok("heb", "nl:hebben", f"{T}.ik"), tok("Tom"), tok("niet"),
         tok("zien", "nl:zien", inf), tok("vallen", "nl:vallen", inf), punct(".")]
    assert t.tag(s) == {f"tense:{T}", "tense:perfectum"}
    s = [tok("Hij", None, None, ""), tok("heeft", "nl:hebben", f"{T}.hij/zij"), tok("altijd"), tok("Japans"),
         tok("willen", "nl:willen", inf), tok("leren", "nl:leren", inf), punct(".")]
    assert t.tag(s) == {f"tense:{T}", "tense:perfectum", "modal"}
    s = [tok("Ik", None, None, ""), tok("ben", "nl:zijn", f"{T}.ik"), tok("gaan", "nl:gaan", inf),
         tok("leren", "nl:leren", inf), punct(".")]
    assert t.tag(s) == {f"tense:{T}", "tense:perfectum", "aux:zijn"}
    # an infinitive spelled like the verb without a form counts too
    s = [tok("Ik", None, None, ""), tok("heb", "nl:hebben", f"{T}.ik"), tok("het"), tok("zien", "nl:zien"),
         tok("vallen", "nl:vallen"), punct(".")]
    assert "tense:perfectum" in t.tag(s)
    # one infinitive, or two after 'te', is no perfect
    s = [tok("Ik", None, None, ""), tok("heb", "nl:hebben", f"{T}.ik"), tok("zin"), tok("om"), tok("te"),
         tok("gaan", "nl:gaan", inf), tok("leren", "nl:leren", inf), punct(".")]
    assert t.tag(s) == {f"tense:{T}"}
    s = [tok("Ik", None, None, ""), tok("wil", "nl:willen", f"{T}.ik"), tok("leren", "nl:leren", inf), punct(".")]
    assert t.tag(s) == {f"tense:{T}", "modal"}
    # the infinitives belong to another clause
    s = [tok("Ik", None, None, ""), tok("heb", "nl:hebben", f"{T}.ik"), tok("tijd"), punct(","),
         tok("zien", "nl:zien", inf), tok("vallen", "nl:vallen", inf), punct(".")]
    assert t.tag(s) == {f"tense:{T}"}
    # an ordinary perfect is unchanged
    s = [tok("Ik", None, None, ""), tok("heb", "nl:hebben", f"{T}.ik"), tok("het"),
         tok("gezien", "nl:zien", "perfectum.ik"), punct(".")]
    assert t.tag(s) == {"tense:perfectum"}


def _toks(text, lang, lex=None):
    out = tokenize(text, lang)
    for t in out:
        if lex and t["t"].lower() in lex:
            t["lex"] = lex[t["t"].lower()]
    return out


def test_translation_check():
    from pipeline.trcheck import invariant_names, mismatch
    items = {"it:due": {"pos": "num"}, "it:essere": {"pos": "verb"}}
    names = {"Tom", "Mary"}

    def bad(text, tr, lang="en", code="it", lex=None):
        return mismatch(_toks(text, code, lex), items, code, tr, lang, names)

    assert bad("Ho due gatti.", "I have two cats.") is None
    assert bad("Ho due gatti.", "I have 2 cats.") is None
    assert bad("Ho due gatti.", "I have three cats.").startswith("numbers")
    assert bad("Ci vediamo lunedì.", "See you on Monday.") is None
    assert bad("Ci vediamo lunedì.", "See you on Tuesday.") == "weekday/month"
    assert bad("Il museo è chiuso il lunedì.", "The museum is closed on Mondays.") is None
    assert bad("Posso venire?", "May I come?") is None                   # 'may' is no month here
    assert bad("Grazie mille!", "Thank you very much!") is None          # idiom
    assert bad("Lo sei.", "You are.", lex={"sei": "it:essere"}) is None  # 'sei' = you are
    assert bad("Ha vent'anni.", "He is twenty.") is None                 # elided number word
    assert bad("Sono le nove e mezza.", "It's 9:30.") is None            # times are not compared
    assert bad("Tom è qui.", "Mary is here.").startswith("names")
    assert bad("Tom è qui.", "Tom is here.") is None
    assert bad("Vado a Londra.", "I'm going to London.") is None         # not an invariant name
    assert bad("Ho due gatti.", "Ik heb drie katten.", "nl").startswith("numbers")
    assert bad("Het feestje is op donderdag.", "The party's Tuesday.", code="nl") == "weekday/month"
    assert bad("Het is half drie.", "It's 2:30.", code="nl") is None
    assert bad("Daar werken 3000 mensen.", "About 3,000 people work there.", code="nl") is None
    pairs = [("Ecco Tom.", "Here is Tom.")] * 3 + [("Vado a Londra.", "I go to London.")] * 3
    assert invariant_names(pairs) == {"Tom"}


def test_dutch_was_is_zijn_unless_it_can_be_wassen():
    T, V = "tegenwoordige_tijd", "verleden_tijd"
    items = [item("nl:zijn", "verb", 1), item("nl:wassen", "verb", 500), item("nl:ik", "pron", 3),
             item("nl:hij", "pron", 5), item("nl:de", "det", 2), item("nl:auto", "noun", 90), item("nl:moe", "adj", 80)]
    verbs = {v["id"]: v for v in [
        verb("nl:zijn", NL_P, ["ben", "bent", "is", "zijn", "zijn", "zijn"], "geweest", "zijn", T,
             extra={V: dict(zip(NL_P, ["was", "was", "was", "waren", "waren", "waren"]))}),
        verb("nl:wassen", NL_P, ["was", "wast", "wast", "wassen", "wassen", "wassen"], "gewassen", "hebben", T),
    ]}
    a = Aligner(get_lang("nl"), items, verbs)
    assert run(a, "Hij was moe.", "nl")["was"] == ("nl:zijn", f"{V}.hij/zij")
    assert run(a, "Ik was moe.", "nl")["was"] == ("nl:zijn", f"{V}.ik")
    assert run(a, "Ik was de auto.", "nl")["was"] == ("nl:zijn", None)          # or: I wash the car


def test_interjections_and_multi_word_phrases():
    items = [item("it:pregare", "verb", 300), item("it:prego", "intj", 900), item("it:per", "prep", 10),
             item("it:favore", "noun", 500), item("it:per favore", "phrase", 950), item("it:io", "pron", 4),
             item("it:grazie", "intj", 20)]
    verbs = {v["id"]: v for v in [
        verb("it:pregare", IT_P, ["prego", "preghi", "prega", "preghiamo", "pregate", "pregano"], "pregato", "avere")]}
    a = Aligner(get_lang("it"), items, verbs)
    assert run(a, "Grazie! Prego.", "it")["Prego"] == ("it:prego", None)        # alone: the interjection
    assert run(a, "Prego, signora.", "it")["Prego"] == ("it:prego", None)
    assert run(a, "Io prego.", "it")["prego"] == ("it:pregare", "presente.io")
    r = run(a, "Un caffè, per favore.", "it")
    assert r["per"] == ("it:per favore", None) and r["favore"] == ("it:per favore", None)
    assert run(a, "Lo faccio per te.", "it")["per"] == ("it:per", None)

