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

from .lang import Lang

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
VAGUE = "?"   # pseudo-person of a vague subject pronoun (Dutch 'u'): fits no person
QUOTES = {'"', "«", "»", "“", "”"}
CLAUSE_PUNCT = {",", ".", "?", "!", ";", ":", "...", "…", "—", "–", "(", ")", '"', "«", "»", "“", "”"}


def norm(s: str) -> str:
    return s.replace("’", "'").lower()


def _form(val) -> str:
    return val["form"] if isinstance(val, dict) else val


class Aligner:
    def __init__(self, lang: Lang, items: list[dict], verbs: dict[str, dict]):
        self.lang = lang
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
        for vid in sorted(verbs):
            v = verbs[vid]
            forms = v.get("forms") or {}
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
                            continue
                        if tense == "participle":
                            for aux in auxes:
                                for pv in lang.participle_variants(f, "essere" if lang.code == "it" else aux):
                                    needs_clitic = lang.code == "it" and aux != "essere" and pv != f
                                    entry = (vid, aux, needs_clitic)
                                    if entry not in self.part_index[norm(pv)]:
                                        self.part_index[norm(pv)].append(entry)
                            continue
                        entry = (vid, tense, person)
                        if entry not in self.verb_index[norm(f)]:
                            self.verb_index[norm(f)].append(entry)
        for aux in lang.auxiliaries:
            vid = by_lemma_verb.get(aux)
            if not vid or vid not in verbs:
                continue
            self.aux_ids[aux] = vid
            table = verbs[vid]["forms"].get(lang.present, {})
            d: dict[str, list[str]] = defaultdict(list)
            for person in lang.persons:
                if table.get(person) is not None:
                    d[norm(_form(table[person]))].append(person)
            self.aux_present[aux] = dict(d)
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
            if it["pos"] == "verb":
                continue
            for s in [it["lemma"], *(it.get("variants") or [])]:
                if " " not in s:
                    self.lemma_index[norm(s)].append(it["id"])
                    if it["pos"] in ("intj", "phrase"):
                        cur = self.intj.get(norm(s))
                        if cur is None or self.rank[it["id"]] < self.rank[cur]:
                            self.intj[norm(s)] = it["id"]
                elif it["pos"] in ("intj", "phrase", "adv"):
                    self.phrases[tuple(norm(s).split())] = it["id"]
            for s in it.get("inflections") or []:
                self.infl_index[norm(s)].append(it["id"])

    # ------------------------------------------------------------------ lookups
    def _best(self, ids: list[str]) -> str:
        return min(ids, key=lambda i: self.rank.get(i, (True, 0, i)))

    def lex_lookup(self, s: str, lemma_only: bool = False) -> str | None:
        keys = [s]
        if self.lang.code == "it" and s.endswith("'"):
            keys = ELISION_IT.get(s, []) + [s] + [s[:-1] + v for v in "aoei"]
        elif self.lang.code == "nl" and s in CLITIC_NL:
            keys = CLITIC_NL[s] + [s]
        for k in keys:
            if self.lemma_index.get(k):
                return self._best(self.lemma_index[k])
        if lemma_only:
            return None
        for k in keys:
            if self.infl_index.get(k):
                return self._best(self.infl_index[k])
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
        k = wi - 1
        while k >= 0 and wi - k <= 4:
            ti = words[k]
            if self._punct_between(toks, ti, words[k + 1]):
                break
            w = norm(toks[ti]["t"])
            if w in lang.vague_pronouns:
                before = [VAGUE]
                break
            if w in lang.pronouns:
                before = list(lang.pronouns[w])
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
        return sorted(cands, key=lambda c: (tenses.index(c[0]) if c[0] in tenses else 99,
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
        return bool(lex and self.items.get(lex, {}).get("pos") == "noun")

    def _choose(self, cands, words, toks, wi, finite_before: bool):
        """Pick (tense, person) among candidates of one verb; None = leave the form unset."""
        lang = self.lang
        prev = norm(toks[words[wi - 1]]["t"]) if wi > 0 else ""
        inf = [c for c in cands if c[0] == "infinitive"]
        finite = [c for c in cands if c[1] != "_"]
        nonfinite = [c for c in cands if c[1] == "_"]
        before, after = self._pronoun_persons(words, toks, wi)
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
        for p in (lang.third_sg, lang.third_pl):
            hit = [c for c in cands if c[1] == p]
            if hit:
                return self._order(hit)[0]
        return self._order(cands)[0]

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

    def _imperative(self, toks: list[dict], words: list[int], wi: int, vid: str, person: str,
                    translation: str | None) -> bool:
        """Italian: whether a present form at word #wi is an imperative (see rule 4)."""
        lang = self.lang
        if not lang.imperative_lead or self.items.get(vid, {}).get("lemma") in lang.imperative_exempt:
            return False
        if person not in (lang.persons[1], lang.persons[2], lang.persons[3], lang.persons[4]):
            return False
        k = wi - 1
        while k >= 0 and not self._punct_between(toks, words[k], words[k + 1]) \
                and norm(toks[words[k]]["t"]) in lang.imperative_lead:
            k -= 1
        if k >= 0 and not self._punct_between(toks, words[k], words[k + 1]):
            return False                     # not clause-initial
        before, after = self._pronoun_persons(words, toks, wi)
        if before or after:
            return False                     # 'Tu parli', 'Parli tu?'
        if any(not t["is_word"] and t["t"] == "!" for t in toks[words[wi]:]):
            return True
        m = self._EN_IMPERATIVE.match((translation or "").lower())
        if not m:
            return False
        w = m.group(1).replace("’", "'")
        if w in ("let's", "lets"):
            return person == lang.persons[3]
        return w in self.en_heads.get(vid, set()) and not (translation or "").rstrip().endswith("?")

    # ------------------------------------------------------------------ main
    def align(self, toks: list[dict], translation: str | None = None) -> list[dict]:
        """Aligned copies of the tokens. `translation` (English) helps to recognize imperatives."""
        lang = self.lang
        out = [dict(t, lex=None, form=None) for t in toks]
        words = [i for i, t in enumerate(out) if t["is_word"]]
        pos_in_words = {ti: wi for wi, ti in enumerate(words)}
        done: set[int] = set()

        # pass 1: compound tenses (participle + auxiliary in the same clause)
        compound = next(iter(lang.compound_tenses), None)
        for wi, ti in enumerate(words):
            s = norm(out[ti]["t"])
            pc = self.part_index.get(s)
            if not pc or compound is None:
                continue
            lo, hi = self._clause_range(out, ti)
            if lang.code == "it":
                cand_idx = []
                for k in range(wi - 1, max(-1, wi - 5), -1):
                    if words[k] < lo:
                        break
                    cand_idx.append(words[k])
                    if norm(out[words[k]]["t"]) not in IT_BETWEEN_AUX_PART:
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
                if awi > 0 and norm(out[words[awi - 1]]["t"]) == "te":
                    continue
                a_s = norm(out[aj]["t"])
                if self._perfect_infinitive(out, words, lo, aj, a_s) or self._possessive(out, words, awi):
                    continue
                for vid, aux, needs_clitic in sorted(pc, key=lambda e: self.rank.get(e[0], (True, 0, e[0]))):
                    persons = self.aux_present.get(aux, {}).get(a_s)
                    if not persons:
                        continue
                    if needs_clitic and not (awi > 0 and norm(out[words[awi - 1]]["t"]) in OBJECT_CLITICS_IT):
                        continue
                    hit = (aj, vid, aux, persons)
                    break
                if hit:
                    break
            if not hit:
                continue
            aj, vid, aux, persons = hit
            person = persons[0]
            b, a = self._pronoun_persons(words, out, pos_in_words[aj])
            fits = [p for p in persons if p in b] or ([] if VAGUE in b else [p for p in persons if p in a])
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
            out[ti]["lex"], out[ti]["form"] = vid, f"{compound}.{person}"
            out[aj]["lex"], out[aj]["form"] = self.aux_ids[aux], f"{lang.present}.{person}"
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
            vc = self.verb_index.get(s)
            pc = self.part_index.get(s)
            lex = self.lex_lookup(s)
            if s in self.intj and self._clause_initial(words, out, wi) and not (
                    wi + 1 < len(words) and not self._punct_between(out, ti, words[wi + 1])
                    and norm(out[words[wi + 1]]["t"]) in lang.pronouns):
                out[ti]["lex"] = self.intj[s]    # 'Prego.', 'Scusa, ...', 'Dag Anna!': the interjection
                continue
            prev = norm(out[words[wi - 1]]["t"]) if wi > 0 else ""
            use_verb = bool(vc) and not (lex and prev in lang.determiners)
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
            if use_verb:
                by_verb: dict[str, list[tuple[str, str]]] = defaultdict(list)
                for vid, tense, person in vc:
                    by_verb[vid].append((tense, person))
                vid = min(by_verb, key=lambda v: self.rank.get(v, (True, 0, v)))
                choice = self._choose(by_verb[vid], words, out, wi, finite_seen)
                out[ti]["lex"] = vid
                if choice and (self.items.get(vid, {}).get("lemma"), choice[0]) in lang.unlinked_forms:
                    choice = None            # Dutch 'zou' is a conditional, not the past of 'zal'
                if choice and len(by_verb) > 1 and choice[1] != "_" \
                        and not self._other_verb_excluded(by_verb, vid, choice, out, words, wi):
                    # a finite form of two verbs ('was': zijn or wassen): the verb is a guess
                    choice = None
                if choice and choice[0] == lang.present and choice[1] != "_" \
                        and self._imperative(out, words, wi, vid, choice[1], translation):
                    choice = None            # 'Chiedi a un poliziotto!': an imperative, not 'tu chiedi'
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
            if pc:
                vid = min((e[0] for e in pc), key=lambda v: self.rank.get(v, (True, 0, v)))
                out[ti]["lex"], out[ti]["form"] = vid, "participle._"
        # pass 3: multi-word phrases ('per favore', 'tot ziens'): every word links to the phrase
        for seq, iid in self.phrases.items():
            n = len(seq)
            for wi in range(len(words) - n + 1):
                span = words[wi:wi + n]
                if tuple(norm(out[x]["t"]) for x in span) == seq \
                        and not any(self._punct_between(out, a, b) for a, b in zip(span, span[1:])):
                    for x in span:
                        out[x]["lex"], out[x]["form"] = iid, None
        return out
