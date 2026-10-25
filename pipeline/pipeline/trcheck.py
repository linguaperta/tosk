"""Lightweight check that a Tatoeba translation belongs to its sentence.

Tatoeba links are sometimes made to a variant of the sentence (another number, day or name):
'Ci vediamo lunedì.' linked to 'See you on Tuesday.'. A translation fails the check when

* the numbers differ: digits and number words (in the sentence only those not aligned to another
  kind of item: Italian 'sei' is mostly 'you are'); one is ignored, it is also an article; Dutch
  'half drie' (2:30) and idioms ('grazie mille') are not compared;
* a weekday or month in either text has no counterpart in the other ('on Mondays' = 'il lunedì');
* the names differ, counting only names both languages write alike (Tom, Mary, Boston: capitalized
  inside sentences of both corpora, `invariant_names`), so Tom -> Mary fails and Giappone -> Japan
  passes.

The importer drops a sentence whose English translation fails, and only the Dutch translation of
an Italian sentence when that one fails.
"""
from __future__ import annotations

import re

NUMBERS = {
    "en": {"zero": 0, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
           "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
           "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
           "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100, "thousand": 1000,
           "million": 10**6, "billion": 10**9},
    "it": {"zero": 0, "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6, "sette": 7, "otto": 8, "nove": 9,
           "dieci": 10, "undici": 11, "dodici": 12, "tredici": 13, "quattordici": 14, "quindici": 15, "sedici": 16,
           "diciassette": 17, "diciotto": 18, "diciannove": 19, "venti": 20, "trenta": 30, "quaranta": 40,
           "cinquanta": 50, "sessanta": 60, "settanta": 70, "ottanta": 80, "novanta": 90, "cento": 100,
           "mille": 1000, "milione": 10**6, "milioni": 10**6, "miliardo": 10**9, "miliardi": 10**9},
    "nl": {"nul": 0, "twee": 2, "drie": 3, "vier": 4, "vijf": 5, "zes": 6, "zeven": 7, "acht": 8, "negen": 9,
           "tien": 10, "elf": 11, "twaalf": 12, "dertien": 13, "veertien": 14, "vijftien": 15, "zestien": 16,
           "zeventien": 17, "achttien": 18, "negentien": 19, "twintig": 20, "dertig": 30, "veertig": 40,
           "vijftig": 50, "zestig": 60, "zeventig": 70, "tachtig": 80, "negentig": 90, "honderd": 100,
           "duizend": 1000, "miljoen": 10**6, "miljard": 10**9},
    "es": {"cero": 0, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
           "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15, "dieciséis": 16,
           "diecisiete": 17, "dieciocho": 18, "diecinueve": 19, "veinte": 20, "veintiuno": 21, "veintidós": 22,
           "veintitrés": 23, "veinticuatro": 24, "veinticinco": 25, "treinta": 30, "cuarenta": 40,
           "cincuenta": 50, "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90, "cien": 100,
           "ciento": 100, "doscientos": 200, "trescientos": 300, "quinientos": 500, "mil": 1000,
           "millón": 10**6, "millones": 10**6},
}
# Italian elided tens before a vowel: quarant'anni
NUMBERS["it"].update({w[:-1]: v for w, v in list(NUMBERS["it"].items()) if 20 <= v <= 90})
# ordinals (dates: 'il venti ottobre' = 'the twentieth of October'); 'first' and 'second' are left
# out like 'one' ('a second')
NUMBERS["en"].update({"third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9,
                      "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
                      "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
                      "twentieth": 20, "thirtieth": 30})
NUMBERS["it"].update({"terzo": 3, "terza": 3, "quinto": 5, "quinta": 5, "sesto": 6, "sesta": 6, "settimo": 7,
                      "settima": 7, "ottavo": 8, "ottava": 8, "nono": 9, "nona": 9, "decimo": 10, "decima": 10})
NUMBERS["es"].update({"tercero": 3, "tercera": 3, "tercer": 3, "cuarto": 4, "cuarta": 4, "quinto": 5,
                      "quinta": 5, "sexto": 6, "sexta": 6, "séptimo": 7, "séptima": 7, "octavo": 8, "octava": 8,
                      "noveno": 9, "novena": 9, "décimo": 10, "décima": 10})
