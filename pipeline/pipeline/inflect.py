"""Inflection tables of non-verbs (docs/ARCHITECTURE.md, "Inflection tables").

A course declares its tables in course.yaml (``inflection_tables``: cells in order, labels, which
parts of speech, the base cell, whether the cells are chosen by agreement). The importer fills them
per item from the Wiktionary entries with the builders below (one per language and table) and
writes them to the lexicon record:

    "infl": {"number": {"sg": {"form": "gatto", "stem": "gatt", "ending": "o"},
                        "pl": {"form": "gatti", "stem": "gatt", "ending": "i", "wrong": ["gatte"]}}}

* ``form`` / ``alts``: the canonical form and accepted alternatives (``kinderen`` / ``kinders``).
* ``stem`` + ``ending``: the split for the ending picker; both or neither (stem+ending == form).
  The stem is the longest common prefix of the table's forms (``gatt`` + o/i, ``wit`` + ''/te).
* ``wrong``: plausible learner errors that are **no word** of the language (checked against the
  50k frequency list and every Wiktionary form): ``katen``, ``huisen``, ``witte`` → ``wite``,
  ``huistje``. The app offers them in sentence exercises (cloze, spot the error), where a real
  word of another lemma could be right against the sentence (``gatte`` for ``gatti``).

The aligner marks inflected tokens with ``form = 'infl:{table}.{cell}'`` (``align_inflections``):
number and diminutive tokens by their spelling; agreement tokens only when the language rules
below find the word that controls the agreement, so another cell of the table is certainly wrong
in that sentence (``una casa bella`` → bello/belli/belle are wrong).

Languages without builders get no tables (an empty ``infl``). A new language adds its builders to
``BUILDERS`` and, for agreement tables, a controller rule to ``AGREEMENT``.
"""
from __future__ import annotations

import re
from typing import Callable

from .wikt import Lexeme

INFL_PREFIX = "infl:"
TABLE_RE = re.compile(r"^[a-z][a-z0-9_]*$")
CELL_RE = re.compile(r"^[a-z0-9_]+(\.[a-z0-9_]+)*$")
BAD = {"archaic", "obsolete", "dialectal", "regional", "rare", "alternative", "misspelling", "dated",
       "nonstandard", "uncommon", "Tuscany", "literary", "poetic", "proscribed", "colloquial", "informal",
       "Belgium", "Flanders", "Suriname", "error-unknown-tag"}
MAX_WRONG = 4


def infl_key(table: str, cell: str) -> str:
    return f"{INFL_PREFIX}{table}.{cell}"


def parse_infl_key(form: str | None) -> tuple[str, str] | None:
    """('number', 'pl') for 'infl:number.pl'; None for verb forms ('presente.noi') and None."""
    if not form or not form.startswith(INFL_PREFIX):
        return None
    rest = form[len(INFL_PREFIX):]
    table, _, cell = rest.partition(".")
    return (table, cell) if table and cell else None


def _lcp(words: list[str]) -> str:
    if not words:
        return ""
    a, b = min(words), max(words)
    i = 0
    while i < len(a) and i < len(b) and a[i] == b[i]:
        i += 1
    return a[:i]


def _good(tags: frozenset[str]) -> bool:
    return not (tags & BAD)


def _forms(lx: Lexeme, want: Callable[[frozenset[str]], bool], entry: int | None = None) -> list[str]:
    """Spellings whose tags satisfy `want`, first entry that has any (several etymologies are merged:
    'boom' tree/bomen and boom barrier/booms), in Wiktionary order, without duplicates."""
    entries = lx.entry_forms if entry is None else lx.entry_forms[entry:entry + 1]
    for forms in entries:
        out: list[str] = []
        for f, tags in forms:
            if want(tags) and _good(tags) and " " not in f and f not in out and f not in ("-", "—"):
                out.append(f)
        if out:
            return out
    return []


def _cell(form: str, alts: list[str] | None = None) -> dict:
    rec: dict = {"form": form}
    alts = [a for a in (alts or []) if a != form]
    if alts:
        rec["alts"] = alts
    return rec


def split_table(table: dict[str, dict], lemma: str, vowel_stem: bool = False) -> None:
    """Adds stem/ending to every cell: the stem is the longest common prefix of the canonical forms
    (at least 2 letters). `vowel_stem` (Italian): a table whose forms all equal the lemma ending in a
    vowel splits off that vowel (città → citt + à), so the picker can still ask for the ending."""
    forms = [c["form"] for c in table.values()]
    if any(" " in f or "'" in f for f in forms):
        return
    stem = _lcp(forms)
    if vowel_stem and stem == lemma and lemma[-1:].lower() in "aeiouàèéìòù" and len(lemma) > 2:
        stem = lemma[:-1]
    if len(stem) < 2 or all(f == stem for f in forms):
        return
    for c in table.values():
        c["stem"], c["ending"] = stem, c["form"][len(stem):]


