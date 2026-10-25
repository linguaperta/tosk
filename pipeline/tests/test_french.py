"""French language rules (lang_fr.py): tokenizer, aligner, moods, features, inflection and numbers."""
from pipeline import features, trcheck
from pipeline.align import Aligner
from pipeline.inflect import _fr_feminine, _fr_plural
from pipeline.lang import get_lang
from pipeline.tokens import render, tokenize

FR = get_lang("fr")
P = ["je", "tu", "il/elle", "nous", "vous", "ils/elles"]


def item(iid, pos, freq, **kw):
    return {"id": iid, "lemma": kw.pop("lemma", iid.split(":", 1)[1]), "pos": pos, "freq": freq,
            "tr": {"en": ["x"]}, **kw}


def table(*forms):
    return dict(zip(P, forms))


def verb(lemma, aux, participle, present, **tenses):
    forms = {"infinitive": {"_": lemma}, "participle": {"_": participle}, "present": table(*present)}
    for t, fs in tenses.items():
        forms[t] = table(*fs) if t != "imperatif" else dict(zip(["tu", "nous", "vous"], fs))
    return {"id": f"fr:{lemma}", "auxiliary": aux, "forms": forms}


def aligner():
    items = [item("fr:être", "verb", 1), item("fr:avoir", "verb", 2), item("fr:je", "pron", 3),
             item("fr:tu", "pron", 4), item("fr:il", "pron", 5), item("fr:elle", "pron", 6),
             item("fr:nous", "pron", 7), item("fr:vous", "pron", 8), item("fr:le", "det", 9, inflections=["la", "les"]),
             item("fr:le.2", "pron", 40, lemma="le"), item("fr:la", "pron", 41), item("fr:les", "pron", 42),
             item("fr:que", "conj", 10), item("fr:ne", "particle", 11), item("fr:pas", "adv", 12),
             item("fr:se", "pron", 13), item("fr:me", "pron", 14), item("fr:porte", "noun", 50),
             item("fr:parler", "verb", 20), item("fr:aller", "verb", 21), item("fr:lever", "verb", 30),
             item("fr:porter", "verb", 31), item("fr:vouloir", "verb", 22), item("fr:savoir", "verb", 23),
             item("fr:voir", "verb", 24), item("fr:lettre", "noun", 60), item("fr:français", "adj", 61),
             item("fr:marier", "verb", 90), item("fr:salut", "intj", 70)]
    verbs = {v["id"]: v for v in [
        verb("être", "avoir", "été", ["suis", "es", "est", "sommes", "êtes", "sont"],
             imparfait=["étais", "étais", "était", "étions", "étiez", "étaient"],
             subjonctif=["sois", "sois", "soit", "soyons", "soyez", "soient"]),
        verb("avoir", "avoir", "eu", ["ai", "as", "a", "avons", "avez", "ont"],
             imparfait=["avais", "avais", "avait", "avions", "aviez", "avaient"],
             subjonctif=["aie", "aies", "ait", "ayons", "ayez", "aient"]),
        verb("parler", "avoir", "parlé", ["parle", "parles", "parle", "parlons", "parlez", "parlent"],
             subjonctif=["parle", "parles", "parle", "parlions", "parliez", "parlent"],
             imperatif=["parle", "parlons", "parlez"]),
        verb("aller", "être", "allé", ["vais", "vas", "va", "allons", "allez", "vont"]),
        verb("lever", "avoir", "levé", ["lève", "lèves", "lève", "levons", "levez", "lèvent"]),
        verb("porter", "avoir", "porté", ["porte", "portes", "porte", "portons", "portez", "portent"]),
        verb("vouloir", "avoir", "voulu", ["veux", "veux", "veut", "voulons", "voulez", "veulent"]),
        verb("savoir", "avoir", "su", ["sais", "sais", "sait", "savons", "savez", "savent"]),
        verb("voir", "avoir", "vu", ["vois", "vois", "voit", "voyons", "voyez", "voient"]),
        verb("marier", "avoir", "marié", ["marie", "maries", "marie", "marions", "mariez", "marient"],
             imperatif=["marie", "marions", "mariez"]),
    ]}
    for v in verbs.values():
        lemma = v["id"].split(":")[1]
        aux = v["auxiliary"]
        part = v["forms"]["participle"]["_"]
        for ct, at in FR.compound_tenses.items():
            src = verbs.get(f"fr:{aux}", {}).get("forms", {}).get(at)
            if src:
                v["forms"][ct] = {p: FR.compound(src, part, p, aux)[0] for p in P}
    return Aligner(FR, items, verbs), items, verbs


def run(al, text, tr=None):
    return [(t["t"], t["lex"], t["form"]) for t in al.align(tokenize(text, "fr"), translation=tr) if t["is_word"]]


def test_tokenizer_elision_and_hyphens():
    for text, want in [("L'homme qu'il voit.", ["L'", "homme", "qu'", "il", "voit", "."]),
                       ("Aujourd'hui, j'arrive.", ["Aujourd'hui", ",", "j'", "arrive", "."]),
                       ("Parlez-vous français ?", ["Parlez-vous", "français", "?"]),
                       ("Jusqu'à quand ?", ["Jusqu'", "à", "quand", "?"]),
                       ("Quelqu'un a-t-il vu ça ?", ["Quelqu'un", "a-t-il", "vu", "ça", "?"])]:
        toks = tokenize(text, "fr")
        assert [t["t"] for t in toks] == want
        assert render(toks) == text