NUMBERS["nl"].update({"derde": 3, "vierde": 4, "vijfde": 5, "zesde": 6, "zevende": 7, "achtste": 8, "negende": 9,
                      "tiende": 10})
# Spanish one-word cardinals: veintiséis .. veintinueve, the hundreds (and their feminine forms)
NUMBERS["es"].update({"veintiséis": 26, "veintisiete": 27, "veintiocho": 28, "veintinueve": 29,
                      "cuatrocientos": 400, "seiscientos": 600, "setecientos": 700, "ochocientos": 800,
                      "novecientos": 900})
NUMBERS["es"].update({w[:-2] + "as": v for w, v in list(NUMBERS["es"].items()) if w.endswith("ientos")})
NUMBERS["es"]["quinientas"] = 500
# French: hyphenated compounds are one token ('vingt-deux', 'soixante-dix', 'quatre-vingt-dix-neuf')
_FR_UNITS = ["", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix", "onze", "douze",
             "treize", "quatorze", "quinze", "seize", "dix-sept", "dix-huit", "dix-neuf"]
NUMBERS["fr"] = {"zéro": 0, **{w: i for i, w in enumerate(_FR_UNITS) if i >= 2},
                 "vingt": 20, "trente": 30, "quarante": 40, "cinquante": 50, "soixante": 60, "quatre-vingts": 80,
                 "quatre-vingt": 80, "cent": 100, "cents": 100, "mille": 1000, "million": 10**6, "millions": 10**6,
                 "milliard": 10**9, "milliards": 10**9}
for _tens, _v in (("vingt", 20), ("trente", 30), ("quarante", 40), ("cinquante", 50), ("soixante", 60)):
    for _u in range(1, 10 if _v < 60 else 20):
        _w = _FR_UNITS[_u]
        if _u in (1, 11):
            NUMBERS["fr"][f"{_tens}-et-{_w}"] = _v + _u              # vingt-et-un (1990 spelling)
        else:
            NUMBERS["fr"][f"{_tens}-{_w}"] = _v + _u
for _u in range(1, 20):
    NUMBERS["fr"][f"quatre-vingt-{_FR_UNITS[_u]}"] = 80 + _u
NUMBERS["fr"].update({"troisième": 3, "quatrième": 4, "cinquième": 5, "sixième": 6, "septième": 7, "huitième": 8,
                      "neuvième": 9, "dixième": 10})

# Compound numbers. Several words make one number ('two hundred' = 200 = 'doscientos', 'twenty
# five' = 25 = 'veinticinco', 'treinta y dos' = 32, 'dos mil' = 2000), and Dutch and Italian write
# compounds as one word ('tweehonderd', 'vijfentwintig', 'duecento', 'trentadue'), so both sides
# are read as whole numbers before they are compared.
MULTIPLIERS = {100, 1000, 10**6, 10**9}
# a word between two parts of one number: 'two hundred and fifty', 'treinta y dos'
CONNECTORS = {"en": {"and"}, "es": {"y"}, "fr": {"et"}}
# extra parts that occur only inside one-word compounds ('one' alone is ignored, see _num); a part
# with value 0 joins a unit and a ten ('vijfentwintig', 'tweeëntwintig')
COMPOUND_PARTS = {
    "nl": {"een": 1, "eën": 1, "en": 0, "ën": 0},
    "it": {"uno": 1, "un": 1, "tré": 3, "mila": 1000},
}


def _mergeable(run: list[int], v: int) -> bool:
    """Can number word `v` continue the number words `run` ('two' + 'hundred', 'thirty' + 'two')?"""
    prev = run[-1]
    if v >= 1000 and v in MULTIPLIERS:
        return all(x < v for x in run)                    # 'dos mil', 'two hundred thousand'
    if v == 100:
        since = run[max((i for i, x in enumerate(run) if x >= 1000), default=-1) + 1:]
        return sum(since) < 100                           # 'two hundred', 'mil cien', 'nineteen hundred'
    if prev >= 100:
        return v < 10 ** (len(str(prev)) - 1) * (10 if prev in MULTIPLIERS else 1)   # 'doscientos cinco'
    return 20 <= prev <= 90 and prev % 10 == 0 and 1 <= v <= 9                       # 'thirty two'


