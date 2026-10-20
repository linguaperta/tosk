"""Grammar features of sentences and skills (docs/ARCHITECTURE.md, "Grammar gating").

A learner should not meet a grammar construct before starting the skill that teaches it. The
pipeline therefore tags every sentence with the features its tokens show, and every skill with
the features it introduces:

* ``tense:{T}`` for every verb token in tense T, read from the token alignment. A compound form
  (``ho mangiato``, ``heb gegeten``) tags its compound tense on the participle; its auxiliary is
  not tagged as present. A participle without an auxiliary tags the compound tense too (passive or
  adjectival use is gated with the perfect). A verb token without a ``form`` is looked up by its
  spelling: only a spelling that is no present form and no infinitive tags a tense (``kwam`` in
  ``Kwam je?``). A Dutch perfect with a double infinitive instead of a participle (``Ik heb Tom
  niet zien vallen``, ``Hij heeft Japans willen leren``, ``Ik ben gaan zwemmen``: a finite form of
  an auxiliary followed in its clause by two adjacent infinitives, the first not after *te*) tags
  the compound tense too, plus ``compound_aux`` for its auxiliary and ``modal_infinitive`` when the
  first infinitive is one of the modal verbs.
* construct features declared per course in ``course.yaml`` under ``feature_detectors``
  (``{feature: {type: ..., ...}}``):

  ``compound_aux``     ``{aux: essere}``  a compound form whose auxiliary is that verb
  ``modal_infinitive`` ``{verbs: [...], infinitive_pattern: regex}``  a finite form of one of the
                       verbs plus a later infinitive (an aligned ``infinitive._`` token, a verb token
                       spelled like its infinitive, or an unaligned word matching the pattern)
  ``words``            ``{words: [...]}``  any of these spellings (lower case), except tokens aligned
                       to a verb form (``tu dai`` = dare, not the articulated preposition)
  ``irregular_tense``  ``{tense: T}``  a form of tense T of a verb with T in its ``irregular_in``
  ``separable``        ``{particles: [...]}``  a separable verb (one whose present table has
                       two-word forms, ``sta op``) in any form, or a finite verb V with a
                       clause-final particle P such that P+V is a separable verb (``Hij komt terug.``)
  ``reflexive``        ``{pronouns: {me: yo, se: [él/ella, ellos/ellas], ...}, clitics: [...],
                       enclitic_any: [se]}``  a pronoun of the verb's own person in the clitic
                       cluster before a finite verb (``me levanto``, ``nos hemos visto``), or attached
                       to a verb word that is no table form (``levantarse``; ``levantarme`` only after
                       a finite verb of that person: ``Quiero levantarme``)
  ``nonfinite``        ``{form: gerund, pattern: regex}``  a verb token in that form (``comiendo``),
                       or a word matching the pattern (with attached clitics: ``haciéndolo``)
  ``pattern``          ``{pattern: regex}``  the regex is found in the sentence text (lower case,
                       apostrophes normalized): ``più \\w+ (di|che)``, ``\\w+issim[oaie]``
  ``enclitic``         ``{tense: T}``  a verb token aligned to a form of tense T (any tense when
                       absent) whose text is no spelling of that cell: the form carries attached
                       pronouns (``dimmi``, ``fallo``; ``alzati`` is a table form and does not count)

  ``words`` entries with spaces match consecutive words (``me lo``); ``reflexive`` with
  ``unbound: true`` only counts pronouns that are no part of the verb's own form (a pronominal verb
  aligns its pronoun to itself: ``mi alzo``), e.g. impersonal ``si dice``.

Skills introduce ``introduces: [...]`` from course.yaml, plus ``tense:{T}`` for a grammar skill
with ``verbs: {tense: T}``. ``base_features`` (course.yaml) are allowed from the start.

A sentence's *home* skill is the last skill, in course order, among the skills it touches (the
skill introducing each aligned item; a verb skill whose tense the sentence shows for one of its
verbs) and the first skill introducing each of its non-base features. A sentence is valid when its
features are all allowed at its home skill: introduced by the home skill, one of its prerequisites
(transitively) or the base set. The importer only selects valid sentences, and the validator checks
the rule again.
"""
from __future__ import annotations

