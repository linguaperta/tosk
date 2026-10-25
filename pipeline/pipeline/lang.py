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


# accented monosyllables that Italian writes with the accent; others in Wiktionary's stress-marked
# forms ('và', 'fà', 'stà', 'sò') lose it
IT_ACCENTED_MONOSYLLABLES = {"è", "dà", "sì", "là", "lì", "già", "può", "più", "ciò", "giù", "né", "sé", "tè", "ché"}


def _unstress_monosyllable(word: str) -> str:
    vowels = sum(1 for ch in word.lower() if ch in "aeiouàèéìíòóùú")
    if vowels == 1 and word[-1:] in "àèéìíòóùú" and word.lower().split("'")[-1] not in IT_ACCENTED_MONOSYLLABLES:
        return word[:-1] + unicodedata.normalize("NFD", word[-1])[0]
    return word


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
    # spellings that are also the imperative of another verb: spelling -> (that verb, its English
    # heads) (Spanish 've' = he sees / go!, 'ven' = they see / come!, 'sé' = I know / be!).
    # Clause-initial without a subject pronoun and with '!' or an English translation starting with
    # one of the heads, the word links to that verb without a form
    imperative_homographs: dict[str, tuple[str, set[str]]] = field(default_factory=dict)
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
    # ... or one of these object clitics right before it ('lo como', 'me mira', 'se para')
    preverbal_clitics: set[str] = field(default_factory=set)
    # verbs ('ser', 'estar') after whose finite form (with only `skip_between` words in between) a word
    # is no finite verb: '¿Estás todavía despierta?' (awake), not 'ella despierta'
    copula_lemmas: set[str] = field(default_factory=set)
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
    # nouns used as time adverbs ("mañana", "hoy"): never the subject of the verb after them
    adverbial_nouns: set[str] = field(default_factory=set)
    # an adjective that is also only a first-person-singular verb form is the adjective unless it
    # starts the clause or 'yo' stands next to it (Spanish 'enfermo', 'largo', 'claro')
    adj_over_first_person: bool = False
    # the language writes no apostrophes: Tatoeba sentences with one (English titles, odd quoting)
    # are skipped by the importer
    no_apostrophes: bool = False
    # a spelling shared by several verbs goes to the verb that has a form of the person an
    # adjacent subject pronoun gives, or a third-person form after one of `third_person_clitics`
    person_hint_verbs: bool = False
    third_person_clitics: set[str] = field(default_factory=set)
    # tenses whose table has only some persons (Italian imperative: no io, no loro); a table of such
    # a tense is complete when it has these persons
    tense_persons: dict[str, list[str]] = field(default_factory=dict)
    # mood of each tense that is not plain indicative ('congiuntivo_presente' -> 'subjunctive',
    # 'imperativo' -> 'imperative', 'condizionale' -> 'conditional'). The aligner uses it to pick
    # between homographs of several moods (Italian 'parli': tu presente / congiuntivo / Lei imperative)
    tense_moods: dict[str, str] = field(default_factory=dict)
    # subjunctive contexts (aligner, _mood_context): conjunctions that always take the subjunctive
    # (one or more words: 'affinché', 'prima che'), the complementizer that takes it after a trigger
    # word ('che' after 'penso', 'voglio', 'è importante'), the trigger lemmas, and words that call
    # for some subjunctive tenses only ('se' + congiuntivo imperfetto)
    subj_conjunctions: set[str] = field(default_factory=set)
    subj_complementizer: str = ""
    subj_triggers: set[str] = field(default_factory=set)
    subj_if: dict[str, set[str]] = field(default_factory=dict)
    # trigger verbs after which the complementizer may be dropped ('Pensavo foste a casa', 'Credo
    # sia vero'): a mood homograph right after one (clitics in between) is the subjunctive
    subj_che_drop: set[str] = field(default_factory=set)
    # multi-word verb forms (Italian pronominal verbs: 'mi alzo', 'mi sono alzato', 'me ne vado') are
    # aligned on every word, like Sarnami 'kare hai' (docs/pack-format.md, 7: multi-word verb forms)
    multiword_forms: bool = False
    # clitic pronouns that may be attached to an infinitive, gerund or imperative ('farlo', 'dimmi',
    # 'alzandosi', 'diglielo'), longest first; such a word links to its verb (aligner, _enclitic)
    enclitics: tuple[str, ...] = ()
    # rarely meant tenses whose forms are also adjectives or participles ('sorpresi': passato remoto
    # io of sorprendere / surprised): such a word is read as the adjective or participle, unless an
    # io subject stands next to it
    homograph_tenses: set[str] = field(default_factory=set)
    # absolute superlative endings ('bellissimo'): such a word links to its adjective (aligner)
    elative: tuple[str, ...] = ()
    # --- (French, 1.4) fields below default to "off"; see lang_fr.py for how French uses them
    # elided words and the full words they stand for ("l'": [le, la], "j'": [je]), for lookups
    elisions: dict[str, list[str]] = field(default_factory=dict)
    # elided complementizer ("qu'") next to subj_complementizer
    subj_complementizer_elided: str = ""
    # trigger lemmas/words after which the complementizer takes the indicative ('je pense que'): a
    # mood homograph there is the indicative, not unsure
    ind_triggers: set[str] = field(default_factory=set)
    # subject pronouns that are also object clitics before the verb ('Il nous parle'): the leftmost
    # pronoun of the clitic cluster is the subject
    clitic_pronouns: set[str] = field(default_factory=set)
    # articles that are also object clitics ('je la porte'): after a subject pronoun (or 'ne', another
    # clitic) the next word is a verb, not a noun after a determiner
    article_clitics: set[str] = field(default_factory=set)
    # rare tenses whose forms are also forms of a common tense or participles ('finis', 'vit', 'mis'):
    # such spellings are read as the common form (the rare tense only where its spelling is unique)
    rare_tense_homographs: set[str] = field(default_factory=set)
    # participle agreement with a preceding direct object ('je les ai vues', 'la lettre que j'ai
    # écrite'): an agreeing participle of an auxiliary outside `agreeing_aux` needs one of
    # `object_clitics` within `agreement_lookback` words before the auxiliary
    object_clitics: set[str] = field(default_factory=set)
    agreeing_aux: set[str] = field(default_factory=set)
    agreement_lookback: int = 1
    # a reflexive pronoun right before `reflexive_aux` makes any verb's participle a compound form
    # ('je me suis levé' with lever, which takes avoir otherwise): pronoun -> persons (comma-joined)
    reflexive_clitics: dict[str, str] = field(default_factory=dict)
    reflexive_aux: str = ""
    # hyphenated verb words: suffix subject pronouns (inversion 'parlez-vous', 'a-t-il') and object
    # pronouns (imperatives 'donne-moi', 'lève-toi'); the host verb is linked with that cell
    hyphen_subjects: dict[str, list[str]] = field(default_factory=dict)
    hyphen_objects: set[str] = field(default_factory=set)
    # after a finite copula a participle homograph of a finite form is the participle ('la lettre est
    # écrite', 'le livre est écrit par ...'), not the copula-only adjective reading
    participle_after_copula: bool = False
    # a verb without a complete present table keeps its third-person cells (impersonal 'falloir':
    # il faut, il fallait), like Italian impersonal pronominal verbs
    impersonal_third: bool = False
    # a finite spelling of two verbs goes to the far more frequent one (French 'suis': être, not
    # suivre) instead of being left without a form
    homograph_verbs_by_rank: bool = False
    # a gerund / present participle that is also another word ('étudiant', 'pendant', 'maintenant',
    # 'important') is the gerund only right after this word ('en étudiant')
    gerund_marker: str = ""
    # spellings of several items: the part of speech to link by default ('la', 'les': the article;
    # an object clitic before a verb is relinked by clitic_relink)
    lookup_pos: dict[str, str] = field(default_factory=dict)
    # prepositions after which an infinitive that is also a noun is the infinitive ('sans dire',
    # 'pour aller'), unlike after an article ('le dîner')
    infinitive_preps: set[str] = field(default_factory=set)
    # a word that is a noun and a verb form, after determiner + adjective, is the noun ('une bonne
    # élève', not 'élever')
    noun_after_adjective: bool = False
    # the forms of an item's own inflection tables are lookup keys too (French 'meilleures', which
    # Wiktionary does not list as a form of 'meilleur')
    table_forms_lookup: bool = False
    # a capitalized word inside a sentence is a name, not a word of the lexicon ('Marie', 'Pierre',
    # 'Claire' are no forms of marier, pierre, clair)
    capitalized_names: bool = False
    # parts of speech of multi-word items that link every word of the phrase (aligner, pass 4)
    phrase_pos: tuple[str, ...] = ("intj", "phrase", "adv")
    # words that are articles (or prepositions) and object clitics ('le', 'les', 'en'): right before a
    # verb they link to the item of that part of speech ('Je le vois': the pronoun 'le')
    clitic_relink: dict[str, str] = field(default_factory=dict)
    # the language never drops the subject: a clause-initial verb with an imperative reading and no
    # subject pronoun is the imperative, whatever its English translation ('Ne cherche pas les
    # problèmes.' = Don't go looking for trouble), unless the translation has a subject
    subject_required: bool = False
    # determiners that also stand as predicates before the copula ('Quel est ...?', 'Quelles sont
    # ...'): a copula form after them is the verb, not a noun homograph ('est': east)
    predicate_determiners: set[str] = field(default_factory=set)

    def auxiliary_of(self, form: str, tags) -> list[str] | None:
        """Perfect auxiliaries named by a conjugation-table row (French 'avoir + past participle'), or
        None when the row names none. Languages whose tables tag an 'auxiliary' row leave it None."""
        return None

    def form_moods(self, tags) -> set[str]:
        """The moods (seed.yaml exclude_moods keys) of a conjugation-table form with these tags."""
        return {m for m in ("subjunctive", "conditional", "imperative") if m in set(tags)}

    @property
    def tenses(self) -> list[str]:
        return self.simple_tenses + list(self.compound_tenses)

    def persons_of(self, tense: str) -> list[str]:
        """The persons a complete table of `tense` has."""
        return self.tense_persons.get(tense, self.persons)

    def pronominal(self, lemma: str) -> tuple[str, str] | None:
        """(base verb lemma, attached pronouns) of a pronominal verb ('alzarsi' -> ('alzare', 'si')),
        or None. Only languages with such verbs in their tables define it."""
        return None

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
        if self.multiword_forms and " " in form.strip() and link and " " not in link.strip():
            # 'mi àlzo' links only its first word ('mi'); the form text marks stress, also on
            # monosyllables that are written without an accent ('se ne và' = 'se ne va')
            s = " ".join(_unstress_monosyllable(w) for w in form.split())
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
    "passato_remoto": {
        "are": ["ai", "asti", "ò", "ammo", "aste", "arono"],
        "ere": ["ei", "esti", "é", "emmo", "este", "erono"],
        "ire": ["ii", "isti", "ì", "immo", "iste", "irono"],
        "isc": ["ii", "isti", "ì", "immo", "iste", "irono"],
    },
    "condizionale": {
        "are": ["erei", "eresti", "erebbe", "eremmo", "ereste", "erebbero"],
        "ere": ["erei", "eresti", "erebbe", "eremmo", "ereste", "erebbero"],
        "ire": ["irei", "iresti", "irebbe", "iremmo", "ireste", "irebbero"],
        "isc": ["irei", "iresti", "irebbe", "iremmo", "ireste", "irebbero"],
    },
    "congiuntivo_presente": {
        "are": ["i", "i", "i", "iamo", "iate", "ino"],
        "ere": ["a", "a", "a", "iamo", "iate", "ano"],
        "ire": ["a", "a", "a", "iamo", "iate", "ano"],
        "isc": ["isca", "isca", "isca", "iamo", "iate", "iscano"],
    },
    "congiuntivo_imperfetto": {
        "are": ["assi", "assi", "asse", "assimo", "aste", "assero"],
        "ere": ["essi", "essi", "esse", "essimo", "este", "essero"],
        "ire": ["issi", "issi", "isse", "issimo", "iste", "issero"],
        "isc": ["issi", "issi", "isse", "issimo", "iste", "issero"],
    },
    # tu, lui/lei (= formal Lei), noi, voi; no io and no loro (None)
    "imperativo": {
        "are": [None, "a", "i", "iamo", "ate", None],
        "ere": [None, "i", "a", "iamo", "ete", None],
        "ire": [None, "i", "a", "iamo", "ite", None],
        "isc": [None, "isci", "isca", "iamo", "ite", None],
    },
}
# Regular -ere passato remoto with -etti (credetti, credette, credettero) next to -ei (credei)
IT_REMOTO_ETTI = ["etti", "esti", "ette", "emmo", "este", "ettero"]
# Tags of Wiktionary's Italian conjugation tables that select the moods the course teaches
# (generic BAD_FORM_TAGS drops them for the other languages)
IT_MOOD_TAGS = {"historic", "conditional", "subjunctive", "imperative"}
IT_REFLEXIVE = {"io": "mi", "tu": "ti", "lui/lei": "si", "noi": "ci", "voi": "vi", "loro": "si"}
IT_REFLEXIVE_NE = {"io": "me", "tu": "te", "lui/lei": "se", "noi": "ce", "voi": "ve", "loro": "se"}
# attached (enclitic) pronouns, longest first: 'diglielo', 'fammelo', 'alzandosi', 'dimmi'
IT_ENCLITICS = tuple(sorted({
    "mi", "ti", "si", "ci", "vi", "lo", "la", "li", "le", "ne", "gli",
    *(a + b for a in ("me", "te", "se", "ce", "ve", "glie") for b in ("lo", "la", "li", "le", "ne")),
    "sene", "mene", "tene", "cene", "vene", "telo", "tela", "melo", "mela", "celo", "cela"}, key=lambda s: (-len(s), s)))