def _add_wrong(table: dict[str, dict], cell: str, cands: list[str], known: set[str]) -> None:
    """Plausible wrong forms for `cell`: no word of the language, no form of the table."""
    taken = {f.lower() for c in table.values() for f in [c["form"], *c.get("alts", [])]}
    out: list[str] = []
    for w in cands:
        lw = w.lower()
        if not w or lw in taken or lw in known or w in out or len(w) < 2:
            continue
        out.append(w)
        if len(out) >= MAX_WRONG:
            break
    if out:
        table[cell]["wrong"] = out


# ------------------------------------------------------------------------------------------ Italian
_IT_VOWELS = "aeiouàèéìòù"


def _it_ending_cands(stem: str, lemma: str) -> list[str]:
    # an h only keeps a hard c/g before i/e: plausible for -co/-ca/-go/-ga words (amici/amichi,
    # lunghi/lungi), not for -ce/-ge (felici, not felichi)
    hard = stem[-1:] in ("c", "g") and lemma[-1:] in ("o", "a")
    ends = ["i", "e"]
    if hard:
        ends += ["hi", "he"]
    if lemma.endswith("o"):
        ends.append("a")
    ends.append("o")
    if stem.endswith(("ch", "gh")):
        return [stem + e for e in ends] + [stem[:-1] + e for e in ("i", "e")]
    return [stem + e for e in ends]


def it_number(lx: Lexeme, known: set[str]) -> dict | None:
    if lx.pos != "noun" or lx.uncountable or lx.plural_only or " " in lx.lemma:
        return None
    lemma = lx.lemma
    if lx.invariable:
        plurals = [lemma]
    else:
        plurals = _forms(lx, lambda t: "plural" in t and "diminutive" not in t and "augmentative" not in t)
        plurals = [p for p in plurals if p != lemma] or ([lx.plural] if lx.plural and lx.plural != lemma else [])
    if not plurals:
        return None
    t = {"sg": _cell(lemma), "pl": _cell(plurals[0], plurals[1:])}
    split_table(t, lemma, vowel_stem=True)
    if "stem" in t["pl"]:
        _add_wrong(t, "pl", _it_ending_cands(t["pl"]["stem"], lemma), known)
    return t


def it_agreement(lx: Lexeme, known: set[str]) -> dict | None:
    """m.sg / f.sg / m.pl / f.pl of adjectives and determiners (possessives, questo, quello). Personal
    pronouns are no agreement table (lui/lei/loro), and only adjectives get rule-based forms."""
    if lx.pos not in ("adj", "det") or " " in lx.lemma:
        return None
    lemma = lx.lemma
    if lx.invariable:
        forms = {c: [lemma] for c in ("m.sg", "f.sg", "m.pl", "f.pl")}
    else:
        fsg = _forms(lx, lambda t: "feminine" in t and "plural" not in t and t <= {"feminine", "singular", "error-unrecognized-form"})
        mpl = _forms(lx, lambda t: "plural" in t and "feminine" not in t and t <= {"masculine", "plural", "error-unrecognized-form"})
        fpl = _forms(lx, lambda t: "plural" in t and "masculine" not in t and t <= {"feminine", "plural", "error-unrecognized-form"})
        msg = [lemma] + _forms(lx, lambda t: "masculine" in t and "singular" in t and "plural" not in t
                               and t <= {"masculine", "singular", "error-unrecognized-form"})
        plain_pl = _forms(lx, lambda t: t == frozenset({"plural"}))
        if lemma.endswith("e") and not fsg:
            fsg = [lemma]                       # grande, felice: m = f
        if plain_pl:
            mpl = mpl or plain_pl
            fpl = fpl or plain_pl
        if lx.pos != "adj" and not (fsg and mpl and fpl):
            return None
        if lemma.endswith("e") and not lemma.endswith(("ce", "ge")) and not mpl and not fpl and \
                re.search(r"plural " + re.escape(lemma[:-1] + "i") + r"\b", lx.head):
            mpl = fpl = [lemma[:-1] + "i"]     # 'grande m or f by sense (plural grandi, ...)'
        if not fsg and lemma.endswith("o") and not lemma.endswith(("co", "go")):
            fsg = [lemma[:-1] + "a"]
        if not mpl and lemma.endswith("o") and not lemma.endswith(("co", "go", "io")):
            mpl = [lemma[:-1] + "i"]
        if not fpl and lemma.endswith("o") and not lemma.endswith(("co", "go")):
            fpl = [lemma[:-1] + "e"]
        if not (fsg and mpl and fpl):
            return None
        forms = {"m.sg": list(dict.fromkeys(msg)), "f.sg": fsg, "m.pl": mpl, "f.pl": fpl}
    t = {c: _cell(v[0], v[1:]) for c, v in forms.items()}
    split_table(t, lemma)
    if "stem" in t["m.sg"]:
        cands = _it_ending_cands(t["m.sg"]["stem"], lemma)
        for c in t:
            _add_wrong(t, c, cands, known)
    return t


