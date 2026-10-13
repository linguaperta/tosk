"""Compile a source pack (course.yaml + JSONL + grammar notes) into course.sqlite.

The schema is created by executing schema/course_db.sql verbatim, so the output always matches
the contract the app reads. Output is deterministic apart from meta.built_at: rows are inserted
in a fixed order and the file is VACUUMed at the end.
"""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from . import query
from .content import Pack
from .paths import DDL_PATH

COURSE_DB_SCHEMA_VERSION = 1

SOURCE_ATTRIBUTION = {
    "wiktionary": "Wiktionary (en.wiktionary.org), via kaikki.org/wiktextract — CC BY-SA 4.0 (and GFDL)",
    "nlwiktionary": "Wiktionary (nl.wiktionary.org), via kaikki.org/wiktextract — CC BY-SA 4.0",
    "wiktionary-pivot": "Wiktionary translation tables (en.wiktionary.org), via kaikki.org — CC BY-SA 4.0",
    "tatoeba": "Tatoeba (tatoeba.org) example sentences — CC BY 2.0 FR",
    "claude": "Glosses, grammar notes and course structure written with Claude (Anthropic) — CC BY-SA 4.0",
    "frequency": "Word frequencies: hermitdave/FrequencyWords (OpenSubtitles 2018) — CC BY-SA 4.0",
}


def _j(v) -> str:
    return json.dumps(v, ensure_ascii=False, separators=(",", ":"))


def attribution_text(pack: Pack) -> str:
    used = {"frequency", "claude"}
    for it in pack.items:
        used |= set((it.get("tr_src") or {}).values())
    if pack.sentences:
        used.add("tatoeba")
    lines = [f"tosk course '{pack.code}' {pack.course.get('version')} — content licensed CC BY-SA 4.0.",
             "Sources:"]
    for key in ("wiktionary", "nlwiktionary", "wiktionary-pivot", "tatoeba", "frequency", "claude"):
        if key in used:
            lines.append(f"- {SOURCE_ATTRIBUTION[key]}")
    lines.append("Sentence ids s:N refer to https://tatoeba.org/sentences/show/N (authors listed there).")
    lines.append("Full details: ATTRIBUTION.md in the tosk-data repository.")
    return "\n".join(lines)


def _tr_json(tr: dict, order: list[str]) -> str:
    keys = [k for k in order if k in tr] + sorted(k for k in tr if k not in order)
    return _j({k: tr[k] for k in keys})


def skill_query_json(skill: dict) -> str:
    kind, q = query.skill_query(skill)
    out = {kind: q}
    if skill.get("facet"):
        out["facet"] = skill["facet"]
    return _j(out)


def resolve_all(pack: Pack) -> dict[str, list[str]]:
    persons = pack.course["persons"]
    return {skill["id"]: query.resolve(skill, pack.items, pack.verbs, persons) for _, _, _, skill in pack.skills()}


def facets_for(skill: dict, item_ids: list[str]) -> list[tuple[str, str, str, str | None, int]]:
    """(facet_id, item_id, kind, tense, ord) per the ARCHITECTURE facet table."""
    out = []
    if "verbs" in skill:
        tense = skill["verbs"]["tense"]
        for i, iid in enumerate(item_ids):
            out.append((f"{iid}#form:{tense}", iid, "form", tense, i))
    elif skill.get("facet") == "article":
        for i, iid in enumerate(item_ids):
            out.append((f"{iid}#article", iid, "article", None, i))
    else:
        for i, iid in enumerate(item_ids):
            out.append((f"{iid}#rec", iid, "rec", None, i))
            out.append((f"{iid}#prod", iid, "prod", None, i))
    return out


def note_texts(pack: Pack, skill: dict) -> dict[str, str]:
    notes = dict(pack.notes.get(skill["id"], {}))
    if skill.get("note"):
        p = pack.root / skill["note"]
        if p.exists():
            notes["en"] = p.read_text(encoding="utf-8")
            nl = p.with_name(p.name[:-3] + ".nl.md") if p.name.endswith(".md") else None
            if nl and nl.exists():
                notes["nl"] = nl.read_text(encoding="utf-8")
    return notes