# subjunctive triggers: lemmas (verbs, adjectives, nouns) after which 'che' takes the subjunctive
IT_SUBJ_TRIGGERS = {
    "pensare", "credere", "volere", "sperare", "immaginare", "temere", "dubitare", "sembrare", "parere",
    "bisognare", "occorrere", "preferire", "desiderare", "aspettare", "supporre", "ritenere", "augurare",
    "permettere", "dispiacere", "piacere", "importare", "aspettarsi", "augurarsi", "immaginarsi",
    "importante", "necessario", "meglio", "possibile", "impossibile", "probabile", "improbabile", "strano",
    "giusto", "normale", "naturale", "facile", "difficile", "utile", "inutile", "peccato", "contento",
    "felice", "triste", "paura", "bene", "male", "assurdo", "incredibile", "ora", "tempo", "speriamo"}


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
            simple_tenses=["presente", "imperfetto", "futuro", "passato_remoto", "condizionale",
                           "congiuntivo_presente", "congiuntivo_imperfetto", "imperativo"],
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
                      "voi": ["voi"], "loro": ["loro"], "egli": ["lui/lei"], "ella": ["lui/lei"],
                      # 'Tutti sono qui', 'Sono tutti stanchi': loro, not io
                      "tutti": ["loro"], "tutte": ["loro"]},
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
            tense_persons={"imperativo": ["tu", "lui/lei", "noi", "voi"]},
            tense_moods={"condizionale": "conditional", "congiuntivo_presente": "subjunctive",
                         "congiuntivo_imperfetto": "subjunctive", "imperativo": "imperative"},
            subj_conjunctions={"affinché", "benché", "sebbene", "purché", "nonostante", "qualora", "malgrado",
                               "prima che", "senza che", "a meno che", "a patto che", "nel caso che",
                               "in modo che", "chiunque", "qualunque", "dovunque", "ovunque", "magari",
                               "come se"},
            subj_complementizer="che",
            subj_triggers=IT_SUBJ_TRIGGERS,
            subj_che_drop={"pensare", "credere", "sperare", "temere", "immaginare", "sembrare", "parere",
                           "supporre", "ritenere", "immaginarsi"},
            subj_if={"se": {"congiuntivo_imperfetto"}},
            multiword_forms=True,
            enclitics=IT_ENCLITICS,
            homograph_tenses={"passato_remoto"},
            interrogatives={"che", "quale", "quali", "quanto", "quanta", "quanti", "quante"},
            # "Cosa fai?": the question word is no subject; nor is a time noun ('Quella sera andammo')
            adverbial_nouns={"cosa", "sera", "mattina", "notte", "pomeriggio", "giorno", "settimana",
                             "mese", "anno", "volta", "estate", "inverno", "primavera", "autunno"},
            elative=("issimo", "issima", "issimi", "issime"),
        )

    def pronominal(self, lemma):
        """alzarsi -> (alzare, si); andarsene -> (andare, sene); sedersi -> (sedere, si); volerci ->
        (volere, ci); farcela -> (fare, cela)."""
        for att in ("sene", "cela", "sela", "si", "ci"):
            if lemma.endswith(att) and lemma[: -len(att)].endswith(("ar", "er", "ir")) and len(lemma) >= len(att) + 3:
                return lemma[: -len(att)] + "e", att
        return None

    def strip_pronouns(self, form: str) -> str:
        """The verb word of a pronominal form: 'mi alzo' -> 'alzo', 'me ne vado' -> 'vado',
        'ce la faccio' -> 'faccio'."""
        words = form.split()
        while len(words) > 1 and words[0] in {"mi", "ti", "si", "ci", "vi", "me", "te", "se", "ce", "ve", "ne",
                                              "la", "l'"}:
            words = words[1:]
        return " ".join(words)

    def slot(self, tags):
        """Italian tables: also the conditional, the subjunctive (present, imperfect), the imperative
        (tu, Lei, noi, voi; not the negative tu form, which is the infinitive) and the passato remoto."""
        t = set(tags)
        if "negative" in t:
            return None
        if "imperative" in t:
            t = t - {"formal", "second-person-semantically", "imperative"}
            if t & BAD_FORM_TAGS:
                return None
            persons = [p for p in self.persons_for(t) if p in self.tense_persons["imperativo"]]
            return ("imperativo", ",".join(persons)) if persons else None
        if t & (BAD_FORM_TAGS - IT_MOOD_TAGS):
            return None
        if t & {"infinitive", "participle", "gerund"}:
            return super().slot(tags)
        tense = None
        if "conditional" in t:
            tense = "condizionale"
        elif "subjunctive" in t:
            tense = "congiuntivo_presente" if "present" in t else "congiuntivo_imperfetto" if "imperfect" in t else None
        elif "historic" in t:
            tense = "passato_remoto" if {"indicative", "past"} <= t else None
        else:
            return super().slot(tags)
        persons = self.persons_for(t) if tense else []
        return (tense, ",".join(persons)) if persons else None

    def verb_stem(self, lemma, cls, complete, irr):
        base = (self.pronominal(lemma) or (lemma, ""))[0]
        return base[:-3] if cls in ("are", "ere", "ire", "isc") else None

    def verb_class(self, lemma, forms, table_tags):
        base = self.pronominal(lemma)
        if base:
            stripped = {t: {p: self.strip_pronouns(f) for p, f in tab.items()} for t, tab in forms.items()}
            return self.verb_class(base[0], stripped, table_tags)
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
        base = self.pronominal(lemma)
        if base:
            # alzarsi: the tenses of 'alzo, alzi, ...' after the pronoun ('mi alzo'); the imperative
            # carries attached pronouns ('alzati') and the participle 'alzatosi' -> 'alzato'
            stripped = {t: {p: self.strip_pronouns(f) for p, f in tab.items()}
                        for t, tab in forms.items() if t not in ("imperativo", "participle")}
            part = (forms.get("participle") or {}).get("_")
            if part:
                stripped["participle"] = {"_": self.base_participle(part)}
            return [t for t in self.irregular_in(base[0], cls, stripped) if t != "imperativo"]
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
        # the moods (pack 1.3): compared with the regular paradigm, spelling variants included
        for tense in ("passato_remoto", "condizionale", "congiuntivo_presente", "congiuntivo_imperfetto", "imperativo"):
            persons = self.persons_of(tense)
            actual = [forms.get(tense, {}).get(p) for p in persons]
            if all(actual) and not self._regular_mood(lemma, cls, tense, actual):
                irr.append(tense)
        return irr

    def _regular_mood(self, lemma: str, cls: str | None, tense: str, actual: list[str]) -> bool:
        if cls not in IT_ENDINGS.get(tense, {}):
            return False
        stem = lemma[:-3]
        idx = [self.persons.index(p) for p in self.persons_of(tense)]
        variants = [IT_ENDINGS[tense][cls]]
        if tense == "passato_remoto" and cls == "ere":
            variants.append(IT_REMOTO_ETTI)
        for ends in variants:
            want = [self._it_join(stem, ends[i], cls, tense) for i in idx]
            # -ere remoto: either ending per cell (credei / credetti)
            if all(a == w or (tense == "passato_remoto" and cls == "ere" and
                              a in (self._it_join(stem, IT_ENDINGS[tense]["ere"][i], cls, tense),
                                    self._it_join(stem, IT_REMOTO_ETTI[i], cls, tense)))
                   for a, w, i in zip(actual, want, idx)):
                return True
        return False

    @staticmethod
    def _it_join(stem: str, ending: str, cls: str | None, tense: str) -> str:
        """stem + ending with the regular spelling changes: cerc+i -> cerchi, mangi+iamo -> mangiamo,
        mangi+erei -> mangerei (-ciare/-giare/-sciare drop the i before e)."""
        if cls == "are" and stem.endswith(("c", "g")) and ending[:1] in ("e", "i"):
            return stem + "h" + ending
        if stem.endswith("i") and ending[:1] == "i":
            return stem + ending[1:]
        if cls == "are" and stem.endswith(("ci", "gi")) and ending[:1] == "e":
            return stem[:-1] + ending
        return stem + ending

    def base_participle(self, participle: str) -> str:
        """The participle of a pronominal verb without its attached pronouns: alzatosi -> alzato,
        andatosene -> andato, volutoci -> voluto."""
        for suf in ("sene", "cela", "sela", "si", "ci"):
            if participle.endswith(suf) and len(participle) > len(suf) + 3:
                return participle[: -len(suf)]
        return participle

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
        if self.pronominal(lemma):
            return None, None            # 'alzati', 'alziamoci': the ending is not word-final
        cands = []
        if cls in IT_ENDINGS[tense]:
            cands.append(IT_ENDINGS[tense][cls][i])
        if tense == "passato_remoto" and cls == "ere":
            cands.append(IT_REMOTO_ETTI[i])
        for c in ("are", "ere", "ire", "isc"):
            e = IT_ENDINGS[tense][c][i]
            if e not in cands:
                cands.append(e)
        cands = [e for e in cands if e]
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
        if aux != "essere" or participle[-1:] not in "oaie" or self.base_participle(participle) != participle:
            return [participle]
        b = participle[:-1]
        return [b + "o", b + "a", b + "i", b + "e"]

    def pronominal_compound(self, aux_forms: dict[str, str], participle: str, person: str, attached: str,
                            aux: str = "essere") -> tuple[str, list[str]]:
        """Passato prossimo of a pronominal verb: mi sono alzato (/alzata), ci siamo alzati (/alzate),
        me ne sono andato. `participle` is the bare one (alzato)."""
        if attached == "ci":       # volerci, metterci: 'ci è voluto', 'ci ho messo'
            form, alts = self.compound(aux_forms, participle, person, aux)
            return f"ci {form}", [f"ci {a}" for a in alts]
        form, alts = self.compound(aux_forms, participle, person, "essere")
        refl = (IT_REFLEXIVE_NE[person] + " ne") if attached == "sene" else IT_REFLEXIVE[person]
        return f"{refl} {form}", [f"{refl} {a}" for a in alts]


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
from .lang_fr import French  # noqa: E402

LANGS: dict[str, Lang] = {"it": Italian(), "nl": Dutch(), "es": Spanish(), "fr": French()}


def get_lang(code: str) -> Lang:
    return LANGS[code]