# ------------------------------------------------------------------------------------------ Dutch
_NL_VOWELS = "aeiouyáéíóúèëïöü"


def _nl_short(word: str) -> bool:
    """Ends in one short vowel + one consonant (kat, dag, zus), so a suffix doubles the consonant."""
    return (len(word) >= 2 and word[-1] not in _NL_VOWELS and word[-2] in _NL_VOWELS
            and (len(word) < 3 or word[-3] not in _NL_VOWELS))


def _nl_variants(word: str, suffix: str) -> list[str]:
    """Spelling-rule errors for word + suffix: naive, doubled and undoubled consonant, open-syllable
    vowel, f/v and s/z (kat: katen, katten; boom: boomen, bomen; huis: huisen; lief: liefe)."""
    out = [word + suffix]
    if len(word) >= 2 and word[-1] not in _NL_VOWELS:
        if _nl_short(word):
            out.append(word + word[-1] + suffix)            # a short vowel: dik -> dikke
        if word[-1] == word[-2]:
            out.append(word[:-1] + suffix)
        if len(word) >= 3 and word[-2] == word[-3] and word[-2] in _NL_VOWELS:
            out.append(word[:-2] + word[-1] + suffix)      # groot -> grote (right or wrong)
        if word[-1] == "f":
            out.append(word[:-1] + "v" + suffix)
        if word[-1] == "s":
            out.append(word[:-1] + "z" + suffix)
        if word[-1] == "v":
            out.append(word[:-1] + "f" + suffix)
        if word[-1] == "z":
            out.append(word[:-1] + "s" + suffix)
    return out


def nl_number(lx: Lexeme, known: set[str]) -> dict | None:
    if lx.pos != "noun" or lx.uncountable or lx.plural_only or " " in lx.lemma:
        return None
    lemma = lx.lemma
    plurals = _forms(lx, lambda t: "plural" in t and "diminutive" not in t)
    plurals = [p for p in plurals if p != lemma]      # 'duizend man': a measure plural, not the plural
    if not plurals:
        return None
    t = {"sg": _cell(lemma), "pl": _cell(plurals[0], plurals[1:])}
    split_table(t, lemma)
    if lemma[-1:] == "e":
        cands = [lemma + "s", lemma + "n"]                        # groenten / groentes, meisjes
    elif lemma[-1:] in _NL_VOWELS:
        cands = [lemma + "s", lemma + "'s", lemma + "n"]          # auto's / autos
    else:
        cands = _nl_variants(lemma, "en") + ([] if lemma[-1:] in "sz" else [lemma + "s"])
    _add_wrong(t, "pl", cands, known)
    return t


def nl_agreement(lx: Lexeme, known: set[str]) -> dict | None:
    """base (predicative, after een + het-word) / infl (the -e form) of adjectives."""
    if lx.pos != "adj" or " " in lx.lemma:
        return None
    lemma = lx.lemma
    infl = _forms(lx, lambda t: {"positive", "singular", "indefinite", "masculine", "feminine"} <= t)
    if not infl:
        return None
    t = {"base": _cell(lemma), "infl": _cell(infl[0])}
    split_table(t, lemma)
    _add_wrong(t, "infl", _nl_variants(lemma, "e"), known)
    return t


def nl_comparison(lx: Lexeme, known: set[str]) -> dict | None:
    if lx.pos != "adj" or " " in lx.lemma:
        return None
    lemma = lx.lemma
    comp = _forms(lx, lambda t: t == frozenset({"comparative"}))
    sup = _forms(lx, lambda t: t == frozenset({"superlative"}))
    if not comp or not sup:
        return None
    t = {"base": _cell(lemma), "comparative": _cell(comp[0], comp[1:]), "superlative": _cell(sup[0], sup[1:])}
    split_table(t, lemma)
    _add_wrong(t, "comparative", _nl_variants(lemma, "er"), known)
    _add_wrong(t, "superlative", _nl_variants(lemma, "st") + [lemma + "ste"], known)
    return t


