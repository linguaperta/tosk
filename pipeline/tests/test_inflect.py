"""Inflection tables (inflect.py): builders, wrong forms, token alignment, compiled facets."""
from pipeline import inflect, query
from pipeline.align import Aligner
from pipeline.compile import facets_for
from pipeline.lang import get_lang
from pipeline.tokens import tokenize
from pipeline.wikt import Lexeme

IT_SPEC = {
    "number": {"pos": ["noun"], "cells": ["sg", "pl"], "base": "sg"},
    "agreement": {"pos": ["adj", "det"], "cells": ["m.sg", "f.sg", "m.pl", "f.pl"], "base": "m.sg", "agreement": True},
}
NL_SPEC = {
    "number": {"pos": ["noun"], "cells": ["sg", "pl"], "base": "sg"},
    "agreement": {"pos": ["adj"], "cells": ["base", "infl"], "base": "base", "agreement": True},
    "diminutive": {"pos": ["noun"], "cells": ["sg", "dim"], "base": "sg"},
}
NL_P = ["ik", "jij", "hij/zij", "wij", "jullie", "zij"]


def lx(lemma, pos, forms, head="", **kw):
    x = Lexeme(lemma=lemma, pos=pos, glosses=["x"], head=head, **kw)
    x.entry_forms = [[(f, frozenset(t)) for f, t in forms]]
    return x


def test_italian_number_and_wrong_forms():
    t = inflect.build_tables("it", lx("amico", "noun", [("amici", ["plural"]), ("amica", ["feminine"])]),
                             IT_SPEC, known={"amiche"})["number"]
    assert t["sg"] == {"form": "amico", "stem": "amic", "ending": "o"}
    assert t["pl"]["form"] == "amici" and t["pl"]["ending"] == "i"
    # plausible errors that are no word: amiche is a word (feminine plural), never offered
    assert "amichi" in t["pl"]["wrong"] and "amiche" not in t["pl"]["wrong"]
    # invariable nouns split off the final vowel; uncountable / plural-only nouns get no table
    inv = inflect.build_tables("it", lx("città", "noun", [], invariable=True), IT_SPEC, set())["number"]
    assert inv["pl"]["form"] == "città" and inv["pl"]["stem"] == "citt"
    assert not query.inflects({"infl": {"number": inv}}, "number")
    assert inflect.build_tables("it", lx("latte", "noun", [], uncountable=True), IT_SPEC, set()) == {}


def test_italian_agreement_from_forms_and_rules():
    bello = lx("bello", "adj", [("bello", ["masculine", "singular", "error-unrecognized-form"]),
                                ("bel", ["masculine", "singular", "error-unrecognized-form"]),
                                ("bella", ["feminine", "singular", "error-unrecognized-form"]),
                                ("belli", ["masculine", "plural", "error-unrecognized-form"]),
                                ("bei", ["masculine", "plural", "error-unrecognized-form"]),
                                ("belle", ["feminine", "plural"])])
    t = inflect.build_tables("it", bello, IT_SPEC, set())["agreement"]
    assert [t[c]["form"] for c in ("m.sg", "f.sg", "m.pl", "f.pl")] == ["bello", "bella", "belli", "belle"]
    assert t["m.sg"]["alts"] == ["bel"] and t["m.pl"]["alts"] == ["bei"]
    grande = lx("grande", "adj", [], head="grande m or f by sense (plural grandi, comparative più grande)")
    g = inflect.build_tables("it", grande, IT_SPEC, set())["agreement"]
    assert [g[c]["form"] for c in ("m.sg", "f.sg", "m.pl", "f.pl")] == ["grande", "grande", "grandi", "grandi"]
    # a pronoun is no agreement table (lui/lei/loro)
    assert inflect.build_tables("it", lx("lui", "pron", [("lei", ["feminine"])]), IT_SPEC, set()) == {}


def test_dutch_tables():
    kat = lx("kat", "noun", [("katten", ["plural"]), ("katje", ["diminutive", "neuter"])])
    t = inflect.build_tables("nl", kat, NL_SPEC, known=set())
    assert t["number"]["pl"] == {"form": "katten", "stem": "kat", "ending": "ten", "wrong": ["katen", "kats"]}
    assert t["diminutive"]["dim"]["form"] == "katje" and "kattetje" in t["diminutive"]["dim"]["wrong"]
    wit = lx("wit", "adj", [("witte", ["feminine", "indefinite", "masculine", "positive", "singular"])])
    a = inflect.build_tables("nl", wit, NL_SPEC, known=set())["agreement"]
    assert a["infl"]["form"] == "witte" and a["infl"]["ending"] == "te" and a["infl"]["wrong"] == ["wite"]
    # 'duizend man': a plural spelled like the singular is left out
    man = lx("man", "noun", [("mannen", ["plural"]), ("man", ["plural"])])
    assert inflect.build_tables("nl", man, NL_SPEC, set())["number"]["pl"] == {
        "form": "mannen", "stem": "man", "ending": "nen", "wrong": ["manen", "mans"]}


def _it_items():
    def it(iid, pos, **kw):
        return {"id": iid, "lemma": iid.split(":")[1], "pos": pos, "freq": 1, "tr": {"en": ["x"]}, **kw}
    num = lambda sg, pl: {"number": {"sg": {"form": sg}, "pl": {"form": pl}}}  # noqa: E731
    agr = lambda *f: {"agreement": dict(zip(["m.sg", "f.sg", "m.pl", "f.pl"], [{"form": x} for x in f]))}  # noqa: E731
    return [it("it:casa", "noun", gender="f", infl=num("casa", "case"), inflections=["case"]),
            it("it:libro", "noun", gender="m", infl=num("libro", "libri"), inflections=["libri"]),
            it("it:bello", "adj", infl=agr("bello", "bella", "belli", "belle"), inflections=["bella", "belli", "belle"]),
            it("it:mio", "det", infl=agr("mio", "mia", "miei", "mie"), inflections=["mia", "miei", "mie"]),
            it("it:molto", "adv"), it("it:la", "det"), it("it:il", "det", inflections=["i"]),
            it("it:essere", "verb")]