def compile_pack(pack: Pack, out: Path, built_at: str | None = None) -> dict:
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    c = pack.course
    order = list(c["translations"])
    con = sqlite3.connect(out)
    try:
        con.executescript(DDL_PATH.read_text(encoding="utf-8"))
        built_at = built_at or datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        meta = {
            "schema_version": str(COURSE_DB_SCHEMA_VERSION),
            "course_id": c["id"],
            "version": c["version"],
            "title": _j(c["title"]),
            "target": c["target"],
            "translations": _j(c["translations"]),
            "persons": _j(c["persons"]),
            "tenses": _j(c["tenses"]),
            "tense_labels": _j(c.get("tense_labels") or {}),
            "articles": _j(c.get("articles") or []),
            "unverified": "1" if c.get("unverified") else "0",
            "built_at": built_at,
            "attribution": attribution_text(pack),
        }
        if c.get("person_labels"):
            meta["person_labels"] = _j(c["person_labels"])
        if c.get("description"):
            meta["description"] = _j(c["description"])
        con.executemany("INSERT INTO meta(key, value) VALUES (?, ?)", sorted(meta.items()))

        for ui, unit in enumerate(c["units"]):
            con.execute("INSERT INTO units(id, ord, title) VALUES (?, ?, ?)", (unit["id"], ui, _j(unit["title"])))
        for ui, unit, si, skill in pack.skills():
            pos = skill.get("pos") or {}
            con.execute(
                "INSERT INTO skills(id, unit_id, ord, kind, title, icon, tense, exercises, pos_x, pos_y, query)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                (skill["id"], unit["id"], si, skill["kind"], _j(skill["title"]), skill.get("icon"),
                 (skill.get("verbs") or {}).get("tense"), _j(skill.get("exercises") or []),
                 pos.get("x"), pos.get("y"), skill_query_json(skill)))
        for _, _, _, skill in pack.skills():
            for r in skill.get("requires") or []:
                con.execute("INSERT INTO skill_requires(skill_id, requires_id) VALUES (?, ?)", (skill["id"], r))
            for lang, md in sorted(note_texts(pack, skill).items()):
                con.execute("INSERT INTO notes(skill_id, lang, md) VALUES (?, ?, ?)", (skill["id"], lang, md))

        for it in sorted(pack.items, key=lambda r: r["id"]):
            con.execute(
                "INSERT INTO items(id, pos, lemma, article, gender, plural, freq, unit_id, tr, variants, tags)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                (it["id"], it["pos"], it["lemma"], it.get("article"), it.get("gender"), it.get("plural"),
                 it.get("freq"), it.get("unit"), _tr_json(it["tr"], order), _j(it.get("variants") or []),
                 _j(it.get("tags") or [])))
            for tag in sorted(set(it.get("tags") or [])):
                con.execute("INSERT INTO item_tags(item_id, tag) VALUES (?, ?)", (it["id"], tag))

        tense_order = ["infinitive", "participle", "gerund"] + list(c["tenses"])
        person_order = list(c["persons"]) + ["_"]
        n_forms = 0
        for vid in sorted(pack.verbs):
            v = pack.verbs[vid]
            con.execute("INSERT INTO verbs(item_id, class, stem, irregular, auxiliary) VALUES (?,?,?,?,?)",
                        (vid, v.get("class"), v.get("stem"), 1 if v.get("irregular") else 0, v.get("auxiliary")))
            forms = v.get("forms") or {}
            for tense in sorted(forms, key=lambda t: (tense_order.index(t) if t in tense_order else 99, t)):
                table = forms[tense]
                for person in sorted(table, key=lambda p: (person_order.index(p) if p in person_order else 99, p)):
                    val = table[person]
                    if isinstance(val, str):
                        val = {"form": val}
                    con.execute(
                        "INSERT INTO verb_forms(item_id, tense, person, form, stem, ending, alts) VALUES (?,?,?,?,?,?,?)",
                        (vid, tense, person, val["form"], val.get("stem"), val.get("ending"), _j(val.get("alts") or [])))
                    n_forms += 1

        n_tokens = 0
        for s in sorted(pack.sentences, key=lambda r: r["id"]):
            con.execute("INSERT INTO sentences(id, text, tr, src, unit_id) VALUES (?,?,?,?,?)",
                        (s["id"], s["text"], _tr_json(s["tr"], order), s.get("src"), s.get("unit")))
            for i, t in enumerate(s["tokens"]):
                con.execute("INSERT INTO tokens(sentence_id, idx, t, pre, is_word, lex, form) VALUES (?,?,?,?,?,?,?)",
                            (s["id"], i, t["t"], t.get("pre", ""), 0 if t.get("is_word") is False else 1,
                             t.get("lex"), t.get("form")))
                n_tokens += 1

        resolved = resolve_all(pack)
        n_facets = 0
        for _, _, _, skill in pack.skills():
            ids = resolved[skill["id"]]
            for i, iid in enumerate(ids):
                con.execute("INSERT INTO skill_items(skill_id, item_id, ord) VALUES (?,?,?)", (skill["id"], iid, i))
            for fid, iid, kind, tense, o in facets_for(skill, ids):
                con.execute("INSERT INTO skill_facets(skill_id, facet_id, item_id, kind, tense, ord) VALUES (?,?,?,?,?,?)",
                            (skill["id"], fid, iid, kind, tense, o))
                n_facets += 1
        con.commit()
        con.execute("VACUUM")
    finally:
        con.close()
    return {"items": len(pack.items), "verbs": len(pack.verbs), "verb_forms": n_forms,
            "sentences": len(pack.sentences), "tokens": n_tokens, "facets": n_facets, "built_at": built_at}
