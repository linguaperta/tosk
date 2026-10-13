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
     form. Dutch imperatives ('Vertel eens') likewise get no form.
  Unmatched tokens stay unlinked.
"""
from __future__ import annotations

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
        by_lemma_verb: dict[str, str] = {}
        for it in sorted(items, key=lambda i: self.rank[i["id"]]):
            if it["pos"] == "verb":
                by_lemma_verb.setdefault(it["lemma"], it["id"])
        for vid in sorted(verbs):
            v = verbs[vid]
            forms = v.get("forms") or {}
            auxes = [a for a in (v.get("auxiliary") or "").split("|") if a]
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
        for it in items:
            if it["pos"] == "verb":
                continue
            for s in [it["lemma"], *(it.get("variants") or [])]:
                if " " not in s:
                    self.lemma_index[norm(s)].append(it["id"])
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
            if w in lang.pronouns:
                before = list(lang.pronouns[w])
                break
            if w not in lang.skip_between:
                break
            k -= 1
        after: list[str] = []
        if wi + 1 < len(words) and not self._punct_between(toks, words[wi], words[wi + 1]):
            w = norm(toks[words[wi + 1]]["t"])
            if w in lang.pronouns:
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
        if finite:
            hit = [c for c in finite if c[1] in before] or [c for c in finite if c[1] in after]
            if hit:
                return self._order(hit)[0]
        if inf and (prev == "te" or finite_before or not finite):
            return inf[0]
        if not finite:
            return self._order(nonfinite)[0] if nonfinite else None
        cands = finite
        if before and not inf:
            return None                      # pronoun that fits no form (subjunctive, imperative ...)
        ps = {c[1] for c in cands}
        if lang.code == "nl" and ps == {"ik"} and "ik" not in after:
            return None                      # inverted jij form or imperative
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

    # ------------------------------------------------------------------ main
    def align(self, toks: list[dict]) -> list[dict]:
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
                cand_idx = [words[k] for k in range(wi - 1, max(-1, wi - 5), -1) if words[k] >= lo]
            else:
                before = [x for x in reversed(words[:wi]) if x >= lo]
                after = [x for x in words[wi + 1:] if x <= hi]
                cand_idx = before + after
            hit = None
            for aj in cand_idx:
                if aj in done:
                    continue
                awi = pos_in_words[aj]
                if awi > 0 and norm(out[words[awi - 1]]["t"]) == "te":
                    continue
                a_s = norm(out[aj]["t"])
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
            if len(persons) > 1:
                b, a = self._pronoun_persons(words, out, pos_in_words[aj])
                pick = [p for p in persons if p in b] or [p for p in persons if p in a]
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
        for wi, ti in enumerate(words):
            if wi > 0 and self._punct_between(out, words[wi - 1], ti):
                finite_seen = False
            if ti in done:
                if out[ti]["form"] and not out[ti]["form"].endswith("._"):
                    finite_seen = True
                continue
            s = norm(out[ti]["t"])
            vc = self.verb_index.get(s)
            pc = self.part_index.get(s)
            lex = self.lex_lookup(s)
            prev = norm(out[words[wi - 1]]["t"]) if wi > 0 else ""
            use_verb = bool(vc) and not (lex and prev in lang.determiners)
            if use_verb and lex and lang.code == "nl":
                persons = {c[2] for c in vc}
                before, after = self._pronoun_persons(words, out, wi)
                if persons == {"ik"} and "ik" not in before + after:
                    use_verb = False         # 'waar' (adverb) rather than 'ik waar' (waren)
            if use_verb and lex and self.items[lex]["pos"] in ("det", "pron") and wi + 1 < len(words) \
                    and prev not in lang.pronouns:
                # possessive 'zijn boek' (det + noun) rather than the verb 'zijn'
                nxt = norm(out[words[wi + 1]]["t"])
                nlex = self.lex_lookup(nxt)
                if nlex and self.items[nlex]["pos"] == "noun" and not self.verb_index.get(nxt):
                    use_verb = False
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
                if choice:
                    tense, person = choice
                    out[ti]["form"] = f"{tense}.{person}"
                    if person != "_":
                        finite_seen = True
                    if lang.code == "nl" and person == "ik" and wi + 1 < len(words):
                        nxt = norm(out[words[wi + 1]]["t"])
                        if nxt in ("jij", "je") and (tense, "jij") not in by_verb[vid]:
                            out[ti]["form"] = None
                continue
            if lex:
                out[ti]["lex"] = lex
                continue
            if pc:
                vid = min((e[0] for e in pc), key=lambda v: self.rank.get(v, (True, 0, v)))
                out[ti]["lex"], out[ti]["form"] = vid, "participle._"
        return out
