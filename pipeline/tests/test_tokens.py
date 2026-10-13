import pytest

from pipeline.tokens import render, tokenize

ROUND_TRIP = [
    ("it", "L'acqua dell'uomo c'è, un po' fredda... vero?!"),
    ("it", "Dov'è l'albergo? Quell'amica è un'insegnante."),
    ("it", "«Andiamo», disse.  Poi   partì."),
    ("it", "Ho 3,5 euro e un'e-mail."),
    ("it", "E' tardi, Tom'."),
    ("nl", "Ik heb 's ochtends twee auto's, zo'n mooie e-mail."),
    ("nl", "'t Is m'n fiets; z'n auto staat daar."),
    ("nl", "\"Hallo\" — zei hij… Echt?"),
    ("nl", "Ze zei: 'kom maar'."),
]


@pytest.mark.parametrize("lang,text", ROUND_TRIP)
def test_round_trip(lang, text):
    toks = tokenize(text, lang)
    assert render(toks) == text
    for t in toks:
        assert t["t"] and t["pre"].strip() == ""


def words(text, lang):
    return [t["t"] for t in tokenize(text, lang) if t["is_word"]]


def test_italian_elision_splits_after_apostrophe():
    assert words("L'acqua dell'uomo c'è", "it") == ["L'", "acqua", "dell'", "uomo", "c'", "è"]
    assert words("un'amica", "it") == ["un'", "amica"]
    toks = tokenize("l'acqua", "it")
    assert toks[1]["pre"] == ""          # no space between l' and acqua


def test_italian_truncation_keeps_apostrophe():
    assert words("un po' di pane", "it") == ["un", "po'", "di", "pane"]
    # a closing quote after a normal word is punctuation
    toks = tokenize("Tom' arriva", "it")
    assert [t["t"] for t in toks] == ["Tom", "'", "arriva"]
    assert toks[1]["is_word"] is False


def test_dutch_apostrophes():
    assert words("twee auto's en zo'n ding", "nl") == ["twee", "auto's", "en", "zo'n", "ding"]
    assert words("'s ochtends", "nl") == ["'s", "ochtends"]


def test_punctuation_tokens():
    toks = tokenize("Sì... no?!", "it")
    assert [(t["t"], t["is_word"]) for t in toks] == [("Sì", True), ("...", False), ("no", True), ("?", False), ("!", False)]
    assert [t["pre"] for t in toks] == ["", "", " ", "", ""]


def test_hyphenated_word_is_one_token():
    assert words("een e-mail sturen", "nl") == ["een", "e-mail", "sturen"]