import re
from collections import defaultdict
from types import SimpleNamespace

from . import query
from .lang import get_lang

DETECTOR_TYPES = {"compound_aux", "modal_infinitive", "words", "irregular_tense", "separable", "reflexive",
                  "nonfinite", "pattern", "enclitic"}
_APOS = str.maketrans({"’": "'", "‘": "'"})
_CLAUSE_PUNCT = {",", ".", "?", "!", ";", ":", "...", "…", "—", "–", "(", ")", '"', "«", "»", "“", "”", "¿", "¡"}


def _norm(s: str) -> str:
    return s.translate(_APOS).lower()


def _form(val) -> str:
    return val["form"] if isinstance(val, dict) else val


def _is_word(tok: dict) -> bool:
    return tok.get("is_word", True) is not False


# ------------------------------------------------------------------------------------------ tagger
class FeatureTagger:
    """Tags token lists (aligner output or sentence records) with grammar features."""

    def __init__(self, course: dict, items: list[dict], verbs: dict[str, dict]):
        self.code = course["id"]
        try:
            self.lang = get_lang(self.code)
        except KeyError:
            # a course without pipeline language rules (e.g. one with its own importer): tenses
            # from the token forms only, no compound tenses or auxiliaries
            self.lang = SimpleNamespace(present=(course.get("tenses") or [None])[0], compound_tenses={},
                                        auxiliaries=[], persons=list(course.get("persons") or ["_"]))
        self.items = {it["id"]: it for it in items}
        self.verbs = verbs
        self.present = self.lang.present
        self.compound = dict(self.lang.compound_tenses)
        self.first_compound = next(iter(self.compound), None)
        lemma_verb: dict[str, str] = {}
        for it in sorted(items, key=lambda i: (i.get("freq") is None, i.get("freq") or 0, i["id"])):
            if it["pos"] == "verb" and it["id"] in verbs:
                lemma_verb.setdefault(it["lemma"], it["id"])
        self.lemma_verb = lemma_verb
        self.aux_ids = {lemma_verb[a]: a for a in self.lang.auxiliaries if a in lemma_verb}
        # spelling -> tenses per verb (single-word simple forms, participle variants)
        self._spell: dict[str, dict[str, set[str]]] = {}
        self.detectors = []
        for name, spec in (course.get("feature_detectors") or {}).items():
            spec = dict(spec or {})
            kind = spec.get("type")
            if kind not in DETECTOR_TYPES:
                raise ValueError(f"{self.code}: feature detector {name!r} has unknown type {kind!r}")
            if kind == "words":
                spec["_words"] = {_norm(w) for w in spec.get("words") or [] if " " not in w.strip()}
                spec["_seqs"] = [tuple(_norm(w).split()) for w in spec.get("words") or [] if " " in w.strip()]
            if kind == "pattern":
                spec["_re"] = re.compile(spec.get("pattern") or "(?!)")
            if kind == "modal_infinitive":
                spec["_ids"] = {lemma_verb[v] for v in spec.get("verbs") or [] if v in lemma_verb}
                pat = spec.get("infinitive_pattern")
                spec["_re"] = re.compile(pat) if pat else None
            if kind == "separable":
                spec["_particles"] = {_norm(p) for p in spec.get("particles") or []}
            if kind == "nonfinite":
                pat = spec.get("pattern")
                spec["_re"] = re.compile(pat) if pat else None
            if kind == "reflexive":
                pron = {}
                for w, ps in (spec.get("pronouns") or {}).items():
                    pron[_norm(w)] = set(ps if isinstance(ps, list) else [ps])
                spec["_pron"] = pron
                spec["_clitics"] = set(pron) | {_norm(w) for w in spec.get("clitics") or []}
                spec["_any"] = {_norm(w) for w in spec.get("enclitic_any") or []}
                spec["_verbs"] = set(spec.get("verbs") or [])     # only these verbs (lemmas)
            self.detectors.append((name, kind, spec))

    # -- helpers ----------------------------------------------------------------------------------
    def _spellings(self, vid: str) -> dict[str, set[str]]:
        sp = self._spell.get(vid)
        if sp is None:
            sp = defaultdict(set)
            v = self.verbs.get(vid) or {}
            for tense, table in (v.get("forms") or {}).items():
                if tense in self.compound:
                    continue
                for val in table.values():
                    alts = val.get("alts", []) if isinstance(val, dict) else []
                    for f in [_form(val), *alts]:
                        if " " in f:
                            continue
                        if tense == "participle" and hasattr(self.lang, "participle_variants"):
                            for pv in self.lang.participle_variants(f, "essere"):
                                sp[_norm(pv)].add(tense)
                        sp[_norm(f)].add(tense)
            self._spell[vid] = sp
        return sp

    def token_tenses(self, tok: dict) -> set[str]:
        """Tenses (course tense keys; participle -> compound tense) a verb token shows."""
        lex = tok.get("lex")
        if not lex or lex not in self.verbs:
            return set()
        form = tok.get("form")
        if form:
            tenses = {form.split(".", 1)[0]}
        else:
            tenses = set(self._spellings(lex).get(_norm(tok["t"]), set()))
            if tenses & {self.present, "infinitive"}:
                return set()    # spelled like a present form or the infinitive: no new feature
        out = set()
        for t in tenses - {"infinitive", "gerund"}:
            if t == "participle":
                # a participle without an auxiliary (passive, adjectival); Spanish 'cansado' is no perfect
                if self.first_compound and getattr(self.lang, "bare_participle_tense", True):
                    out.add(self.first_compound)
            else:
                out.add(t)
        return out

    def _is_participle(self, tok: dict) -> bool:
        form = tok.get("form") or ""
        if form.split(".", 1)[0] in self.compound or form == "participle._":
            return True
        if not form and tok.get("lex") in self.verbs:
            return "participle" in self._spellings(tok["lex"]).get(_norm(tok["t"]), set())
        return False

    def _aux_for(self, toks: list[dict], i: int) -> int | None:
        """Index of the auxiliary token of the participle at i: the nearest auxiliary-verb token
        in a present form (preceding first)."""
        best = None
        for j, t in enumerate(toks):
            if j == i or t.get("lex") not in self.aux_ids:
                continue
            f = t.get("form") or ""
            if f and not f.startswith(self.present + "."):
                continue
            if not f and self.present not in self._spellings(t["lex"]).get(_norm(t["t"]), set()):
                continue
            d = (0 if j < i else 1, abs(i - j))
            if best is None or d < best[0]:
                best = (d, j)
        return best[1] if best else None

    def _infinitive_after(self, toks: list[dict], i: int, spec: dict) -> bool:
        rx = spec.get("_re")
        for t in toks[i + 1:]:
            if not _is_word(t):
                continue
            if t.get("form") == "infinitive._":
                return True
            lex = t.get("lex")
            if lex in self.verbs and not t.get("form"):
                inf = ((self.verbs[lex].get("forms") or {}).get("infinitive") or {}).get("_")
                if inf and _norm(t["t"]) == _norm(_form(inf)):
                    return True
            if rx and (not lex or (lex in self.verbs and not t.get("form"))) and rx.fullmatch(_norm(t["t"])):
                return True                  # a clitic infinitive: 'posso farlo', 'puedo hacerlo'

        return False

    def _is_infinitive(self, tok: dict) -> bool:
        if tok.get("form") == "infinitive._":
            return True
        lex = tok.get("lex")
        if lex in self.verbs and not tok.get("form"):
            inf = ((self.verbs[lex].get("forms") or {}).get("infinitive") or {}).get("_")
            return bool(inf) and _norm(tok["t"]) == _norm(_form(inf))
        return False

    def double_infinitive_perfect(self, toks: list[dict]) -> tuple[int, int] | None:
        """(auxiliary index, first infinitive index) of a perfect with a double infinitive
        ('Ik heb Tom niet zien vallen'), or None."""
        if not getattr(self.lang, "double_infinitive_perfect", False):
            return None
        for i, t in enumerate(toks):
            if not _is_word(t) or t.get("lex") not in self.aux_ids or self._is_infinitive(t) \
                    or self._is_participle(t):
                continue
            prev = None                      # index of the previous word when it is an infinitive
            before = None                    # the word before that infinitive
            last_word = None
            for j in range(i + 1, len(toks)):
                u = toks[j]
                if not _is_word(u):
                    if u["t"] in _CLAUSE_PUNCT:
                        break
                    continue
                if self._is_participle(u):
                    break                    # an ordinary compound form
                if self._is_infinitive(u):
                    if prev is not None and _norm(before or "") not in ("te", "om"):
                        return i, prev
                    prev, before = j, last_word
                else:
                    prev = None
                last_word = u["t"]
        return None

    def _reflexive(self, toks: list[dict], spec: dict) -> bool:
        """A reflexive pronoun of the verb's own person in the clitic cluster before a finite verb
        ('me levanto', 'se llama', 'nos hemos visto'), or attached to an infinitive/gerund/imperative
        ('levantarse'; 'levantarme' after a finite verb of the same person: 'Quiero levantarme')."""
        pron, clitics, any_ = spec["_pron"], spec["_clitics"], spec["_any"]
        unbound = bool(spec.get("unbound"))
        persons_seen: set[str] = set()
        for i, t in enumerate(toks):
            if not _is_word(t):
                if t["t"] in _CLAUSE_PUNCT:
                    persons_seen = set()
                continue
            if t.get("lex") not in self.verbs:
                continue
            if spec["_verbs"] and self.items.get(t["lex"], {}).get("lemma") not in spec["_verbs"]:
                continue
            f = t.get("form") or ""
            person = f.split(".", 1)[1] if "." in f else "_"
            if person != "_":
                persons_seen.add(person)
                j = i - 1
                while j >= 0 and _is_word(toks[j]) and _norm(toks[j]["t"]) in clitics:
                    if person in pron.get(_norm(toks[j]["t"]), ()) and not (unbound and toks[j].get("lex") in self.verbs):
                        return True
                    j -= 1
                continue
            w = _norm(t["t"])
            if w in self._spellings(t["lex"]):
                continue                     # a plain form, no enclitic
            for suf, ps in pron.items():
                if len(w) > len(suf) + 2 and w.endswith(suf) and (suf in any_ or ps & persons_seen):
                    return True
        return False

    def _separable(self, vid: str) -> bool:
        v = self.verbs.get(vid) or {}
        ik = ((v.get("forms") or {}).get(self.present) or {}).get(self.lang.persons[0])
        return bool(ik) and " " in _form(ik)

    # -- main -------------------------------------------------------------------------------------
    def tag(self, toks: list[dict]) -> set[str]:
        feats: set[str] = set()
        aux_pos: set[int] = set()
        parts = [i for i, t in enumerate(toks) if _is_word(t) and t.get("lex") in self.verbs and self._is_participle(t)]
        part_aux = {i: self._aux_for(toks, i) for i in parts}
        for i in parts:
            if part_aux[i] is not None and (toks[i].get("form") or "").split(".", 1)[0] in self.compound:
                aux_pos.add(part_aux[i])
        ipp = self.double_infinitive_perfect(toks)
        if ipp and self.first_compound:
            feats.add(f"tense:{self.first_compound}")
        tenses_at: dict[int, set[str]] = {}
        for i, t in enumerate(toks):
            if not _is_word(t):
                continue
            ts = self.token_tenses(t)
            if i in aux_pos:
                ts = ts - {self.present}
            tenses_at[i] = ts
            feats |= {f"tense:{x}" for x in ts}
        for name, kind, spec in self.detectors:
            if self._detect(kind, spec, toks, parts, part_aux, aux_pos, tenses_at, ipp):
                feats.add(name)
        return feats

    def _detect(self, kind, spec, toks, parts, part_aux, aux_pos, tenses_at, ipp=None) -> bool:
        if kind == "words":
            # a token aligned to a verb form is that verb, not the listed word (``tu dai`` is dare, not da+i)
            if any(_is_word(t) and not t.get("form") and _norm(t["t"]) in spec["_words"] for t in toks):
                return True
            ws = [t for t in toks if _is_word(t)]
            for seq in spec["_seqs"]:
                n = len(seq)
                for i in range(len(ws) - n + 1):
                    if tuple(_norm(t["t"]) for t in ws[i:i + n]) == seq and not any(t.get("form") for t in ws[i:i + n]):
                        return True
            return False
        if kind == "pattern":
            if spec.get("annotate"):
                # every word followed by its aligned form in braces: 'non{} preoccuparti{infinitive._}'
                text = _norm("".join((t.get("pre") or "") + t["t"] + ("{" + (t.get("form") or "") + "}" if _is_word(t) else "")
                                     for t in toks))
            else:
                text = _norm("".join((t.get("pre") or "") + t["t"] for t in toks))
            return bool(spec["_re"].search(text))
        if kind == "enclitic":
            want = spec.get("tense")
            for t in toks:
                f, lex = t.get("form") or "", t.get("lex")
                if not _is_word(t) or lex not in self.verbs or "." not in f or f.startswith("infl:"):
                    continue
                tense, person = f.split(".", 1)
                if want and tense != want:
                    continue
                val = ((self.verbs[lex].get("forms") or {}).get(tense) or {}).get(person)
                if val is None:
                    continue
                acc = [_norm(x) for x in [_form(val), *(val.get("alts", []) if isinstance(val, dict) else [])]]
                if not any(_norm(t["t"]) in a.split() for a in acc):
                    return True
            return False
        if kind == "compound_aux":
            want = spec.get("aux")
            if ipp and self.aux_ids.get(toks[ipp[0]].get("lex")) == want:
                return True
            for i in parts:
                a = part_aux[i]
                if a is not None:
                    if self.aux_ids.get(toks[a].get("lex")) == want:
                        return True
                else:
                    primary = (self.verbs[toks[i]["lex"]].get("auxiliary") or "").split("|")[0]
                    if primary == want:
                        return True
            return False
        if kind == "irregular_tense":
            tense = spec.get("tense")
            for i, ts in tenses_at.items():
                if tense in ts and i not in aux_pos:
                    if tense in (self.verbs[toks[i]["lex"]].get("irregular_in") or []):
                        return True
            return False
        if kind == "modal_infinitive":
            if ipp and toks[ipp[1]].get("lex") in spec["_ids"]:
                return True                  # 'Hij heeft Japans willen leren'
            for i, t in enumerate(toks):
                if t.get("lex") in spec["_ids"] and i not in aux_pos and _is_word(t):
                    f = t.get("form") or ""
                    if f.startswith(("infinitive", "participle", "gerund")):
                        continue
                    if self._infinitive_after(toks, i, spec):
                        return True
            return False
        if kind == "reflexive":
            return self._reflexive(toks, spec)
        if kind == "nonfinite":
            # a verb in that non-finite form ('estoy comiendo'), also with attached clitics ('haciéndolo')
            want, rx = spec.get("form"), spec.get("_re")
            for t in toks:
                if not _is_word(t):
                    continue
                f, lex = t.get("form") or "", t.get("lex")
                if f.split(".", 1)[0] == want:
                    return True
                if lex in self.verbs and not f:
                    if want in self._spellings(lex).get(_norm(t["t"]), set()):
                        return True
                if rx and (not lex or (lex in self.verbs and not f)) and rx.fullmatch(_norm(t["t"])):
                    return True
            return False
        if kind == "separable":
            particles = spec["_particles"]
            for i, t in enumerate(toks):
                lex = t.get("lex")
                if lex in self.verbs and self._separable(lex):
                    return True
            for i, t in enumerate(toks):
                lex = t.get("lex")
                if lex not in self.verbs or not _is_word(t):
                    continue
                lemma = self.items.get(lex, {}).get("lemma", "")
                for j in range(i + 1, len(toks)):
                    p = toks[j]
                    if not _is_word(p):
                        if p["t"] in _CLAUSE_PUNCT:
                            break
                        continue
                    nxt = toks[j + 1] if j + 1 < len(toks) else None
                    at_end = nxt is None or (not _is_word(nxt) and nxt["t"] in _CLAUSE_PUNCT)
                    if at_end and _norm(p["t"]) in particles:
                        vid = self.lemma_verb.get(_norm(p["t"]) + lemma)
                        if vid and self._separable(vid):
                            return True
            return False
        return False


