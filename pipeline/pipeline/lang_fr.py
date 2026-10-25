"""French (`fr`) language rules for the pipeline (see lang.py for the fields).

Decisions (content/fr/course.yaml in tosk-data):
* Variety: standard French of France. *on* takes the il/elle forms; *vous* is plural and the polite
  singular (both take the vous forms).
* Tenses (keys are ASCII): present, imparfait, passe_simple (recognition only), futur, conditionnel,
  subjonctif (present subjunctive), imperatif (tu, nous, vous); compound tenses from the auxiliary's
  tense + the past participle: passe_compose (present), plus_que_parfait (imparfait), futur_anterieur
  (futur), conditionnel_passe (conditionnel), subjonctif_passe (subjonctif). The imperfect
  subjunctive and the passé antérieur are left out (seed.yaml exclude_moods: imperfect-subjunctive).
* Elision: *l'*, *j'*, *d'*, *qu'*, *n'*, *c'*, *s'*, *m'*, *t'*, *jusqu'*, *lorsqu'*, *puisqu'* are
  tokens of their own (tokens.py), looked up as their full words (le/la, je, de, que, ...).
* Hyphenated inversion and imperatives (*parlez-vous*, *a-t-il*, *est-ce*, *donne-moi*, *lève-toi*)
  stay one token; the aligner links the host verb with the cell the suffix calls for (an indicative
  form of the suffix's person, or the imperative), so the app glosses it but never asks it.
* Reflexive verbs are the plain verb + its pronoun (*je me lève* = lever + me), like Spanish: the
  `reflexive` detector finds them. A reflexive pronoun before *être* makes any verb's participle a
  compound form (*je me suis levé*); verbs taught as reflexive list être as a second auxiliary
  (seed.yaml `aux`), so the app finds those forms too. Wiktionary tables of verbs that only exist as
  reflexives (*se souvenir*: *me souviens*) lose their pronouns.
* Participles agree: with être (*elle est allée*), and with avoir after a preceding direct object
  (*je les ai vues*, *la lettre que j'ai écrite*); such a spelling is linked to the compound tense.
* Moods: a present form that is also a subjunctive (*parle*, *finissent*) or an imperfect that is
  also one (*parlions*) is the subjunctive only after a trigger + *que* (*il faut que*, *je veux
  que*, *bien que*); after *penser que*, *dire que* or a relative *que* it is the indicative; after
  any other *que* the mood is unsure and the importer drops the sentence.
"""
from __future__ import annotations

import re

from .lang import BAD_FORM_TAGS, Lang

FR_PERSONS = ["je", "tu", "il/elle", "nous", "vous", "ils/elles"]

# endings per class: er (parler), ir (finir: finissons), re (vendre)
FR_ENDINGS = {
    "present": {
        "er": ["e", "es", "e", "ons", "ez", "ent"],
        "ir": ["is", "is", "it", "issons", "issez", "issent"],
        "re": ["s", "s", "", "ons", "ez", "ent"],
    },
    "imparfait": {c: ["ais", "ais", "ait", "ions", "iez", "aient"] for c in ("er", "ir", "re")},
    "passe_simple": {
        "er": ["ai", "as", "a", "âmes", "âtes", "èrent"],
        "ir": ["is", "is", "it", "îmes", "îtes", "irent"],
        "re": ["is", "is", "it", "îmes", "îtes", "irent"],
    },
    "futur": {c: ["ai", "as", "a", "ons", "ez", "ont"] for c in ("er", "ir", "re")},
    "conditionnel": {c: ["ais", "ais", "ait", "ions", "iez", "aient"] for c in ("er", "ir", "re")},
    "subjonctif": {c: ["e", "es", "e", "ions", "iez", "ent"] for c in ("er", "ir", "re")},
    # tu, nous, vous (no je, il/elle, ils/elles)
    "imperatif": {
        "er": [None, "e", None, "ons", "ez", None],
        "ir": [None, "is", None, "issons", "issez", None],
        "re": [None, "s", None, "ons", "ez", None],
    },
}

