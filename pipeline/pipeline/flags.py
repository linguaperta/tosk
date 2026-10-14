"""Triage of exercise flags exported from the app (Settings -> Feedback & flags).

The app writes JSON Lines (``tosk-flags-YYYYMMDD.jsonl``, one flag per
line, format ``tosk-flag/1``; see ``docs/feedback.md``). This module reads
those files and prints them grouped by course, skill and exercise type, with
the exercise rendered readably (correct answer marked ``*``), so a developer
(or a Claude session) can triage them quickly::

    python -m pipeline flags summarize tosk-flags-20261014.jsonl
    python -m pipeline flags summarize a.jsonl b.jsonl --course it --verdict exercise_wrong --json

Pure standard library; no network.
"""

from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable

FORMAT = "tosk-flag/1"

REASON_LABELS = {
    "answer_wrong": "The answer is wrong",
    "multiple_answers": "Multiple answers are possible",
    "unclear": "Unclear / confusing",
    "translation_wrong": "Translation is wrong",
    "other": "Other",
}

VERDICT_LABELS = {
    "exercise_wrong": "AI: exercise WRONG",
    "ambiguous": "AI: AMBIGUOUS",
    "exercise_correct": "AI: exercise correct (learner mistaken)",
}


class FlagFileError(ValueError):
    pass


def load_flags(paths: Iterable[str | Path]) -> tuple[list[dict[str, Any]], list[str]]:
    """Reads flags from JSONL files. Returns (flags, warnings); duplicate ids
    across files are kept once (the latest file wins)."""
    by_id: dict[str, dict[str, Any]] = {}
    warnings: list[str] = []
    for path in paths:
        p = Path(path)
        for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            try:
                flag = json.loads(line)
            except json.JSONDecodeError as e:
                warnings.append(f"{p.name}:{n}: not JSON ({e.msg})")
                continue
            if not isinstance(flag, dict) or "id" not in flag:
                warnings.append(f"{p.name}:{n}: not a flag object")
                continue
            fmt = flag.get("format")
            if fmt != FORMAT:
                warnings.append(f"{p.name}:{n}: format {fmt!r}, expected {FORMAT!r} (reading anyway)")
            by_id[flag["id"]] = flag
    flags = sorted(by_id.values(), key=lambda f: f.get("created_at") or "")
    return flags, warnings


def _opts(options: list[Any], correct: int | None) -> str:
    return "  |  ".join(f"{'*' if i == correct else ' '}{o}" for i, o in enumerate(options))


def render_exercise(ex: dict[str, Any]) -> list[str]:
    """The exercise snapshot as readable lines (correct answer marked ``*``)."""
    t = ex.get("type")
    out: list[str] = []
    if ex.get("instruction"):
        out.append(str(ex["instruction"]))
    if t == "flashcard":
        hint = f"   [{ex['hint']}]" if ex.get("hint") else ""
        out.append(f"{ex.get('front')}  =>  {ex.get('back')}{hint}  ({ex.get('direction')})")
    elif t == "multiple_choice":
        hint = f"   ({ex['hint']})" if ex.get("hint") else ""
        out.append(f"{ex.get('prompt')}{hint}")
        out.append(_opts(ex.get("options", []), ex.get("correct_index")))
    elif t == "match_pairs":
        left, right, sol = ex.get("left", []), ex.get("right", []), ex.get("solution", {})
        for i, w in enumerate(left):
            j = sol.get(str(i))
            out.append(f"{w}  =  {right[j] if isinstance(j, int) and j < len(right) else '?'}")
    elif t == "conj_pick":
        out.append(f"{ex.get('lemma')} ({ex.get('gloss')}) - {ex.get('person_label')}, {ex.get('tense_label')}")
        out.append(f"{ex.get('stem')}___   {_opts(ex.get('endings', []), ex.get('correct_index'))}   => {ex.get('full_form')}")
    elif t == "conj_grid":
        out.append(f"{ex.get('lemma')} ({ex.get('gloss')}) - {ex.get('tense_label')}")
        for c in ex.get("cells", []):
            form = f"({c.get('expected')})" if c.get("prefilled") else c.get("expected")
            alts = [a for a in c.get("accepted", []) if a != c.get("expected")]
            out.append(f"  {str(c.get('person_label')):10} {form}{'  also: ' + ', '.join(alts) if alts else ''}")
        out.append("tiles: " + " . ".join(map(str, ex.get("tiles", []))))
    elif t in ("sentence_builder", "transform"):
        if t == "transform":
            out.append(f"{ex.get('source')}  {ex.get('target_description')}")
        else:
            out.append(str(ex.get("prompt")))
        if ex.get("translation"):
            out.append(f'"{ex["translation"]}"')
        out.append("tiles: " + " . ".join(map(str, ex.get("tiles", []))))
        for a in ex.get("answers", []):
            out.append("=> " + " ".join(map(str, a)))
    elif t == "cloze":
        hint = f"   ({ex['hint']})" if ex.get("hint") else ""
        out.append(f"{ex.get('before')}___{ex.get('after')}{hint}")
        if ex.get("translation"):
            out.append(f'"{ex["translation"]}"')
        if ex.get("options") is not None:
            out.append(_opts(ex["options"], ex.get("correct_index")))
        else:
            out.append("free text => " + " / ".join(map(str, ex.get("accepted", []))))
    elif t == "spot_error":
        tokens, pre = ex.get("tokens", []), ex.get("token_pre")
        idx = ex.get("error_index")
        parts = []
        for i, tok in enumerate(tokens):
            space = pre[i] if pre and i < len(pre) else (" " if i else "")
            parts.append(space + (f"[{tok}]" if i == idx else str(tok)))
        out.append("".join(parts).strip())
        if ex.get("translation"):
            out.append(f'"{ex["translation"]}"')
        if isinstance(idx, int) and idx < len(tokens):
            out.append(f'error: "{tokens[idx]}" -> "{ex.get("correction")}"')
    else:
        out.append(json.dumps(ex, ensure_ascii=False))
    return out