# ------------------------------------------------------------------------------------------ skills
class SkillGraph:
    """Course order, introduced/allowed features per skill, and the home-skill rule."""

    def __init__(self, course: dict, resolved: dict[str, list[str]], tagger: FeatureTagger | None = None):
        self.course = course
        # gating applies to courses that declare base_features (an empty list gates everything);
        # older packs without the key are tagged but not checked
        self.enforced = "base_features" in course
        self.base: set[str] = set(course.get("base_features") or [])
        self.order: list[str] = []
        self.skill: dict[str, dict] = {}
        for unit in course["units"]:
            for s in unit.get("skills") or []:
                self.order.append(s["id"])
                self.skill[s["id"]] = s
        self.pos = {sid: i for i, sid in enumerate(self.order)}
        self.introduces: dict[str, set[str]] = {}
        for sid in self.order:
            s = self.skill[sid]
            f = set(s.get("introduces") or [])
            if "verbs" in s and s["verbs"].get("tense"):
                f.add(f"tense:{s['verbs']['tense']}")
            self.introduces[sid] = f
        self.feature_skill: dict[str, str] = {}
        for sid in self.order:
            for f in sorted(self.introduces[sid]):
                self.feature_skill.setdefault(f, sid)
        self.allowed: dict[str, set[str]] = {}
        for sid in self.order:
            self.allowed[sid] = self.base | set().union(*(self.introduces[x] for x in self.closure(sid)))
        self.item_skill: dict[str, str] = {}
        for sid in self.order:
            for iid in resolved.get(sid, []):
                self.item_skill.setdefault(iid, sid)
        self.verb_skills: list[tuple[str, str, set[str]]] = [
            (sid, self.skill[sid]["verbs"]["tense"], set(resolved.get(sid, [])))
            for sid in self.order if "verbs" in self.skill[sid]]
        # skills training inflection tables (course.yaml `inflections`), in course order
        self.infl_skills: list[tuple[str, set[str], set[str]]] = [
            (sid, set(query.infl_tables(self.skill[sid])), set(resolved.get(sid, [])))
            for sid in self.order if query.infl_tables(self.skill[sid])]
        self.tagger = tagger

    def closure(self, sid: str) -> set[str]:
        seen = set()
        stack = [sid]
        while stack:
            x = stack.pop()
            if x in seen or x not in self.skill:
                continue
            seen.add(x)
            stack.extend(self.skill[x].get("requires") or [])
        return seen

    def grammar_skill(self, vid: str, tense: str) -> str | None:
        for sid, t, ids in self.verb_skills:
            if t == tense and vid in ids:
                return sid
        return None

    def infl_skill(self, iid: str, table: str) -> str | None:
        """The first skill training `table` of item `iid` (for the importer's sentence quotas)."""
        for sid, tables, ids in self.infl_skills:
            if table in tables and iid in ids:
                return sid
        return None

    def touched(self, toks: list[dict], feats: set[str]) -> set[str]:
        out = set()
        tagger = self.tagger
        for t in toks:
            lex = t.get("lex")
            if not lex:
                continue
            if lex in self.item_skill:
                out.add(self.item_skill[lex])
            if tagger and lex in tagger.verbs:
                for tense in tagger.token_tenses(t):
                    g = self.grammar_skill(lex, tense)
                    if g:
                        out.add(g)
        for f in feats - self.base:
            if f in self.feature_skill:
                out.add(self.feature_skill[f])
        return out

    def home(self, toks: list[dict], feats: set[str]) -> str | None:
        t = self.touched(toks, feats)
        return max(t, key=self.pos.__getitem__) if t else None

    def problems(self, toks: list[dict], feats: set[str]) -> list[str]:
        """Why a sentence with these features is not valid (empty = valid)."""
        out = []
        if not self.enforced:
            return out
        unknown = sorted(f for f in feats - self.base if f not in self.feature_skill)
        if unknown:
            out.append(f"features {unknown} are introduced by no skill")
        home = self.home(toks, feats)
        if home is not None:
            missing = sorted(feats - self.allowed[home] - set(unknown))
            if missing:
                out.append(f"home skill {home} does not allow {missing}")
        return out


def build(course: dict, items: list[dict], verbs: dict[str, dict]) -> tuple[FeatureTagger, SkillGraph]:
    resolved = {s["id"]: query.resolve(s, items, verbs, query.course_persons(course))
                for u in course["units"] for s in (u.get("skills") or [])}
    tagger = FeatureTagger(course, items, verbs)
    return tagger, SkillGraph(course, resolved, tagger)
