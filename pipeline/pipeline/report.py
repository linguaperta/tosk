"""Per-skill content report: items, facets, verbs with complete tables, sentences touching the
skill, and (for verb grammar skills) how many sentences carry an aligned form of each verb in
the skill's tense — the material cloze / spot-the-error / transform exercises are built from."""
from __future__ import annotations

from collections import defaultdict
from statistics import median

from . import query
from .compile import facets_for
from .content import Pack


def build_report(pack: Pack) -> dict:
    persons = pack.course["persons"]
    by_lex: dict[str, set[str]] = defaultdict(set)
    by_form: dict[tuple[str, str], set[str]] = defaultdict(set)        # (verb, tense) -> sentence ids
    by_person: dict[tuple[str, str, str], int] = defaultdict(int)      # (verb, tense, person) -> count
    n_words = n_linked = n_formed = 0
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
            if form and "." in form:
                n_formed += 1
                tense, person = form.split(".", 1)
                by_form[(lex, tense)].add(s["id"])
                by_person[(lex, tense, person)] += 1
    lemma = {it["id"]: it["lemma"] for it in pack.items}
    skills = []
    for _, unit, _, s in pack.skills():
        ids = query.resolve(s, pack.items, pack.verbs, persons)
        sents = set()
        for iid in ids:
            sents |= by_lex.get(iid, set())
        row = {"skill": s["id"], "unit": unit["id"], "kind": s["kind"], "items": len(ids),
               "facets": len(facets_for(s, ids)), "sentences": len(sents)}
        if "verbs" in s:
            tense = s["verbs"]["tense"]
            row["tense"] = tense
            row["complete_verbs"] = sum(1 for i in ids if query.complete_tense(pack.verbs.get(i), tense, persons))
            per_verb = {lemma[i]: len(by_form.get((i, tense), ())) for i in ids}
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
        skills.append(row)
    return {
        "course": pack.code,
        "items": len(pack.items),
        "skill_items": len({i for _, _, _, s in pack.skills() for i in query.resolve(s, pack.items, pack.verbs, persons)}),
        "verbs": len(pack.verbs),
        "sentences": len(pack.sentences),
        "words": n_words, "linked_words": n_linked, "form_tokens": n_formed,
        "skills": skills,
    }


def format_report(r: dict, verbose: bool = True) -> str:
    lines = [f"== {r['course']}: {r['items']} items ({r['skill_items']} in skills), {r['verbs']} verbs, "
             f"{r['sentences']} sentences; {r['linked_words']}/{r['words']} word tokens linked "
             f"({100 * r['linked_words'] / max(1, r['words']):.0f}%), {r['form_tokens']} verb-form tokens"]
    lines.append(f"{'skill':<20} {'unit':<4} {'kind':<7} {'items':>5} {'facets':>6} {'sents':>5}  verb-form coverage")
    for s in r["skills"]:
        cov = ""
        if "coverage" in s:
            c = s["coverage"]
            cov = (f"{s['tense']}: {s['complete_verbs']} complete tables; verbs with >=1 sentence "
                   f"{c['verbs_with_sentence']}/{s['items']}, >=5 {c['verbs_with_5']}/{s['items']}, "
                   f"min {c['min']}, median {c['median']}; person slots {c['person_slots_covered']}/{c['person_slots']}")
        lines.append(f"{s['skill']:<20} {s['unit']:<4} {s['kind']:<7} {s['items']:>5} {s['facets']:>6} {s['sentences']:>5}  {cov}")
        if verbose and "coverage" in s:
            pv = s["coverage"]["per_verb"]
            lines.append("      " + ", ".join(f"{k} {v}" for k, v in pv.items()))
    return "\n".join(lines)
