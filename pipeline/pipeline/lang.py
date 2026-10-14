"""Language-specific knowledge used by the pipeline (never by the app).

Each course language defines: persons, tenses (simple ones read from Wiktionary tables, compound
ones built from auxiliary + participle), how to read kaikki conjugation tags, regularity checks,
the stem/ending split for the ending-picker, articles, subject pronouns and tokenizer details.
"""
from __future__ import annotations

import unicodedata
from dataclasses import dataclass, field

# Tags that disqualify a conjugation-table form (dialectal, archaic, formal 'u', ...).
BAD_FORM_TAGS = {
    "obsolete", "archaic", "poetic", "literary", "Traditional", "dialectal", "rare", "regional",
    "nonstandard", "uncommon", "Tuscany", "Flanders", "colloquial", "formal", "majestic",
    "subjunctive", "conditional", "imperative", "historic", "subordinate-clause", "dated",
    "Southern-Italy", "Northern-Italy", "Rome", "Belgium", "Suriname", "informal", "proscribed",
}


def strip_inner_accents(word: str) -> str:
    """Remove pronunciation accents Wiktionary puts on non-final vowels (màngio -> mangio).

    Italian only writes accents on a final vowel (città, mangerò), so those are kept.
    """
    out = []
    n = len(word)
    for i, ch in enumerate(word):
        if i < n - 1 and ch.lower() in "àèéìíòóùú" and word[i + 1].isalpha():
            ch = unicodedata.normalize("NFD", ch)[0]
        out.append(ch)
    return "".join(out)