def nl_diminutive(lx: Lexeme, known: set[str]) -> dict | None:
    if lx.pos != "noun" or " " in lx.lemma:
        return None
    lemma = lx.lemma
    dims = _forms(lx, lambda t: "diminutive" in t)
    if not dims or dims[0] == lemma:
        return None
    t = {"sg": _cell(lemma), "dim": _cell(dims[0])}
    split_table(t, lemma)
    cands = [lemma + s for s in ("je", "tje", "etje")]
    if lemma[-1:] == "m":
        cands.append(lemma + "pje")                          # boompje / boomtje
    if _nl_short(lemma):
        cands.append(lemma + lemma[-1] + "etje")             # mannetje / manetje
    elif lemma[-1:] in "aou":
        cands.append(lemma + lemma[-1] + "tje")              # autootje / autotje
    _add_wrong(t, "dim", cands, known)
    return t


# ------------------------------------------------------------------------------------------ Spanish
def _es_plural_cands(lemma: str) -> list[str]:
    """Plausible plural mistakes: -s/-es confusions, z kept (lápizes), the accent kept or lost."""
    plain = lemma.translate(str.maketrans("áéíóú", "aeiou"))
    cands = [lemma + "s", lemma + "es", plain + "es", plain + "s"]
    if lemma.endswith("z"):
        cands += [lemma[:-1] + "zes", lemma[:-1] + "ses"]
    return cands


def es_number(lx: Lexeme, known: set[str]) -> dict | None:
    """sg/pl of Spanish nouns: casa/casas, ciudad/ciudades, luz/luces, canción/canciones; nouns
    whose plural equals the singular (el lunes / los lunes) are left out like Italian città."""
    if lx.pos != "noun" or lx.uncountable or lx.plural_only or " " in lx.lemma:
        return None
    lemma = lx.lemma
    plurals = _forms(lx, lambda t: "plural" in t and "diminutive" not in t and "augmentative" not in t)
    plurals = [p for p in plurals if p != lemma] or ([lx.plural] if lx.plural and lx.plural != lemma else [])
    plurals = [p for p in plurals if p[:2].lower() == lemma[:2].lower()]   # not 'reinas' for 'rey'
    if not plurals:
        return None
    t = {"sg": _cell(lemma), "pl": _cell(plurals[0], plurals[1:])}
    split_table(t, lemma)
    if len(t["sg"].get("stem", lemma)) < len(lemma) - 2:
        for c in t.values():               # 'ex' + amen / ámenes: an accent shift, no clean ending
            c.pop("stem", None), c.pop("ending", None)
    _add_wrong(t, "pl", _es_plural_cands(lemma), known)
    return t


def es_agreement(lx: Lexeme, known: set[str]) -> dict | None:
    """m.sg / f.sg / m.pl / f.pl of adjectives and determiners (bonito/bonita/bonitos/bonitas,
    fácil/fácil/fáciles/fáciles, nuestro, mi/mis). Forms from Wiktionary, with the regular -o/-a and
    -e/consonant patterns as a fallback for adjectives."""
    if lx.pos not in ("adj", "det") or " " in lx.lemma:
        return None
    lemma = lx.lemma
    ok = {"error-unrecognized-form"}
    fsg = _forms(lx, lambda t: "feminine" in t and "plural" not in t and t <= {"feminine", "singular"} | ok)
    mpl = _forms(lx, lambda t: "plural" in t and "feminine" not in t and t <= {"masculine", "plural"} | ok)
    fpl = _forms(lx, lambda t: "plural" in t and "masculine" not in t and t <= {"feminine", "plural"} | ok)
    common_pl = _forms(lx, lambda t: "plural" in t and (t <= {"plural"} | ok
                                                        or t <= {"masculine", "feminine", "plural"} | ok))
    if common_pl:
        mpl, fpl = mpl or common_pl, fpl or common_pl
    if not fsg and not lemma.endswith("o"):
        fsg = [lemma]                          # grande, fácil, azul, mi: m = f
    if lx.pos == "adj":
        if not fsg and lemma.endswith("o"):
            fsg = [lemma[:-1] + "a"]
        if not mpl:
            mpl = [lemma + ("s" if lemma[-1:] in "aeiouáéó" else "es")]
        if not fpl:
            fpl = [fsg[0] + ("s" if fsg[0][-1:] in "aeiouáéó" else "es")]
    if not (fsg and mpl and fpl):
        return None
    forms = {"m.sg": [lemma], "f.sg": fsg, "m.pl": mpl, "f.pl": fpl}
    t = {c: _cell(v[0], v[1:]) for c, v in forms.items()}
    split_table(t, lemma)
    if "stem" in t["m.sg"]:
        stem = t["m.sg"]["stem"]
        cands = [stem + e for e in ("o", "a", "os", "as", "es", "e", "s")]
        for c in t:
            _add_wrong(t, c, cands, known)
    return t