FR_LETTERS = re.compile(r"^[a-zàâäçéèêëîïôöùûüÿœæ' -]+$", re.I)
FR_REFL_PREFIX = re.compile(r"^(?:(?:me|te|se|nous|vous) (?:en |y )?|[mts]'(?:en |y )?)(?=\S)")
FR_REFL_SUFFIX = re.compile(r"-(?:toi|nous|vous)$")
FR_AUX = re.compile(r"(?:s'en |s'|se )?(avoir|être)(?: or (avoir|être))? \+ past participle$")

# h aspiré: no elision, no liaison (le héros, la honte)
FR_H_ASPIRE = {
    "hache", "haie", "haine", "hall", "halle", "halte", "hamac", "hameau", "hamburger", "hamster", "hanche",
    "handicap", "hangar", "hareng", "haricot", "harpe", "hasard", "hâte", "hausse", "haut", "hauteur", "havre",
    "hérisson", "héros", "hibou", "hiérarchie", "hockey", "hollande", "homard", "honte", "hors-d'œuvre",
    "housse", "hublot", "huit", "huitième", "hurlement", "hutte", "hamac", "hamster", "harcèlement", "hargne",
    "haut-parleur", "hérissé", "hernie", "héron", "hêtre", "hibou", "hoquet", "houx", "huée", "hachis",
}

PRONOUNS = {
    "je": ["je"], "j'": ["je"], "tu": ["tu"], "il": ["il/elle"], "elle": ["il/elle"], "on": ["il/elle"],
    "nous": ["nous"], "vous": ["vous"], "ils": ["ils/elles"], "elles": ["ils/elles"],
    # 'c'est', 'ça marche', 'cela suffit'; 'ce sont'
    "c'": ["il/elle"], "ça": ["il/elle"], "cela": ["il/elle"], "ceci": ["il/elle"],
    "ce": ["il/elle", "ils/elles"],
}
# object clitics that may stand between the subject and the verb ('je ne le lui donne pas')
CLITICS = {"ne", "n'", "me", "m'", "te", "t'", "se", "s'", "le", "la", "les", "l'", "lui", "leur", "y", "en",
           "nous", "vous"}
PREPOSITIONS = {"à", "de", "d'", "en", "dans", "sur", "sous", "avec", "pour", "par", "sans", "chez", "entre",
                "vers", "contre", "depuis", "pendant", "après", "avant", "au", "aux", "du", "des", "malgré",
                "parmi", "selon", "dès", "jusqu'à", "près", "loin"}
DETERMINERS = {
    "le", "la", "l'", "les", "un", "une", "des", "du", "ce", "cet", "cette", "ces", "mon", "ma", "mes",
    "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs", "quel", "quelle",
    "quels", "quelles", "chaque", "plusieurs", "quelques", "aucun", "aucune", "tout", "toute", "tous", "toutes",
    "certains", "certaines", "nul", "nulle", "deux", "trois", "quatre", "cinq", "dix", "cent", "mille",
} | PREPOSITIONS

# words that may stand between an auxiliary and its participle ('je n'ai jamais vu', 'il a déjà mangé')
FR_BETWEEN_AUX_PART = {
    "pas", "plus", "jamais", "rien", "déjà", "toujours", "bien", "mal", "beaucoup", "trop", "encore", "souvent",
    "vraiment", "tout", "tous", "toutes", "peut-être", "enfin", "presque", "aussi", "assez", "longtemps", "guère",
    "point", "certainement", "sûrement", "probablement", "même", "seulement", "également", "finalement", "vite",
    "tellement", "très", "mieux", "moins", "si", "tant", "juste", "aussitôt", "forcément", "évidemment",
    "complètement", "parfois", "rarement", "sans", "doute", "mal", "jamais", "personne", "ensemble",
}

