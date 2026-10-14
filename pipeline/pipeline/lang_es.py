"""Spanish (`es`) language rules for the pipeline (see lang.py for the fields).

Decisions (docs/new-language.md, content/es/course.yaml):
* Variety: neutral/peninsular standard. All six persons are taught, including *vosotros*; Latin
  American Spanish uses *ustedes* there, which the grammar notes explain.
* *usted* / *ustedes* are subject pronouns of the third person (él/ella, ellos/ellas): they take
  those forms, so unlike Dutch *u* they decide the person.
* Tenses (keys are ASCII): presente, imperfecto, preterito_indefinido (simple past), futuro
  (simple), and preterito_perfecto = present of *haber* + invariable participle (he comido). Vos
  forms, subjunctive, conditional and imperative forms are not read from Wiktionary.
* The tú-imperative looks like the él/ella present (¡Habla!): handled like Italian imperatives.
* Enclitic pronouns (hacerlo, dímelo, levantarse): Wiktionary's second conjugation template lists
  them; they become inflections of the verb item, so the word links to the verb without a form.
"""
from __future__ import annotations

from .lang import Lang

ES_PERSONS = ["yo", "tú", "él/ella", "nosotros", "vosotros", "ellos/ellas"]

ES_ENDINGS = {
    "presente": {
        "ar": ["o", "as", "a", "amos", "áis", "an"],
        "er": ["o", "es", "e", "emos", "éis", "en"],
        "ir": ["o", "es", "e", "imos", "ís", "en"],
    },
    "imperfecto": {
        "ar": ["aba", "abas", "aba", "ábamos", "abais", "aban"],
        "er": ["ía", "ías", "ía", "íamos", "íais", "ían"],
        "ir": ["ía", "ías", "ía", "íamos", "íais", "ían"],
    },
    "preterito_indefinido": {
        "ar": ["é", "aste", "ó", "amos", "asteis", "aron"],
        "er": ["í", "iste", "ió", "imos", "isteis", "ieron"],
        "ir": ["í", "iste", "ió", "imos", "isteis", "ieron"],
    },
}
# the future adds these to the whole infinitive (hablar+é)
ES_FUTURE = ["é", "ás", "á", "emos", "éis", "án"]

# feminine nouns that take 'el' in the singular (stressed a-: el agua, el hambre)
ES_EL_FEMININE = {"agua", "alma", "arma", "hambre", "área", "aula", "ave", "ala", "águila", "hacha", "hada",
                  "habla", "ancla", "arpa", "asa", "haba", "alba", "asma", "ama", "aria", "álgebra"}

# spelling changes that keep a verb regular: busc-ar -> busqu-é, lleg-ar -> llegu-é, empez-ar ->
# empec-é, cog-er -> coj-o, venc-er -> venz-o, distingu-ir -> disting-o
_ORTHO = [("c", "qu"), ("g", "gu"), ("z", "c"), ("g", "j"), ("c", "z"), ("gu", "g"), ("gu", "gü")]

PRONOUNS = {"yo": ["yo"], "tú": ["tú"], "él": ["él/ella"], "ella": ["él/ella"], "usted": ["él/ella"],
            "ello": ["él/ella"], "nosotros": ["nosotros"], "nosotras": ["nosotros"], "vosotros": ["vosotros"],
            "vosotras": ["vosotros"], "ellos": ["ellos/ellas"], "ellas": ["ellos/ellas"],
            "ustedes": ["ellos/ellas"]}

PREPOSITIONS = {"a", "de", "en", "con", "por", "para", "sin", "sobre", "desde", "hasta", "entre", "hacia",
                "contra", "según", "tras", "durante", "al", "del"}
DETERMINERS = {
    "el", "la", "los", "las", "un", "una", "unos", "unas", "este", "esta", "estos", "estas", "ese", "esa",
    "esos", "esas", "aquel", "aquella", "aquellos", "aquellas", "mi", "tu", "su", "mis", "tus", "sus",
    "nuestro", "nuestra", "nuestros", "nuestras", "vuestro", "vuestra", "vuestros", "vuestras", "cada",
    "algún", "alguna", "algunos", "algunas", "ningún", "ninguna", "otro", "otra", "otros", "otras",
    "mucho", "mucha", "muchos", "muchas", "poco", "poca", "pocos", "pocas", "varios", "varias",
    "tanto", "tanta", "tantos", "tantas", "todo", "toda",
    "todos", "todas", "dos", "tres", "cuatro", "cinco",
} | PREPOSITIONS
CLITICS = {"me", "te", "se", "nos", "os", "lo", "la", "los", "las", "le", "les"}