# ------------------------------------------------------------------------------------------ French
def _fr_plural_cands(lemma: str) -> list[str]:
    """Plausible plural mistakes, the regular rule where the word is irregular and the other way
    round: chevals, travails, gâteaus, bijous, œils; festivaux, troux, pneux. Only forms that are no
    word and no form of the table are kept (_add_wrong)."""
    if lemma.endswith(("s", "x", "z")):
        return []
    cands = [lemma + "s"]
    if lemma.endswith("al"):
        cands.append(lemma[:-2] + "aux")
    if lemma.endswith("ail"):
        cands.append(lemma[:-3] + "aux")
    if lemma.endswith(("eau", "au", "eu", "ou")):
        cands.append(lemma + "x")
    return cands


def fr_number(lx: Lexeme, known: set[str]) -> dict | None:
    """sg/pl of French nouns (maison/maisons, cheval/chevaux, œil/yeux); nouns whose plural equals
    the singular (le prix / les prix) are left out like Italian città."""
    if lx.pos != "noun" or lx.uncountable or lx.plural_only or " " in lx.lemma:
        return None
    lemma = lx.lemma
    plurals = _forms(lx, lambda t: "plural" in t and "diminutive" not in t)
    plurals = [p for p in plurals if p != lemma] or ([lx.plural] if lx.plural and lx.plural != lemma else [])
    if not plurals:
        return None
    t = {"sg": _cell(lemma), "pl": _cell(plurals[0], plurals[1:])}
    split_table(t, lemma)
    _add_wrong(t, "pl", _fr_plural_cands(lemma), known)
    return t


def _fr_feminine(lemma: str) -> str:
    """The regular feminine of an adjective (petit -> petite, heureux -> heureuse, actif -> active,
    cruel -> cruelle, ancien -> ancienne, bon -> bonne, cher -> chère, rapide -> rapide)."""
    if lemma.endswith(("ieur", "meilleur", "majeur", "mineur")):
        return lemma + "e"                  # meilleur -> meilleure, supérieur -> supérieure
    for a, b in (("eux", "euse"), ("eur", "euse"), ("if", "ive"), ("el", "elle"), ("eil", "eille"), ("ien", "ienne"),
                 ("on", "onne"), ("er", "ère"), ("et", "ète"), ("c", "che")):
        if lemma.endswith(a):
            return lemma[: -len(a)] + b
    return lemma if lemma.endswith("e") else lemma + "e"


def _fr_plural(word: str) -> str:
    if word.endswith(("s", "x", "z")):
        return word
    if word.endswith("al"):
        return word[:-2] + "aux"
    if word.endswith(("eau", "eu")):
        return word + "x"
    return word + "s"


def fr_agreement(lx: Lexeme, known: set[str]) -> dict | None:
    """m.sg / f.sg / m.pl / f.pl of adjectives and determiners (petit/petite/petits/petites,
    heureux/heureuse/heureux/heureuses, mon/ma/mes/mes, ce/cette/ces/ces). Forms from Wiktionary,
    the regular patterns as a fallback for adjectives."""
    if lx.pos not in ("adj", "det") or " " in lx.lemma:
        return None
    lemma = lx.lemma
    ok = {"error-unrecognized-form"}
    fsg = _forms(lx, lambda t: "feminine" in t and "plural" not in t and t <= {"feminine", "singular"} | ok)
    mpl = _forms(lx, lambda t: "plural" in t and "feminine" not in t and t <= {"masculine", "plural"} | ok)
    fpl = _forms(lx, lambda t: "plural" in t and "masculine" not in t and t <= {"feminine", "plural"} | ok)
    common_pl = _forms(lx, lambda t: "plural" in t and (t <= {"plural"} | ok
                                                        or t <= {"masculine", "feminine", "plural"} | ok))
    if common_pl:
        mpl, fpl = mpl or common_pl, fpl or common_pl
    if lx.pos == "adj":
        if lx.invariable:
            fsg, mpl, fpl = [lemma], [lemma], [lemma]
        fsg = fsg or [_fr_feminine(lemma)]
        mpl = mpl or [_fr_plural(lemma)]
        fpl = fpl or [fsg[0] + "s"]
    if not (fsg and mpl and fpl):
        return None
    forms = {"m.sg": [lemma], "f.sg": fsg, "m.pl": mpl, "f.pl": fpl}
    t = {c: _cell(v[0], v[1:]) for c, v in forms.items()}
    split_table(t, lemma)
    # the regular endings where the adjective is irregular: heureuxe, blance, bone, actife, beaus,
    # nouveaus, normals (no ending on the m.sg, the form the learner starts from)
    if not lemma.endswith(("s", "x")):
        _add_wrong(t, "m.pl", [lemma + "s"], known)
    if not lemma.endswith("e"):
        _add_wrong(t, "f.sg", [lemma + "e"], known)
        _add_wrong(t, "f.pl", [lemma + "es"], known)
    return t


