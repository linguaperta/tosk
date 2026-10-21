"""Built-in topic trees (pack format 1.2, docs/pack-format.md "Topics", docs/extensions.md).

A topic is a themed side tree of a course: its own units and skills, drawn as its own map and
attached to the main tree at its **anchor**, the topic's entry point: the last main-tree skill its
first skill requires. Later skills of the topic may require later main-tree skills (*late
requirements*); such a skill stays locked, with a note, until those are started. These helpers
resolve the anchor and the late requirements and check the cross-tree rules; compile.py and
validate.py use them.
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


def first_skill(topic: dict) -> dict | None:
    """The topic's first skill (its first unit's first skill): where a learner enters the topic."""
    for u in topic.get("units") or []:
        for s in u.get("skills") or []:
            return s
    return None


def entry_requirements(course: dict, topic: dict) -> list[str]:
    """The main-tree skills the topic's first skill requires directly, in course order."""
    first = first_skill(topic)
    trees = skill_topics(course)
    wanted = {r for r in (first or {}).get("requires") or [] if r in trees and trees[r] is None}
    return [s["id"] for s in main_skills(course) if s["id"] in wanted]


def default_anchor(course: dict, topic: dict) -> str | None:
    """The topic's entry point: the deepest main-tree skill its first skill requires (ties: the
    later one in course order); None when the first skill requires no main-tree skill. Later
    skills of the topic may require later main-tree skills (`late_requirements`)."""
    reqs = entry_requirements(course, topic)
    if not reqs:
        return None
    depth = main_depths(course)
    order = {s["id"]: i for i, s in enumerate(main_skills(course))}
    return max(reqs, key=lambda sid: (depth.get(sid, 0), order[sid]))


def anchor_of(course: dict, topic: dict) -> str | None:
    """The topic's anchor: `anchor` from course.yaml, else the default."""
    return topic.get("anchor") or default_anchor(course, topic)


def _after_anchor(course: dict, anchor: str, reqs: list[str]) -> list[str]:
    """The requirements in [reqs] that come after [anchor]: neither the anchor, nor one of its
    prerequisites, nor a sibling no deeper than it (kitchen requires colours and possessives)."""
    before = closure(course, anchor)
    depth = main_depths(course)
    return [r for r in reqs if r not in before and depth.get(r, 0) > depth.get(anchor, 0)]


def late_requirements(course: dict, topic: dict) -> dict[str, list[str]]:
    """Skill id -> the main-tree skills it requires that come after the topic's anchor (in course
    order), for the topic's skills that have any. The app keeps such a skill locked until they are
    started and says so ("needs Condizionale · unit 12")."""
    anchor = anchor_of(course, topic)
    trees = skill_topics(course)
    if anchor is None or anchor not in trees or trees[anchor] is not None:
        return {}
    order = {s["id"]: i for i, s in enumerate(main_skills(course))}
    out: dict[str, list[str]] = {}
    for u in topic.get("units") or []:
        for s in u.get("skills") or []:
            reqs = [r for r in s.get("requires") or [] if r in trees and trees[r] is None]
            late = _after_anchor(course, anchor, reqs)
            if late:
                out[s["id"]] = sorted(late, key=order.__getitem__)
    return out


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
    main-tree requirements of the topic's first skill (later skills may require later main-tree
    skills); main-tree skills require no topic skill; a topic skill requires only main-tree skills
    and skills of its own topic. (Unique skill and unit ids over every tree and the absence of
    cycles are checked with the other skills.)"""
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
            errors.append(f"{where}: no anchor: give `anchor` (a main-tree skill) or let its first skill require one")
            continue
        if anchor not in trees:
            errors.append(f"{where}: anchor {anchor!r} is no skill of the course")
            continue
        if trees[anchor] is not None:
            errors.append(f"{where}: anchor {anchor!r} is a skill of topic {trees[anchor]!r}, not of the main tree")
            continue
        # The anchor is where the topic starts: the last main-tree skill its first skill needs.
        # Every other requirement of the first skill is one of the anchor's prerequisites or a
        # sibling no deeper than it (kitchen requires colours and possessives). Later skills may
        # require later main-tree skills (late requirements: locked, with a note, until started).
        first = first_skill(t)
        later = _after_anchor(course, anchor, entry_requirements(course, t))
        if later:
            errors.append(f"{where}: its first skill {first['id']} requires main-tree skills {later} that "
                          f"come after its anchor {anchor!r}; the anchor is where the topic starts, the "
                          f"last main-tree skill its first skill needs")
    return errors
