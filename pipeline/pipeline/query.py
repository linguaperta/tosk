"""Skill selection queries from course.yaml, resolved against lexicon + verb records.

Shared by the importer (to decide which unit introduces an item) and the compiler (to fill
skill_items / skill_facets), so both always agree.

items query (vocab skills, and grammar skills with `facet: article`):
    tags: [a, b]        item has any of these tags
    pos: noun | [..]    part of speech
    lemmas: [..]        explicit lemmas or ids
    exclude: [..]       lemmas or ids to leave out
    top: N              keep the N most frequent
  With `facet: article` only items with a non-null article qualify.

verbs query (grammar skills):
    tense: T            required; the verb must have a complete table for T (all persons)
    class: c | [..]     verb class ('are', 'ere', 'ire', 'isc', 'weak', 'strong', ...)
    tags: [a, b]        verb item has any of these tags
    regular: bool       true: forms in T follow the regular pattern (T not in irregular_in); false: they don't
    aux: avere|essere|hebben|zijn   the verb's primary (first-listed) perfect auxiliary
    lemmas, exclude, top as above
    min: N              (validator) minimum verbs with complete tables; default min(15, top) or len(lemmas)
"""
from __future__ import annotations

from typing import Any

DEFAULT_MIN_VERBS = 15
DEFAULT_MIN_ITEMS = 5


def _as_list(v: Any) -> list:
    if v is None:
        return []
    return list(v) if isinstance(v, (list, tuple)) else [v]


def _freq_key(item: dict) -> tuple:
    f = item.get("freq")
    return (f is None, f if f is not None else 0, item["id"])


def _match_name(item: dict, names: list[str]) -> bool:
    return item["id"] in names or item["lemma"] in names


def complete_tense(verb: dict | None, tense: str, persons: list[str]) -> bool:
    if not verb:
        return False
    t = (verb.get("forms") or {}).get(tense) or {}
    for p in persons:
        v = t.get(p)
        form = v.get("form") if isinstance(v, dict) else v
        if not form:
            return False
    return True


def skill_query(skill: dict) -> tuple[str, dict]:
    if "verbs" in skill:
        return "verbs", dict(skill["verbs"] or {})
    return "items", dict(skill.get("items") or {})


def resolve(skill: dict, items: list[dict], verbs: dict[str, dict], persons: list[str]) -> list[str]:
    """Item ids selected by a skill, in introduction order (by frequency rank, then id)."""
    kind, q = skill_query(skill)
    tags = set(_as_list(q.get("tags")))
    pos = _as_list(q.get("pos"))
    lemmas = [str(x) for x in _as_list(q.get("lemmas"))]
    exclude = [str(x) for x in _as_list(q.get("exclude"))]
    out = []
    for it in items:
        if tags and not tags & set(it.get("tags") or []):
            continue
        if pos and it["pos"] not in pos:
            continue
        if lemmas and not _match_name(it, lemmas):
            continue
        if exclude and _match_name(it, exclude):
            continue
        if kind == "items":
            if skill.get("facet") == "article" and not it.get("article"):
                continue
        else:
            if it["pos"] != "verb":
                continue
            v = verbs.get(it["id"])
            tense = q.get("tense")
            if not complete_tense(v, tense, persons):
                continue
            classes = _as_list(q.get("class"))
            if classes and v.get("class") not in classes:
                continue
            if "regular" in q:
                irregular = tense in (v.get("irregular_in") or [])
                if bool(q["regular"]) == irregular:
                    continue
            if q.get("aux") and q["aux"] != (v.get("auxiliary") or "").split("|")[0]:
                continue
        out.append(it)
    out.sort(key=_freq_key)
    if lemmas and not q.get("top"):
        # explicit lists keep the author's order
        order = {name: i for i, name in enumerate(lemmas)}
        out.sort(key=lambda it: order.get(it["id"], order.get(it["lemma"], 1 << 30)))
    top = q.get("top")
    if top:
        out = out[: int(top)]
    return [it["id"] for it in out]


def min_required(skill: dict) -> int:
    kind, q = skill_query(skill)
    if q.get("min") is not None:
        return int(q["min"])
    if kind == "verbs":
        if q.get("lemmas"):
            return len(_as_list(q["lemmas"]))
        return min(DEFAULT_MIN_VERBS, int(q.get("top") or DEFAULT_MIN_VERBS))
    return min(DEFAULT_MIN_ITEMS, int(q.get("top") or DEFAULT_MIN_ITEMS))
