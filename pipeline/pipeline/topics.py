"""Built-in topic trees (pack format 1.2, docs/pack-format.md "Topics", docs/extensions.md).

A topic is a themed side tree of a course: its own units and skills, drawn as its own map and
attached to the main tree at its **anchor**, the last main-tree skill its skills require. These
helpers resolve the anchor and check the cross-tree rules; compile.py and validate.py use them.
"""
from __future__ import annotations

from .content import skill_topics


def main_skills(course: dict) -> list[dict]:
    """The main tree's skills in course order."""
    return [s for u in course.get("units") or [] for s in u.get("skills") or []]


def main_depths(course: dict) -> dict[str, int]:
    """Longest prerequisite path to each main-tree skill (roots are 0; unknown prerequisites and
    cycles are skipped, the validator reports those)."""
    skills = {s["id"]: s for s in main_skills(course)}
    depth: dict[str, int] = {}
    visiting: set[str] = set()

    def visit(sid: str) -> int:
        if sid in depth:
            return depth[sid]
        visiting.add(sid)
        d = 0
        for r in skills[sid].get("requires") or []:
            if r in skills and r not in visiting and r != sid:
                d = max(d, visit(r) + 1)
        visiting.discard(sid)
        depth[sid] = d
        return d

    for sid in skills:
        visit(sid)
    return depth


def main_requirements(course: dict, topic: dict) -> list[str]:
    """The main-tree skills the topic's skills require directly, in course order."""
    trees = skill_topics(course)
    wanted = {r for u in topic.get("units") or [] for s in u.get("skills") or []
              for r in s.get("requires") or [] if r in trees and trees[r] is None}
    return [s["id"] for s in main_skills(course) if s["id"] in wanted]


def default_anchor(course: dict, topic: dict) -> str | None:
    """The deepest main-tree skill among the topic's requirements (ties: the later one in course
    order); None when the topic requires no main-tree skill."""
    reqs = main_requirements(course, topic)
    if not reqs:
        return None
    depth = main_depths(course)
    order = {s["id"]: i for i, s in enumerate(main_skills(course))}
    return max(reqs, key=lambda sid: (depth.get(sid, 0), order[sid]))


def anchor_of(course: dict, topic: dict) -> str | None:
    """The topic's anchor: `anchor` from course.yaml, else the default."""
    return topic.get("anchor") or default_anchor(course, topic)


def closure(course: dict, sid: str) -> set[str]:
    """sid and its prerequisites, transitively (over every tree)."""
    req = {s["id"]: s.get("requires") or [] for u in _units(course) for s in u.get("skills") or []}
    seen: set[str] = set()
    stack = [sid]
    while stack:
        x = stack.pop()
        if x in seen or x not in req:
            continue
        seen.add(x)
        stack.extend(req[x])
    return seen


def _units(course: dict):
    yield from course.get("units") or []
    for t in course.get("topics") or []:
        yield from t.get("units") or []


def validate_topics(course: dict) -> list[str]:
    """The cross-tree rules: topic ids unique; the anchor is a main-tree skill and the last of the
    topic's main-tree requirements; main-tree skills require no topic skill; a topic skill requires
    only main-tree skills and skills of its own topic. (Unique skill and unit ids over every tree
    and the absence of cycles are checked with the other skills.)"""
    code = course.get("id", "?")
    errors: list[str] = []
    topics = course.get("topics") or []
    if not topics:
        return errors
    trees = skill_topics(course)
    ids = [t["id"] for t in topics]
    for d in sorted({x for x in ids if ids.count(x) > 1}):
        errors.append(f"{code}: duplicate topic id {d!r}")
    for s in main_skills(course):
        for r in s.get("requires") or []:
            if trees.get(r) is not None:
                errors.append(f"{code}: main-tree skill {s['id']} requires {r!r} of topic {trees[r]!r}; "
                              f"the main tree cannot depend on a topic")
    for t in topics:
        where = f"{code}: topic {t['id']}"
        for u in t.get("units") or []:
            for s in u.get("skills") or []:
                for r in s.get("requires") or []:
                    other = trees.get(r, "?")
                    if other not in (None, "?", t["id"]):
                        errors.append(f"{where}: skill {s['id']} requires {r!r} of another topic {other!r}")
        anchor = anchor_of(course, t)
        if anchor is None:
            errors.append(f"{where}: no anchor: give `anchor` (a main-tree skill) or let a skill require one")
            continue
        if anchor not in trees:
            errors.append(f"{where}: anchor {anchor!r} is no skill of the course")
            continue
        if trees[anchor] is not None:
            errors.append(f"{where}: anchor {anchor!r} is a skill of topic {trees[anchor]!r}, not of the main tree")
            continue
        # The anchor is the last main-tree skill the topic needs: every other requirement is one of
        # its prerequisites or a sibling no deeper than it (kitchen requires colours and possessives).
        before = closure(course, anchor)
        depth = main_depths(course)
        later = [r for r in main_requirements(course, t)
                 if r not in before and depth.get(r, 0) > depth.get(anchor, 0)]
        if later:
            errors.append(f"{where}: requires main-tree skills {later} that come after its anchor "
                          f"{anchor!r}; the anchor must be the last main-tree skill the topic needs")
    return errors