@dataclass
class Lang:
    code: str
    persons: list[str]
    simple_tenses: list[str]          # read from the conjugation table
    compound_tenses: dict[str, str]   # compound tense -> tense of the auxiliary ('passato_prossimo' -> 'presente')
    present: str                      # key of the present tense
    auxiliaries: list[str]            # lemmas of perfect auxiliaries
    tense_tags: dict[str, set[str]]   # tense -> kaikki tags that must all be present
    articles: list[str]
    pronouns: dict[str, list[str]]    # lowercase subject pronoun -> persons it can be
    determiners: set[str]             # words after which a noun reading is preferred over a verb reading
    skip_between: set[str] = field(default_factory=set)  # words skipped when looking for a subject pronoun
    third_sg: str = ""
    third_pl: str = ""
    # subject pronouns that take the forms of several persons interchangeably (Dutch polite 'u':
    # 'u bent' / 'u is', 'u hebt' / 'u heeft'); a verb next to one gets no person
    vague_pronouns: set[str] = field(default_factory=set)
    # lemmas of modal verbs that take a (perfect) infinitive: 'zou ... geweest zijn'
    modals: set[str] = field(default_factory=set)
    # auxiliary that also forms the passive: when a verb lists it only as its second auxiliary,
    # aux + participle is not linked to the compound tense
    passive_aux: str = ""
    # words that start a new (sub)clause, after which a new finite verb may follow
    clause_starters: set[str] = field(default_factory=set)
    # coordinating conjunctions: a new clause when a subject pronoun follows ('en jullie werken')
    coordinators: set[str] = field(default_factory=set)
    # degree words before an adjective that is also a verb form ('hoe laat', not 'laten')
    degree_words: set[str] = field(default_factory=set)
    # relative/interrogative pronouns that start a clause ('wat er gebeurt')
    relatives: set[str] = field(default_factory=set)
    # subject pronouns that are also object pronouns ('je', 'ze', 'het')
    object_pronouns: set[str] = field(default_factory=set)
    # demonstratives that are also pronoun subjects at the start of a clause ('Dat moest je ...')
    demonstratives: set[str] = field(default_factory=set)
    # dummy subjects ('dat er iets gebeurt')
    dummy_subjects: set[str] = field(default_factory=set)
    # (lemma, tense) forms that are not linked because their use differs from the tense label
    # (Dutch 'zou' is nearly always a conditional, not the past of 'zullen')
    unlinked_forms: set[tuple[str, str]] = field(default_factory=set)
    # copula forms after which a word that is both an adjective and a verb form is the adjective
    # (Dutch 'dat ik laat ben': late, not 'laten')
    copulas: set[str] = field(default_factory=set)
    # perfect with a double infinitive instead of a participle ('Ik heb Tom niet zien vallen',
    # 'Hij heeft Japans willen leren'): features.py tags it as the compound tense
    double_infinitive_perfect: bool = False
    # Italian imperatives look like present forms ('Chiedi a un poliziotto!', 'Andiamo!'): verbs that
    # never form one that way (their imperative is distinct: sii, abbi)
    imperative_exempt: set[str] = field(default_factory=set)
    # words that may precede a clause-initial imperative ('Non parlate!', 'Mi scusi!')
    imperative_lead: set[str] = field(default_factory=set)
    # read the gerund from the conjugation table ('gerund._': mangiando, hablando)
    gerund: bool = False
    # compound tenses: the auxiliary stands before the participle, at most `aux_window` words back,
    # with only `aux_between` words in between (it: 'ho già mangiato'; es: 'he comido'); 0 = anywhere
    # in the clause, before or after (Dutch 'dat ik heb gegeten' / 'dat ik gegeten heb')
    aux_window: int = 0
    aux_between: set[str] = field(default_factory=set)
    # a participle without an auxiliary (passive, adjectival) tags the compound tense; Spanish
    # 'estoy cansado', 'la puerta está cerrada' are adjectival and tag nothing
    bare_participle_tense: bool = True
    # spellings whose verb reading needs an adjacent subject pronoun; otherwise the word is read as
    # its other item (Spanish 'como' = like/as, not 'I eat', unless 'yo como')
    verb_needs_pronoun: set[str] = field(default_factory=set)
    # a word that is both a noun and a verb form, directly after a finite verb, is the noun (its
    # object): Spanish 'Bebo vino' (wine, not 'he came'), 'Busco trabajo'
    object_noun_after_verb: bool = False
    # ... and after one of these between two nouns ('agua o vino')
    noun_coordinators: set[str] = field(default_factory=set)
    # the conjugation table's second template lists enclitic combinations (Spanish hacerlo, dímelo,
    # levantarse): kept as the verb item's inflections, so such a word links to the verb (no form)
    clitic_forms: bool = False
    # infinitive endings of verbs eligible for the pool (it: pronominal verbs like alzarsi are not)
    infinitive_endings: tuple[str, ...] = ()
    # first word of the English translation -> person, used when persons share a form and no subject
    # pronoun decides (Spanish 'hablaba' = yo or él; 'I was talking' -> yo). Also: an English
    # translation starting with 'Please' marks a clause-initial present form as an imperative.
    translation_subjects: dict[str, str] = field(default_factory=dict)
    # multi-word phrase items that only count when they form a clause of their own ('¡De nada!')
    standalone_phrases: set[str] = field(default_factory=set)
    # words that mark a tense: a form shared by several tenses takes this one (es 'ayer' ->
    # preterito_indefinido: 'Ayer hablamos' is not the present 'hablamos')
    tense_hints: dict[str, str] = field(default_factory=dict)
    # question words before a noun ('qué hora', 'cuántos años'): that noun is not the verb's subject
    interrogatives: set[str] = field(default_factory=set)
    # a spelling shared by several verbs goes to the verb that has a form of the person an
    # adjacent subject pronoun gives, or a third-person form after one of `third_person_clitics`
    person_hint_verbs: bool = False
    third_person_clitics: set[str] = field(default_factory=set)

    @property
    def tenses(self) -> list[str]:
        return self.simple_tenses + list(self.compound_tenses)

    # -- conjugation-table reading ------------------------------------------------------------
    def slot(self, tags: list[str]) -> tuple[str, str] | None:
        """Map kaikki form tags to (tense, person) or None."""
        t = set(tags)
        if t & BAD_FORM_TAGS:
            return None
        if "infinitive" in t:
            return ("infinitive", "_")
        if {"participle", "past"} <= t:
            return ("participle", "_")
        if "gerund" in t and self.gerund:
            return ("gerund", "_")
        if "participle" in t or "gerund" in t:
            return None
        for tense, req in self.tense_tags.items():
            if req <= t and self._tense_exclusive(tense, t):
                persons = self.persons_for(t)
                if persons:
                    return (tense, ",".join(persons))
        return None

    def _tense_exclusive(self, tense: str, t: set[str]) -> bool:
        others = {"imperfect", "future", "past", "present"} - self.tense_tags[tense]
        if self.code == "nl":
            return not (others & t)
        return not (others & t)

    def persons_for(self, t: set[str]) -> list[str]:
        num = "singular" if "singular" in t else "plural" if "plural" in t else None
        per = ("first-person" if "first-person" in t else "second-person" if "second-person" in t
               else "third-person" if "third-person" in t else None)
        idx = {"first-person": 0, "second-person": 1, "third-person": 2}
        if num is None:
            return []
        if per is None:
            # Dutch tables give one plural form for all plural persons.
            return self.persons[3:] if num == "plural" and self.code == "nl" else []
        return [self.persons[idx[per] + (0 if num == "singular" else 3)]]

    def spelling(self, form: str, link: str | None) -> str:
        s = link if link else form
        if self.code == "it":
            s = strip_inner_accents(s)
        return s.strip()

    # -- morphology ---------------------------------------------------------------------------
    def verb_class(self, lemma: str, forms: dict, table_tags: str) -> str | None:
        raise NotImplementedError

    def irregular_in(self, lemma: str, cls: str | None, forms: dict) -> list[str]:
        raise NotImplementedError

    def split(self, lemma: str, cls: str | None, tense: str, person: str, form: str, regular: bool,
              table: dict | None = None):
        """Return (stem, ending) or (None, None)."""
        raise NotImplementedError

    def article_for(self, lemma: str, gender: str | None) -> str | None:
        raise NotImplementedError

    def compound(self, aux_forms: dict[str, str], participle: str, person: str, aux: str) -> tuple[str, list[str]]:
        raise NotImplementedError

    def verb_stem(self, lemma: str, cls: str | None, complete: dict, irr: list[str]) -> str | None:
        """The verb record's `stem` (it: mangi(are); nl: the ik-form of a regular present)."""
        p = complete[self.present]
        return p[self.persons[0]] if self.present not in irr else None