def _value(parts: list[int]) -> int:
    total = current = 0
    for v in parts:
        if v >= 1000:
            total += (current or 1) * v
            current = 0
        elif v == 100:
            current = (current or 1) * 100
        else:
            current += v
    return total + current


def _compound(word: str, lang: str) -> int | None:
    """Value of a one-word compound number ('tweehonderd' 200, 'vijfentwintig' 25, 'trentadue' 32)."""
    extra = COMPOUND_PARTS.get(lang)
    if not extra or len(word) < 6:
        return None
    parts = {w: v for w, v in NUMBERS[lang].items() if v not in (0,) and "'" not in w} | extra
    best: dict[int, list[int]] = {0: []}
    for i in range(len(word)):
        if i not in best:
            continue
        for p, v in parts.items():
            if word.startswith(p, i) and i + len(p) not in best:
                best[i + len(p)] = best[i] + [v]
    seq = best.get(len(word))
    if not seq or len(seq) < 2:
        return None
    if seq[0] == 0 or seq[-1] == 0:
        return None                 # 'vieren', 'achten' (verbs), 'honderden'
    vals = []
    for i, v in enumerate(seq):
        if v == 0:
            if not (1 <= seq[i - 1] <= 9 and 20 <= seq[i + 1] <= 90):
                return None
            continue
        vals.append(v)
    for i in range(1, len(vals)):
        a, b = vals[i - 1], vals[i]
        if not (_mergeable(vals[:i], b) or (1 <= a <= 9 and 20 <= b <= 90 and lang == "nl")):
            return None
    return _value(vals)


def number_values(words: list[str], lang: str) -> list[tuple[int, bool]]:
    """Numbers in a list of lowercased words, compounds joined: (value, from an ambiguous word).
    Digits are left to the caller."""
    out: list[tuple[int, bool]] = []
    run: list[int] = []
    amb = False
    conn = CONNECTORS.get(lang, set())

    def flush():
        nonlocal run, amb
        if run:
            out.append((_value(run), amb and len(run) == 1))
        run, amb = [], False

    def _starts_number(run: list[int], v: int, j: int) -> bool:
        # 'five hundred and five hundred': the second 'five' begins a new number
        nxt = NUMBERS.get(lang, {}).get(words[j]) if j < len(words) else None
        return nxt is not None and not _mergeable(run + [v], nxt) and _mergeable([v], nxt)

    i = 0
    while i < len(words):
        w = words[i]
        v = None
        if w and not w[:1].isdigit():
            v = NUMBERS.get(lang, {}).get(w)
            if v is None:
                v = _compound(w, lang)
        if v is None:
            if run and w in conn and i + 1 < len(words):
                nxt = NUMBERS.get(lang, {}).get(words[i + 1])
                if nxt is not None and _mergeable(run, nxt) and not _starts_number(run, nxt, i + 2):
                    i += 1
                    continue
            flush()
            i += 1
            continue
        if run and (not _mergeable(run, v) or _starts_number(run, v, i + 1)):
            flush()
        run.append(v)
        amb = amb or w in AMBIGUOUS.get(lang, set())
        i += 1
    flush()
    return out


# idioms with a number word that is no number: 'grazie mille' (thanks a lot)
IDIOMS = {"it": {("grazie", "mille")}}
# number words that are mostly something else (Italian 'sei' = you are, Dutch 'vier' = celebrate,
# 'acht' = attention, 'elf' = elf, 'zeven' = to sieve): their value is not compared when the
# sentence has one
AMBIGUOUS = {"it": {"sei"}, "nl": {"vier", "acht", "elf", "zeven"}, "es": {"cuarto", "cuarta"},
             "fr": {"neuf", "cent"}}