BUILDERS: dict[str, dict[str, Callable[[Lexeme, set[str]], dict | None]]] = {
    "it": {"number": it_number, "agreement": it_agreement},
    "es": {"number": es_number, "agreement": es_agreement},
    "fr": {"number": fr_number, "agreement": fr_agreement},
    "nl": {"number": nl_number, "agreement": nl_agreement, "comparison": nl_comparison,
           "diminutive": nl_diminutive},
}


def build_tables(code: str, lx: Lexeme, declared: dict, known: set[str]) -> dict[str, dict]:
    """Tables declared in course.yaml that the language can build for this lexeme."""
    out = {}
    for name, spec in (declared or {}).items():
        b = BUILDERS.get(code, {}).get(name)
        if b is None or lx.pos not in (spec.get("pos") or []):
            continue
        t = b(lx, known)
        if t and set(t) == set(spec.get("cells") or []):
            out[name] = {c: t[c] for c in spec["cells"]}
    return out


def distinct_forms(table: dict) -> int:
    return len({c["form"].lower() for c in table.values()})


# ------------------------------------------------------------------------------------------ alignment
def _norm(s: str) -> str:
    return s.replace("’", "'").lower()


def _is_word(t: dict) -> bool:
    return t.get("is_word", True) is not False


def _cells_matching(table: dict, word: str, main_only: bool) -> list[str]:
    w = _norm(word)
    out = []
    for cell, c in table.items():
        forms = [c["form"]] if main_only else [c["form"], *c.get("alts", [])]
        if any(_norm(f) == w for f in forms):
            out.append(cell)
    return out


IT_DEGREE = {"molto", "così", "troppo", "più", "poco", "tanto", "davvero", "abbastanza", "assai", "meno"}
IT_COPULA = {"è", "sono", "sei", "siamo", "siete", "era", "erano", "ero", "eri", "sembra", "sembrano",
             "diventa", "diventano", "resta", "restano", "rimane", "rimangono", "sarà", "saranno"}
NL_DEGREE = {"heel", "erg", "zeer", "zo", "te", "best", "nogal", "echt", "vrij", "ontzettend", "super", "hele",
             "enorm", "redelijk", "behoorlijk", "tamelijk", "zó", "bijzonder", "uiterst"}
NL_DEFINITE = {"de", "het", "deze", "die", "dit", "dat", "mijn", "jouw", "je", "zijn", "haar", "ons", "onze",
               "jullie", "hun", "uw", "m'n", "z'n", "d'r", "welke", "elke", "iedere", "alle", "beide"}
NL_INDEFINITE = {"een", "geen", "elk", "ieder", "veel", "weinig", "zo'n", "welk", "wat", "genoeg", "meer",
                 "minder", "zulk", "ander", "enig", "menig", "allerlei", "ieder", "één"}


