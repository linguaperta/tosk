"""Thin spots in a course's sentence material (`python -m pipeline gaps it nl`).

A sentence is *easy* at a skill when its grammar features are all allowed there (features.py) and
at most one of its words is taught after the skill or never (the report's `easy` column; names and
numbers don't count). The gaps are:

* grammar slots: per verb skill, each (verb, person) of the skill's tense with fewer than
  SLOT_TARGET easy sentences showing that form (impersonal verbs: third persons only);
* vocabulary items: per item skill, each item with fewer than ITEM_TARGET easy sentences;
* skills with fewer than SKILL_TARGET easy sentences (UNIT1_TARGET for the first unit).

The generated sentences (sentences/gen-*.jsonl, generate.py) fill them; `--words SKILL` prints the
vocabulary a sentence for that skill may use.
"""
from __future__ import annotations

from collections import defaultdict
from statistics import median

from . import features, query
from .content import Pack

SLOT_TARGET = 8
ITEM_TARGET = 3
SKILL_TARGET = 40
UNIT1_TARGET = 150
# Verbs used only in the third person ('it happens'): their other person slots are not gaps.
IMPERSONAL = {"it": {"succedere"}, "nl": {"gebeuren"}, "es": {"ocurrir", "suceder", "llover", "nevar"}}


class Material:
    """Per-sentence features and the skill position at which each word becomes known."""

    def __init__(self, pack: Pack):
        self.pack = pack
        c = pack.course
        self.persons = list(c["persons"])
        self.resolved = {s["id"]: query.resolve(s, pack.items, pack.verbs, self.persons) for _, _, _, s in pack.skills()}
        self.tagger, self.graph = features.build(c, pack.items, pack.verbs)
        self.never = len(self.graph.order)
        self.feats: dict[str, set[str]] = {}
        self.known_at: dict[str, list[int]] = {}
        for s in pack.sentences:
            self.add(s)

    def word_positions(self, toks: list[dict]) -> list[int]:
        g = self.graph
        return [g.pos[g.item_skill[t["lex"]]] if t.get("lex") in g.item_skill else self.never
                for t in toks
                if t.get("is_word", True) is not False and (t.get("lex") or not t["t"][:1].isupper())
                and not t["t"][:1].isdigit()]

    def add(self, s: dict) -> None:
        self.feats[s["id"]] = self.tagger.tag(s["tokens"])
        self.known_at[s["id"]] = self.word_positions(s["tokens"])

    def later_words(self, sid: str, skill: str) -> int:
        here = self.graph.pos[skill]
        return sum(1 for k in self.known_at[sid] if k > here)

    def easy(self, sid: str, skill: str) -> bool:
        return self.feats[sid] <= self.graph.allowed[skill] and self.later_words(sid, skill) <= 1


def analyze(pack: Pack, mat: Material | None = None) -> dict:
    mat = mat or Material(pack)
    g = mat.graph
    by_lex: dict[str, set[str]] = defaultdict(set)
    by_cell: dict[tuple[str, str], set[str]] = defaultdict(set)   # (verb, 'tense.person') -> sentence ids
    for s in pack.sentences:
        for t in s["tokens"]:
            if t.get("lex"):
                by_lex[t["lex"]].add(s["id"])
                if t.get("form"):
                    by_cell[(t["lex"], t["form"])].add(s["id"])
    lemma = {it["id"]: it["lemma"] for it in pack.items}
    skills = []
    for ui, unit, _, sk in pack.skills():
        sid = sk["id"]
        ids = mat.resolved[sid]
        sents = set().union(*(by_lex.get(i, set()) for i in ids)) if ids else set()
        easy = {x for x in sents if mat.easy(x, sid)}
        row = {"skill": sid, "unit": unit["id"], "unit_index": ui, "kind": sk["kind"], "easy": len(easy),
               "target": UNIT1_TARGET if ui == 0 else SKILL_TARGET}
        if "verbs" in sk:
            tense = sk["verbs"]["tense"]
            row["tense"] = tense
            slots = {}
            third = {mat.persons[2], mat.persons[5]} if len(mat.persons) == 6 else set(mat.persons)
            for i in ids:
                for p in mat.persons:
                    if lemma[i] in IMPERSONAL.get(pack.code, ()) and p not in third:
                        continue
                    slots[(lemma[i], p)] = sum(1 for x in by_cell.get((i, f"{tense}.{p}"), ()) if mat.easy(x, sid))
            row["slots"] = slots
        else:
            row["items"] = {lemma[i]: sum(1 for x in by_lex.get(i, ()) if mat.easy(x, sid)) for i in ids}
        skills.append(row)
    return {"course": pack.code, "skills": skills}


def summary(r: dict) -> dict:
    """Counts for the report: easy sentences per skill (min/median), slots and items below target."""
    easy = [s["easy"] for s in r["skills"]]
    slots = [v for s in r["skills"] for v in (s.get("slots") or {}).values()]
    items = [v for s in r["skills"] if s["kind"] == "vocab" for v in (s.get("items") or {}).values()]
    return {
        "easy_min": min(easy), "easy_median": median(easy),
        "skills_below": sum(1 for s in r["skills"] if s["easy"] < s["target"]),
        "slots": len(slots), "slots_below": sum(1 for v in slots if v < SLOT_TARGET),
        "slot_deficit": sum(max(0, SLOT_TARGET - v) for v in slots),
        "vocab_items": len(items), "items_below": sum(1 for v in items if v < ITEM_TARGET),
        "item_deficit": sum(max(0, ITEM_TARGET - v) for v in items),
    }


def format_gaps(r: dict, verbose: bool = True) -> str:
    sm = summary(r)
    lines = [f"== {r['course']} gaps: easy sentences per skill min {sm['easy_min']}, median {sm['easy_median']}; "
             f"skills below target {sm['skills_below']}; grammar slots below {SLOT_TARGET}: {sm['slots_below']}/{sm['slots']} "
             f"(deficit {sm['slot_deficit']}); vocab items below {ITEM_TARGET}: {sm['items_below']}/{sm['vocab_items']} "
             f"(deficit {sm['item_deficit']})"]
    for s in r["skills"]:
        flag = " <" if s["easy"] < s["target"] else ""
        line = f"{s['skill']:<24} {s['unit']:<4} easy {s['easy']:>5}/{s['target']}{flag}"
        if "slots" in s:
            low = {k: v for k, v in s["slots"].items() if v < SLOT_TARGET}
            line += f"  slots below {SLOT_TARGET}: {len(low)}/{len(s['slots'])}"
            lines.append(line)
            if verbose and low:
                lines.append("      " + ", ".join(f"{v}.{p} {n}" for (v, p), n in sorted(low.items())))
        else:
            low = {k: v for k, v in s["items"].items() if v < ITEM_TARGET}
            line += f"  items below {ITEM_TARGET}: {len(low)}/{len(s['items'])}"
            lines.append(line)
            if verbose and low:
                lines.append("      " + ", ".join(f"{k} {v}" for k, v in sorted(low.items())))
    return "\n".join(lines)


def skill_words(pack: Pack, skill: str, mat: Material | None = None) -> dict[str, list[str]]:
    """Lemmas a learner at `skill` knows, grouped by the skill that introduces them."""
    mat = mat or Material(pack)
    here = mat.graph.pos[skill]
    lemma = {it["id"]: it["lemma"] for it in pack.items}
    out: dict[str, list[str]] = {}
    for sid in mat.graph.order[: here + 1]:
        out[sid] = [lemma[i] for i in mat.resolved[sid] if mat.graph.item_skill.get(i) == sid]
    return out