# words that imply or rewrite numbers (times, pairs): no number comparison at all
NUMBER_WORDS_VAGUE = {
    "en": {"half", "quarter", "fortnight", "fortnights", "dozen", "dozens", "couple", "both", "pair", "twice",
           "double", "o'clock", "noon", "midnight", "decade", "decades"},
    "it": {"mezza", "mezzo", "quarto", "quarta", "entrambi", "entrambe", "paio", "coppia", "doppio", "mezzogiorno",
           "mezzanotte"},
    "nl": {"half", "kwart", "kwartier", "beide", "beiden", "paar", "dubbel", "middag", "middernacht"},
    "es": {"medio", "media", "cuarto", "ambos", "ambas", "par", "pareja", "doble", "mediodía", "medianoche",
           "docena", "quincena"},
    "fr": {"demi", "demie", "quart", "moitié", "paire", "couple", "double", "midi", "minuit", "douzaine",
           "dizaine", "vingtaine", "trentaine", "quarantaine", "cinquantaine", "centaine", "quinzaine", "huitaine"},
}
VAGUE_EN = re.compile(r"\b(you|we|they|us|them) two\b|\btwo of (you|us|them)\b", re.I)
# weekdays then months, in the same order per language
CALENDAR = {
    "en": "monday tuesday wednesday thursday friday saturday sunday january february march april may june "
          "july august september october november december",
    "it": "lunedì martedì mercoledì giovedì venerdì sabato domenica gennaio febbraio marzo aprile maggio giugno "
          "luglio agosto settembre ottobre novembre dicembre",
    "nl": "maandag dinsdag woensdag donderdag vrijdag zaterdag zondag januari februari maart april mei juni "
          "juli augustus september oktober november december",
    "es": "lunes martes miércoles jueves viernes sábado domingo enero febrero marzo abril mayo junio "
          "julio agosto septiembre octubre noviembre diciembre",
    "fr": "lundi mardi mercredi jeudi vendredi samedi dimanche janvier février mars avril mai juin "
          "juillet août septembre octobre novembre décembre",
}
CALENDAR_IDX = {lang: {w: i for i, w in enumerate(words.split())} for lang, words in CALENDAR.items()}
CALENDAR_IDX["en"].update({w + "s": i for w, i in list(CALENDAR_IDX["en"].items()) if i < 7})   # 'on Mondays'
CALENDAR_IDX["es"].update({"sábados": 5, "domingos": 6})   # 'los domingos' = on Sundays
CALENDAR_IDX["nl"].update({w + sfx: i for w, i in list(CALENDAR_IDX["nl"].items()) if i < 7
                           for sfx in ("s", "en", "ochtend", "middag", "avond", "nacht", "morgen")})
# "'s zondags", 'op maandagen', 'zaterdagavond'
# English 'may' and 'march' are mostly verbs: they are months only when capitalized inside a sentence
EN_VERB_MONTHS = {"may", "march"}
_WORD = re.compile(r"[^\W\d_]+|\d+")      # apostrophes split: Sami's -> Sami, s; l'Australia
_THOUSANDS = re.compile(r"(?<=\d)[,.](?=\d{3}(?!\d))")                     # 3,000 / 3.000 = 3000


def _words(text: str) -> list[str]:
    return _WORD.findall(text)


def _num(word: str, lang: str) -> int | None:
    if word.isdigit():
        v = int(word)
        return None if v == 1 or (v == 0 and len(word) > 1) else v     # 'one' is ignored; '9:00'
    return NUMBERS.get(lang, {}).get(word.lower().replace("’", "'"))


def numbers_in(text: str, lang: str) -> set[int]:
    """Number values in a text: digits (1,000 = 1000) and number words."""
    text = _THOUSANDS.sub("", text)
    ws = _words(text)
    digits = {v for w in ws if w.isdigit() and (v := _num(w, lang)) is not None}
    return digits | {v for v, _ in number_values([w.lower().replace("’", "'") for w in ws], lang)}


