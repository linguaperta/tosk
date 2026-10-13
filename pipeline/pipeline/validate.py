"""Validator for a source pack. Returns a list of error strings (empty = valid).

Checks:
  * JSON Schema validation of course.yaml and of every JSONL line (schema/*.schema.json)
  * unique item ids, sentence ids, verb records (one per verb item, pointing at a verb item);
    ids agree with ids.tsv when that file exists
  * units/skills: unique ids, prerequisites exist and form a DAG (no cycles)
  * every skill has at least its minimum number of items; every grammar verb skill has enough
    verbs with complete tables (all persons) for its tense
  * every skill item (and item with a unit) has glosses for every declared translation language
  * article skills: every selected noun has an article from meta.articles
  * verb forms: tenses are declared (or non-finite), persons are declared (or '_'),
    stem + ending == form whenever both are set
  * sentences: tokens re-render the text exactly; every token lex exists; a token form exists in
    that verb's table
  * grammar skills have an English and a Dutch grammar note
  * grammar gating (features.py): every feature a sentence uses is introduced by its home skill,
    one of that skill's prerequisites (transitively) or the course's base set; base features and
    feature detectors are well-formed
"""
from __future__ import annotations

import json
from functools import lru_cache

from jsonschema import Draft202012Validator

from . import features, query
from .compile import note_texts
from .content import Pack
from .paths import SCHEMA_DIR

NON_FINITE = {"infinitive", "participle", "gerund"}
NOTE_LANGS = ("en", "nl")


@lru_cache(maxsize=None)
def schema_validator(name: str) -> Draft202012Validator:
    with open(SCHEMA_DIR / f"{name}.schema.json", encoding="utf-8") as f:
        schema = json.load(f)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def _schema_errors(name: str, rec, where: str) -> list[str]:
    v = schema_validator(name)
    out = []
    for e in sorted(v.iter_errors(rec), key=lambda e: list(e.absolute_path)):
        path = "/".join(str(p) for p in e.absolute_path)
        out.append(f"{where}: schema: {path or '<root>'}: {e.message}")
    return out


def find_cycle(graph: dict[str, list[str]]) -> list[str] | None:
    WHITE, GREY, BLACK = 0, 1, 2
    color = {n: WHITE for n in graph}
    stack: list[str] = []

    def visit(n: str) -> list[str] | None:
        color[n] = GREY
        stack.append(n)
        for m in graph.get(n, []):
            if m not in color:
                continue
            if color[m] == GREY:
                return stack[stack.index(m):] + [m]
            if color[m] == WHITE:
                cyc = visit(m)
                if cyc:
                    return cyc
        stack.pop()
        color[n] = BLACK
        return None

    for n in sorted(graph):
        if color[n] == WHITE:
            cyc = visit(n)
            if cyc:
                return cyc
    return None


def _form_value(val):
    return (val.get("form"), val.get("stem"), val.get("ending")) if isinstance(val, dict) else (val, None, None)