# ------------------------------------------------------------------------------------------ it
IT_ENDINGS = {
    "presente": {
        "are": ["o", "i", "a", "iamo", "ate", "ano"],
        "ere": ["o", "i", "e", "iamo", "ete", "ono"],
        "ire": ["o", "i", "e", "iamo", "ite", "ono"],
        "isc": ["isco", "isci", "isce", "iamo", "ite", "iscono"],
    },
    "imperfetto": {
        "are": ["avo", "avi", "ava", "avamo", "avate", "avano"],
        "ere": ["evo", "evi", "eva", "evamo", "evate", "evano"],
        "ire": ["ivo", "ivi", "iva", "ivamo", "ivate", "ivano"],
        "isc": ["ivo", "ivi", "iva", "ivamo", "ivate", "ivano"],
    },
    "futuro": {
        "are": ["erò", "erai", "erà", "eremo", "erete", "eranno"],
        "ere": ["erò", "erai", "erà", "eremo", "erete", "eranno"],
        "ire": ["irò", "irai", "irà", "iremo", "irete", "iranno"],
        "isc": ["irò", "irai", "irà", "iremo", "irete", "iranno"],
    },
}


# Italian words that may stand between an auxiliary and its participle ('ho già mangiato', 'non
# sono mai stato', 'abbiamo tutti capito'); any other word in between ends the search, so a noun
# or adjective is never taken for a participle ('Sono sicura del suo successo', 'Non siete
# coraggiosi come sembrate').
IT_BETWEEN_AUX_PART = {
    "già", "mai", "appena", "ancora", "sempre", "più", "anche", "ben", "bene", "molto", "tanto", "poco",
    "spesso", "davvero", "proprio", "forse", "solo", "soltanto", "subito", "finalmente", "tutto", "tutti",
    "tutte", "quasi", "veramente", "certo", "certamente", "sicuramente", "probabilmente", "ormai", "pure",
    "mica", "neanche", "nemmeno", "neppure", "così", "appunto", "completamente", "davvero", "io", "tu",
    "lui", "lei", "noi", "voi", "loro"}