def calendar_in(text: str, lang: str) -> set[int]:
    out = set()
    idx = CALENDAR_IDX.get(lang, {})
    for m in _WORD.finditer(text):
        w = m.group(0)
        k = w.lower()
        if k in idx:
            if lang == "en" and k in EN_VERB_MONTHS:
                before = text[:m.start()].rstrip(" \"'“‘«")
                if not w[:1].isupper() or not before or before[-1] in ".!?":
                    continue                 # 'may I', 'May I ...?'
            out.add(idx[k])
    return out


def names_in(text: str) -> set[str]:
    """Capitalized words that do not start the text."""
    ws = _words(text)
    return {w for w in ws[1:] if w[:1].isupper() and not w.isupper()}


def _unpaired(names: set[str], other_text: str) -> set[str]:
    """Names with no word in the other text sharing their first 3 letters (Maria ~ Mary, Thomas ~
    Tom, Google ~ googled)."""
    prefixes = {w[:3].lower() for w in _words(other_text)}
    return {n for n in names if n[:3].lower() not in prefixes}


def mismatch(tokens: list[dict], items: dict[str, dict], code: str, tr: str, tr_lang: str,
             names: set[str] = frozenset()) -> str | None:
    """Why `tr` (in tr_lang) does not translate the aligned sentence `tokens` (in code), or None.
    `names`: names both languages write alike (Tom, Mary, Boston; see `invariant_names`), checked
    for English translations only."""
    text = "".join(t.get("pre", "") + t["t"] for t in tokens)
    words = [t for t in tokens if t.get("is_word", True) is not False]
    low = [t["t"].lower().replace("’", "'").rstrip("'") for t in words]
    src_nums = {v for d in re.findall(r"\d+", _THOUSANDS.sub("", text))
                if (v := _num(d, code)) is not None}
    ignore = set()
    # idiom words ('grazie mille') are no numbers; digits were counted above
    plain = ["" if (i > 0 and (low[i - 1], w) in IDIOMS.get(code, set())) or w[:1].isdigit() else w
             for i, w in enumerate(low)]
    for v, ambiguous in number_values(plain, code):
        (ignore if ambiguous else src_nums).add(v)
    tr_nums = numbers_in(tr, tr_lang) - ignore
    vague = bool(set(low) & NUMBER_WORDS_VAGUE.get(code, set())) \
        or bool({w.lower() for w in _words(tr)} & NUMBER_WORDS_VAGUE.get(tr_lang, set())) \
        or re.search(r"\d[:.]\d", text + " " + tr) is not None \
        or (tr_lang == "en" and VAGUE_EN.search(tr) is not None)
    if src_nums - ignore != tr_nums and not vague:
        return f"numbers {sorted(src_nums - ignore)} vs {sorted(tr_nums)}"
    if calendar_in(text, code) != calendar_in(tr, tr_lang):
        return "weekday/month"
    if tr_lang == "en" and names:
        src_names = set(_words(text)) & names
        tr_names = set(_words(tr)) & names
        odd = _unpaired(src_names - tr_names, tr) | _unpaired(tr_names - src_names, text)
        if odd:
            return f"names {sorted(src_names)} vs {sorted(tr_names)}"
    return None


def invariant_names(pairs, min_count: int = 3, min_share: float = 0.8) -> set[str]:
    """Names written alike in both languages, from (sentence, translation) pairs: capitalized words
    inside a translation that the sentence also contains in at least `min_share` of at least
    `min_count` pairs (Tom, Mary, Boston; not London, which Italian writes Londra) and that never
    occur in lower case ('Ma' after a quote is the conjunction)."""
    lower: set[str] = set()
    seen: dict[str, int] = {}
    both: dict[str, int] = {}
    for src, tr in pairs:
        sw, tw = _words(src), _words(tr)
        lower.update(w for w in sw + tw if w[:1].islower())
        ss = set(sw)
        for w in names_in(tr):
            seen[w] = seen.get(w, 0) + 1
            if w in ss:
                both[w] = both.get(w, 0) + 1
    return {w for w, n in seen.items() if n >= min_count and both.get(w, 0) >= min_share * n and len(w) > 1
            and w.lower() not in lower}