class InflectionAligner:
    """Adds 'infl:{table}.{cell}' forms to aligned tokens (after Aligner.align)."""

    def __init__(self, code: str, items: dict[str, dict], tables_spec: dict):
        self.code = code
        self.items = items
        self.spec = tables_spec or {}
        # diminutive form -> noun item (diminutives are their own Wiktionary lemmas and usually
        # unaligned or aligned to a pool item: 'huisje')
        self.dim_of: dict[str, str] = {}
        for iid, it in sorted(items.items()):
            d = ((it.get("infl") or {}).get("diminutive") or {}).get("dim")
            if d and _norm(d["form"]) not in self.dim_of:
                self.dim_of[_norm(d["form"])] = iid

    def _item(self, tok: dict) -> dict | None:
        lex = tok.get("lex")
        return self.items.get(lex) if lex else None

    def _noun_number(self, tok: dict) -> str | None:
        """'sg' / 'pl' of an aligned noun token (from its number table)."""
        it = self._item(tok)
        if not it or it.get("pos") != "noun":
            return None
        t = (it.get("infl") or {}).get("number")
        if not t:
            return None
        cells = _cells_matching(t, tok["t"], main_only=False)
        return cells[0] if len(cells) == 1 else None

    def align(self, toks: list[dict]) -> list[dict]:
        # 1. diminutives on unaligned tokens or tokens aligned to an untaught item spelled the same
        for t in toks:
            if not _is_word(t) or t.get("form"):
                continue
            noun = self.dim_of.get(_norm(t["t"]))
            if noun and "diminutive" in self.spec:
                cur = self._item(t)
                if cur is None or (not cur.get("unit") and _norm(cur["lemma"]) == _norm(t["t"])):
                    t["lex"] = noun
        # 2. spelling-determined tables (no agreement): number, diminutive, comparison, ...
        for t in toks:
            it = self._item(t)
            if not _is_word(t) or t.get("form") or not it or it.get("pos") == "verb":
                continue
            for table, spec in self.spec.items():
                tab = (it.get("infl") or {}).get(table)
                if not tab or spec.get("agreement"):
                    continue
                cells = _cells_matching(tab, t["t"], main_only=False)
                if len(cells) != 1:
                    continue      # 'città': singular or plural
                if cells[0] == spec.get("base") and it.get("pos") != "noun":
                    continue      # an adjective's base form is left to the agreement rules
                t["form"] = infl_key(table, cells[0])
                break
        # 3. agreement tables: only where the language rule finds the controlling word
        rule = AGREEMENT.get(self.code)
        if rule:
            for i, t in enumerate(toks):
                it = self._item(t)
                if not _is_word(t) or not it or it.get("pos") == "verb":
                    continue
                if t.get("form") and not t["form"].startswith(INFL_PREFIX + "comparison."):
                    continue
                for table, spec in self.spec.items():
                    tab = (it.get("infl") or {}).get(table)
                    if not tab or not spec.get("agreement") or distinct_forms(tab) < 2:
                        continue
                    cells = _cells_matching(tab, t["t"], main_only=True)
                    if not cells:
                        continue
                    cell = rule(self, toks, i, cells, it)
                    if cell:
                        t["form"] = infl_key(table, cell)
                        break
        return toks


def _it_agreement(al: InflectionAligner, toks: list[dict], i: int, cells: list[str], item: dict) -> str | None:
    """The noun next to the word (or before a copula: 'la casa è bella'), with a fixed gender (m or
    f) and a known number, agrees with one of the cells the word can be."""
    def noun_cell(j: int) -> str | None:
        n = al._item(toks[j])
        if not n or n.get("pos") != "noun" or n.get("gender") not in ("m", "f"):
            return None
        num = al._noun_number(toks[j])
        return f"{n['gender']}.{num}" if num else None

    if _norm(toks[i]["t"]) in IT_DEGREE:
        return None       # 'molto alto': an adverb, invariable
    found: set[str] = set()
    # after: 'mia madre', 'il bel ragazzo' (only the main forms are used, so not 'bel')
    if i + 1 < len(toks) and _is_word(toks[i + 1]):
        c = noun_cell(i + 1)
        if c:
            found.add(c)
    # before, possibly over degree words and a copula: 'una casa molto bella', 'la pizza è buona'
    j = i - 1
    while j >= 0 and _is_word(toks[j]) and _norm(toks[j]["t"]) in IT_DEGREE:
        j -= 1
    if j >= 0 and _is_word(toks[j]):
        if _norm(toks[j]["t"]) in IT_COPULA and j - 1 >= 0 and _is_word(toks[j - 1]):
            j -= 1
        c = noun_cell(j)
        if c:
            found.add(c)
    hits = [c for c in found if c in cells]
    return hits[0] if len(hits) == 1 and len(found) == 1 else None