class Italian(Lang):
    def __init__(self) -> None:
        super().__init__(
            code="it",
            persons=["io", "tu", "lui/lei", "noi", "voi", "loro"],
            simple_tenses=["presente", "imperfetto", "futuro"],
            compound_tenses={"passato_prossimo": "presente"},
            present="presente",
            auxiliaries=["avere", "essere"],
            tense_tags={
                "presente": {"indicative", "present"},
                "imperfetto": {"indicative", "imperfect"},
                "futuro": {"indicative", "future"},
            },
            articles=["il", "lo", "la", "l'"],
            pronouns={"io": ["io"], "tu": ["tu"], "lui": ["lui/lei"], "lei": ["lui/lei"], "noi": ["noi"],
                      "voi": ["voi"], "loro": ["loro"], "egli": ["lui/lei"], "ella": ["lui/lei"]},
            determiners={"il", "lo", "la", "l'", "i", "gli", "le", "un", "uno", "una", "un'", "del", "della",
                         "dello", "dell'", "dei", "degli", "delle", "al", "alla", "allo", "all'", "ai", "agli",
                         "alle", "nel", "nella", "nello", "nell'", "nei", "negli", "nelle", "sul", "sulla",
                         "dal", "dalla", "questo", "questa", "quel", "quella", "mio", "mia", "tuo", "tua",
                         "suo", "sua", "nostro", "nostra", "vostro", "vostra", "miei", "mie", "tuoi", "tue",
                         "suoi", "sue", "nostri", "nostre", "vostri", "vostre", "questi", "queste",
                         "quei", "quegli", "quelle", "quello", "ogni", "alcuni", "alcune", "molti",
                         "molte", "tanti", "tante", "pochi", "poche", "qualche", "nessun", "di", "in",
                         "con", "per", "a", "da", "su", "tra", "fra"},
            skip_between={"non", "mi", "ti", "ci", "vi", "si", "lo", "la", "li", "le", "ne", "gli", "già",
                          "anche", "sempre", "mai", "più", "ancora", "pure", "poi"},
            third_sg="lui/lei",
            third_pl="loro",
            imperative_exempt={"essere", "avere"},
            imperative_lead={"non", "mi", "ti", "ci", "vi", "si", "lo", "la", "li", "le", "ne", "gli", "me", "te",
                             "ce", "ve", "se", "pure", "ora", "adesso", "allora"},
            gerund=True,
            aux_window=4,
            aux_between=IT_BETWEEN_AUX_PART,
            infinitive_endings=("are", "ere", "ire", "rre"),
        )

    def verb_stem(self, lemma, cls, complete, irr):
        return lemma[:-3] if cls in ("are", "ere", "ire", "isc") else None

    def verb_class(self, lemma, forms, table_tags):
        pres = forms.get("presente", {})
        if lemma.endswith("are"):
            return "are"
        if lemma.endswith("ere"):
            return "ere"
        if lemma.endswith("ire"):
            if pres.get("io", "").endswith("isco"):
                return "isc"
            return "ire"
        return "other"   # porre, tradurre, ... (-rre)

    def regular_present(self, lemma: str, cls: str) -> list[list[str]] | None:
        """All acceptable regular presente paradigms for lemma (orthographic variants included)."""
        if cls not in IT_ENDINGS["presente"]:
            return None
        stem = lemma[:-3]
        ends = IT_ENDINGS["presente"][cls]
        out = []
        base = [stem + e for e in ends]
        if cls == "are" and stem.endswith(("c", "g")):
            base = [stem + ("h" + e if e.startswith(("i", "e")) else e) for e in ends]
        out.append(base)
        if stem.endswith("i"):
            # mangiare: mangi (not mangii), mangiamo (not mangiiamo); stressed i: invii, inviamo
            out.append([stem + e if not e.startswith("i") else stem + e[1:] for e in ends])
            out.append([stem + e if e != "iamo" else stem + "amo" for e in ends])
        if stem.endswith(("gl", "gn")):
            out.append([stem + e if e != "iamo" else stem + "iamo" for e in ends])
        return out

    def irregular_in(self, lemma, cls, forms):
        irr = []
        pres = forms.get("presente", {})
        paradigms = self.regular_present(lemma, cls) if cls else None
        actual = [pres.get(p) for p in self.persons]
        if not paradigms or actual not in paradigms:
            irr.append("presente")
        stem = lemma[:-3]
        for tense in ("imperfetto", "futuro"):
            actual = [forms.get(tense, {}).get(p) for p in self.persons]
            if all(actual) and actual not in self.regular_simple(lemma, cls, tense):
                irr.append(tense)
        part = forms.get("participle", {}).get("_")
        reg_part = {"are": stem + "ato", "ere": stem + "uto", "ire": stem + "ito", "isc": stem + "ito"}.get(cls or "")
        if part is None or part != reg_part:
            irr.append("passato_prossimo")
        return irr

    def regular_simple(self, lemma: str, cls: str | None, tense: str) -> list[list[str]]:
        """Regular imperfetto/futuro paradigms (spelling variants included): parlavo, cercherò,
        mangerò (-ciare/-giare drop the i), studierò (a stressed i stays)."""
        if cls not in IT_ENDINGS.get(tense, {}):
            return []
        stem = lemma[:-3]
        ends = IT_ENDINGS[tense][cls]
        out = [[stem + e for e in ends]]
        if tense == "futuro" and cls == "are":
            if stem.endswith(("c", "g")):
                out.append([stem + "h" + e for e in ends])
            if stem.endswith("i"):
                out.append([stem[:-1] + e for e in ends])
        return out

    def split(self, lemma, cls, tense, person, form, regular, table=None):
        """Italian: ending = the class ending for the person (falling back to other classes);
        the remaining stem must match the infinitive stem (ignoring an inserted 'h': cerch+i)."""
        if tense not in IT_ENDINGS or " " in form:
            return None, None
        i = self.persons.index(person)
        cands = []
        if cls in IT_ENDINGS[tense]:
            cands.append(IT_ENDINGS[tense][cls][i])
        for c in ("are", "ere", "ire", "isc"):
            e = IT_ENDINGS[tense][c][i]
            if e not in cands:
                cands.append(e)
        inf_stem = lemma[:-3] if len(lemma) > 3 else lemma
        for e in cands:
            if form.endswith(e) and len(form) > len(e):
                stem = form[: -len(e)]
                s = stem[:-1] if stem.endswith("h") and stem[-2:-1] in ("c", "g") else stem
                if len(s) >= 2 and (inf_stem.startswith(s) or s.startswith(inf_stem)):
                    return stem, e
        return None, None

    def article_for(self, lemma, gender):
        if not gender or not lemma:
            return None
        w = lemma.lower()
        vowel = w[0] in "aeiouàèéìòóù" or (w[0] == "h" and len(w) > 1 and w[1] in "aeiou")
        if gender.startswith("m"):
            if vowel:
                return "l'"
            if (w[0] == "s" and len(w) > 1 and w[1] not in "aeiouàèéìòù") or w[0] in "zxy" or \
                    w.startswith(("gn", "ps", "pn")) or (w[0] == "i" and len(w) > 1 and w[1] in "aeiou"):
                return "lo"
            return "il"
        if gender.startswith("f"):
            return "l'" if vowel else "la"
        return None

    def compound(self, aux_forms, participle, person, aux):
        a = aux_forms[person]
        if aux != "essere":
            return f"{a} {participle}", []
        base = participle[:-1] if participle[-1:] in "oaie" else participle
        plural = self.persons.index(person) >= 3
        if plural:
            return f"{a} {base}i", [f"{a} {base}e"]
        return f"{a} {base}o", [f"{a} {base}a"]

    def participle_variants(self, participle: str, aux: str) -> list[str]:
        if aux != "essere" or participle[-1:] not in "oaie":
            return [participle]
        b = participle[:-1]
        return [b + "o", b + "a", b + "i", b + "e"]


