"""Per-skill content report: items, facets, verbs with complete tables, sentences touching the
skill, and (for verb grammar skills) how many sentences carry an aligned form of each verb in
the skill's tense — the material cloze / spot-the-error / transform exercises are built from.

Grammar gating: 'fit' counts the sentences touching the skill whose grammar features are all
allowed at the skill (features.py), i.e. the ones a learner who just reached it may see; 'easy'
are the fit ones with at most one word taught after the skill (or never); the per-verb counts are
fit sentences too. The summary lists how many sentences use each feature."""
from __future__ import annotations

import re

from collections import defaultdict
from statistics import median

from . import features, query
from .compile import facets_for
from .content import Pack


def build_report(pack: Pack) -> dict:
    persons = pack.course["persons"]
    by_lex: dict[str, set[str]] = defaultdict(set)
    by_form: dict[tuple[str, str], set[str]] = defaultdict(set)        # (verb, tense) -> sentence ids
    by_person: dict[tuple[str, str, str], int] = defaultdict(int)      # (verb, tense, person) -> count
    by_infl: dict[tuple[str, str], set[str]] = defaultdict(set)        # (item, 'infl:table.cell') -> sentence ids
    n_words = n_linked = n_formed = n_infl = 0
    for s in pack.sentences:
        for t in s["tokens"]:
            if t.get("is_word") is False:
                continue
            n_words += 1
            lex = t.get("lex")
            if not lex:
                continue
            n_linked += 1
            by_lex[lex].add(s["id"])
            form = t.get("form")
            if form and form.startswith("infl:"):
                n_infl += 1
                by_infl[(lex, form)].add(s["id"])
            elif form and "." in form:
                n_formed += 1
                tense, person = form.split(".", 1)
                by_form[(lex, tense)].add(s["id"])
                by_person[(lex, tense, person)] += 1
    lemma = {it["id"]: it["lemma"] for it in pack.items}
    tagger, graph = features.build(pack.course, pack.items, pack.verbs)
    feats = {s["id"]: tagger.tag(s["tokens"]) for s in pack.sentences}
    never = len(graph.order)
    known_at = {s["id"]: [graph.pos[graph.item_skill[t["lex"]]] if t.get("lex") in graph.item_skill else never
                          for t in s["tokens"]
                          if t.get("is_word", True) is not False and (t.get("lex") or not t["t"][:1].isupper())
                          and not t["t"][:1].isdigit()]
                for s in pack.sentences}
    feature_counts: dict[str, int] = defaultdict(int)
    for fs in feats.values():
        for f in fs:
            feature_counts[f] += 1
    skills = []
    items_by_id = {it["id"]: it for it in pack.items}
    tables_spec = pack.course.get("inflection_tables") or {}
    for _, unit, _, s in pack.skills():
        ids = query.resolve(s, pack.items, pack.verbs, persons)
        sents = set()
        for iid in ids:
            sents |= by_lex.get(iid, set())
        allowed = graph.allowed[s["id"]]
        fit = {x for x in sents if feats[x] <= allowed}
        here = graph.pos[s["id"]]
        easy = sum(1 for x in fit if sum(1 for k in known_at[x] if k > here) <= 1)
        row = {"skill": s["id"], "unit": unit["id"], "kind": s["kind"], "items": len(ids),
               "facets": len(facets_for(s, ids, items_by_id)), "sentences": len(sents), "fit": len(fit), "easy": easy,
               "introduces": sorted(graph.introduces[s["id"]])}
        if "verbs" in s:
            tense = s["verbs"]["tense"]
            row["tense"] = tense
            row["complete_verbs"] = sum(1 for i in ids if query.complete_tense(pack.verbs.get(i), tense, persons))
            per_verb = {lemma[i]: len([x for x in by_form.get((i, tense), ()) if feats[x] <= allowed]) for i in ids}
            counts = list(per_verb.values()) or [0]
            pairs = [(i, p) for i in ids for p in persons]
            row["coverage"] = {
                "verbs_with_sentence": sum(1 for v in counts if v > 0),
                "verbs_with_5": sum(1 for v in counts if v >= 5),
                "min": min(counts), "median": median(counts),
                "person_slots_covered": sum(1 for i, p in pairs if by_person.get((i, tense, p))),
                "person_slots": len(pairs),
                "per_verb": per_verb,
            }
        for table in query.infl_tables(s):
            spec = tables_spec.get(table) or {}
            cells = [c for c in spec.get("cells") or [] if spec.get("agreement") or c != spec.get("base")]
            inflecting = [i for i in ids if query.inflects(items_by_id[i], table)]
            per = [len({x for c in cells for x in by_infl.get((i, f"infl:{table}.{c}"), ()) if feats[x] <= allowed})
                   for i in inflecting] or [0]
            row.setdefault("infl", []).append(
                f"{table}: {len(inflecting)}/{len(ids)} inflect; fit sentences with an asked cell per item "
                f"min {min(per)}, median {median(per)}, >=3 {sum(1 for v in per if v >= 3)}")
        skills.append(row)
    return {
        "course": pack.code,
        "items": len(pack.items),
        "skill_items": len({i for _, _, _, s in pack.skills() for i in query.resolve(s, pack.items, pack.verbs, persons)}),
        "verbs": len(pack.verbs),
        "sentences": len(pack.sentences),
        "words": n_words, "linked_words": n_linked, "form_tokens": n_formed, "infl_tokens": n_infl,
        "skills": skills,
        "base_features": sorted(graph.base),
        "features": dict(sorted(feature_counts.items())),
        "sources": source_counts(pack),
        "stories": _story_counts(pack),
    }