def test_compound_tenses_with_their_auxiliary_tense():
    al, _, _ = aligner()
    assert run(al, "Elle est allée.")[1:3] == [("est", "fr:être", "present.il/elle"),
                                                ("allée", "fr:aller", "passe_compose.il/elle")]
    assert run(al, "J'avais parlé.")[1:3] == [("avais", "fr:avoir", "imparfait.je"),
                                               ("parlé", "fr:parler", "plus_que_parfait.je")]
    # agreement with a preceding direct object ('les ... que j'ai écrites'), never without one
    assert run(al, "Je les ai vues.")[3] == ("vues", "fr:voir", "passe_compose.je")
    assert run(al, "J'ai vues.")[2][2] != "passe_compose.je"


def test_reflexive_compound_takes_etre():
    al, _, _ = aligner()
    assert run(al, "Je me suis levé.")[3] == ("levé", "fr:lever", "passe_compose.je")
    assert run(al, "Il est levé.")[2][2] != "passe_compose.il/elle"       # no reflexive pronoun


def test_moods_after_que():
    al, _, _ = aligner()
    assert run(al, "Je veux que tu parles.")[4] == ("parles", "fr:parler", "subjonctif.tu")
    assert run(al, "Je sais que tu parles.")[4] == ("parles", "fr:parler", "present.tu")
    out = al.align(tokenize("Il dit que tu parles.", "fr"))
    assert any(t.get("unsure") for t in out)          # 'dire que' is no trigger: unsure, dropped


def test_hyphenated_inversion_and_imperative():
    al, _, _ = aligner()
    assert run(al, "Parlez-vous ?")[0] == ("Parlez-vous", "fr:parler", "present.vous")
    assert run(al, "Parlez-moi !")[0] == ("Parlez-moi", "fr:parler", "imperatif.vous")



def test_subjectless_clause_initial_verb_is_imperative():
    al, _, _ = aligner()
    # French never drops the subject, so the translation's verb need not match ('Keep talking.')
    assert run(al, "Parle.", "Keep talking.")[0] == ("Parle", "fr:parler", "imperatif.tu")
    assert run(al, "Parle.", "He talks.")[0][2] != "imperatif.tu"     # the translation has a subject
    assert run(al, "Il parle.", "Keep talking.")[1] == ("parle", "fr:parler", "present.il/elle")
    # a sentence-initial name kept in the translation is no imperative of marier
    assert run(al, "Marie parle.", "Marie talks.")[0][1] is None
    # a reporting verb after a quote is inverted, not an imperative
    assert run(al, "« Tu parles ? » parle Marie.", "\"Are you talking?\" Marie talks.")[2][2] != "imperatif.tu"

def test_object_clitics_and_names():
    al, _, _ = aligner()
    out = run(al, "Je la porte.")
    assert out[1][1] == "fr:la" and out[2] == ("porte", "fr:porter", "present.je")
    assert run(al, "La porte.")[1][1] == "fr:porte"
    assert run(al, "Salut, Marie !")[1][1] is None    # a name, not the imperative of marier


def test_reflexive_detector_needs_two_nous():
    al, items, verbs = aligner()
    course = {"id": "fr", "persons": P, "feature_detectors": {"reflexive": {
        "type": "reflexive", "pronouns": {"me": "je", "nous": "nous", "vous": "vous"},
        "clitics": ["ne"], "subject_pronouns": ["nous", "vous"]}}}
    tagger = features.FeatureTagger(course, items, verbs)

    def refl(text):
        return "reflexive" in tagger.tag(al.align(tokenize(text, "fr")))
    assert refl("Je me lève.") and refl("Nous nous levons.") and refl("Vous ne vous levez pas.")
    assert not refl("Vous levez la main.")


def test_french_spelling_morphology_and_numbers():
    assert FR.spelling("me souviens", None) == "souviens"
    assert FR.spelling("souviens-toi", None) == "souviens"
    assert FR.spelling("paʁl", None) == ""
    assert FR.auxiliary_of("s'être + past participle", ["infinitive", "multiword-construction"]) == ["être"]
    assert FR.compound(table("suis", "es", "est", "sommes", "êtes", "sont"), "allé", "vous", "être") == \
        ("êtes allés", ["êtes allées", "êtes allé", "êtes allée"])
    assert FR.participle_variants("pris", "avoir") == ["pris", "prise", "pris", "prises"]
    assert FR.article_for("homme", "m") == "l'" and FR.article_for("héros", "m") == "le"
    assert _fr_feminine("meilleur") == "meilleure" and _fr_feminine("heureux") == "heureuse"
    assert _fr_plural("cheval") == "chevaux"
    assert [v for v, _ in trcheck.number_values(["vingt-deux", "ans", "quatre-vingt-dix", "euros", "deux", "cents"], "fr")] == [22, 90, 200]