# subjunctive after these + que (lemmas and words): il faut que, je veux que, je suis content que
FR_SUBJ_TRIGGERS = {
    "falloir", "vouloir", "souhaiter", "désirer", "préférer", "aimer", "exiger", "demander", "ordonner",
    "permettre", "interdire", "empêcher", "accepter", "refuser", "attendre", "craindre", "regretter", "douter",
    "sembler", "suffire", "valoir", "tenir", "veiller", "proposer", "conseiller", "supplier", "insister",
    "content", "heureux", "triste", "désolé", "surpris", "étonné", "ravi", "furieux", "fier", "fâché", "déçu",
    "dommage", "important", "nécessaire", "essentiel", "possible", "impossible", "temps", "normal", "naturel",
    "rare", "étrange", "bizarre", "juste", "injuste", "utile", "inutile", "préférable", "mieux", "urgent",
    "indispensable", "obligatoire", "honte", "envie", "besoin", "peur", "crainte", "bon", "dommage",
    "inquiet", "contente", "heureuse", "désolée", "surprise", "étonnée", "ravie", "fière", "inquiète",
    "faut", "fallait", "faudra", "faudrait", "veux", "veut", "voulez", "voulons", "veulent", "voudrais",
    "voudrait", "vaut", "vaudrait", "semble", "suffit",
}
# indicative after these + que: je pense que, il dit que, je suis sûr que, parce que, pendant que
FR_IND_TRIGGERS = {
    "penser", "croire", "espérer", "dire", "savoir", "voir", "trouver", "apprendre", "remarquer", "affirmer",
    "promettre", "expliquer", "annoncer", "répondre", "écrire", "sentir", "entendre", "oublier", "comprendre",
    "paraître", "imaginer", "supposer", "prétendre", "jurer", "ajouter", "raconter", "lire", "montrer",
    "décider", "constater", "reconnaître", "deviner", "rappeler", "prouver", "admettre",
    "sûr", "sûre", "certain", "certaine", "évident", "clair", "vrai", "probable", "convaincu", "persuadé",
    "parce", "pendant", "alors", "depuis", "dès", "tandis", "après", "ainsi", "maintenant", "lors", "vu",
    "étant", "sauf", "si", "même",
}
FR_SUBJ_CONJUNCTIONS = {
    "bien que", "bien qu'", "quoique", "quoiqu'", "pour que", "pour qu'", "afin que", "afin qu'", "avant que",
    "avant qu'", "à moins que", "à moins qu'", "sans que", "sans qu'", "jusqu'à ce que", "jusqu'à ce qu'",
    "en attendant que", "en attendant qu'", "de peur que", "de peur qu'", "de crainte que", "pourvu que",
    "pourvu qu'", "à condition que", "à condition qu'", "quoi que", "quoi qu'", "où que", "qui que",
}

# suffixes of hyphenated verb words: subject pronouns (inversion: 'parlez-vous', 'a-t-il', 'est-ce')
# and object pronouns (imperative: 'donne-moi', 'lève-toi', 'allez-y', 'dis-le-moi')
FR_HYPHEN_SUBJECTS = {"je": ["je"], "tu": ["tu"], "il": ["il/elle"], "elle": ["il/elle"], "on": ["il/elle"],
                      "nous": ["nous"], "vous": ["vous"], "ils": ["ils/elles"], "elles": ["ils/elles"],
                      "ce": ["il/elle", "ils/elles"]}
FR_HYPHEN_OBJECTS = {"moi", "toi", "le", "la", "les", "lui", "leur", "nous", "vous", "y", "en", "m'", "t'",
                     "l'", "m'en", "t'en", "ci", "là"}


def _strip_accents(s: str) -> str:
    return s.translate(str.maketrans("éèêëàâäîïôöùûüç", "eeeeaaaiioouuuc"))