def _align(aligner, text, code):
    return [(t["t"], t["lex"], t["form"]) for t in aligner.align(tokenize(text, code)) if t["is_word"]]


def test_italian_agreement_alignment_needs_the_controlling_noun():
    verbs = {"it:essere": {"id": "it:essere", "forms": {"infinitive": {"_": "essere"}, "presente": dict(
        zip(["io", "tu", "lui/lei", "noi", "voi", "loro"], ["sono", "sei", "è", "siamo", "siete", "sono"]))}}}
    a = Aligner(get_lang("it"), _it_items(), verbs, IT_SPEC)
    got = _align(a, "La casa è molto bella.", "it")
    assert ("casa", "it:casa", "infl:number.sg") in got and ("bella", "it:bello", "infl:agreement.f.sg") in got
    assert ("libri", "it:libro", "infl:number.pl") in _align(a, "I miei libri.", "it")
    assert ("miei", "it:mio", "infl:agreement.m.pl") in _align(a, "I miei libri.", "it")
    # no noun next to it: the speaker's gender is unknown ('Sono bella' / 'Sono bello'), no form
    assert ("bella", "it:bello", None) in _align(a, "Sono bella.", "it")
    # a noun that does not agree is not the controller: no form
    assert ("bella", "it:bello", None) in _align(a, "Il libro bella.", "it")


def test_dutch_agreement_and_separable_alignment():
    def it(iid, pos, **kw):
        return {"id": iid, "lemma": iid.split(":")[1], "pos": pos, "freq": 1, "tr": {"en": ["x"]}, **kw}
    agr = {"agreement": {"base": {"form": "groot"}, "infl": {"form": "grote"}}}
    items = [it("nl:groot", "adj", infl=agr, inflections=["grote"]),
             it("nl:huis", "noun", article="het", infl={"number": {"sg": {"form": "huis"}, "pl": {"form": "huizen"}}}),
             it("nl:man", "noun", article="de", infl={"number": {"sg": {"form": "man"}, "pl": {"form": "mannen"}}}),
             it("nl:een", "det"), it("nl:het", "det"), it("nl:is", "verb"), it("nl:ik", "pron"),
             it("nl:staan", "verb"), it("nl:opstaan", "verb"), it("nl:op", "prep"), it("nl:vroeg", "adv"),
             it("nl:zijn", "verb")]
    T = "tegenwoordige_tijd"
    verbs = {
        "nl:staan": {"id": "nl:staan", "forms": {"infinitive": {"_": "staan"}, T: dict(zip(NL_P, ["sta", "staat", "staat", "staan", "staan", "staan"]))}},
        "nl:opstaan": {"id": "nl:opstaan", "forms": {"infinitive": {"_": "opstaan"}, T: dict(zip(NL_P, ["sta op", "staat op", "staat op", "staan op", "staan op", "staan op"]))}},
        "nl:zijn": {"id": "nl:zijn", "forms": {"infinitive": {"_": "zijn"}, T: dict(zip(NL_P, ["ben", "bent", "is", "zijn", "zijn", "zijn"]))}},
    }
    a = Aligner(get_lang("nl"), items, verbs, NL_SPEC)
    assert ("groot", "nl:groot", "infl:agreement.base") in _align(a, "Een groot huis.", "nl")
    assert ("grote", "nl:groot", "infl:agreement.infl") in _align(a, "Het grote huis.", "nl")
    assert ("grote", "nl:groot", "infl:agreement.infl") in _align(a, "Een grote man.", "nl")
    assert ("groot", "nl:groot", "infl:agreement.base") in _align(a, "Het huis is groot.", "nl")
    # 'een groot man' (archaic: a great man) contradicts the rule: no form
    assert ("groot", "nl:groot", None) in _align(a, "Een groot man.", "nl")
    got = _align(a, "Ik sta vroeg op.", "nl")
    assert ("sta", "nl:opstaan", f"{T}.ik") in got and ("op", "nl:opstaan", f"{T}.ik") in got
    # the particle must end the clause
    assert ("sta", "nl:staan", f"{T}.ik") in _align(a, "Ik sta op het huis.", "nl")


def test_facets_for_inflection_skills():
    items = {i["id"]: i for i in _it_items()}
    plurals = {"id": "plurals", "kind": "grammar", "facet": "infl", "inflections": {"table": "number"},
               "items": {"pos": "noun"}}
    assert [f[0] for f in facets_for(plurals, ["it:casa", "it:libro"], items)] == [
        "it:casa#infl:number", "it:libro#infl:number"]
    adj = {"id": "adjectives", "kind": "grammar", "inflections": {"table": "agreement"}, "items": {"tags": ["x"]}}
    assert [f[0] for f in facets_for(adj, ["it:bello", "it:molto"], items)] == [
        "it:bello#rec", "it:bello#prod", "it:bello#infl:agreement", "it:molto#rec", "it:molto#prod"]
    assert facets_for(adj, ["it:bello"], items)[2][2:4] == ("infl", "agreement")
    # facet: infl selects only items that inflect
    assert query.resolve(plurals, list(items.values()), {}, []) == ["it:casa", "it:libro"]
    assert inflect.parse_infl_key("infl:agreement.f.sg") == ("agreement", "f.sg")
    assert inflect.parse_infl_key("presente.noi") is None