def _nl_agreement(al: InflectionAligner, toks: list[dict], i: int, cells: list[str], item: dict) -> str | None:
    """Attributive (adjective + noun): -e unless a singular het-word follows after een/geen/no
    article ('een groot huis', 'het grote huis', 'een grote man', 'grote huizen'); the attested form
    must match the rule (so fixed expressions like 'het openbaar vervoer' are left alone).
    Predicative at the clause end without a determiner before it ('Het huis is mooi.'): base."""
    if i + 1 < len(toks) and _is_word(toks[i + 1]):
        n = al._item(toks[i + 1])
        if not n or n.get("pos") != "noun" or n.get("article") not in ("de", "het"):
            return None
        num = al._noun_number(toks[i + 1])
        if num is None:
            return None
        j = i - 1
        while j >= 0 and _is_word(toks[j]) and (_norm(toks[j]["t"]) in NL_DEGREE or
                                                 (al._item(toks[j]) or {}).get("pos") == "adj"):
            j -= 1
        prev = _norm(toks[j]["t"]) if j >= 0 and _is_word(toks[j]) else ""
        if prev in NL_DEFINITE:
            definite = True
        elif prev in NL_INDEFINITE or prev == "" or (al._item(toks[j]) or {}).get("pos") in ("verb", "prep", "adv", "conj"):
            definite = False
        else:
            return None
        expected = "base" if (n["article"] == "het" and num == "sg" and not definite) else "infl"
        return expected if expected in cells else None
    # predicative: the clause ends here
    end = i + 1 >= len(toks) or (not _is_word(toks[i + 1]) and toks[i + 1]["t"] in {".", "!", "?", ",", ";", ":"})
    if not end or "base" not in cells:
        return None
    prev = _norm(toks[i - 1]["t"]) if i > 0 and _is_word(toks[i - 1]) else ""
    pitem = al._item(toks[i - 1]) if i > 0 else None
    if not prev or prev in NL_DEFINITE or prev in NL_INDEFINITE or (pitem or {}).get("pos") in ("det", "noun", "adj"):
        return None
    return "base"


ES_DEGREE = {"muy", "tan", "demasiado", "bastante", "más", "menos", "poco", "algo", "realmente"}
ES_COPULA = {"es", "son", "eres", "soy", "somos", "sois", "está", "están", "estás", "estoy", "estamos",
             "estáis", "era", "eran", "estaba", "estaban", "parece", "parecen", "será", "serán", "fue",
             "fueron", "sigue", "siguen", "queda", "quedan"}


def _es_agreement(al: InflectionAligner, toks: list[dict], i: int, cells: list[str], item: dict) -> str | None:
    """As Italian: the noun right after the word (determiners, 'buen día'), or before it over degree
    words and a copula ('una casa muy bonita', 'la sopa está fría'), with gender m or f and a known
    number decides the cell."""
    if _norm(toks[i]["t"]) in ES_DEGREE:
        return None
    return _agreement_by_noun(al, toks, i, cells, ES_DEGREE, ES_COPULA)


def _agreement_by_noun(al: InflectionAligner, toks: list[dict], i: int, cells: list[str], degree: set[str],
                       copula: set[str]) -> str | None:
    def noun_cell(j: int) -> str | None:
        n = al._item(toks[j])
        if not n or n.get("pos") != "noun" or n.get("gender") not in ("m", "f"):
            return None
        num = al._noun_number(toks[j])
        return f"{n['gender']}.{num}" if num else None

    found: set[str] = set()
    if i + 1 < len(toks) and _is_word(toks[i + 1]):
        c = noun_cell(i + 1)
        if c:
            found.add(c)
    j = i - 1
    while j >= 0 and _is_word(toks[j]) and _norm(toks[j]["t"]) in degree:
        j -= 1
    if j >= 0 and _is_word(toks[j]):
        if _norm(toks[j]["t"]) in copula and j - 1 >= 0 and _is_word(toks[j - 1]):
            j -= 1
        c = noun_cell(j)
        if c:
            found.add(c)
    hits = [c for c in found if c in cells]
    return hits[0] if len(hits) == 1 and len(found) == 1 else None


FR_DEGREE = {"très", "si", "trop", "assez", "plus", "moins", "aussi", "vraiment", "tellement", "bien", "peu",
             "vraiment", "plutôt", "fort", "super", "extrêmement", "particulièrement"}
FR_COPULA = {"est", "sont", "es", "suis", "sommes", "êtes", "était", "étaient", "étais", "étions", "étiez", "sera",
             "seront", "serai", "seras", "serons", "serez", "semble", "semblent", "devient", "deviennent", "reste",
             "restent", "paraît", "paraissent", "été", "être"}


def _fr_agreement(al: InflectionAligner, toks: list[dict], i: int, cells: list[str], item: dict) -> str | None:
    """As Spanish: the noun right after the word (determiners, 'un petit chat') or before it over
    degree words and a copula ('une maison très ancienne', 'la soupe est froide') decides the cell."""
    if _norm(toks[i]["t"]) in FR_DEGREE:
        return None
    return _agreement_by_noun(al, toks, i, cells, FR_DEGREE, FR_COPULA)


AGREEMENT: dict[str, Callable[..., str | None]] = {"it": _it_agreement, "nl": _nl_agreement, "es": _es_agreement,
                                                   "fr": _fr_agreement}
