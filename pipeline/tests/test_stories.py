"""Graded mini-stories (pipeline/stories.py): vocabulary and grammar gating per unit, question checks,
compilation into stories / story_sentences / story_questions, and the validate/report integration."""
import copy
import json
import sqlite3

import yaml

from pipeline.compile import compile_pack
from pipeline.content import load_pack
from pipeline.report import build_report, format_report
from pipeline.stories import StoryChecker, fold, sentence_id
from pipeline.validate import validate

from test_generate import _gated

STORY = {
    "id": "u1-ciao",
    "unit": "u1",
    "title": {"it": "Ciao, Marco!", "en": "Hi, Marco!", "nl": "Hoi, Marco!"},
    "sentences": [
        {"it": "Ciao, Marco!", "en": "Hi, Marco!", "nl": "Hoi, Marco!"},
        {"it": "Io parlo.", "en": "I speak.", "nl": "Ik spreek."},
        {"it": "Noi mangiamo.", "en": "We eat.", "nl": "Wij eten."},
        {"it": "Io guardo Anna.", "en": "I look at Anna.", "nl": "Ik kijk naar Anna."},
        {"it": "Grazie, Anna!", "en": "Thanks, Anna!", "nl": "Bedankt, Anna!"},
    ],
    "questions": [
        {"q": {"en": "Who does he look at?", "nl": "Naar wie kijkt hij?"}, "options": ["Anna", "Marco", "Luca"],
         "answer": 0},
        {"q": {"en": "What do we do?", "nl": "Wat doen wij?"}, "prompt": "Noi mangiamo?",
         "options": [{"en": "We eat", "nl": "We eten"}, {"en": "We sleep", "nl": "We slapen"},
                     {"en": "We sing", "nl": "We zingen"}], "answer": 0,
         "why": {"en": "Sentence 3.", "nl": "Zin 3."}},
        {"q": {"en": "Who says thanks?", "nl": "Wie zegt bedankt?"}, "options": ["io", "noi", "Anna"], "answer": 0},
    ],
}


def _write(root, *stories):
    d = root / "stories"
    d.mkdir(exist_ok=True)
    (d / "u1.yaml").write_text(yaml.safe_dump(list(stories), allow_unicode=True, sort_keys=False), encoding="utf-8")
    return load_pack(root)


def _problems(root, **changes):
    s = copy.deepcopy(STORY)
    s.update(changes)
    pack = _write(root, s)
    return "; ".join(StoryChecker(pack).check_all()[1])


def test_a_good_story_passes_and_is_aligned(mini_pack_dir):
    root = _gated(mini_pack_dir)
    pack = _write(root, STORY)
    stories, problems = StoryChecker(pack).check_all()
    assert problems == []
    st = stories[0]
    assert st["unit"] == "u1" and st["new_words"] == [] and len(st["sentences"]) == 5
    assert st["sentences"][1]["id"] == sentence_id("u1-ciao", 2) == "st:u1-ciao.2"
    parlo = next(t for t in st["sentences"][1]["tokens"] if t["t"] == "parlo")
    assert parlo["lex"] == "it:parlare" and parlo["form"] == "presente.io"
    assert validate(pack) == []


def test_vocabulary_is_gated_by_unit_with_one_declared_new_word(mini_pack_dir):
    root = _gated(mini_pack_dir)
    pizza = {"it": "Io mangio la pizza.", "en": "I eat the pizza.", "nl": "Ik eet de pizza."}
    libro = {"it": "Io guardo il libro.", "en": "I look at the book.", "nl": "Ik kijk naar het boek."}
    # pizza is a unit-2 word: allowed once declared
    assert "words taught after unit u1: ['pizza (it:pizza)']" in _problems(root, sentences=STORY["sentences"] + [pizza])
    assert _problems(root, sentences=STORY["sentences"] + [pizza], new_words=["pizza"]) == ""
    # ... but only one new word per story
    p = _problems(root, sentences=STORY["sentences"] + [pizza, libro], new_words=["pizza"])
    assert "2 new words" in p and "libro" in p
    assert "new word 'libro' is not used" in _problems(root, new_words=["libro"])
    # an unknown word fails, a name passes (also one declared by the story)
    assert "unaligned word 'Bella'" in _problems(
        root, sentences=STORY["sentences"][:4] + [{"it": "Grazie, Bella!", "en": "Thanks, Bella!", "nl": "Bedankt, Bella!"}])
    assert _problems(root, names=["Bella"], sentences=STORY["sentences"][:4] + [
        {"it": "Grazie, Bella!", "en": "Thanks, Bella!", "nl": "Bedankt, Bella!"}]) == ""
    # the same words are fine in a unit-2 story
    assert _problems(root, unit="u2", sentences=STORY["sentences"] + [pizza]) == ""


def test_grammar_features_are_gated_by_unit(mini_pack_dir):
    root = _gated(mini_pack_dir)
    past = {"it": "Noi abbiamo mangiato.", "en": "We have eaten.", "nl": "Wij hebben gegeten."}
    p = _problems(root, sentences=STORY["sentences"] + [past])
    assert "features ['tense:passato_prossimo'] not allowed at unit u1" in p
    assert _problems(root, unit="u2", new_words=["avere"], sentences=STORY["sentences"] + [past]) == ""  # avere: pool here


