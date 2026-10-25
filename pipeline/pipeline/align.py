"""Token alignment: link sentence tokens to lexicon items and verb forms.

Lookup is by lowercase surface form:
  * verb forms come from the pack's conjugation tables (simple tenses, infinitive, gerund) and
    participles;
  * other items match on their lemma or variants first, then on inflections (plural, feminine,
    ...); among several items the most frequent wins. Italian elided forms (l', dell', c', un')
    are looked up as their full forms (la/lo, della, ci, una).

Rules (also in pipeline/README.md):
  1. Noun vs verb: when a surface is both a verb form and another item, the verb reading wins
     unless the previous word is a determiner/preposition ("la porta" = noun, "lui porta" = verb),
     or (Dutch) the only verb reading is an ik-form with no 'ik' next to it ("waar", "baan").
  2. Compound tenses (passato prossimo, perfectum): a participle whose verb takes auxiliary A is
     linked to the compound tense when a present form of A occurs in the same clause (Italian: up to
     4 words before it; Dutch: anywhere in the clause, nearest preceding first; an auxiliary right
     after 'te' does not count). The participle token gets lex = the verb and
     form = '{compound}.{person}'; the auxiliary token gets lex = the auxiliary and
     form = '{present}.{person}'. The token text is then only the participle part of the
     multi-word form in verb_forms ('mangiato' for 'ho mangiato'). Italian participle agreement:
     -o/-a/-i/-e endings are accepted with essere, and with avere after an object clitic
     ('li ho visti'). A participle without a matching auxiliary is linked as 'participle._'
     (Dutch also prefers that reading over a homographic present form once a finite verb has
     occurred in the clause: 'wordt ... gebruikt').
  3. Ambiguous person/tense (e.g. 'sono' = io/loro, 'lopen' = wij/jullie/zij/infinitive):
       a. a subject pronoun just before (skipping 'non', clitics, short adverbs) or just after
          the token decides; if it fits no candidate (e.g. Italian subjunctive 'che lei ascolti'),
          the token keeps its lex but gets no form;
       b. Dutch infinitive: chosen after 'te' or when a finite verb already occurred in the clause;
       c. a name or noun right before the verb implies 3rd person; when there is no 3rd-person
          candidate ('Tom mangi', subjunctive) the token gets no form;
       d. Italian io/loro ('sono'): a following adjective/noun/participle ending in -i/-e means
          loro, otherwise io;
       e. otherwise 3rd person singular, then 3rd plural, then the first in person order.
  4. Dutch inversion: 'loop jij' uses the ik-form for jij; such a token keeps its lex but gets no
     form. Dutch imperatives ('Vertel eens') likewise get no form, and so do Italian imperatives,
     which look like present forms ('Chiedi a un poliziotto!', 'Andiamo!'): a clause-initial verb
     (after 'non' or clitics at most) without a subject pronoun, not of a verb with a distinct
     imperative (essere, avere), in a sentence with '!' or whose English translation starts with
     an imperative ('Ask ...', 'Please ask ...', "Don't ...", "Let's ..."). A Dutch adjective/verb
     homograph before a copula is the adjective ('dat ik laat ben').
  5. Compound-tense exceptions (the words keep their lex, the compound form is not linked):
       a. a subject pronoun next to the auxiliary that fits none of its persons: inversion
          ('Heb je gegeten?' uses the ik-form), a coordinated subject ('io e lui abbiamo');
       b. Dutch polite 'u' (also in simple tenses): 'u bent' / 'u is' are both right, so no person;
       c. Dutch modal + perfect infinitive ('zou ... geweest zijn'): 'zijn'/'hebben' after a finite
          modal in the clause is an infinitive, the participle stays 'participle._';
       d. Dutch verbs that list 'zijn' only as their second auxiliary (nl.wiktionary does so for
          transitive verbs because of the passive): 'is gezien' is passive, not perfectum;
       e. Dutch possessive 'zijn' before a noun ('zijn belofte') is never an auxiliary;
       f. Italian: a word after a form of 'essere' that is both a participle and a finite form is
          the participle ('sono state costruite', not 'voi costruite').
  Unmatched tokens stay unlinked.
"""
from __future__ import annotations

import re
from collections import defaultdict

from .inflect import InflectionAligner
from .lang import IT_BETWEEN_AUX_PART, Lang  # noqa: F401  (IT_BETWEEN_AUX_PART: re-exported)
from .tokens import tokenize

ELISION_IT = {
    "l'": ["la", "lo", "il"], "c'": ["ci"], "m'": ["mi"], "t'": ["ti"], "s'": ["si"], "v'": ["vi"],
    "n'": ["ne"], "d'": ["di"], "po'": ["poco"], "un'": ["una", "uno", "un"], "quest'": ["questa", "questo"],
    "quell'": ["quella", "quello"], "dell'": ["della", "dello", "del"], "all'": ["alla", "allo", "al"],
    "dall'": ["dalla", "dallo", "dal"], "nell'": ["nella", "nello", "nel"], "sull'": ["sulla", "sullo", "sul"],
    "com'": ["come"], "dov'": ["dove"], "anch'": ["anche"], "tutt'": ["tutto", "tutta"], "sant'": ["santo"],
    "buon'": ["buona", "buono"], "nessun'": ["nessuna", "nessuno"], "qual'": ["quale"], "cos'": ["cosa"],
    "ch'": ["che"], "mezz'": ["mezzo"], "senz'": ["senza"], "grand'": ["grande"], "bell'": ["bella", "bello"],
}
CLITIC_NL = {"'t": ["het"], "'k": ["ik"], "'n": ["een"], "m'n": ["mijn"], "z'n": ["zijn"], "d'r": ["haar"],
             "'m": ["hem"], "'r": ["haar"]}
OBJECT_CLITICS_IT = {"lo", "la", "li", "le", "l'", "ne"}
VAGUE = "?"   # pseudo-person of a vague subject pronoun (Dutch 'u'): fits no person
QUOTES = {'"', "«", "»", "“", "”"}
# punctuation after which a capitalized word starts a sentence (lang.capitalized_names)
SENTENCE_STARTS = {".", "!", "?", "«", "»", ":", '"', "“", "”", "—", "–", "…", "...", "(", "-"}
CLAUSE_PUNCT = {",", ".", "?", "!", ";", ":", "...", "…", "—", "–", "(", ")", '"', "«", "»", "“", "”", "¿", "¡"}


def norm(s: str) -> str:
    return s.replace("’", "'").lower()


def _form(val) -> str:
    return val["form"] if isinstance(val, dict) else val


def by_lemma_verb_id(aligner: "Aligner", lemma: str) -> str | None:
    """The id of the most frequent verb item with this lemma."""
    ids = [i for i in aligner.verb_ids if aligner.items.get(i, {}).get("lemma") == lemma]
    return aligner._best(ids) if ids else None