def summarize(
    flags: list[dict[str, Any]],
    *,
    course: str | None = None,
    verdict: str | None = None,
    raw_json: bool = False,
) -> str:
    """Flags grouped by course / skill / exercise type, as text."""
    sel = [
        f
        for f in flags
        if (course is None or f.get("course_id") == course)
        and (verdict is None or (f.get("ai_verdict") or "none") == verdict)
    ]
    lines: list[str] = []
    verdicts = Counter((f.get("ai_verdict") or "none") for f in sel)
    reasons = Counter(r for f in sel for r in f.get("reasons", []))
    lines.append(f"{len(sel)} flag(s)" + (f" of {len(flags)}" if len(sel) != len(flags) else ""))
    if sel:
        lines.append("  AI verdicts: " + ", ".join(f"{k} {v}" for k, v in sorted(verdicts.items())))
        lines.append("  reasons:     " + ", ".join(f"{k} {v}" for k, v in reasons.most_common()))
        apps = sorted({str(f.get("app_version")) for f in sel})
        lines.append("  app versions: " + ", ".join(apps))

    groups: dict[str, dict[str, dict[str, list[dict[str, Any]]]]] = defaultdict(
        lambda: defaultdict(lambda: defaultdict(list))
    )
    for f in sel:
        groups[str(f.get("course_id"))][str(f.get("skill_id") or "-")][str(f.get("exercise_type"))].append(f)

    for c in sorted(groups):
        packs = sorted({str(f.get("pack_version")) for s in groups[c].values() for t in s.values() for f in t})
        lines.append("")
        lines.append(f"== course {c} (pack {', '.join(packs)})")
        for s in sorted(groups[c]):
            lines.append(f"-- skill {s}")
            for t in sorted(groups[c][s]):
                group = groups[c][s][t]
                lines.append(f"   [{t}] {len(group)} flag(s)")
                for f in group:
                    lines.extend(("      " + x) if x else "" for x in _flag_lines(f, raw_json))
    return "\n".join(lines)


def _flag_lines(f: dict[str, Any], raw_json: bool) -> list[str]:
    out = [""]
    ok = "accepted" if f.get("correct") else "marked wrong"
    out.append(f"#{str(f.get('id'))[:8]}  {f.get('created_at')}  {f.get('facet_id')}"
               + (f"  sentence {f['sentence_id']}" if f.get("sentence_id") else ""))
    rs = [REASON_LABELS.get(r, r) for r in f.get("reasons", [])]
    out.append("reasons: " + ("; ".join(rs) if rs else "(none)"))
    if f.get("comment"):
        out.append(f"comment: {f['comment']}")
    out.append(f"given:    {f.get('given')!r} ({ok})")
    out.append(f"expected: {f.get('expected')!r}")
    if f.get("ai_verdict"):
        out.append(VERDICT_LABELS.get(f["ai_verdict"], f["ai_verdict"]))
        for r in str(f.get("ai_reasoning") or "").splitlines():
            out.append("  > " + r)
    ex = f.get("exercise") or {}
    out.append("exercise:")
    out.extend("  " + x for x in render_exercise(ex))
    if raw_json:
        out.append("snapshot: " + json.dumps(ex, ensure_ascii=False, sort_keys=True))
    return out


def main_summarize(paths: list[str], course: str | None, verdict: str | None, raw_json: bool) -> int:
    # Exercises contain arrows and accents; don't die on a legacy console encoding.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    flags, warnings = load_flags(paths)
    for w in warnings:
        print(f"warning: {w}")
    print(summarize(flags, course=course, verdict=verdict, raw_json=raw_json))
    return 0