class French(Lang):
    def __init__(self) -> None:
        super().__init__(
            code="fr",
            persons=list(FR_PERSONS),
            simple_tenses=["present", "imparfait", "passe_simple", "futur", "conditionnel", "subjonctif",
                           "imperatif"],
            compound_tenses={"passe_compose": "present", "plus_que_parfait": "imparfait",
                             "futur_anterieur": "futur", "conditionnel_passe": "conditionnel",
                             "subjonctif_passe": "subjonctif"},
            present="present",
            auxiliaries=["avoir", "être"],
            tense_tags={
                "present": {"indicative", "present"},
                "imparfait": {"indicative", "imperfect"},
                "futur": {"indicative", "future"},
            },
            articles=["le", "la", "l'"],
            pronouns=PRONOUNS,
            determiners=DETERMINERS,
            skip_between=set(CLITICS),
            third_sg="il/elle",
            third_pl="ils/elles",
            # their imperatives are subjunctive-like (sois, aie, sache, veuille): a present form of
            # these verbs is never an imperative
            imperative_exempt={"être", "avoir", "savoir", "vouloir"},
            imperative_lead={"ne", "n'", "me", "m'", "te", "t'", "le", "la", "les", "l'", "lui", "leur", "y", "en",
                             "nous", "vous", "maintenant", "alors", "donc", "allez", "s'il"},
            gerund=True,
            aux_window=4,
            aux_between=FR_BETWEEN_AUX_PART,
            # 'la porte est fermée', 'il est mort': a participle without auxiliary tags no tense
            bare_participle_tense=False,
            copula_lemmas={"être", "devenir", "rester", "sembler", "paraître"},
            infinitive_endings=("er", "ir", "re", "ïr"),
            interrogatives={"quel", "quelle", "quels", "quelles", "combien", "que", "qu'"},
            adverbial_nouns={"matin", "soir", "nuit", "jour", "semaine", "mois", "an", "année", "hier",
                             "aujourd'hui", "demain", "fois", "lundi", "mardi", "mercredi", "jeudi", "vendredi",
                             "samedi", "dimanche", "midi", "minuit", "après-midi", "soirée", "matinée"},
            person_hint_verbs=True,
            third_person_clitics={"se", "s'"},
            tense_persons={"imperatif": ["tu", "nous", "vous"]},
            tense_moods={"conditionnel": "conditional", "conditionnel_passe": "conditional",
                         "subjonctif": "subjunctive", "subjonctif_passe": "subjunctive",
                         "imperatif": "imperative"},
            subj_conjunctions=FR_SUBJ_CONJUNCTIONS,
            subj_complementizer="que",
            subj_complementizer_elided="qu'",
            subj_triggers=FR_SUBJ_TRIGGERS,
            ind_triggers=FR_IND_TRIGGERS,
            elisions={"l'": ["le", "la"], "j'": ["je"], "m'": ["me"], "t'": ["te"], "s'": ["se", "si"],
                      "n'": ["ne"], "c'": ["ce"], "d'": ["de"], "qu'": ["que"], "jusqu'": ["jusque"],
                      "lorsqu'": ["lorsque"], "puisqu'": ["puisque"], "quoiqu'": ["quoique"],
                      "presqu'": ["presque"], "quelqu'": ["quelque"]},
            clitic_pronouns={"nous", "vous"},
            article_clitics={"le", "la", "les", "l'", "leur", "en", "y"},
            rare_tense_homographs={"passe_simple"},
            object_clitics={"le", "la", "les", "l'", "que", "qu'"},
            agreeing_aux={"être"},
            agreement_lookback=3,
            reflexive_clitics={"me": "je", "m'": "je", "te": "tu", "t'": "tu", "se": "il/elle,ils/elles",
                               "s'": "il/elle,ils/elles", "nous": "nous", "vous": "vous"},
            reflexive_aux="être",
            hyphen_subjects=FR_HYPHEN_SUBJECTS,
            hyphen_objects=FR_HYPHEN_OBJECTS,
            participle_after_copula=True,
            impersonal_third=True,
            homograph_verbs_by_rank=True,
            gerund_marker="en",
            lookup_pos={"le": "det", "la": "det", "les": "det", "l'": "det", "leur": "det", "en": "prep",
                        "tous": "det", "toutes": "det", "toute": "det"},
            infinitive_preps={"de", "d'", "à", "pour", "sans", "par", "après", "avant"},
            noun_after_adjective=True,
            table_forms_lookup=True,
            capitalized_names=True,
            subject_required=True,
            predicate_determiners={"quel", "quelle", "quels", "quelles"},
            # verbs that take a bare infinitive, so 'va le voir' is clitic + infinitive
            modals={"pouvoir", "vouloir", "devoir", "savoir", "aller", "venir", "falloir", "aimer", "préférer",
                    "laisser", "faire", "oser", "espérer", "sembler", "adorer", "détester"},
            degree_words={"très", "trop", "si", "assez", "plus", "moins", "aussi", "vraiment", "tellement", "bien",
                          "peu", "plutôt"},
            phrase_pos=("intj", "phrase", "adv", "conj", "prep", "pron", "particle"),
            clitic_relink={"le": "pron", "la": "pron", "les": "pron", "l'": "pron", "leur": "pron", "en": "pron"},
        )

    # -- conjugation-table reading ------------------------------------------------------------
    def spelling(self, form, link):
        """The written form of a table cell: no IPA rows ('paʁl'), no reflexive pronouns of a
        pronominal-only verb's table ('me souviens' -> 'souviens', 'souviens-toi' -> 'souviens')."""
        s = (form or "").strip()
        if not s or s == "-" or not FR_LETTERS.match(s):
            return ""
        s = FR_REFL_PREFIX.sub("", s)
        s = FR_REFL_SUFFIX.sub("", s)
        return s.strip()

    def auxiliary_of(self, form: str, tags) -> list[str] | None:
        """'avoir + past participle', "s'être + past participle" (the infinitive row of a table)."""
        t = set(tags)
        if "multiword-construction" not in t or "infinitive" not in t:
            return None
        m = FR_AUX.match((form or "").strip())
        if not m:
            return []
        return [a for a in m.groups() if a]

    def form_moods(self, tags) -> set[str]:
        """Moods of a table form for seed.yaml exclude_moods; the imperfect subjunctive (parlât,
        fût, eût) is its own 'imperfect-subjunctive'."""
        t = set(tags)
        out = {m for m in ("subjunctive", "conditional", "imperative") if m in t}
        if {"imperfect", "subjunctive"} <= t:
            out = {"imperfect-subjunctive"}
        return out

    def slot(self, tags):
        t = set(tags) - {"reflexive"}
        if "multiword-construction" in t:
            return None
        if "imperative" in t:
            t = t - {"imperative"}
            if t & BAD_FORM_TAGS:
                return None
            persons = [p for p in self.persons_for(t) if p in self.tense_persons["imperatif"]]
            return ("imperatif", ",".join(persons)) if persons else None
        if t & {"infinitive", "participle", "gerund"}:
            return super().slot(list(t))
        if t & (BAD_FORM_TAGS - {"historic", "conditional", "subjunctive"}):
            return None
        tense = None
        if "conditional" in t:
            tense = "conditionnel"
        elif "subjunctive" in t:
            tense = "subjonctif" if "present" in t else None
        elif "historic" in t:
            tense = "passe_simple" if {"indicative", "past"} <= t else None
        else:
            return super().slot(list(t))
        persons = self.persons_for(t) if tense else []
        return (tense, ",".join(persons)) if persons else None

    # -- morphology ---------------------------------------------------------------------------
    def verb_class(self, lemma, forms, table_tags):
        """er (parler; not aller), ir (finir: finissons), re (vendre: vendons), other."""
        nous = (forms.get("present") or {}).get("nous", "")
        if lemma.endswith("er") and lemma != "aller":
            return "er"
        if lemma.endswith(("ir", "ïr")) and nous.endswith("issons"):
            return "ir"
        if lemma.endswith("re") and nous.endswith("ons") and not nous.endswith("issons"):
            return "re"
        return "other"

    def _stem(self, lemma: str, cls: str | None) -> str:
        return lemma[:-2] if cls in ("er", "ir", "re") else lemma

    @staticmethod
    def _join(stem: str, ending: str, cls: str | None) -> str:
        """stem + ending with the regular spelling changes of -ger and -cer verbs (mangeons,
        commençais): a soft g or c keeps its sound before a and o."""
        if cls == "er" and ending[:1] in ("a", "o", "â"):
            if stem.endswith("g"):
                return stem + "e" + ending
            if stem.endswith("c"):
                return stem[:-1] + "ç" + ending
        return stem + ending

    @staticmethod
    def _soft(stem: str, ending: str) -> str:
        """A stem from 'nous mangeons / commençons' before an ending: mange+ais, mang+ions,
        commenç+ais, commenc+ions."""
        if ending[:1] in ("i", "e"):
            if stem.endswith("ge"):
                return stem[:-1] + ending
            if stem.endswith("ç"):
                return stem[:-1] + "c" + ending
        return stem + ending

    def _derived(self, lemma: str, tense: str, forms: dict) -> list[str] | None:
        """Paradigms derived from the present as French grammars teach them, for every verb: the
        imparfait from 'nous' (pren-ons: prenais), the subjunctive from 'ils' and 'nous' (prenn-ent,
        pren-ons: que je prenne, que nous prenions), the imperative from the present (tu without
        the -s of -er verbs: parle, va). Verbs that break these (être, avoir, aller, faire, pouvoir,
        savoir, vouloir in the subjunctive) are irregular in that tense."""
        pres = forms.get("present") or {}
        nous, ils = pres.get("nous") or "", pres.get("ils/elles") or ""
        if not nous.endswith("ons") or (tense == "subjonctif" and not ils.endswith("ent")):
            return None
        nstem, istem = nous[:-3], ils[:-3]
        if tense == "imparfait":
            return [self._soft(nstem, e) for e in FR_ENDINGS["imparfait"]["er"]]
        if tense == "subjonctif":
            return [istem + "e", istem + "es", istem + "e", self._soft(nstem, "ions"), self._soft(nstem, "iez"),
                    istem + "ent"]
        if tense == "imperatif":
            tu = pres.get("tu") or ""
            if tu.endswith("es") or tu == "vas":
                tu = tu[:-1]
            return [tu, nous, pres.get("vous") or ""]
        return None

    def _regular(self, lemma: str, cls: str | None, tense: str, forms: dict) -> list[str] | None:
        """The regular paradigm of `tense` (in persons_of order), or None for class 'other'."""
        if tense in ("imparfait", "subjonctif", "imperatif"):
            return self._derived(lemma, tense, forms)
        if cls not in ("er", "ir", "re") or tense not in FR_ENDINGS:
            return None
        stem = self._stem(lemma, cls)
        persons = self.persons_of(tense)
        idx = [self.persons.index(p) for p in persons]
        ends = FR_ENDINGS[tense][cls]
        if tense in ("futur", "conditionnel"):
            base = lemma[:-1] if cls == "re" else lemma
            return [base + ends[i] for i in idx]
        if tense == "imparfait":
            st = stem + ("iss" if cls == "ir" else "")
            return [self._join(st, ends[i], cls) for i in idx]
        if tense == "subjonctif":
            st = stem + ("iss" if cls == "ir" else "")
            return [st + ends[i] for i in idx]
        return [self._join(stem, ends[i], cls) for i in idx]

    def irregular_in(self, lemma, cls, forms):
        irr = []
        for tense in ("present", "imparfait", "passe_simple", "futur", "conditionnel", "subjonctif", "imperatif"):
            persons = self.persons_of(tense)
            actual = [(forms.get(tense) or {}).get(p) for p in persons]
            if tense != "present" and not all(actual):
                continue
            if actual != self._regular(lemma, cls, tense, forms):
                irr.append(tense)
        # the participle is regular when it follows the infinitive's ending (parlé, fini, vendu; also
        # allé, parti, sorti of verbs that are irregular elsewhere), irregular otherwise (fait, pris, venu)
        part = (forms.get("participle") or {}).get("_")
        reg = None
        for inf, ending in (("er", "é"), ("ir", "i"), ("re", "u")):
            if lemma.endswith(inf):
                reg = lemma[: -len(inf)] + ending
        if lemma.endswith("re") and cls != "re":
            reg = None                       # prendre, mettre, dire, écrire: irregular participles
        if part is None or part != reg:
            irr += list(self.compound_tenses)
        return irr

    def verb_stem(self, lemma, cls, complete, irr):
        return self._stem(lemma, cls) if cls in ("er", "ir", "re") else None

    def split(self, lemma, cls, tense, person, form, regular, table=None):
        """Stem + class ending for verbs regular in the tense (parl+ons, finiss+ons, vend+ez,
        parler+ai, mange+ons); irregular forms get no split."""
        if " " in form or "-" in form or not regular or cls not in ("er", "ir", "re") or tense not in FR_ENDINGS:
            return None, None
        i = self.persons.index(person)
        e = FR_ENDINGS[tense][cls][i]
        if e is None:
            return None, None
        if tense in ("futur", "conditionnel"):
            stem = lemma[:-1] if cls == "re" else lemma
        elif tense in ("imparfait", "subjonctif") and cls == "ir":
            stem = lemma[:-2] + "iss"
        else:
            stem = self._stem(lemma, cls)
        if form == stem + e:
            return stem, e
        if form.endswith(e) and len(form) > len(e) and form[: len(form) - len(e)] in (stem + "e", stem[:-1] + "ç"):
            return form[: len(form) - len(e)], e        # mange+ons, commenç+ais
        return None, None

    def article_for(self, lemma, gender):
        if not gender or not lemma:
            return None
        g = gender.split("|")
        w = lemma.lower()
        vowel = w[:1] in "aeiouyàâäéèêëîïôöùûüœæ" or (w[:1] == "h" and w not in FR_H_ASPIRE)
        if vowel:
            return "l'"
        if len(g) > 1:
            return None
        if g[0].startswith("m"):
            return "le"
        if g[0].startswith("f"):
            return "la"
        return None

    def compound(self, aux_forms, participle, person, aux):
        a = aux_forms[person]
        if aux != "être" or participle == "été":
            return f"{a} {participle}", []
        v = self.participle_variants(participle, aux)          # [m.sg, f.sg, m.pl, f.pl]
        if len(v) < 4:
            return f"{a} {participle}", []
        if person == "vous":
            main, alts = v[2], [v[3], v[0], v[1]]      # plural, or the polite singular
        elif self.persons.index(person) >= 3:
            main, alts = v[2], [v[3]]
        else:
            main, alts = v[0], [v[1]]
        return f"{a} {main}", [f"{a} {x}" for x in dict.fromkeys(alts) if x != main]

    def participle_variants(self, participle: str, aux: str) -> list[str]:
        """m.sg, f.sg, m.pl, f.pl of a past participle (allé, allée, allés, allées; pris, prise, pris,
        prises; dû, due, dus, dues); 'été' never agrees."""
        p = participle
        if not p or p == "été" or " " in p:
            return [p]
        if p.endswith("û"):
            b = p[:-1] + "u"
            return [p, b + "e", b + "s", b + "es"]
        if p.endswith(("s", "x")):
            return [p, p + "e", p, p + "es"]
        return [p, p + "e", p + "s", p + "es"]