def _strip_accent(s: str) -> str:
    return s.translate(str.maketrans("áéíóú", "aeiou"))


class Spanish(Lang):
    def __init__(self) -> None:
        super().__init__(
            code="es",
            persons=list(ES_PERSONS),
            simple_tenses=["presente", "imperfecto", "preterito_indefinido", "futuro"],
            compound_tenses={"preterito_perfecto": "presente"},
            present="presente",
            auxiliaries=["haber"],
            tense_tags={
                "presente": {"indicative", "present"},
                "imperfecto": {"indicative", "imperfect"},
                "preterito_indefinido": {"indicative", "preterite"},
                "futuro": {"indicative", "future"},
            },
            articles=["el", "la"],
            pronouns=PRONOUNS,
            determiners=DETERMINERS,
            skip_between=CLITICS | {"no", "ya", "también", "siempre", "nunca", "todavía", "sí", "solo", "aún",
                                    "tampoco", "casi", "jamás"},
            third_sg="él/ella",
            third_pl="ellos/ellas",
            # 'ser', 'estar', 'haber' forms are never a tú-imperative (sé, está, he are other words)
            imperative_exempt={"ser", "estar", "haber", "ir"},
            imperative_lead={"ahora", "pues", "entonces", "bueno", "y", "ya", "también"},
            gerund=True,
            # 'he comido', 'no lo he visto', '¿Has visto...?'; 'he ya comido' is not Spanish
            aux_window=2,
            aux_between={"ya", "siempre", "nunca", "jamás", "también", "todavía", "bien", "mal", "realmente",
                         "tú", "usted", "él", "ella", "ustedes"},
            bare_participle_tense=False,
            verb_needs_pronoun={"como", "para", "bajo", "nada", "cerca", "junto", "salvo", "medio", "entre",
                                "sobre", "vale", "mira", "claro", "pase"},
            object_noun_after_verb=True,
            noun_coordinators={"y", "e", "o", "u", "ni"},
            clitic_forms=True,
            infinitive_endings=("ar", "er", "ir", "ír"),
            translation_subjects={"i": "yo", "i'm": "yo", "i've": "yo", "i'd": "yo", "i'll": "yo",
                                  "he": "él/ella", "she": "él/ella", "he's": "él/ella", "she's": "él/ella",
                                  "he'd": "él/ella", "she'd": "él/ella"},
            standalone_phrases={"de nada", "qué tal", "hasta luego", "hasta mañana"},
            tense_hints={w: "preterito_indefinido" for w in ("ayer", "anoche", "anteayer", "pasado", "pasada")},
            interrogatives={"qué", "cuánto", "cuánta", "cuántos", "cuántas", "cuál", "cuáles"},
            adverbial_nouns={"mañana", "tarde", "noche", "hoy", "ayer", "anoche", "domingo", "lunes", "sábado"},
            person_hint_verbs=True,
            adj_over_first_person=True,
            no_apostrophes=True,
            degree_words={"muy", "tan", "más", "menos", "demasiado", "bastante", "poco"},
            third_person_clitics={"se"},
        )

    # -- conjugation-table reading ------------------------------------------------------------
    def slot(self, tags):
        t = set(tags)
        if t & {"vos-form", "combined-form", "imperfect-se", "with-vos", "with-tú", "voseo"}:
            return None
        # en.wiktionary marks the tú forms 'informal' (against 'formal' usted imperatives)
        t.discard("informal")
        return super().slot(list(t))

    def _tense_exclusive(self, tense, t):
        others = {"imperfect", "future", "past", "present", "preterite", "conditional", "pluperfect",
                  "perfect"} - self.tense_tags[tense]
        return not (others & t)

    def spelling(self, form, link):
        return (form or "").strip()

    # -- morphology ---------------------------------------------------------------------------
    def verb_class(self, lemma, forms, table_tags):
        if lemma.endswith("ar"):
            return "ar"
        if lemma.endswith("er"):
            return "er"
        if lemma.endswith(("ir", "ír")):
            return "ir"
        return None

    def verb_stem(self, lemma, cls, complete, irr):
        return lemma[:-2] if cls else None

    def _stems(self, lemma: str) -> list[str]:
        """The infinitive stem plus regular spelling variants (busc: busqu; cog: coj)."""
        stem = lemma[:-2]
        out = [stem]
        for a, b in _ORTHO:
            if stem.endswith(a):
                out.append(stem[: -len(a)] + b)
        return out

    def regular_paradigms(self, lemma: str, cls: str | None, tense: str) -> list[list[str]]:
        if not cls:
            return []
        if tense == "futuro":
            inf = _strip_accent(lemma[:-2]) + lemma[-2:].replace("í", "i")
            return [[inf + e for e in ES_FUTURE]]
        ends = ES_ENDINGS.get(tense, {}).get(cls)
        if not ends:
            return []
        stem = lemma[:-2]
        base = [stem + e for e in ends]
        out = [base]
        # one person with a spelling change: busqué (pret. yo), cojo / venzo / distingo (pres. yo)
        for st in self._stems(lemma)[1:]:
            for i in range(6):
                if tense == "preterito_indefinido" and cls == "ar" and i == 0:
                    out.append(base[:i] + [st + ends[i]] + base[i + 1:])
                if tense == "presente" and i == 0 and cls in ("er", "ir"):
                    out.append(base[:i] + [st + ends[i]] + base[i + 1:])
        return out

    def irregular_in(self, lemma, cls, forms):
        irr = []
        for tense in ("presente", "imperfecto", "preterito_indefinido", "futuro"):
            actual = [forms.get(tense, {}).get(p) for p in self.persons]
            if tense == "presente" or all(actual):
                if actual not in self.regular_paradigms(lemma, cls, tense):
                    irr.append(tense)
        part = forms.get("participle", {}).get("_")
        reg = {"ar": lemma[:-2] + "ado", "er": lemma[:-2] + "ido", "ir": lemma[:-2] + "ido"}.get(cls or "")
        if part is None or part != reg:
            irr.append("preterito_perfecto")
        return irr

    def split(self, lemma, cls, tense, person, form, regular, table=None):
        """Stem + class ending; the stem must be the infinitive stem or a regular spelling variant
        of it (busqu+é, coj+o); the future: the infinitive + ending (hablar+é)."""
        if " " in form or not cls:
            return None, None
        i = self.persons.index(person)
        if tense == "futuro":
            e = ES_FUTURE[i]
            stem = form[: -len(e)]
            if form.endswith(e) and stem in (lemma, _strip_accent(lemma)):
                return stem, e
            return None, None
        ends = ES_ENDINGS.get(tense, {})
        cands = [ends[cls][i]] if cls in ends else []
        cands += [ends[c][i] for c in ("ar", "er", "ir") if c in ends and ends[c][i] not in cands]
        stems = self._stems(lemma)
        for e in cands:
            if form.endswith(e) and len(form) > len(e) and form[: -len(e)] in stems:
                return form[: -len(e)], e
        return None, None

    def article_for(self, lemma, gender):
        if not gender or not lemma:
            return None
        g = gender.replace(" ", "")
        if g in ("m|f", "f|m", "mf", "mfbysense"):
            return "el|la"
        if g.startswith("m"):
            return "el"
        if g.startswith("f"):
            return "el" if lemma.lower() in ES_EL_FEMININE else "la"
        return None

    def compound(self, aux_forms, participle, person, aux):
        return f"{aux_forms[person]} {participle}", []

    def participle_variants(self, participle: str, aux: str) -> list[str]:
        """Agreeing forms for adjectival/passive use (cerrado, cerrada, cerrados, cerradas); the
        perfect itself always uses the masculine singular."""
        if participle.endswith("o"):
            b = participle[:-1]
            return [participle, b + "a", b + "os", b + "as"]
        return [participle]