def test_questions_are_checked_like_engine_options(mini_pack_dir):
    root = _gated(mini_pack_dir)
    q0 = STORY["questions"][0]

    def with_q0(**kw):
        return _problems(root, questions=[{**q0, **kw}] + STORY["questions"][1:])

    assert "duplicate options" in with_q0(options=["Anna", "anna!", "Marco"])
    assert "answer 3 is not an option index" in with_q0(answer=3)
    assert "2 options" in with_q0(options=["Anna", "Marco"])
    assert "an option lacks its nl text" in with_q0(options=[{"en": "A"}, {"en": "B", "nl": "B"}, {"en": "C", "nl": "C"}])
    assert "mixes target-language and translated options" in with_q0(options=["Anna", {"en": "B", "nl": "B"}, "Luca"])
    assert "no nl question" in with_q0(q={"en": "Who?"})
    assert "option 1: unaligned word 'pane'" in with_q0(options=["pane", "Marco", "Luca"])
    assert "2 questions" in _problems(root, questions=STORY["questions"][:2])
    assert "4 sentences" in _problems(root, sentences=STORY["sentences"][:4])
    assert "no nl translation" in _problems(root, sentences=STORY["sentences"][:4] + [{"it": "Io parlo.", "en": "I speak."}])
    assert fold("Perché?") == fold("perche") == "perche"


def test_compile_writes_story_tables_and_validate_reports_errors(mini_pack_dir, tmp_path):
    root = _gated(mini_pack_dir)
    bad = copy.deepcopy(STORY)
    bad["id"] = "u1-bad"
    bad["sentences"] = STORY["sentences"][:4] + [{"it": "Io guardo Bella.", "en": "I look at Bella.", "nl": "Ik kijk naar Bella."}]
    assert any("u1-bad" in e and "Bella" in e for e in validate(_write(root, STORY, bad)))
    second = {**copy.deepcopy(STORY), "id": "u1-due"}
    pack = _write(root, STORY, second)
    out = tmp_path / "it.sqlite"
    stats = compile_pack(pack, out, built_at="2026-10-14T00:00:00Z")
    assert stats["stories"] == 2 and stats["story_sentences"] == 10 and stats["story_questions"] == 6
    con = sqlite3.connect(out)
    rows = con.execute("SELECT id, unit_id, ord, title, title_tr, src, new_words FROM stories ORDER BY ord").fetchall()
    assert rows[0] == ("u1-ciao", "u1", 0, "Ciao, Marco!", '{"en":"Hi, Marco!","nl":"Hoi, Marco!"}', "claude-gen (story)", "[]")
    assert rows[1][:3] == ("u1-due", "u1", 1)
    assert con.execute("SELECT sentence_id FROM story_sentences WHERE story_id = 'u1-ciao' ORDER BY idx").fetchall() == [
        (f"st:u1-ciao.{n}",) for n in range(1, 6)]
    text, tr, src, unit = con.execute("SELECT text, tr, src, unit_id FROM sentences WHERE id = 'st:u1-ciao.2'").fetchone()
    assert (text, json.loads(tr), src, unit) == ("Io parlo.", {"en": "I speak.", "nl": "Ik spreek."},
                                                 "claude-gen (story: u1-ciao)", "u1")
    assert con.execute("SELECT lex, form FROM tokens WHERE sentence_id = 'st:u1-ciao.2' AND t = 'parlo'").fetchone() == (
        "it:parlare", "presente.io")
    assert ("tense:presente",) in con.execute(
        "SELECT feature FROM sentence_features WHERE sentence_id = 'st:u1-ciao.2'").fetchall()
    q = con.execute("SELECT prompt, prompt_tr, options, correct, explanation_tr FROM story_questions "
                    "WHERE story_id = 'u1-ciao' ORDER BY idx").fetchall()
    assert q[0] == (None, '{"en":"Who does he look at?","nl":"Naar wie kijkt hij?"}', '["Anna","Marco","Luca"]', 0, "{}")
    assert q[1][0] == "Noi mangiamo?" and json.loads(q[1][2])[1] == {"en": "We sleep", "nl": "We slapen"}
    assert json.loads(q[1][4]) == {"en": "Sentence 3.", "nl": "Zin 3."}
    con.close()
    report = format_report(build_report(pack))
    assert "stories: 2 (10 sentences, 6 questions); per unit: u1 2" in report


def test_packs_without_stories_compile_empty_tables(mini_pack_dir, tmp_path):
    pack = load_pack(_gated(mini_pack_dir))
    assert pack.stories == []
    out = tmp_path / "it.sqlite"
    stats = compile_pack(pack, out)
    assert stats["stories"] == 0
    con = sqlite3.connect(out)
    assert con.execute("SELECT COUNT(*) FROM stories").fetchone() == (0,)
    assert con.execute("SELECT COUNT(*) FROM story_questions").fetchone() == (0,)
    con.close()
