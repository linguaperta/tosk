"""`python -m pipeline flags summarize` on the fixture the app's export test
writes (app/test/feedback/feedback_test.dart keeps them in sync)."""
from __future__ import annotations

import json
from pathlib import Path

from pipeline.__main__ import main
from pipeline.flags import load_flags, render_exercise, summarize

FIXTURES = Path(__file__).parent / "fixtures"

SAMPLE = FIXTURES / "flags" / "sample.jsonl"


def test_load_flags_reads_every_line_oldest_first():
    flags, warnings = load_flags([SAMPLE])
    assert warnings == []
    assert len(flags) == 9
    assert [f["exercise_type"] for f in flags][:3] == ["flashcard", "multiple_choice", "match_pairs"]
    assert {f["format"] for f in flags} == {"tosk-flag/1"}


def test_load_flags_dedupes_and_warns(tmp_path):
    lines = SAMPLE.read_text(encoding="utf-8").splitlines()
    other = tmp_path / "b.jsonl"
    other.write_text("\n".join([lines[0], "not json", '{"no": "id"}', ""]) + "\n", encoding="utf-8")
    flags, warnings = load_flags([SAMPLE, other])
    assert len(flags) == 9
    assert len(warnings) == 2
    assert "b.jsonl:2" in warnings[0]


def test_summarize_groups_by_course_skill_and_type():
    flags, _ = load_flags([SAMPLE])
    text = summarize(flags)
    assert text.startswith("9 flag(s)")
    assert "== course it (pack 1.2.0)" in text
    assert "== course nl (pack 1.2.0)" in text
    assert text.index("== course it") < text.index("== course nl")
    assert "-- skill present_are" in text
    assert "[cloze] 1 flag(s)" in text
    assert "reasons: Multiple answers are possible; Other" in text
    assert "comment: Both should work?" in text
    assert "AI: exercise WRONG" in text
    assert "  > For noi only -iamo is right." in text
    # The exercise is rendered with the correct answer marked.
    assert "*mangiamo" in text
    assert "Io [sei] qui." in text
    assert 'error: "sei" -> "sono"' in text


def test_summarize_filters():
    flags, _ = load_flags([SAMPLE])
    only_nl = summarize(flags, course="nl")
    assert only_nl.startswith("4 flag(s) of 9")
    assert "== course it" not in only_nl
    wrong = summarize(flags, verdict="exercise_wrong")
    assert wrong.startswith("3 flag(s) of 9")
    assert summarize(flags, verdict="none").startswith("0 flag(s)")
    assert "snapshot: {" in summarize(flags, raw_json=True)


def test_render_every_type():
    flags, _ = load_flags([SAMPLE])
    rendered = {f["exercise_type"]: "\n".join(render_exercise(f["exercise"])) for f in flags}
    assert "il pane  =>  bread" in rendered["flashcard"]
    assert "*il" in rendered["multiple_choice"]
    assert "pane  =  bread" in rendered["match_pairs"]
    assert "mang___" in rendered["conj_pick"]
    assert "(parlo)" in rendered["conj_grid"]
    assert "=> Io mangio il pane" in rendered["sentence_builder"]
    assert "Io mangio.  → noi" in rendered["transform"]
    assert render_exercise({"type": "future_type", "x": 1}) == ['{"type": "future_type", "x": 1}']


def test_cli(capsys):
    assert main(["flags", "summarize", str(SAMPLE), "--course", "it"]) == 0
    out = capsys.readouterr().out
    assert out.startswith("5 flag(s) of 9")
    json.dumps(out)  # plain text
