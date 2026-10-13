"""Grammar features of sentences and skills (docs/ARCHITECTURE.md, "Grammar gating").

A learner should not meet a grammar construct before starting the skill that teaches it. The
pipeline therefore tags every sentence with the features its tokens show, and every skill with
the features it introduces:

* ``tense:{T}`` for every verb token in tense T, read from the token alignment. A compound form
  (``ho mangiato``, ``heb gegeten``) tags its compound tense on the participle; its auxiliary is
  not tagged as present. A participle without an auxiliary tags the compound tense too (passive or
  adjectival use is gated with the perfect). A verb token without a ``form`` is looked up by its
  spelling: only a spelling that is no present form and no infinitive tags a tense (``kwam`` in
  ``Kwam je?``).
* construct features declared per course in ``course.yaml`` under ``feature_detectors``
  (``{feature: {type: ..., ...}}``):

  ``compound_aux``     ``{aux: essere}``  a compound form whose auxiliary is that verb
  ``modal_infinitive`` ``{verbs: [...], infinitive_pattern: regex}``  a finite form of one of the
                       verbs plus a later infinitive (an aligned ``infinitive._`` token, a verb token
                       spelled like its infinitive, or an unaligned word matching the pattern)
  ``words``            ``{words: [...]}``  any of these spellings (lower case)
  ``irregular_tense``  ``{tense: T}``  a form of tense T of a verb with T in its ``irregular_in``
  ``separable``        ``{particles: [...]}``  a separable verb (one whose present table has
                       two-word forms, ``sta op``) in any form, or a finite verb V with a
                       clause-final particle P such that P+V is a separable verb (``Hij komt terug.``)

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

from . import query
from .lang import get_lang

DETECTOR_TYPES = {"compound_aux", "modal_infinitive", "words", "irregular_tense", "separable"}
_APOS = str.maketrans({"’": "'", "‘": "'"})
_CLAUSE_PUNCT = {",", ".", "?", "!", ";", ":", "...", "…", "—", "–", "(", ")", '"', "«", "»", "“", "”"}


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
        self.lang = get_lang(self.code)
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
                spec["_words"] = {_norm(w) for w in spec.get("words") or []}
            if kind == "modal_infinitive":
                spec["_ids"] = {lemma_verb[v] for v in spec.get("verbs") or [] if v in lemma_verb}
                pat = spec.get("infinitive_pattern")
                spec["_re"] = re.compile(pat) if pat else None
            if kind == "separable":
                spec["_particles"] = {_norm(p) for p in spec.get("particles") or []}
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
                if self.first_compound:
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
            if rx and not lex and rx.fullmatch(_norm(t["t"])):
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
            if self._detect(kind, spec, toks, parts, part_aux, aux_pos, tenses_at):
                feats.add(name)
        return feats

    def _detect(self, kind, spec, toks, parts, part_aux, aux_pos, tenses_at) -> bool:
        if kind == "words":
            return any(_is_word(t) and _norm(t["t"]) in spec["_words"] for t in toks)
        if kind == "compound_aux":
            want = spec.get("aux")
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
            for i, t in enumerate(toks):
                if t.get("lex") in spec["_ids"] and i not in aux_pos and _is_word(t):
                    f = t.get("form") or ""
                    if f.startswith(("infinitive", "participle", "gerund")):
                        continue
                    if self._infinitive_after(toks, i, spec):
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
    resolved = {s["id"]: query.resolve(s, items, verbs, course["persons"])
                for u in course["units"] for s in (u.get("skills") or [])}
    tagger = FeatureTagger(course, items, verbs)
    return tagger, SkillGraph(course, resolved, tagger)