def _story_counts(pack: Pack) -> dict:
    """Stories, sentences and questions per unit (stories.py)."""
    out: dict[str, list[int]] = {}
    for s in pack.stories:
        row = out.setdefault(str(s.get("unit")), [0, 0, 0])
        row[0] += 1
        row[1] += len(s.get("sentences") or [])
        row[2] += len(s.get("questions") or [])
    return out


def source_counts(pack: Pack) -> dict[str, dict[str, int]]:
    """Records per source id, from the optional `src` fields (kind -> source -> n). The id is
    the part before ':' / ' (' of each '; '-separated entry ('tatoeba:4821' -> tatoeba)."""
    out: dict[str, dict[str, int]] = {}

    def add(kind: str, src) -> None:
        if not src:
            return
        for part in str(src).split(";"):
            sid = re.split(r"[:(\s]", part.strip(), maxsplit=1)[0]
            if sid:
                d = out.setdefault(kind, {})
                d[sid] = d.get(sid, 0) + 1

    for it in pack.items:
        add("items", it.get("src"))
    for v in pack.verbs.values():
        add("verb tables", v.get("src"))
    for s in pack.sentences:
        add("sentences", s.get("src"))
    return out


def format_report(r: dict, verbose: bool = True) -> str:
    lines = [f"== {r['course']}: {r['items']} items ({r['skill_items']} in skills), {r['verbs']} verbs, "
             f"{r['sentences']} sentences; {r['linked_words']}/{r['words']} word tokens linked "
             f"({100 * r['linked_words'] / max(1, r['words']):.0f}%), {r['form_tokens']} verb-form tokens, "
             f"{r.get('infl_tokens', 0)} inflected-form tokens"]
    lines.append(f"base features {r['base_features']}; sentences per feature: "
                 + ", ".join(f"{k} {v}" for k, v in r["features"].items()))
    for kind, d in (r.get("sources") or {}).items():
        lines.append(f"{kind} per source: " + ", ".join(f"{k} {v}" for k, v in sorted(d.items(), key=lambda kv: -kv[1])))
    st = r.get("stories") or {}
    if st:
        lines.append(f"stories: {sum(v[0] for v in st.values())} ({sum(v[1] for v in st.values())} sentences, "
                     f"{sum(v[2] for v in st.values())} questions); per unit: "
                     + ", ".join(f"{u} {v[0]}" for u, v in st.items()))
    lines.append(f"{'skill':<24} {'unit':<4} {'kind':<7} {'items':>5} {'facets':>6} {'sents':>5} {'fit':>5} {'easy':>5}  "
                 "introduces / verb-form coverage (fit sentences)")
    for s in r["skills"]:
        cov = ""
        if "coverage" in s:
            c = s["coverage"]
            cov = (f"{s['tense']}: {s['complete_verbs']} complete tables; verbs with >=1 sentence "
                   f"{c['verbs_with_sentence']}/{s['items']}, >=5 {c['verbs_with_5']}/{s['items']}, "
                   f"min {c['min']}, median {c['median']}; person slots {c['person_slots_covered']}/{c['person_slots']}")
        if s.get("infl"):
            cov = (cov + "; " if cov else "") + "; ".join(s["infl"])
        intro = f"[{', '.join(s['introduces'])}] " if s["introduces"] else ""
        lines.append(f"{s['skill']:<24} {s['unit']:<4} {s['kind']:<7} {s['items']:>5} {s['facets']:>6} {s['sentences']:>5} "
                     f"{s['fit']:>5} {s['easy']:>5}  {intro}{cov}")
        if verbose and "coverage" in s:
            pv = s["coverage"]["per_verb"]
            lines.append("      " + ", ".join(f"{k} {v}" for k, v in pv.items()))
    return "\n".join(lines)