class Aligner:
    def __init__(self, lang: Lang, items: list[dict], verbs: dict[str, dict], infl_tables: dict | None = None):
        self.lang = lang
        self._before_weak = False
        # inflected non-verb forms ('gatti' -> infl:number.pl), see inflect.py
        self.infl = InflectionAligner(lang.code, {it["id"]: it for it in items}, infl_tables) if infl_tables else None
        # split separable verbs ('Ik sta morgen vroeg op'): (finite word, clause-final particle) ->
        # [(separable verb, tense, person)] from the two-word simple-tense forms ('sta op')
        self.separable: dict[tuple[str, str], list[tuple[str, str, str]]] = defaultdict(list)
        self.items = {it["id"]: it for it in items}
        self.rank = {it["id"]: (it.get("freq") is None, it.get("freq") or 0, it["id"]) for it in items}
        self.verb_index: dict[str, list[tuple[str, str, str]]] = defaultdict(list)
        # surface -> [(verb id, auxiliary, needs_object_clitic)]
        self.part_index: dict[str, list[tuple[str, str, bool]]] = defaultdict(list)
        self.lemma_index: dict[str, list[str]] = defaultdict(list)
        self.infl_index: dict[str, list[str]] = defaultdict(list)
        self.aux_present: dict[str, dict[str, list[str]]] = {}  # aux lemma -> surface -> persons
        self.aux_ids: dict[str, str] = {}
        self.verb_ids: set[str] = set(verbs)
        self.verb_forms: dict[str, dict] = {vid: (v.get("forms") or {}) for vid, v in verbs.items()}
        # first words of a verb's English glosses ('to ask for' -> 'ask'), for imperative translations
        self.en_heads: dict[str, set[str]] = {}
        for it in items:
            if it["pos"] == "verb":
                heads = set()
                for g in (it.get("tr") or {}).get("en") or []:
                    w = g.lower().split()
                    if w and w[0] == "to":
                        w = w[1:]
                    if w:
                        heads.add(w[0].strip("(),;"))
                self.en_heads[it["id"]] = heads
        by_lemma_verb: dict[str, str] = {}
        for it in sorted(items, key=lambda i: self.rank[i["id"]]):
            if it["pos"] == "verb":
                by_lemma_verb.setdefault(it["lemma"], it["id"])
        # multi-word verb forms (lang.multiword_forms: Italian pronominal verbs 'mi alzo', 'mi sono
        # alzato', 'me ne vado'): word tuple -> [(verb id, tense, person)], every word aligned
        self.multi: dict[tuple[str, ...], list[tuple[str, str, str]]] = defaultdict(list)
        # hosts of attached pronouns (lang.enclitics): 'parlar' (parlare), 'parlando', 'parla'
        # (imperativo.tu), 'di' (di', doubling: dimmi) -> [(verb id, form key, doubles)]
        self.enclitic_hosts: dict[str, list[tuple[str, str, bool]]] = defaultdict(list)
        for vid in sorted(verbs):
            v = verbs[vid]
            forms = v.get("forms") or {}
            if lang.multiword_forms:
                pronominal = lang.pronominal(self.items.get(vid, {}).get("lemma", "")) is not None
                for tense, table in forms.items():
                    if tense in lang.compound_tenses and not pronominal:
                        continue             # 'ho mangiato': auxiliary + participle (pass 1)
                    for person, val in table.items():
                        alts = val.get("alts", []) if isinstance(val, dict) else []
                        for f in [_form(val), *alts]:
                            w = tuple(norm(f).split())
                            if len(w) > 1 and (vid, tense, person) not in self.multi[w]:
                                self.multi[w].append((vid, tense, person))
            if lang.enclitics:
                self._add_hosts(vid, forms)
            auxes = [a for a in (v.get("auxiliary") or "").split("|") if a]
            if lang.passive_aux and len(auxes) > 1 and auxes[0] != lang.passive_aux:
                # nl.wiktionary lists 'zijn' second for most transitive verbs because of the
                # passive ('het is gedaan'); zijn + participle of such a verb is not linked to
                # the perfectum ('Hij is door iedereen gezien' is passive)
                auxes = [a for a in auxes if a != lang.passive_aux]
            for tense, table in forms.items():
                if tense in lang.compound_tenses:
                    continue
                for person, val in table.items():
                    alts = val.get("alts", []) if isinstance(val, dict) else []
                    for f in [_form(val), *alts]:
                        if " " in f:
                            w = norm(f).split()
                            if lang.clause_starters and len(w) == 2 and tense in lang.simple_tenses and person != "_":
                                self.separable[(w[0], w[1])].append((vid, tense, person))
                            continue
                        if tense == "participle":
                            for aux in auxes:
                                for pv in lang.participle_variants(f, "essere" if lang.code == "it" else aux):
                                    needs_clitic = (lang.code == "it" and aux != "essere" and pv != f) or \
                                        (bool(lang.agreeing_aux) and aux not in lang.agreeing_aux and pv != f)
                                    entry = (vid, aux, needs_clitic)
                                    if entry not in self.part_index[norm(pv)]:
                                        self.part_index[norm(pv)].append(entry)
                            if lang.reflexive_aux and auxes and lang.reflexive_aux not in auxes:
                                # 'je me suis levé': a reflexive pronoun before the auxiliary
                                for pv in lang.participle_variants(f, lang.reflexive_aux):
                                    entry = (vid, lang.reflexive_aux, "refl")
                                    if entry not in self.part_index[norm(pv)]:
                                        self.part_index[norm(pv)].append(entry)
                            continue
                        entry = (vid, tense, person)
                        if entry not in self.verb_index[norm(f)]:
                            self.verb_index[norm(f)].append(entry)
        # every agreeing participle spelling -> its most frequent verb ('sorpresi' -> sorprendere),
        # for homographs of rare-tense forms (lang.homograph_tenses)
        self.part_any: dict[str, str] = {}
        if lang.homograph_tenses:
            for vid in sorted(verbs, key=lambda v: self.rank.get(v, (True, 0, v)), reverse=True):
                part = ((verbs[vid].get("forms") or {}).get("participle") or {}).get("_")
                if part:
                    for pv in lang.participle_variants(_form(part), "essere"):
                        self.part_any[norm(pv)] = vid
        # aux lemma -> tense of the auxiliary -> surface -> persons (French: the plus-que-parfait uses
        # the imparfait of the auxiliary, the futur antérieur its futur, ...)
        self.aux_forms: dict[str, dict[str, dict[str, list[str]]]] = {}
        for aux in lang.auxiliaries:
            vid = by_lemma_verb.get(aux)
            if not vid or vid not in verbs:
                continue
            self.aux_ids[aux] = vid
            for atense in dict.fromkeys([lang.present, *lang.compound_tenses.values()]):
                table = verbs[vid]["forms"].get(atense, {})
                d: dict[str, list[str]] = defaultdict(list)
                for person in lang.persons:
                    if table.get(person) is not None:
                        d[norm(_form(table[person]))].append(person)
                self.aux_forms.setdefault(aux, {})[atense] = dict(d)
            self.aux_present[aux] = self.aux_forms[aux][lang.present]
        if lang.rare_tense_homographs:
            # 'finis' (present / passé simple), 'vit' (vivre present / voir passé simple), 'mis'
            # (participle / passé simple): the rare tense only where its spelling is unique
            for s, entries in self.verb_index.items():
                common = [e for e in entries if e[1] not in lang.rare_tense_homographs]
                if (common or s in self.part_index) and len(common) < len(entries):
                    self.verb_index[s] = common
            for s in [s for s, e in self.verb_index.items() if not e]:
                del self.verb_index[s]
        # Italian: every form of 'essere' (present + participle variants), after which a word that
        # is both a participle and a finite form is a participle ('sono state costruite')
        self.essere_forms: set[str] = set()
        if lang.code == "it" and "essere" in self.aux_ids:
            ev = verbs[self.aux_ids["essere"]]["forms"]
            self.essere_forms = set(self.aux_present.get("essere", {}))
            part = ev.get("participle", {}).get("_")
            if part:
                self.essere_forms |= {norm(x) for x in lang.participle_variants(_form(part), "essere")}
        # multi-word phrases ('per favore', 'tot ziens', 'dank je'): word sequence -> item id
        self.phrases: dict[tuple[str, ...], str] = {}
        # interjections that share their spelling with another word ('Prego', 'Dag', 'Bedankt')
        self.intj: dict[str, str] = {}
        for it in items:
            if it["pos"] == "verb":   # verbs: only their inflections (Spanish enclitic forms: hacerlo)
                for s in it.get("inflections") or []:
                    self.infl_index[norm(s)].append(it["id"])
                continue
            for s in [it["lemma"], *(it.get("variants") or [])]:
                # French: an elided word starts a token of its own, so 'd'accord' is two words
                ws = norm(s).split()
                if lang.elisions:
                    # a final elided word ('dès qu'', 'à côté d'') only splits off before a letter
                    tail = s.endswith(("'", "’"))
                    ws = [norm(t["t"]) for t in tokenize(s + ("a" if tail else ""), lang.code) if t["is_word"]]
                    ws = ws[:-1] if tail else ws
                if len(ws) == 1 and (" " not in s or lang.elisions):
                    self.lemma_index[norm(s)].append(it["id"])
                    if it["pos"] in ("intj", "phrase") or "greetings" in (it.get("tags") or []):
                        cur = self.intj.get(norm(s))
                        if cur is None or self.rank[it["id"]] < self.rank[cur]:
                            self.intj[norm(s)] = it["id"]
                elif len(ws) > 1 and it["pos"] in lang.phrase_pos:
                    self.phrases[tuple(ws)] = it["id"]
            for s in it.get("inflections") or []:
                self.infl_index[norm(s)].append(it["id"])
        # forms in an item's own inflection tables: a form that several items list as an inflection
        # belongs to the item whose table has it (Wiktionary lists 'esa', 'esta', 'aquella' under
        # each Spanish demonstrative; 'esa' is a cell of 'ese' only). Only between items of one part
        # of speech: Italian 'dei' stays 'del' (of the), not the plural of 'dio'.
        self.table_forms: dict[str, set[str]] = defaultdict(set)
        for it in items:
            for table in (it.get("infl") or {}).values():
                for cell in table.values():
                    for f in [cell.get("form"), *(cell.get("alts") or [])]:
                        if f:
                            self.table_forms[norm(f)].add(it["id"])
        if lang.table_forms_lookup:
            for f, ids in self.table_forms.items():
                for iid in sorted(ids):
                    if iid not in self.infl_index[f] and iid not in self.lemma_index.get(f, ()):
                        self.infl_index[f].append(iid)

    def _add_hosts(self, vid: str, forms: dict) -> None:
        """Hosts of attached pronouns for one verb: the infinitive without its final -e ('parlar',
        'por' for porre, 'alzar' for alzarsi), the gerund ('parlando', 'alzando'), and the tu/noi/voi
        imperative ('parla', 'parliamo', 'parlate'; truncated 'di'', 'fa'' double the consonant:
        'dimmi', 'fallo')."""
        def one(table: str) -> list[str]:
            val = (forms.get(table) or {}).get("_")
            return [norm(_form(val))] if val else []
        pron = self.lang.pronominal(self.items.get(vid, {}).get("lemma", ""))
        for inf in one("infinitive"):
            if pron:
                inf = inf[: -len(pron[1])] + "e" if inf.endswith(pron[1]) else inf
            host = inf[:-2] if inf.endswith("rre") else inf[:-1]
            self.enclitic_hosts[host].append((vid, "infinitive._", False))
        for ger in one("gerund"):
            if pron and ger.endswith(pron[1]):
                ger = ger[: -len(pron[1])]
            self.enclitic_hosts[ger].append((vid, "gerund._", False))
        imp = forms.get("imperativo") or {}
        for person in ("tu", "noi", "voi"):
            val = imp.get(person)
            if not val:
                continue
            alts = val.get("alts", []) if isinstance(val, dict) else []
            for f in [_form(val), *alts]:
                f = norm(f)
                if " " in f or pron:
                    continue
                if f.endswith("'"):
                    self.enclitic_hosts[f[:-1]].append((vid, f"imperativo.{person}", True))
                else:
                    self.enclitic_hosts[f].append((vid, f"imperativo.{person}", False))

    # ------------------------------------------------------------------ lookups
    def _best(self, ids: list[str]) -> str:
        return min(ids, key=lambda i: self.rank.get(i, (True, 0, i)))

    def lex_lookup(self, s: str, lemma_only: bool = False) -> str | None:
        keys = [s]
        if self.lang.code == "it" and s.endswith("'"):
            keys = ELISION_IT.get(s, []) + [s] + [s[:-1] + v for v in "aoei"]
        elif self.lang.code == "nl" and s in CLITIC_NL:
            keys = CLITIC_NL[s] + [s]
        elif s in self.lang.elisions:
            keys = self.lang.elisions[s] + [s]
        pref = self.lang.lookup_pos.get(s)
        if pref and not lemma_only:
            # 'la', 'les' are articles by default (French; clitics are relinked before verbs)
            hit = [i for k in keys for i in self.lemma_index.get(k, []) + self.infl_index.get(k, [])
                   if self.items[i]["pos"] == pref]
            if hit:
                return self._best(hit)
        for k in keys:
            if self.lemma_index.get(k):
                return self._best(self.lemma_index[k])
        if lemma_only:
            return None
        for k in keys:
            if self.infl_index.get(k):
                ids = self.infl_index[k]
                own = []
                if len(ids) > 1 and len({self.items[i]["pos"] for i in ids}) == 1:
                    own = [i for i in ids if i in self.table_forms.get(k, ())]
                return self._best(own or ids)
        return None

    @staticmethod
    def _is_clause_break(tok: dict) -> bool:
        return not tok["is_word"] and tok["t"] in CLAUSE_PUNCT

    def _punct_between(self, toks: list[dict], a: int, b: int) -> bool:
        lo, hi = min(a, b), max(a, b)
        return any(self._is_clause_break(toks[x]) for x in range(lo + 1, hi))

    def _clause_range(self, toks: list[dict], i: int) -> tuple[int, int]:
        lo = i
        while lo > 0 and not self._is_clause_break(toks[lo - 1]):
            lo -= 1
        hi = i
        while hi + 1 < len(toks) and not self._is_clause_break(toks[hi + 1]):
            hi += 1
        return lo, hi

    def _pronoun_persons(self, words: list[int], toks: list[dict], wi: int) -> tuple[list[str], list[str]]:
        """(persons from a pronoun before, persons from a pronoun right after) word #wi."""
        lang = self.lang
        before: list[str] = []
        self._before_weak = False
        k = wi - 1
        while k >= 0 and wi - k <= (6 if lang.clitic_pronouns else 4):
            ti = words[k]
            if self._punct_between(toks, ti, words[k + 1]):
                break
            w = norm(toks[ti]["t"])
            if w in lang.vague_pronouns:
                before = [VAGUE]
                break
            if w in lang.pronouns:
                before = list(lang.pronouns[w])
                if w in lang.clitic_pronouns:
                    # 'Il nous parle', 'Je vous aime': nous/vous may be objects; the leftmost
                    # pronoun of the clitic cluster is the subject ('Nous nous levons')
                    self._before_weak = True
                    k -= 1
                    continue
                self._before_weak = False
                break
            if w not in lang.skip_between:
                break
            k -= 1
        after: list[str] = []
        if wi + 1 < len(words) and not self._punct_between(toks, words[wi], words[wi + 1]):
            w = norm(toks[words[wi + 1]]["t"])
            if w in lang.vague_pronouns:
                after = [VAGUE]
            elif w in lang.pronouns:
                after = list(lang.pronouns[w])
        return before, after

    def _order(self, cands):
        lang = self.lang
        tenses = lang.tenses + ["infinitive", "gerund", "participle"]
        persons = lang.persons + ["_"]
        hint = getattr(self, "_tense_hint", None)
        return sorted(cands, key=lambda c: (c[0] != hint, tenses.index(c[0]) if c[0] in tenses else 99,
                                            persons.index(c[1]) if c[1] in persons else 99))

    def _subject_before(self, words, toks, wi) -> bool:
        """A name or noun directly before the verb (likely its subject)."""
        if wi == 0:
            return False
        tok = toks[words[wi - 1]]
        if self._punct_between(toks, words[wi - 1], words[wi]):
            return False
        t = tok["t"]
        if t[:1].isupper() and wi - 1 > 0 and not tok.get("lex"):
            return True
        lex = tok.get("lex")
        if norm(t) in self.lang.adverbial_nouns:
            return False                     # "Mañana hablaremos": a time noun is no subject
        if wi >= 2 and norm(toks[words[wi - 2]]["t"]) in self.lang.interrogatives:
            return False                     # '¿A qué hora llegáis?': the noun is no subject
        if self.lang.tense_moods and lex and self.items.get(lex, {}).get("pos") == "noun":
            # 'Al tuo posto direi ...': a noun after a preposition (and its determiners) is no subject
            k = wi - 2
            while k >= 0 and not self._punct_between(toks, words[k], words[k + 1]):
                plex = toks[words[k]].get("lex") or self.lex_lookup(norm(toks[words[k]]["t"]))
                ppos = self.items.get(plex or "", {}).get("pos")
                if ppos == "prep":
                    return False
                if ppos not in ("det", "pron", "adj"):
                    break
                k -= 1
        return bool(lex and self.items.get(lex, {}).get("pos") == "noun")

    def _choose(self, cands, words, toks, wi, finite_before: bool):
        """Pick (tense, person) among candidates of one verb; None = leave the form unset."""
        lang = self.lang
        prev = norm(toks[words[wi - 1]]["t"]) if wi > 0 else ""
        inf = [c for c in cands if c[0] == "infinitive"]
        finite = [c for c in cands if c[1] != "_"]
        nonfinite = [c for c in cands if c[1] == "_"]
        before, after = self._pronoun_persons(words, toks, wi)
        if self._before_weak and not any(c[1] in before for c in finite):
            before = []                      # 'Tom nous parle': nous is the object
        if lang.clause_starters and inf and (prev == "te" or finite_before):
            # one finite verb per (sub)clause: after it, an infinitive ('Ik zal jullie vertellen',
            # 'Wat kan ik voor jullie doen?'), even with an (object) pronoun next to it
            return inf[0]
        vague = False
        if finite:
            hit = [c for c in finite if c[1] in before]
            if not hit and VAGUE not in before:
                hit = [c for c in finite if c[1] in after]
            if hit and lang.clause_starters:
                # 'zoals hij je vertelt': the pronoun next to the verb may be an object; when another
                # pronoun in the clause fits another candidate person, the person stays open
                strong, weak = self._clause_pronouns(words, toks, wi)
                if len({c[1] for c in finite if c[1] in strong | weak}) > 1:
                    return None
                # an object-or-subject pronoun right after a relative ('wat je gebeurt' / 'wat je
                # doet') decides nothing when another person has the same form
                p_prev = norm(toks[words[wi - 1]]["t"]) if wi > 0 else ""
                p_prev2 = norm(toks[words[wi - 2]]["t"]) if wi > 1 else ""
                if p_prev in lang.object_pronouns and p_prev2 in lang.relatives and len(finite) > len(hit):
                    return None
            if hit:
                return self._order(hit)[0]
            vague = VAGUE in before or VAGUE in after
        if inf and (prev == "te" or finite_before or not finite):
            return inf[0]
        if vague:
            return None                      # 'u bent' / 'u is': the person is not determined
        if not finite:
            return self._order(nonfinite)[0] if nonfinite else None
        cands = finite
        if before and not inf:
            return None                      # pronoun that fits no form (subjunctive, imperative ...)
        ps = {c[1] for c in cands}
        if lang.code == "nl" and ps == {"ik"} and "ik" not in after:
            last = wi + 1 >= len(words) or self._punct_between(toks, words[wi], words[wi + 1])
            if not (last and "ik" in self._clause_pronouns(words, toks, wi)[0]):
                return None                  # inverted jij form or imperative ('dat ik laat ben': ik)
        if lang.clause_starters and not after and self._clause_initial(words, toks, wi):
            # a clause-initial verb without a subject pronoun after it: an imperative ('Laat me ...',
            # the ik-form is the imperative), or a question with another subject ('Komt Tom?')
            return None
        if lang.clause_starters and len(ps) > 1:
            # 'hoe je kaas maakt', 'dat ik weg moet': several persons share the form and the subject
            # of a verb-final clause is further back. The subject pronouns earlier in the clause
            # decide when exactly one candidate person fits them; when they fit several (one may
            # be an object: 'dat hij je ziet') or a pronoun fits none, the person stays open.
            # 'je', 'ze', 'het' may be objects ('dat dat je niet gebeurt'): they never decide, but a
            # candidate person they fit keeps the person open.
            strong, weak = self._clause_pronouns(words, toks, wi)
            if VAGUE in strong:
                return None                  # 'dat u een fijne avond heeft': heeft / hebt
            fit = {c[1] for c in cands if c[1] in strong}
            fit_weak = {c[1] for c in cands if c[1] in weak}
            if len(fit) == 1 and fit_weak <= fit:
                return next(c for c in cands if c[1] in fit)
            if fit or fit_weak:
                return None
        third = [c for c in cands if c[1] in (lang.third_sg, lang.third_pl)]
        if self._subject_before(words, toks, wi) and not before:
            if not third:
                return None
            cands = third
        if len(cands) == 1:
            return cands[0]
        if lang.code == "it" and {"io", "loro"} <= {c[1] for c in cands}:
            nxt = norm(toks[words[wi + 1]]["t"]) if wi + 1 < len(words) else ""
            nlex = self.lex_lookup(nxt) if nxt else None
            agrees = (nlex and self.items[nlex]["pos"] in ("adj", "noun")) or nxt in self.part_index
            want = "loro" if agrees and nxt[-1:] in ("i", "e") else "io"
            hit = [c for c in cands if c[1] == want]
            if hit:
                return self._order(hit)[0]
        if lang.translation_subjects and not finite_before and self._tr_person:
            # 'No sabía' = 'I didn't know': the English subject decides between persons that share
            # the form (yo/él hablaba), for the first finite verb of the sentence only
            hit = [c for c in cands if c[1] == self._tr_person]
            if hit:
                return self._order(hit)[0]
        if lang.tense_moods and len({c[1] for c in cands}) > 1 \
                and all(self._mood(c[0]) == "subjunctive" for c in cands):
            # 'Pensavo stessi andando' (io or tu), 'Penso che parli' (io, tu or lui/lei): the
            # subjunctive singular needs its subject; without one the person stays open
            return None
        for p in (lang.third_sg, lang.third_pl):
            hit = [c for c in cands if c[1] == p]
            if hit:
                return self._order(hit)[0]
        return self._order(cands)[0]

    def _agreement_object(self, toks: list[dict], words: list[int], awi: int) -> bool:
        """An object clitic (or a relative 'que') right before the auxiliary at word #awi, which an
        agreeing participle of a non-agreeing auxiliary needs ('li ho visti', 'je les ai vues', 'la
        lettre que j'ai écrite')."""
        lang = self.lang
        clitics = lang.object_clitics or OBJECT_CLITICS_IT
        for k in range(awi - 1, max(-1, awi - 1 - lang.agreement_lookback), -1):
            if self._punct_between(toks, words[k], words[k + 1]):
                break
            if norm(toks[words[k]]["t"]) in clitics:
                return True
        return False

    def _hyphen_split(self, s: str) -> tuple[str, str] | None:
        """(host, subject pronoun) of an inverted verb word ('as-tu' -> as, tu; 'a-t-il' -> a, il;
        'est-ce' -> est, ce), or None."""
        subj = self.lang.hyphen_subjects
        if not subj or "-" not in s:
            return None
        parts = s.split("-")
        rest = [p for p in parts[1:] if p != "t"]
        if len(rest) == 1 and rest[0] in subj and parts[0]:
            return parts[0], rest[0]
        return None

    def _align_hyphen(self, out: list[dict], words: list[int], translation: str | None) -> None:
        """French hyphenated verb words: inversion ('Parlez-vous', 'a-t-il', 'est-ce') links the host
        verb with the indicative (or conditional, subjunctive) cell of the suffix's person;
        imperatives with pronouns ('donne-moi', 'lève-toi', 'allez-y', 'dis-le-moi') link it with the
        imperative cell. The token text is no form of the cell, so the app glosses it and tags its
        grammar but never asks it. 'celui-là', 'ce jour-là' link the host word."""
        lang = self.lang
        question = any(not t["is_word"] and t["t"] == "?" for t in out)
        for ti in words:
            t = out[ti]
            if t["lex"]:
                continue
            w = norm(t["t"])
            if "-" not in w:
                continue
            parts = w.split("-")
            host, rest = parts[0], [p for p in parts[1:] if p != "t"]
            if not host or not rest:
                continue
            cands = self.verb_index.get(host, [])
            if not cands:
                if all(p in ("ci", "là") for p in rest):
                    lex = self.lex_lookup(host)
                    if lex:
                        t["lex"] = lex
                continue
            subject = len(rest) == 1 and rest[0] in lang.hyphen_subjects
            objects = all(p in lang.hyphen_objects for p in rest)
            if subject and objects:          # 'parlez-vous' (question) / 'levez-vous' (imperative)
                subject = question or not any(self._mood(c[1]) == "imperative" for c in cands)
            if subject:
                persons = set(lang.hyphen_subjects[rest[0]])
                cc = [c for c in cands if c[2] in persons and self._mood(c[1]) != "imperative"]
                if any(self._mood(c[1]) == "indicative" for c in cc):
                    cc = [c for c in cc if self._mood(c[1]) == "indicative"]
            elif objects:
                cc = [c for c in cands if self._mood(c[1]) == "imperative"]
            else:
                continue
            if not cc:
                continue
            vid = min({c[0] for c in cc}, key=lambda v: self.rank.get(v, (True, 0, v)))
            tense, person = self._order([(c[1], c[2]) for c in cc if c[0] == vid])[0]
            t["lex"], t["form"] = vid, f"{tense}.{person}"

    def _in_translation(self, vid: str, translation: str | None, entries) -> bool:
        """French: whether the English translation shows verb `vid` (a gloss head word starting a
        translation word: 'Il a plu' = It rained -> pleuvoir, not plaire), used only when the
        participle belongs to several verbs."""
        if not self.lang.homograph_verbs_by_rank or not translation or len({e[0] for e in entries}) < 2:
            return False
        words = re.findall(r"[a-z]+", translation.lower())
        return any(w.startswith(h) for h in self.en_heads.get(vid, ()) if len(h) >= 3 for w in words)

    def _after_copula(self, out: list[dict], words: list[int], wi: int) -> bool:
        """A form of a copula verb (lang.copula_lemmas, any form: 'est', 'être', 'été') right before
        word #wi, maybe over adverbs ('a été très bien reçu')."""
        k = wi - 1
        while k > 0 and norm(out[words[k]]["t"]) in self.lang.aux_between \
                and not self._punct_between(out, words[k - 1], words[k]):
            k -= 1
        if self._punct_between(out, words[k], words[wi]):
            return False
        lex = out[words[k]].get("lex")
        return self.items.get(lex or "", {}).get("lemma") in self.lang.copula_lemmas

    def _dominant_verb(self, vid: str, by_verb: dict) -> bool:
        """Whether verb `vid` is at least ten times as frequent as every other verb sharing the
        spelling (French 'suis': être, not suivre), so the reading is no guess."""
        f = self.items.get(vid, {}).get("freq")
        if not f:
            return False
        others = [self.items.get(v, {}).get("freq") for v in by_verb if v != vid]
        return all(o and o >= 10 * f for o in others)

    def _relink_clitics(self, out: list[dict], words: list[int]) -> None:
        """A word that is both an article (or preposition) and an object clitic right before a verb
        word (not a gerund: 'en parlant') is the clitic: 'Je le vois', 'Il faut les manger', 'Je l'ai
        vu', 'J'en ai'."""
        lang = self.lang
        if not hasattr(self, "_clitic_items"):
            self._clitic_items = {}
            for it in sorted(self.items.values(), key=lambda i: self.rank[i["id"]], reverse=True):
                self._clitic_items[(norm(it["lemma"]), it["pos"])] = it["id"]
        for wi, ti in enumerate(words[:-1]):
            w = norm(out[ti]["t"])
            if w not in lang.clitic_relink:
                continue
            nxt = out[words[wi + 1]]
            if self._punct_between(out, ti, words[wi + 1]) or nxt.get("lex") not in self.verb_ids \
                    or (nxt.get("form") or "").startswith("gerund"):
                continue
            lemma = (lang.elisions.get(w) or [w])[0]
            iid = self._clitic_items.get((lemma, lang.clitic_relink[w]))
            if iid:
                out[ti]["lex"], out[ti]["form"] = iid, None

    def _perfect_infinitive(self, toks: list[dict], words: list[int], lo: int, aj: int, a_s: str) -> bool:
        """Whether the auxiliary candidate at token aj is an infinitive after a finite modal in the
        same clause ('Waarom zou Tom daar geweest zijn?': 'zijn' is part of the perfect infinitive
        'geweest zijn', not a present form)."""
        if not self.lang.modals or a_s not in {norm(a) for a in self.lang.auxiliaries}:
            return False
        for x in words:
            if x < lo or x >= aj:
                continue
            for vid, tense, person in self.verb_index.get(norm(toks[x]["t"]), []):
                if person != "_" and self.items.get(vid, {}).get("lemma") in self.lang.modals:
                    return True
        return False

    def _demonstrative(self, toks: list[dict], words: list[int], wi: int) -> bool:
        """Dutch 'dat' is the conjunction only after a verb or adjective ('Ik weet dat', 'fijn dat')
        or at the start of a clause, and not before an adjective or noun: 'Laat Tom dat doen',
        'Moet je dat hoge gebouw zien' use the demonstrative."""
        if norm(toks[words[wi]]["t"]) != "dat":
            return False
        if wi + 1 < len(words):
            nlex = self.lex_lookup(norm(toks[words[wi + 1]]["t"]))
            if nlex and self.items[nlex]["pos"] in ("adj", "noun"):
                return True
        if self._clause_initial(words, toks, wi):
            return False
        prev = norm(toks[words[wi - 1]]["t"])
        plex = self.lex_lookup(prev)
        if plex and self.items[plex]["pos"] == "adj":
            return False
        if not (self.verb_index.get(prev) or self.part_index.get(prev)):
            # 'Weet je dat ...': verb + subject pronoun + conjunction
            prev2 = norm(toks[words[wi - 2]]["t"]) if wi > 1 else ""
            return not (prev in self.lang.pronouns and self.verb_index.get(prev2))
        # after a verb: the conjunction only when the clause already has its subject ('Ik weet
        # dat', 'Weet je dat'); otherwise 'dat' is the subject ('Waaraan doet dat je denken?')
        k = wi - 1
        while k > 0 and not self._punct_between(toks, words[k - 1], words[k]):
            k -= 1
        for x in range(k, wi):
            t = toks[words[x]]["t"]
            w = norm(t)
            xlex = self.lex_lookup(w)
            if w in self.lang.pronouns or (xlex and self.items[xlex]["pos"] == "noun" and not self.verb_index.get(w)) \
                    or (x > k and t[:1] != w[:1]):
                return False
        return True

    def _subject_like(self, toks: list[dict], words: list[int], wi: int) -> bool:
        """Whether word #wi can start the subject of a subordinate clause: a pronoun, a determiner, a
        name, a noun or a dummy subject ('dat er ...'). 'Je mag dat niet ... vertellen' has 'niet'."""
        if wi >= len(words):
            return False
        t = toks[words[wi]]["t"]
        w = norm(t)
        if w in self.lang.pronouns or w in self.lang.determiners or w in self.lang.dummy_subjects \
                or w in self.lang.vague_pronouns or t[:1] != w[:1]:
            return True
        lex = self.lex_lookup(w)
        return bool(lex and self.items[lex]["pos"] == "noun")

    def _clause_initial(self, words: list[int], toks: list[dict], wi: int) -> bool:
        return wi == 0 or self._punct_between(toks, words[wi - 1], words[wi])

    def _clause_pronouns(self, words: list[int], toks: list[dict], wi: int) -> tuple[set[str], set[str]]:
        """Persons of the pronouns earlier in the (sub)clause of word #wi: (subject-only pronouns,
        pronouns that may also be objects)."""
        out: set[str] = set()
        weak: set[str] = set()
        k = wi - 1
        while k >= 0 and not self._punct_between(toks, words[k], words[k + 1]):
            w = norm(toks[words[k]]["t"])
            # stop at the start of the clause, or at the finite verb of the clause before it
            # ('Weet jij wat er gebeurt?': 'jij' belongs to 'Weet')
            if w in self.lang.clause_starters or w in self.lang.relatives:
                break
            f = toks[words[k]].get("form")
            if toks[words[k]].get("lex") in self.verb_ids and (f is None or not f.endswith("._")):
                break
            if w in self.lang.vague_pronouns:
                out.add(VAGUE)
            (weak if w in self.lang.object_pronouns else out).update(self.lang.pronouns.get(w, []))
            k -= 1
        return out, weak

    def _possessive(self, toks: list[dict], words: list[int], wi: int) -> bool:
        """A determiner/pronoun reading directly before a noun ('zijn belofte'), not a verb."""
        s = norm(toks[words[wi]]["t"])
        lex = self.lex_lookup(s)
        if not lex or self.items[lex]["pos"] not in ("det", "pron") or wi + 1 >= len(words):
            return False
        prev = norm(toks[words[wi - 1]]["t"]) if wi > 0 else ""
        if prev in self.lang.pronouns:
            return False
        nxt = norm(toks[words[wi + 1]]["t"])
        nlex = self.lex_lookup(nxt)
        # a noun that is also only an ik-form ('plan', 'werk') counts as a noun here
        verbal = [c for c in self.verb_index.get(nxt, []) if not (self.lang.code == "nl" and c[2] == "ik")]
        return bool(nlex and self.items[nlex]["pos"] == "noun" and not verbal)

    _EN_IMPERATIVE = re.compile(r"^[\"'“‘«\s]*(?:please,?\s+)?(?:(?:don['’]t|do not|never)\s+)?([a-z]+(?:['’]s)?)")
    _EN_SUBJECT = re.compile(r"^[\"'“‘«\s]*(?:i|you|he|she|it|we|they|i'm|you're|he's|she's|it's|we're|they're|"
                             r"there|this|that|these|those)\b(?!\s*,)")

    # ------------------------------------------------------------------ moods (lang.tense_moods)
    def _mood(self, tense: str) -> str:
        return self.lang.tense_moods.get(tense, "indicative")

    # words between a che-less trigger and its subjunctive ('Credo non lo sappia')
    _CHE_DROP_BETWEEN = {"non", "mi", "ti", "si", "ci", "vi", "lo", "la", "li", "le", "gli", "ne", "l'",
                         "me", "te", "se", "ce", "ve", "glielo", "gliela", "glieli", "gliele", "gliene",
                         "io", "tu", "lui", "lei", "noi", "voi", "loro"}

    def _mood_context(self, toks: list[dict], words: list[int], wi: int):
        """What calls for a subjunctive before word #wi: 'strong' (a conjunction that takes it, or
        'che' after a trigger: 'Penso che', 'Voglio che', 'È importante che'), 'weak' ('che' after
        anything else: relative or 'So che'), ('if', tenses) ('se' + congiuntivo imperfetto), or
        None. The search stops at the end of the previous sentence and at a finite verb."""
        lang = self.lang
        conj_multi = [tuple(c.split()) for c in lang.subj_conjunctions if " " in c]
        k = wi - 1
        while k >= 0:
            ti = words[k]
            if any(not toks[x]["is_word"] and toks[x]["t"] in {".", "?", "!", ";", ":", "…", "..."}
                   for x in range(ti + 1, words[k + 1])):
                return None
            w = norm(toks[ti]["t"])
            for seq in conj_multi:
                n = len(seq)
                if k - n + 1 >= 0 and tuple(norm(toks[words[k - j]]["t"]) for j in range(n - 1, -1, -1)) == seq:
                    return "strong"
            if w in lang.subj_conjunctions:
                return "strong"
            if w in lang.subj_if:
                return ("if", lang.subj_if[w])
            if w == lang.subj_complementizer or w == "ch'" or (lang.subj_complementizer_elided
                                                                 and w == lang.subj_complementizer_elided):
                # an interrogative or exclamative 'che' ('A che ora ...?', 'Che cosa fai?', 'Che
                # bello!'): at the start of the sentence or a clause, after a preposition, or before
                # a noun or adjective, it calls for no subjunctive
                prev_w = norm(toks[words[k - 1]]["t"]) if k > 0 else ""
                nxt_lex = self.lex_lookup(norm(toks[words[k + 1]]["t"])) if k + 1 < len(words) else None
                if k == 0 or self._punct_between(toks, words[k - 1], ti) \
                        or self.items.get(self.lex_lookup(prev_w) or "", {}).get("pos") == "prep" \
                        or (nxt_lex and self.items[nxt_lex]["pos"] in ("noun", "adj") and k + 1 < wi):
                    return None
                if lang.ind_triggers and k > 0:
                    # a relative 'que' after a noun or 'ce' ('les films qu'elle regarde', 'ce que tu
                    # dis'); not after a trigger noun ('J'ai peur que', 'Il est temps que')
                    pt = toks[words[k - 1]]
                    plemma = self.items.get(pt.get("lex") or "", {}).get("lemma")
                    if norm(pt["t"]) in ("ce", "c'") or (
                            self.items.get(pt.get("lex") or "", {}).get("pos") == "noun"
                            and plemma not in lang.subj_triggers and norm(pt["t"]) not in lang.subj_triggers):
                        return "indicative"
                negated = False
                for j in range(k - 1, max(-1, k - 5), -1):
                    t = toks[words[j]]
                    lemma = self.items.get(t.get("lex") or "", {}).get("lemma")
                    if lemma in lang.subj_triggers or norm(t["t"]) in lang.subj_triggers:
                        return "strong"
                    if lang.ind_triggers and (lemma in lang.ind_triggers or norm(t["t"]) in lang.ind_triggers):
                        # 'Je pense que', 'parce que'; 'Je ne pense pas que' may take either mood
                        return "weak" if negated else "indicative"
                    if norm(t["t"]) in ("pas", "ne", "n'", "jamais"):
                        negated = True
                    if self._punct_between(toks, words[j], words[j + 1]):
                        break
                return "weak"
            f = toks[ti].get("form") or ""
            if toks[ti].get("lex") in self.verb_ids and "." in f and not f.endswith("._") \
                    and f.split(".", 1)[0] not in lang.compound_tenses:
                # 'Pensavo foste a casa', 'Credo lo sappia': a che-less trigger verb right before
                # (only clitics or 'non' in between) calls for the subjunctive
                if wi - k <= 3 and self.items.get(toks[ti]["lex"], {}).get("lemma") in lang.subj_che_drop \
                        and self._mood(f.split(".", 1)[0]) != "subjunctive" \
                        and all(norm(toks[words[j]]["t"]) in self._CHE_DROP_BETWEEN for j in range(k + 1, wi)) \
                        and not any(self._punct_between(toks, words[j], words[j + 1]) for j in range(k, wi)):
                    return "strong"
                return None                  # a finite verb of its own clause comes first
            k -= 1
        return None

    def _mood_filter(self, cands: list[tuple[str, str]], toks: list[dict], words: list[int], wi: int,
                     imperative: bool) -> tuple[list[tuple[str, str]], bool]:
        """The candidates (tense, person) of one verb that fit the context, and whether the mood is
        unsure (an indicative/subjunctive homograph after a 'che' without a trigger: 'So che parli' /
        'Dice che parli'; such a sentence is not used). `imperative`: the word stands where an
        imperative can (clause-initial, no subject, '!' or an imperative translation)."""
        if not self.lang.tense_moods:
            return cands, False
        imp = [c for c in cands if self._mood(c[0]) == "imperative"]
        if imperative and imp:
            return imp, False
        rest = [c for c in cands if self._mood(c[0]) != "imperative"]
        if not rest:
            return [], False                 # only an imperative form outside an imperative context
        subj = [c for c in rest if self._mood(c[0]) == "subjunctive"]
        other = [c for c in rest if self._mood(c[0]) != "subjunctive"]
        if not subj:
            return rest, False
        ctx = self._mood_context(toks, words, wi)
        if ctx == "strong":
            return subj, False
        if ctx == "indicative":
            return (other or subj), False
        if isinstance(ctx, tuple):
            hit = [c for c in subj if c[0] in ctx[1]]
            return (hit, False) if hit else (other or subj, False)
        if ctx == "weak" and other:
            return other, True
        return (other or subj), False

    def _imperative_context(self, toks: list[dict], words: list[int], wi: int, vid: str,
                            translation: str | None, cands: list[tuple[str, str]]) -> bool:
        """Whether word #wi stands where an imperative can (rule 4). Verbs whose imperative is
        distinct (essere, avere: sii, abbi) only count with a form that is no present form."""
        if not any(self._mood(c[0]) == "imperative" for c in cands):
            return False
        lemma = self.items.get(vid, {}).get("lemma")
        persons = {c[1] for c in cands if self._mood(c[0]) == "imperative"}
        if lemma in self.lang.imperative_exempt and any(c[0] == self.lang.present for c in cands):
            # 'Siamo pronti!' is a statement; only a 'Let's ...' translation makes the noi form an
            # imperative ('Siamo seri!' = Let's be serious!, 'Abbiamo pazienza!' = Let's be patient!)
            noi = self.lang.persons[3]
            return noi in persons and bool(re.match(r"^[\"'“‘«\s]*let'?s\b", (translation or "").lower().replace("’", "'"))) \
                and self._imperative(toks, words, wi, vid, noi, translation, check_exempt=False)
        return any(self._imperative(toks, words, wi, vid, p, translation, check_exempt=False) for p in sorted(persons))

    def _align_multiword(self, out: list[dict], words: list[int], done: set[int], translation: str | None) -> None:
        """Pass 0: multi-word verb forms ('mi alzo', 'ti sei alzato', 'me ne vado', 'si sieda'): every
        word gets the verb and the cell. Contiguous words; a compound form may have adverbs before its
        participle ('mi sono già alzato')."""
        lang = self.lang
        lens = sorted({len(k) for k in self.multi}, reverse=True)
        wi = 0
        while wi < len(words):
            hit = None
            for n in lens:
                if wi + n > len(words):
                    continue
                # contiguous span, or n-1 contiguous words + up to 2 adverbs + the participle
                for gap in (0, 1, 2):
                    if wi + n + gap > len(words):
                        break
                    span = words[wi:wi + n - 1] + [words[wi + n - 1 + gap]]
                    between = words[wi + n - 1:wi + n - 1 + gap]
                    if any(norm(out[x]["t"]) not in lang.aux_between for x in between):
                        break
                    key = tuple(norm(out[x]["t"]) for x in span)
                    cands = self.multi.get(key)
                    if not cands or any(x in done for x in span) or \
                            any(self._punct_between(out, a, b) for a, b in zip(span, span[1:])):
                        continue
                    if gap and not any(c[1] in lang.compound_tenses for c in cands):
                        continue
                    hit = (span, cands)
                    break
                if hit:
                    break
            if not hit:
                wi += 1
                continue
            span, cands = hit
            by_verb: dict[str, list[tuple[str, str]]] = defaultdict(list)
            for vid, tense, person in cands:
                by_verb[vid].append((tense, person))
            vid = min(by_verb, key=lambda v: self.rank.get(v, (True, 0, v)))
            first = pos = words.index(span[0])
            imperative = self._imperative_context(out, words, first, vid, translation, by_verb[vid])
            cs, unsure = self._mood_filter(by_verb[vid], out, words, first, imperative)
            before, after = self._pronoun_persons(words, out, pos)
            if not cs or (before and lang.persons and set(before) <= set(lang.persons)
                          and not any(c[1] in before for c in cs)):
                # 'che tu mi chiami' is chiamare with an object 'mi', not '(io) mi chiami'
                wi += 1
                continue
            choice = None
            if not unsure:
                fit = [c for c in cs if c[1] in before] or [c for c in cs if c[1] in after]
                if not fit and len({c[1] for c in cs}) > 1:
                    fit = [c for c in cs if c[1] in (lang.third_sg, lang.third_pl)] or cs
                choice = self._order(fit or cs)[0]
            for x in span:
                out[x]["lex"], out[x]["form"] = vid, (f"{choice[0]}.{choice[1]}" if choice else None)
                if unsure:
                    out[x]["unsure"] = True
            done |= set(span)
            wi = words.index(span[-1]) + 1

    def _align_enclitic(self, out: list[dict], words: list[int], translation: str | None) -> None:
        """Words with attached pronouns ('farlo', 'dimmi', 'alzarmi', 'aspettandoti', 'parlagli'):
        an infinitive, gerund or imperative host + clitics (lang.enclitics) links to its verb with
        that cell ('imperativo.tu', 'infinitive._'; the token text is no form of the cell, so the
        app never asks it). A reflexive clitic prefers the pronominal verb (alzarmi -> alzarsi)."""
        lang = self.lang
        refl = {"mi", "ti", "si", "ci", "vi"}
        for wi, ti in enumerate(words):
            t = out[ti]
            if t["lex"] and not (self.items.get(t["lex"], {}).get("pos") != "verb"
                                 and self._imperative_bang(out, words, wi, translation)):
                continue
            w = norm(t["t"])
            best = None
            for suf in lang.enclitics:
                if not w.endswith(suf) or len(w) <= len(suf) + 1:
                    continue
                host = w[: -len(suf)]
                cands = [(c, False) for c in self.enclitic_hosts.get(host, ())]
                if suf[0] not in "aeiou" and host.endswith(suf[0]):       # di' + mmi, fa' + llo
                    cands += [(c, True) for c in self.enclitic_hosts.get(host[:-1], ()) if c[2]]
                elif suf.startswith("gli"):
                    cands += [(c, True) for c in self.enclitic_hosts.get(host, ()) if c[2]]   # digli, fagli
                cands = [c for c, doubled in cands if c[2] == doubled or suf.startswith("gli")]
                if not cands:
                    continue
                own = self._enclitic_person_clitic(out, words, wi)

                def fits(pron, cell) -> bool:
                    # the clitics are the pronominal verb's own: a reflexive one for a si-verb
                    # (alzarmi -> alzarsi), of the subject's person when that is known ('Devo
                    # alzarmi', 'Alzati!'; not 'Non trattarmi' -> trattarsi), 'ci' for a ci-verb
                    # (pensarci; not tenermi -> tenerci)
                    att = pron[1]
                    if att == "si":
                        need = self._REFL_OF.get(cell.split(".", 1)[1]) if cell.startswith("imperativo.") else own
                        return suf[:2] in refl and (need is None or suf[:2] == need)
                    if att == "ci":
                        return suf.startswith(("ci", "ce"))
                    return suf.endswith(att[-2:]) and suf[:2] in {"me", "te", "se", "ce", "ve"}

                def key(c):
                    pron = lang.pronominal(self.items.get(c[0], {}).get("lemma", ""))
                    return (0 if pron and fits(pron, c[1]) else 2 if pron else 1, self.rank.get(c[0], (True, 0, c[0])))
                best = min(cands, key=key)
                break
            if best:
                t["lex"], t["form"] = best[0], best[1]

    _REFL_OF = {"io": "mi", "tu": "ti", "lui/lei": "si", "noi": "ci", "voi": "vi", "loro": "si"}

    def _enclitic_person_clitic(self, out: list[dict], words: list[int], wi: int) -> str | None:
        """The reflexive clitic an infinitive at word #wi would carry as a pronominal verb: of the
        finite verb before it in the clause ('Devo alzarmi': mi), 'ti' for a negative tu-imperative
        ('Non alzarti!'), or None when unknown."""
        k = wi - 1
        while k >= 0 and not self._punct_between(out, words[k], words[k + 1]):
            t = out[words[k]]
            f = t.get("form") or ""
            if t.get("lex") in self.verb_ids and "." in f and not f.endswith("._"):
                return self._REFL_OF.get(f.split(".", 1)[1])
            k -= 1
        first = wi - 1
        if first >= 0 and norm(out[words[first]]["t"]) == "non" \
                and (first == 0 or self._punct_between(out, words[first - 1], words[first])):
            return "ti"
        return None

    def _align_elative(self, out: list[dict], words: list[int]) -> None:
        """An unlinked word with an elative ending links to its adjective (or other non-verb):
        'bellissimo' -> bello, 'facilissima' -> facile, 'lunghissimi' -> lungo, 'moltissimo' -> molto."""
        for ti in words:
            t = out[ti]
            if t["lex"]:
                continue
            w = norm(t["t"])
            suf = next((s for s in self.lang.elative if w.endswith(s) and len(w) > len(s) + 1), None)
            if not suf:
                continue
            stem = w[: -len(suf)]
            stems = [stem, stem[:-1]] if stem.endswith(("ch", "gh")) else [stem]
            cands = [i for s in stems for end in ("o", "e") for i in self.lemma_index.get(s + end, ())
                     if self.items[i]["pos"] != "verb"]
            if cands:
                adj = [i for i in cands if self.items[i]["pos"] == "adj"]
                t["lex"] = self._best(adj or cands)

    def _imperative_bang(self, toks: list[dict], words: list[int], wi: int, translation: str | None) -> bool:
        """A clause-initial word in an exclamation or with an imperative translation ('Fallo!')."""
        if not self._clause_initial(words, toks, wi):
            return False
        if any(not t["is_word"] and t["t"] == "!" for t in toks[words[wi]:]):
            return not self._EN_SUBJECT.match((translation or "").lower())
        return False

    def _other_verb_excluded(self, by_verb: dict, vid: str, choice: tuple[str, str], toks: list[dict],
                             words: list[int], wi: int) -> bool:
        """Whether the other verbs sharing this spelling cannot be meant: none has a finite form of
        the chosen person ('Hij was moe': wassen has 'was' only for ik), or (ik) their only reading
        is a present ik-form and no object follows ('Ik was moe', not 'Ik was de auto')."""
        for other, cands in by_verb.items():
            if other == vid:
                continue
            persons = {p for _, p in cands if p != "_"}
            if choice[1] not in persons:
                continue
            if {(t, p) for t, p in cands} == {(self.lang.present, self.lang.persons[0])} \
                    and choice[1] == self.lang.persons[0] and wi + 1 < len(words) \
                    and not self._punct_between(toks, words[wi], words[wi + 1]):
                nxt = norm(toks[words[wi + 1]]["t"])
                if nxt not in self.lang.determiners and nxt not in self.lang.pronouns \
                        and nxt not in self.lang.object_pronouns and nxt not in {"hem", "haar", "ze", "zich", "me", "mij"}:
                    continue
            return False
        return True

    # copulas after which a rare-tense homograph is the adjective/participle ('Erano sorpresi')
    _COPULAS = {"essere", "sembrare", "stare", "rimanere", "restare", "diventare"}
    # articles that are also object clitics ('le chiese' = the churches / asked her)
    _CLITIC_ARTICLES = {"la", "le", "lo", "gli", "l'"}

    def _homograph_nonverb(self, toks: list[dict], words: list[int], wi: int, lex: str | None,
                           s: str, translation: str | None, finite_seen: bool) -> bool:
        """Whether a rare-tense form at word #wi that is also a noun, an adjective or a participle
        ('chiese' churches/asked, 'prese' taken/took, 'fu' late/was, 'sorpresi' surprised) is that
        other word. The non-verb reading needs a cue: a copula before it ('Siamo sorpresi'), a
        determiner before it ('delle prese', 'il fu Mattia'), a noun before it after a finite verb
        ('Ho trovato le chiavi perse'), or the noun's English gloss in the translation ('Le chiese
        sono antiche' = The churches are old). Otherwise the form is the verb ('Lei prese il treno',
        'Mi chiese aiuto', 'Fu un errore')."""
        pos = self.items[lex]["pos"] if lex else None
        if not ((pos and pos != "verb") or s in self.part_any):
            return False
        if self._pronoun_persons(words, toks, wi)[0]:
            return False                     # 'Io sorpresi tutti'
        if pos == "noun" and translation:
            tr = set(re.findall(r"[a-z]+", translation.lower()))
            tr |= {x[:-1] for x in tr if x.endswith("s")} | {x[:-2] for x in tr if x.endswith("es")}
            for g in (self.items[lex].get("tr") or {}).get("en") or []:
                w = g.lower().split()
                if w and w[-1].strip("(),;") in tr:
                    return True
        if wi == 0 or self._punct_between(toks, words[wi - 1], words[wi]):
            return False
        prev = toks[words[wi - 1]]
        pt, plex = norm(prev["t"]), prev.get("lex")
        k = wi - 1                           # a copula, maybe before adverbs ('sembrarono molto sorpresi')
        while k > 0 and norm(toks[words[k]]["t"]) in self.lang.aux_between \
                and not self._punct_between(toks, words[k - 1], words[k]):
            k -= 1
        ct, clex = norm(toks[words[k]]["t"]), toks[words[k]].get("lex")
        if ct in self.essere_forms or (clex and self.items.get(clex, {}).get("lemma") in self._COPULAS):
            return True
        if pt in self.lang.determiners:
            # 'le chiese' (the churches) / 'Le chiese aiuto' (he asked her for help): an
            # article that is also a clitic counts only after the clause's finite verb
            return pt not in self._CLITIC_ARTICLES or (pos == "noun" and finite_seen)
        return bool(plex and self.items.get(plex, {}).get("pos") == "noun" and finite_seen)

    def _imperative(self, toks: list[dict], words: list[int], wi: int, vid: str, person: str,
                    translation: str | None, check_exempt: bool = True) -> bool:
        """Italian: whether a present form at word #wi is an imperative (see rule 4)."""
        lang = self.lang
        homograph = lang.imperative_homographs.get(norm(toks[words[wi]]["t"]), (None, None))[1]
        if not lang.imperative_lead or (check_exempt and self.items.get(vid, {}).get("lemma") in lang.imperative_exempt
                                        and homograph is None):
            return False
        if homograph is None and person not in (lang.persons[1], lang.persons[2], lang.persons[3], lang.persons[4]):
            return False
        k = wi - 1
        while k >= 0 and not self._punct_between(toks, words[k], words[k + 1]) \
                and norm(toks[words[k]]["t"]) in lang.imperative_lead:
            k -= 1
        if k >= 0 and not self._punct_between(toks, words[k], words[k + 1]):
            return False                     # not clause-initial
        before, after = self._pronoun_persons(words, toks, wi)
        if lang.clitic_pronouns and self._before_weak and k + 1 < wi \
                and norm(toks[words[k + 1]]["t"]) in ("ne", "n'"):
            before = []                      # French 'Ne vous inquiétez pas !': vous is the clitic
        if (before or after) and not (lang.tense_moods and person not in before + after):
            return False                     # 'Tu parli', 'Parli tu?' (not 'Non parlate tutti insieme!')
        if any(not t["is_word"] and t["t"] == "!" for t in toks[words[wi]:]):
            # ... unless the translation has a subject ('Siamo pronti!' = We're ready!)
            return not (lang.tense_moods and self._EN_SUBJECT.match((translation or "").lower()))
        if lang.subject_required and translation and not self._EN_SUBJECT.match(translation.lower()) \
                and not translation.rstrip().endswith("?") \
                and not any(not t["is_word"] and "?" in t["t"] for t in toks[words[wi]:]) \
                and not (k >= 0 and any(q in toks[x]["t"] for x in range(words[k] + 1, words[k + 1])
                                        for q in ("»", "”", '"'))) \
                and toks[words[wi]]["t"] not in re.findall(r"[^\W\d_]+", translation):
            # French has no subject-less finite verbs; not in a question, not a reporting verb after
            # a quote ('« Voulez-vous entrer ? » demande ...'), not a name kept in the translation
            return True
        m = self._EN_IMPERATIVE.match((translation or "").lower())
        if not m:
            return False
        w = m.group(1).replace("’", "'")
        if lang.translation_subjects and re.match(r"^[\"'“‘«\s]*please\b", (translation or "").lower()):
            return True                      # 'Por favor ve con Tom' = 'Please take Tom with you'
        if w in ("let's", "lets"):
            return person == lang.persons[3]
        heads = self.en_heads.get(vid, set()) | (homograph or set())
        return w in heads and not (translation or "").rstrip().endswith("?")

    # ------------------------------------------------------------------ main
    def align(self, toks: list[dict], translation: str | None = None) -> list[dict]:
        """Aligned copies of the tokens. `translation` (English) helps to recognize imperatives."""
        lang = self.lang
        self._tr_person = None
        # a form shared by two tenses ('hablamos': presente / indefinido) takes the tense of a time
        # word in the sentence ('Ayer hablamos con Ana')
        self._tense_hint = None
        if lang.tense_hints:
            for t in toks:
                h = lang.tense_hints.get(norm(t["t"]))
                if h:
                    self._tense_hint = h
                    break
        if lang.translation_subjects and translation:
            m = re.match(r"^[\"'“‘«¿¡\s]*([a-z]+)", translation.lower().replace("’", "'"))
            if m:
                self._tr_person = lang.translation_subjects.get(m.group(1))
        out = [dict(t, lex=None, form=None) for t in toks]
        words = [i for i, t in enumerate(out) if t["is_word"]]
        pos_in_words = {ti: wi for wi, ti in enumerate(words)}
        done: set[int] = set()

        # pass 0: multi-word verb forms (Italian pronominal verbs: 'mi alzo', 'mi sono alzato')
        if self.multi:
            self._align_multiword(out, words, done, translation)

        # pass 1: compound tenses (participle + auxiliary in the same clause)
        compound = next(iter(lang.compound_tenses), None)
        for wi, ti in enumerate(words):
            if ti in done:
                continue
            s = norm(out[ti]["t"])
            pc = self.part_index.get(s)
            if not pc or compound is None:
                continue
            lo, hi = self._clause_range(out, ti)
            if lang.aux_window:
                # the auxiliary before the participle, with only aux_between words in between
                cand_idx = []
                for k in range(wi - 1, max(-1, wi - 1 - lang.aux_window), -1):
                    if words[k] < lo:
                        break
                    cand_idx.append(words[k])
                    if norm(out[words[k]]["t"]) not in lang.aux_between:
                        break
            else:
                before = [x for x in reversed(words[:wi]) if x >= lo]
                after = [x for x in words[wi + 1:] if x <= hi]
                # a subordinate clause's auxiliary right after the participle ('wat er gebeurd is')
                # wins over one further back in the main clause ('Ik ben ... over wat er gebeurd is')
                cand_idx = after[:1] + before + after[1:]
            hit = None
            for aj in cand_idx:
                if aj in done:
                    continue
                awi = pos_in_words[aj]
                if lang.clause_starters and awi > 0 and norm(out[words[awi - 1]]["t"]) == "te":   # Dutch te + infinitive
                    continue
                a_s = norm(out[aj]["t"])
                if self._perfect_infinitive(out, words, lo, aj, a_s) or self._possessive(out, words, awi):
                    continue
                hyphen = self._hyphen_split(a_s)          # French 'as-tu', 'a-t-il' + participle
                if hyphen:
                    a_s = hyphen[0]
                for vid, aux, needs_clitic in sorted(pc, key=lambda e: (not self._in_translation(e[0], translation, pc),
                                                                         self.rank.get(e[0], (True, 0, e[0])))):
                    for ct, atense in lang.compound_tenses.items():
                        persons = self.aux_forms.get(aux, {}).get(atense, {}).get(a_s)
                        if persons:
                            break
                    if not persons:
                        continue
                    if needs_clitic == "refl":
                        refl = norm(out[words[awi - 1]]["t"]) if awi > 0 else ""
                        if hyphen or refl not in lang.reflexive_clitics or \
                                not set(lang.reflexive_clitics[refl].split(",")) & set(persons):
                            continue
                    elif needs_clitic and not self._agreement_object(out, words, awi):
                        continue
                    hit = (aj, vid, aux, persons, ct, atense)
                    break
                if hit:
                    break
            if not hit:
                continue
            aj, vid, aux, persons, compound, atense = hit
            person = persons[0]
            b, a = self._pronoun_persons(words, out, pos_in_words[aj])
            hyphen = self._hyphen_split(norm(out[aj]["t"]))
            if hyphen:
                b, a = list(lang.hyphen_subjects.get(hyphen[1], [])), []
            fits = [p for p in persons if p in b] or ([] if VAGUE in b else [p for p in persons if p in a])
            if self._before_weak and not fits and not hyphen:
                b = []                       # 'Tom nous a vus': nous is the object
            if not fits and (b or a):
                # a subject pronoun that fits no form of the auxiliary: Dutch inversion ('heb je
                # gegeten' uses the ik-form for jij), polite 'u' (bent/is), a coordinated subject
                # ('io e lui abbiamo'): link the words but leave the person open
                out[ti]["lex"], out[ti]["form"] = vid, None
                out[aj]["lex"], out[aj]["form"] = self.aux_ids[aux], None
                done |= {ti, aj}
                continue
            if len(persons) > 1:
                pick = fits
                if not pick and lang.code == "it":
                    plural = s[-1:] in ("i", "e")
                    pick = [p for p in persons if (lang.persons.index(p) >= 3) == plural]
                if not pick:
                    pick = [p for p in (lang.third_sg, lang.third_pl) if p in persons]
                person = (pick or persons)[0]
            if person not in (self.verb_forms.get(vid, {}).get(compound) or {person: 1}):
                person = None                # a defective verb lacks the cell ('j'ai frit': frire)
            out[ti]["lex"], out[ti]["form"] = vid, person and f"{compound}.{person}"
            out[aj]["lex"], out[aj]["form"] = self.aux_ids[aux], person and f"{atense}.{person}"
            done |= {ti, aj}

        # pass 2: everything else, left to right
        finite_seen = False
        finite_events = 0                    # finite verbs seen so far
        starter = False                      # a clause starter was seen, its subject not yet
        starter_events = 0
        for wi, ti in enumerate(words):
            if starter and finite_events != starter_events:
                starter = False              # 'Waarom wil hij ...': the finite verb came first
            if wi > 0 and any(self._is_clause_break(out[x]) and out[x]["t"] not in QUOTES
                              for x in range(words[wi - 1] + 1, ti)):   # 'Je kan niet "nee" zeggen'
                finite_seen = False
                starter = False
            w0 = norm(out[ti]["t"])
            nxt0 = norm(out[words[wi + 1]]["t"]) if wi + 1 < len(words) else ""
            if w0 in lang.coordinators and nxt0 in lang.pronouns and nxt0 not in lang.determiners:
                finite_seen = False          # 'en jullie werken' (not 'maar het woord'): a new clause
            # 'Ik weet dat jullie werken': a subordinate clause starts over (a new finite verb may
            # follow) when its subject comes right after the clause starter and is a pronoun, a name
            # or 'er'. Not after a demonstrative 'dat' ('Kun je me dat laten weten?', 'Je mag dat niet
            # ... vertellen'), and not on a noun, which may be an object ('Ik moet dat deze avond doen').
            if w0 in lang.clause_starters and not self._demonstrative(out, words, wi) \
                    and self._subject_like(out, words, wi + 1):
                starter, starter_events = True, finite_events
            elif starter and not self.verb_index.get(w0) and (w0 in lang.pronouns or w0 in lang.dummy_subjects
                                                              or w0[:1] != out[ti]["t"][:1]):
                finite_seen = False
                starter = False
            if ti in done:
                if out[ti]["form"] and not out[ti]["form"].endswith("._"):
                    finite_seen, finite_events = True, finite_events + 1
                continue
            s = norm(out[ti]["t"])
            if lang.capitalized_names and wi > 0 and out[ti]["t"][:1].isupper() \
                    and not any(not out[x]["is_word"] and out[x]["t"] in SENTENCE_STARTS
                                for x in range(words[wi - 1] + 1, ti)):
                # a capitalized word inside a sentence is a name ('Salut, Marie !', 'Pierre arrive'),
                # unless an item is written so ('Paris', 'France')
                lexc = self.lex_lookup(s, lemma_only=True)
                if not (lexc and self.items[lexc]["lemma"][:1].isupper()):
                    continue
            elif lang.capitalized_names and translation and out[ti]["t"][:1].isupper() \
                    and out[ti]["t"] in re.findall(r"[^\W\d_]+", translation):
                # a sentence-initial word kept as it is in the translation is a name ('Marie
                # choisit ...' = Marie chooses ...), unless it is the English gloss ('Simple.')
                lexc = self.lex_lookup(s)
                cands = [lexc] if lexc else sorted({v[0] for v in self.verb_index.get(s, [])})
                if cands and all(s not in {g.lower() for g in (self.items[c].get("tr") or {}).get("en") or []}
                                 and not self.items[c]["lemma"][:1].isupper() for c in cands if c in self.items):
                    continue
            vc = self.verb_index.get(s)
            pc = self.part_index.get(s)
            lex = self.lex_lookup(s)
            if s in self.intj and self._clause_initial(words, out, wi) and not (
                    wi + 1 < len(words) and not self._punct_between(out, ti, words[wi + 1])
                    and norm(out[words[wi + 1]]["t"]) in lang.pronouns):
                out[ti]["lex"] = self.intj[s]    # 'Prego.', 'Scusa, ...', 'Dag Anna!': the interjection
                continue
            prev = norm(out[words[wi - 1]]["t"]) if wi > 0 else ""
            if lang.participle_after_copula and pc and not vc and wi > 0 \
                    and (lex is None or self.items[lex]["pos"] == "noun") and self._after_copula(out, words, wi):
                # 'être traité comme un enfant', 'il a été construit': the participle, not the noun
                vid = min((e[0] for e in pc), key=lambda v: self.rank.get(v, (True, 0, v)))
                out[ti]["lex"], out[ti]["form"] = vid, "participle._"
                continue
            use_verb = bool(vc) and not (lex and prev in lang.determiners)
            if vc and not use_verb and prev in lang.article_clitics and wi > 1 \
                    and not self._punct_between(out, words[wi - 2], words[wi - 1]) \
                    and (norm(out[words[wi - 2]]["t"]) in lang.pronouns
                         or norm(out[words[wi - 2]]["t"]) in lang.skip_between
                         or (self.items.get(out[words[wi - 2]].get("lex") or "", {}).get("lemma") in lang.modals
                             and any(c[1] == "infinitive" for c in vc))):     # 'va le voir', 'peux la porter'
                use_verb = True              # 'Je la porte', 'Il ne la ferme pas': a clitic, not 'la porte'
            if vc and not use_verb and prev in lang.infinitive_preps and any(c[1] == "infinitive" for c in vc):
                use_verb = True              # 'sans dire un mot', 'pour aller à la gare': the infinitive
            if vc and not use_verb and prev in lang.predicate_determiners \
                    and any(self.items.get(c[0], {}).get("lemma") in lang.copula_lemmas for c in vc):
                use_verb = True              # 'Quel est ce bâtiment ?': the copula, not 'est' (east)
            if use_verb and lex and lang.gerund_marker and all(c[1] == "gerund" for c in vc) \
                    and prev != lang.gerund_marker:
                use_verb = False             # 'étudiant', 'pendant', 'maintenant': not a gerund without 'en'
            if use_verb and lex and lang.noun_after_adjective and wi > 1 and self.items[lex]["pos"] == "noun" \
                    and self.items.get(out[words[wi - 1]].get("lex") or "", {}).get("pos") == "adj" \
                    and norm(out[words[wi - 2]]["t"]) in lang.determiners \
                    and not self._punct_between(out, words[wi - 2], ti):
                use_verb = False             # 'une bonne élève': the noun, not 'élever'
            if use_verb and lex and s in lang.verb_needs_pronoun and not any(self._pronoun_persons(words, out, wi))                     and prev not in lang.preverbal_clitics:
                use_verb = False             # Spanish 'como' (like, as) unless 'yo como', 'lo como'
            copula_before = False
            if use_verb and lang.copula_lemmas:
                k = wi - 1
                while k >= 0 and norm(out[words[k]]["t"]) in lang.skip_between                         and not self._punct_between(out, words[k], words[k + 1]):
                    k -= 1
                if k >= 0 and not self._punct_between(out, words[k], words[k + 1]):
                    pt = out[words[k]]
                    f = pt.get("form") or ""
                    copula_before = self.items.get(pt.get("lex") or "", {}).get("lemma") in lang.copula_lemmas                         and bool(f) and not f.endswith("._")
            if use_verb and lex and lang.object_noun_after_verb and wi > 0 and self.items[lex]["pos"] == "noun" \
                    and not self._punct_between(out, words[wi - 1], ti) \
                    and (out[words[wi - 1]].get("lex") in self.verb_ids
                         or (prev in lang.noun_coordinators and wi > 1
                             and self.items.get(out[words[wi - 2]].get("lex") or "", {}).get("pos") == "noun")):
                use_verb = False             # 'Bebo vino', 'agua o vino': the noun (wine), not 'vino' (came)
            if vc and not use_verb and prev in lang.demonstratives and self.items[lex]["pos"] != "noun" \
                    and self._clause_initial(words, out, wi - 1):
                use_verb = True              # 'Dat moest je ...': a demonstrative subject, not 'dat moest(e)'
            if use_verb and lang.clause_starters and prev == "te" and not any(c[1] == "infinitive" for c in vc):
                use_verb = False             # 'te laat' (too late): after 'te' a verb is an infinitive
            noun = bool(lex) and self.items[lex]["pos"] == "noun"
            if use_verb and noun and lang.clause_starters and prev.endswith("e") \
                    and self.items.get(self.lex_lookup(prev) or "", {}).get("pos") == "adj":
                use_verb = False             # 'het eeuwige leven', 'je andere plannen': inflected adjective + noun
            if use_verb and noun and lang.clause_starters and self._clause_initial(words, out, wi) \
                    and not (wi + 1 < len(words) and norm(out[words[wi + 1]]["t"]) in lang.pronouns):
                use_verb = False             # 'Leven is ...': a clause-initial noun, not a verb without subject
            if use_verb and lex and lang.adj_over_first_person and self.items[lex]["pos"] == "adj" \
                    and all(c[2] == lang.persons[0] for c in vc) and not self._clause_initial(words, out, wi) \
                    and prev not in lang.skip_between \
                    and lang.persons[0] not in sum(self._pronoun_persons(words, out, wi), []):
                use_verb = False             # 'está enfermo', 'un día largo': the adjective, not 'yo enfermo'
            if use_verb and lex and prev in lang.degree_words and self.items[lex]["pos"] == "adj":
                use_verb = False             # 'hoe laat', 'zo laat': the adjective
            if use_verb and lex and lang.copulas and self.items[lex]["pos"] == "adj" and wi + 1 < len(words) \
                    and not self._punct_between(out, ti, words[wi + 1]):
                nxt = norm(out[words[wi + 1]]["t"])
                last = wi + 2 >= len(words) or self._punct_between(out, words[wi + 1], words[wi + 2])
                if nxt in lang.copulas and (nxt != "zijn" or last):
                    use_verb = False         # 'dat ik laat ben', 'of het open is': the adjective
            if use_verb and lang.clause_starters and finite_seen and lex and not pc \
                    and not any(c[1] in ("infinitive", "participle") for c in vc):
                use_verb = False             # 'Ik zal een beetje laat aankomen': one finite verb per clause
            if use_verb and lex and lang.code == "nl":
                persons = {c[2] for c in vc}
                before, after = self._pronoun_persons(words, out, wi)
                if persons == {"ik"} and "ik" not in before + after:
                    use_verb = False         # 'waar' (adverb) rather than 'ik waar' (waren)
            if use_verb and self._possessive(out, words, wi):
                use_verb = False             # possessive 'zijn boek' (det + noun) rather than the verb 'zijn'
            if use_verb and pc and prev in self.essere_forms:
                use_verb = False             # 'sono state costruite': participle, not 'voi costruite'
            if use_verb and pc and lang.code == "nl" and finite_seen:
                use_verb = False             # 'wordt als keuken gebruikt': participle, not present
                lex = None
            if use_verb and copula_before and all(p != "_" for _, _, p in vc):
                if pc and lang.participle_after_copula:
                    # 'Le livre est écrit en français': the participle, not 'il écrit'
                    vid = min((e[0] for e in pc), key=lambda v: self.rank.get(v, (True, 0, v)))
                    out[ti]["lex"], out[ti]["form"] = vid, "participle._"
                    continue
                # '¿Estás todavía despierta?': after 'to be' the word is an adjective, no finite verb
                out[ti]["lex"] = lex or min({c[0] for c in vc}, key=lambda v: self.rank.get(v, (True, 0, v)))
                continue
            if use_verb:
                by_verb: dict[str, list[tuple[str, str]]] = defaultdict(list)
                for vid, tense, person in vc:
                    by_verb[vid].append((tense, person))
                pool = list(by_verb)
                if len(pool) > 1 and lang.person_hint_verbs:
                    # one spelling, several verbs ('viste': vestir él / ver tú; 'vengo': venir / vengar):
                    # keep the verbs with a form of the person an adjacent subject pronoun or a
                    # third-person clitic ('se viste') points to
                    b_, a_ = self._pronoun_persons(words, out, wi)
                    want = set(b_ or a_)
                    if not want and wi > 0 and prev in lang.third_person_clitics:
                        want = {lang.third_sg, lang.third_pl}
                    fit = [v for v in pool if any(p in want for _, p in by_verb[v])]
                    if want and fit:
                        pool = fit
                vid = min(pool, key=lambda v: self.rank.get(v, (True, 0, v)))
                if len(pool) < len(by_verb):
                    by_verb = {v: by_verb[v] for v in pool}
                cands = by_verb[vid]
                unsure = False
                if lang.tense_moods:
                    # several moods share the spelling ('parli': presente tu, congiuntivo, Lei
                    # imperative): the context decides (_mood_filter)
                    imperative = self._imperative_context(out, words, wi, vid, translation, cands)
                    all_cands = cands
                    cands, unsure = self._mood_filter(cands, out, words, wi, imperative)
                    if not cands and not unsure and not ((lex and self.items[lex]["pos"] != "verb")
                                                         or s in self.part_any):
                        # a form that can only be an imperative ('Oggi divertiamoci!', 'Siamo in
                        # vacanza, rilassiamoci!') is one wherever it stands
                        cands = [c for c in all_cands if self._mood(c[0]) == "imperative"]
                    # 'Siamo arrabbiati' (not 'arrabbiati!' = get angry), 'Sono sorpresi' (not
                    # 'sorpresi' = I surprised): an imperative outside an imperative context, or a
                    # rare-tense form that is also an adjective or a participle in a context that
                    # calls for one (_homograph_nonverb), is that word
                    if not unsure and (not cands or (
                            all(c[0] in lang.homograph_tenses for c in cands)
                            and self._homograph_nonverb(out, words, wi, lex, s, translation, finite_seen))):
                        if lex:
                            out[ti]["lex"] = lex
                        elif s in self.part_any:
                            out[ti]["lex"], out[ti]["form"] = self.part_any[s], "participle._"
                        continue
                choice = None if unsure or not cands else self._choose(cands, words, out, wi, finite_seen)
                out[ti]["lex"] = vid
                if unsure:
                    out[ti]["unsure"] = True
                if choice and (self.items.get(vid, {}).get("lemma"), choice[0]) in lang.unlinked_forms:
                    choice = None            # Dutch 'zou' is a conditional, not the past of 'zal'
                if choice and len(by_verb) > 1 and choice[1] != "_" \
                        and not self._other_verb_excluded(by_verb, vid, choice, out, words, wi) \
                        and not (lang.homograph_verbs_by_rank and self._dominant_verb(vid, by_verb)):
                    # a finite form of two verbs ('was': zijn or wassen): the verb is a guess
                    choice = None
                if choice and choice[0] == lang.present and choice[1] != "_" \
                        and self._imperative(out, words, wi, vid, choice[1], translation):
                    choice = None            # 'Chiedi a un poliziotto!': an imperative, not 'tu chiedi'
                    other = lang.imperative_homographs.get(s, (None,))[0]
                    if other and by_lemma_verb_id(self, other):
                        out[ti]["lex"] = by_lemma_verb_id(self, other)   # 'Ven aquí': venir, not ver
                if choice:
                    tense, person = choice
                    out[ti]["form"] = f"{tense}.{person}"
                    if person != "_":
                        finite_seen, finite_events = True, finite_events + 1
                    if lang.code == "nl" and wi + 1 < len(words):
                        nxt = norm(out[words[wi + 1]]["t"])
                        if nxt in ("jij", "je"):
                            # inversion 'Wil je', 'Kwam je': the jij-form drops its -t here, so
                            # the word is no reliable instance of a cell (and 'Komt je' is wrong)
                            out[ti]["form"] = None
                elif all(p != "_" for _, p in by_verb[vid]):
                    # finite, person open ('Wilt u ...', 'Werk jij ...', imperative 'Laat ...')
                    finite_seen, finite_events = True, finite_events + 1
                continue
            if lex:
                out[ti]["lex"] = lex
                continue
            if pc and prev in lang.determiners and prev not in lang.pronouns:
                continue                     # 'su pedido', 'el resultado': a noun the lexicon lacks, no participle
            if pc:
                vid = min((e[0] for e in pc), key=lambda v: self.rank.get(v, (True, 0, v)))
                out[ti]["lex"], out[ti]["form"] = vid, "participle._"
        # French hyphenated verb words: 'parlez-vous', 'a-t-il', 'donne-moi' (lang.hyphen_subjects)
        if lang.hyphen_subjects:
            self._align_hyphen(out, words, translation)
        # object clitics spelled like articles: 'Je le vois', 'J'en ai' (lang.clitic_relink)
        if lang.clitic_relink:
            self._relink_clitics(out, words)
        # pass 3: split separable verbs: a finite verb and the clause-final particle that together
        # make a two-word form of a separable verb ('Ik sta morgen vroeg op' -> opstaan, ik)
        if self.separable:
            self._align_separable(out, words)
        # attached pronouns: 'farlo', 'dimmi', 'alzarmi' (lang.enclitics)
        if self.enclitic_hosts:
            self._align_enclitic(out, words, translation)
        # absolute superlatives: 'bellissimo' -> bello, 'lunghissima' -> lungo (lang.elative)
        if lang.elative:
            self._align_elative(out, words)
        # pass 4: multi-word phrases ('per favore', 'tot ziens'): every word links to the phrase
        for seq, iid in self.phrases.items():
            n = len(seq)
            for wi in range(len(words) - n + 1):
                span = words[wi:wi + n]
                if tuple(norm(out[x]["t"]) for x in span) == seq \
                        and not any(self._punct_between(out, a, b) for a, b in zip(span, span[1:])):
                    if " ".join(seq) in lang.standalone_phrases and not (
                            self._clause_initial(words, out, wi)
                            and (wi + n >= len(words) or self._punct_between(out, span[-1], words[wi + n]))):
                        continue             # 'de nada' (you're welcome), not 'No me arrepiento de nada'
                    for x in span:
                        out[x]["lex"], out[x]["form"] = iid, None
        if self.infl:
            self.infl.align(out)
        return out

    def _align_separable(self, out: list[dict], words: list[int]) -> None:
        """Both words of a split separable verb get the separable verb and the finite word's cell,
        like the two words of a compound form. Only when the finite word has a person (not after
        inversion: 'Sta je op?') and the particle is the last word of its clause (no punctuation in
        between is needed: 'Ik sta op, en ...' ends the clause at the comma)."""
        for ti in words:
            t = out[ti]
            form = t.get("form") or ""
            if not t.get("lex") or "." not in form or form.startswith("infl:") or t["lex"] not in self.verb_ids:
                continue
            tense, person = form.split(".", 1)
            if person == "_":
                continue
            lo, hi = self._clause_range(out, ti)
            for x in words:
                if ti < x <= hi and norm(out[x]["t"]) in (self.lang.coordinators | self.lang.clause_starters):
                    hi = x - 1          # 'Ik sta op en ga ...', 'Ik bel je op als ...'
                    break
            last = max((x for x in words if lo <= x <= hi), default=None)
            if last is None or last <= ti:
                continue
            p = out[last]
            if p.get("form"):
                continue
            if any(norm(out[x]["t"]) in ("hier", "daar", "waar") for x in words if lo <= x <= hi):
                continue        # a stranded preposition ('Hier komt nooit een eind aan'): no particle
            hits = [e for e in self.separable.get((norm(t["t"]), norm(p["t"])), []) if e[1] == tense and e[2] == person]
            if not hits:
                continue
            vid = min({e[0] for e in hits}, key=lambda v: self.rank.get(v, (True, 0, v)))
            for x in (ti, last):
                out[x]["lex"], out[x]["form"] = vid, f"{tense}.{person}"