def validate(pack: Pack, check_notes: bool = True) -> list[str]:
    errors: list[str] = []
    c = pack.course
    code = c.get("id", "?")
    errors += _schema_errors("course", c, f"{code}/course.yaml")
    for kind, rel, n, rec in pack.raw_lines:
        name = {"lexicon": "lexicon", "verbs": "verbs", "sentences": "sentences"}[kind]
        errors += _schema_errors(name, rec, f"{code}/{rel}:{n}")
    if errors:
        return errors   # structural problems: later checks would only produce noise

    persons = list(c["persons"])
    tenses = list(c["tenses"])
    translations = list(c["translations"])

    # ---- ids
    items: dict[str, dict] = {}
    for it in pack.items:
        if it["id"] in items:
            errors.append(f"{code}: duplicate item id {it['id']}")
        items[it["id"]] = it
        if not it["id"].startswith(f"{code}:"):
            errors.append(f"{code}: item id {it['id']} lacks the course prefix '{code}:'")
    unit_ids = [u["id"] for u in c["units"]]
    for it in pack.items:
        if it.get("unit") and it["unit"] not in unit_ids:
            errors.append(f"{code}: item {it['id']} has unknown unit {it['unit']}")
    ids_tsv = pack.root / "ids.tsv"
    if ids_tsv.exists():
        known = {}
        for line in ids_tsv.read_text(encoding="utf-8").splitlines()[1:]:
            parts = line.split("\t")
            if len(parts) >= 3:
                known[parts[0]] = (parts[1], parts[2])
        for it in pack.items:
            k = known.get(it["id"])
            if k is None:
                errors.append(f"{code}: item {it['id']} is not recorded in ids.tsv")
            elif k != (it["lemma"], it["pos"]):
                errors.append(f"{code}: item {it['id']} is {it['lemma']}/{it['pos']} but ids.tsv says {k[0]}/{k[1]}")
    for vid, v in pack.verbs.items():
        if vid.startswith("__dup__"):
            errors.append(f"{code}: duplicate verb record {v.get('id')} ({vid[7:]})")
            continue
        it = items.get(vid)
        if it is None:
            errors.append(f"{code}: verb record {vid} has no lexicon item")
        elif it["pos"] != "verb":
            errors.append(f"{code}: verb record {vid} belongs to a {it['pos']}")
    sids = set()
    for s in pack.sentences:
        if s["id"] in sids:
            errors.append(f"{code}: duplicate sentence id {s['id']}")
        sids.add(s["id"])

    # ---- units and skills
    if len(set(unit_ids)) != len(unit_ids):
        errors.append(f"{code}: duplicate unit ids")
    skills = [s for _, _, _, s in pack.skills()]
    skill_ids = [s["id"] for s in skills]
    dup = {x for x in skill_ids if skill_ids.count(x) > 1}
    if dup:
        errors.append(f"{code}: duplicate skill ids {sorted(dup)}")
    graph = {}
    for s in skills:
        reqs = s.get("requires") or []
        for r in reqs:
            if r not in skill_ids:
                errors.append(f"{code}: skill {s['id']} requires unknown skill {r!r}")
            if r == s["id"]:
                errors.append(f"{code}: skill {s['id']} requires itself")
        graph[s["id"]] = list(reqs)
    cyc = find_cycle(graph)
    if cyc:
        errors.append(f"{code}: prerequisite cycle: {' -> '.join(cyc)}")
    for s in skills:
        if "verbs" in s and s["verbs"].get("tense") not in tenses:
            errors.append(f"{code}: skill {s['id']} trains undeclared tense {s['verbs'].get('tense')!r}")

    # ---- skill membership
    unit_index = {u: i for i, u in enumerate(unit_ids)}
    articles = set(c.get("articles") or [])
    for ui, unit, si, s in pack.skills():
        ids = query.resolve(s, pack.items, pack.verbs, persons)
        need = query.min_required(s)
        what = "verbs with complete tables for " + s["verbs"]["tense"] if "verbs" in s else "items"
        if len(ids) < need:
            errors.append(f"{code}: skill {s['id']} has {len(ids)} {what}, needs at least {need}")
        if "verbs" in s and s["verbs"].get("lemmas"):
            got = {items[i]["lemma"] for i in ids} | set(ids)
            missing = [str(x) for x in s["verbs"]["lemmas"] if str(x) not in got]
            if missing:
                errors.append(f"{code}: skill {s['id']}: no complete {s['verbs']['tense']} table for {missing}")
        for iid in ids:
            it = items[iid]
            miss = [l for l in translations if not it["tr"].get(l)]
            if miss:
                errors.append(f"{code}: skill {s['id']} item {iid} has no translation for {miss}")
            if not it.get("unit"):
                errors.append(f"{code}: skill {s['id']} item {iid} has no unit")
            elif unit_index.get(it["unit"], 99) > ui:
                errors.append(f"{code}: skill {s['id']} (unit {unit['id']}) uses {iid} introduced later in {it['unit']}")
            if s.get("facet") == "article" and articles and it.get("article") not in articles:
                errors.append(f"{code}: skill {s['id']} noun {iid} has article {it.get('article')!r} not in meta.articles")
        if check_notes and s["kind"] == "grammar":
            notes = note_texts(pack, s)
            for lang in NOTE_LANGS:
                if not (notes.get(lang) or "").strip():
                    errors.append(f"{code}: grammar skill {s['id']} has no '{lang}' grammar note")
    for it in pack.items:
        if it.get("unit"):
            miss = [l for l in translations if not it["tr"].get(l)]
            if miss:
                errors.append(f"{code}: item {it['id']} (unit {it['unit']}) has no translation for {miss}")

    # ---- verb tables
    valid_tenses = set(tenses) | NON_FINITE
    valid_persons = set(persons) | {"_"}
    table_keys: dict[str, set[str]] = {}
    for vid, v in pack.verbs.items():
        if vid.startswith("__dup__"):
            continue
        keys = set()
        for tense, table in (v.get("forms") or {}).items():
            if tense not in valid_tenses:
                errors.append(f"{code}: verb {vid} has undeclared tense {tense!r}")
            for person, val in table.items():
                if person not in valid_persons:
                    errors.append(f"{code}: verb {vid} {tense} has undeclared person {person!r}")
                if (tense in NON_FINITE) != (person == "_"):
                    errors.append(f"{code}: verb {vid} {tense}.{person}: non-finite tenses use person '_' only")
                form, stem, ending = _form_value(val)
                if (stem is None) != (ending is None):
                    errors.append(f"{code}: verb {vid} {tense}.{person}: stem and ending must both be set or both absent")
                elif stem is not None and stem + ending != form:
                    errors.append(f"{code}: verb {vid} {tense}.{person}: stem+ending {stem!r}+{ending!r} != form {form!r}")
                keys.add(f"{tense}.{person}")
        table_keys[vid] = keys

    # ---- sentences
    for s in pack.sentences:
        toks = s["tokens"]
        text = "".join(t.get("pre", "") + t["t"] for t in toks)
        if text != s["text"]:
            errors.append(f"{code}: sentence {s['id']}: tokens render {text!r}, not the text {s['text']!r}")
        for i, t in enumerate(toks):
            lex = t.get("lex")
            if lex and lex not in items:
                errors.append(f"{code}: sentence {s['id']} token {i} {t['t']!r}: unknown lex {lex}")
            form = t.get("form")
            if form and lex in items:
                if form not in table_keys.get(lex, set()):
                    errors.append(f"{code}: sentence {s['id']} token {i} {t['t']!r}: {lex} has no form {form}")
        if s.get("unit") and s["unit"] not in unit_ids:
            errors.append(f"{code}: sentence {s['id']} has unknown unit {s['unit']}")

    # ---- grammar gating
    try:
        tagger, graph = features.build(c, pack.items, pack.verbs)
    except ValueError as e:
        errors.append(str(e))
        return errors
    known_features = {f"tense:{t}" for t in tenses} | set(c.get("feature_detectors") or {})
    for f in sorted(set(c.get("base_features") or []) - known_features):
        errors.append(f"{code}: base feature {f!r} is no tense feature and has no detector")
    for sid in graph.order:
        for f in sorted(graph.introduces[sid] - known_features):
            errors.append(f"{code}: skill {sid} introduces {f!r}, which is no tense feature and has no detector")
    for s in pack.sentences:
        feats = tagger.tag(s["tokens"])
        for p in graph.problems(s["tokens"], feats):
            errors.append(f"{code}: sentence {s['id']} {s['text']!r}: {p}")
    return errors