# ------------------------------------------------------------------------------------------ nl
DUTCH_VOWELS = "aeiouyáéíóúèëïöü"


def _nl_canon(s: str) -> str:
    """Spelling-insensitive skeleton of a Dutch stem: loop/lop, zeg/zegg, leef/lev, lees/lez."""
    s = s.lower()
    for a, b in (("aa", "a"), ("ee", "e"), ("oo", "o"), ("uu", "u")):
        s = s.replace(a, b)
    out = []
    for ch in s:
        if out and out[-1] == ch and ch not in DUTCH_VOWELS:
            continue
        out.append(ch)
    s = "".join(out)
    if s.endswith("v"):
        s = s[:-1] + "f"
    if s.endswith("z"):
        s = s[:-1] + "s"
    return s


class Dutch(Lang):
    def __init__(self) -> None:
        super().__init__(
            code="nl",
            persons=["ik", "jij", "hij/zij", "wij", "jullie", "zij"],
            simple_tenses=["tegenwoordige_tijd", "verleden_tijd"],
            compound_tenses={"perfectum": "tegenwoordige_tijd"},
            present="tegenwoordige_tijd",
            auxiliaries=["hebben", "zijn"],
            tense_tags={
                "tegenwoordige_tijd": {"present"},
                "verleden_tijd": {"past"},
            },
            articles=["de", "het"],
            pronouns={"ik": ["ik"], "jij": ["jij"], "je": ["jij"], "hij": ["hij/zij"], "zij": ["hij/zij", "zij"],
                      "ze": ["hij/zij", "zij"], "het": ["hij/zij"], "wij": ["wij"], "we": ["wij"],
                      "jullie": ["jullie"], "u": ["jij", "hij/zij"], "men": ["hij/zij"]},
            determiners={"de", "het", "een", "die", "dat", "deze", "dit", "mijn", "jouw", "zijn", "haar", "ons",
                         "onze", "hun", "uw", "geen", "elk", "elke", "ieder", "iedere", "welk", "welke"},
            skip_between={"niet", "ook", "nog", "al", "graag", "altijd", "nooit", "vaak", "dan", "toch"},
            third_sg="hij/zij",
            third_pl="zij",
            vague_pronouns={"u"},
            modals={"zullen", "kunnen", "moeten", "willen", "mogen", "hoeven"},
            passive_aux="zijn",
            clause_starters={"dat", "omdat", "wanneer", "toen", "terwijl", "zodat", "voordat", "nadat", "totdat",
                             "hoewel", "tenzij", "waar", "waarom", "hoe", "waarmee", "waarover", "zodra", "alsof",
                             "indien"},
            coordinators={"en", "maar", "want", "of", "dus"},
            relatives={"wat", "wie", "die", "welke"},
            object_pronouns={"je", "ze", "het", "jullie"},
            demonstratives={"dat", "die", "dit", "deze"},
            dummy_subjects={"er"},
            degree_words={"hoe", "zo", "te", "heel", "erg", "nogal", "vrij", "best", "even"},
            unlinked_forms={("zullen", "verleden_tijd")},
            copulas={"ben", "bent", "is", "was", "waren", "zijn", "geweest", "word", "wordt", "worden", "werd",
                     "werden", "geworden", "blijf", "blijft", "blijven", "bleef", "bleven", "gebleven"},
            double_infinitive_perfect=True,
        )

    def slot(self, tags):
        t = set(tags)
        if "main-clause" in t:
            t = t - {"main-clause"}
        return super().slot(list(t))

    def _tense_exclusive(self, tense, t):
        if tense == "tegenwoordige_tijd":
            return "past" not in t and "participle" not in t
        if tense == "verleden_tijd":
            return "present" not in t and "participle" not in t
        return True

    def verb_class(self, lemma, forms, table_tags):
        tt = (table_tags or "").split()
        if "strong" in tt and "weak" in tt:
            return "mixed"
        if "strong" in tt:
            return "strong"
        if "weak" in tt:
            return "weak"
        past = forms.get("verleden_tijd", {}).get("ik", "")
        if past.endswith(("de", "te")):
            return "weak"
        return "strong" if past else None

    def _inf_stems(self, lemma: str) -> list[str]:
        """Candidate stems: werk(en), roei(en), zie(n), gaa(n)."""
        out = []
        if lemma.endswith("en"):
            out.append(lemma[:-2])
        if lemma.endswith("n"):
            out.append(lemma[:-1])
        return out or [lemma]

    def irregular_in(self, lemma, cls, forms):
        irr = []
        p = forms.get("tegenwoordige_tijd", {})
        ik, jij, hij = p.get("ik"), p.get("jij"), p.get("hij/zij")
        pl = [p.get(x) for x in ("wij", "jullie", "zij")]
        ok = bool(ik)
        if ok:
            exp = _nl_canon(ik if ik.endswith("t") else ik + "t")   # ga + t = gaat
            ok = _nl_canon(jij or "") == exp and _nl_canon(hij or "") == exp and all(x == lemma for x in pl)
            ok = ok and any(_nl_canon(ik) == _nl_canon(s) for s in self._inf_stems(lemma))
        if not ok:
            irr.append("tegenwoordige_tijd")
        past = forms.get("verleden_tijd", {})
        if cls != "weak" or not past.get("ik", "").endswith(("de", "te")):
            irr.append("verleden_tijd")
        part = forms.get("participle", {}).get("_", "")
        if cls != "weak" or not part.endswith(("d", "t")):
            irr.append("perfectum")
        return irr

    def split(self, lemma, cls, tense, person, form, regular, table=None):
        """Dutch: only verbs regular in the tense get a split.

        Present: ik = stem + '' (ending is the empty string), jij/hij = stem + 't' (or + '' when
        the stem already ends in t), plural = stem + 'en'/'n'. Weak past: stem + te/de/ten/den.
        """
        if " " in form or not regular:
            return None, None
        i = self.persons.index(person)
        table = table or {}
        if tense == "tegenwoordige_tijd":
            if i >= 3:
                for e in ("en", "n"):
                    if form.endswith(e) and len(form) > len(e) + 1:
                        return form[: -len(e)], e
                return None, None
            ik = table.get("ik", form)
            if i == 0 or form == ik:
                return form, ""
            if form == ik + "t":
                return ik, "t"
            if form.endswith("t") and _nl_canon(form) == _nl_canon(ik + "t"):
                return form[:-1], "t"      # ga -> gaa + t
            return None, None
        if tense == "verleden_tijd" and cls == "weak":
            for e in ("ten", "den", "te", "de"):
                if form.endswith(e) and len(form) > len(e) + 1:
                    return form[: -len(e)], e
        return None, None

    def article_for(self, lemma, gender):
        if not gender:
            return None
        g = gender.split("|")[0]
        return "het" if g == "n" else "de"

    def compound(self, aux_forms, participle, person, aux):
        return f"{aux_forms[person]} {participle}", []

    def participle_variants(self, participle: str, aux: str) -> list[str]:
        return [participle]


from .lang_es import Spanish  # noqa: E402  (imports Lang from this module)

LANGS: dict[str, Lang] = {"it": Italian(), "nl": Dutch(), "es": Spanish()}


def get_lang(code: str) -> Lang:
    return LANGS[code]
