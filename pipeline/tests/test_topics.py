"""Built-in topic trees (pack format 1.2; docs/pack-format.md "Topics", docs/extensions.md): the
course.yaml `topics` key, its validator rules and the compiled `topics` / `topic_units` tables."""
import json
import sqlite3

import pytest

from pipeline.compile import COURSE_DB_SCHEMA_MINOR_TOPICS, compile_pack
from pipeline.content import all_units, load_pack, skill_topics, write_jsonl
from pipeline.topics import default_anchor
from pipeline.validate import validate

from test_validate import edit_course, skill

FOOD_ITEMS = [
    {"id": "it:pane", "lemma": "pane", "pos": "noun", "article": "il", "gender": "m", "freq": 80, "unit": "cibo-u1",
     "tags": ["food"], "tr": {"en": ["bread"], "nl": ["brood"]}},
    {"id": "it:vino", "lemma": "vino", "pos": "noun", "article": "il", "gender": "m", "freq": 85, "unit": "cibo-u1",
     "tags": ["food"], "tr": {"en": ["wine"], "nl": ["wijn"]}},
]


def food_topic(**over):
    t = {
        "id": "cibo",
        "title": {"en": "Food and cooking", "nl": "Eten en koken"},
        "short_title": {"en": "Food", "nl": "Eten"},
        "icon": "food",
        "units": [{
            "id": "cibo-u1",
            "title": {"en": "At the table", "nl": "Aan tafel"},
            "skills": [
                {"id": "cibo-words", "kind": "vocab", "title": {"en": "Food", "nl": "Eten"}, "icon": "food",
                 "requires": ["greetings", "articles"], "items": {"tags": ["food"], "min": 2}},
                {"id": "cibo-more", "kind": "vocab", "title": {"en": "More food", "nl": "Meer eten"},
                 "requires": ["cibo-words"], "items": {"lemmas": ["pane", "vino", "pizza"], "min": 3}},
            ],
        }],
    }
    t.update(over)
    return t


def travel_topic(**over):
    t = {
        "id": "viaggio",
        "title": {"en": "Travel", "nl": "Reizen"},
        "units": [{
            "id": "viaggio-u1",
            "title": {"en": "On the road", "nl": "Onderweg"},
            "skills": [
                {"id": "viaggio-words", "kind": "vocab", "title": {"en": "Travel", "nl": "Reizen"},
                 "requires": ["passato"], "items": {"lemmas": ["libro", "zio"], "min": 2}},
            ],
        }],
    }
    t.update(over)
    return t


@pytest.fixture
def topic_pack(mini_pack_dir):
    """The mini course with two topics: food (its own words) and travel (main-tree words)."""
    write_jsonl(mini_pack_dir / "lexicon" / "cibo.jsonl", FOOD_ITEMS)
    with open(mini_pack_dir / "ids.tsv", "a", encoding="utf-8", newline="\n") as f:
        for it in FOOD_ITEMS:
            f.write(f"{it['id']}\t{it['lemma']}\t{it['pos']}\t{it['pos']}\n")
    def f(c):
        # the mini article skill takes every noun; the food nouns belong to the topic
        skill(c, "articles")["items"] = {"lemmas": ["libro", "pizza", "zio"], "min": 2}
        c["topics"] = [food_topic(), travel_topic()]
    edit_course(mini_pack_dir, f)
    return mini_pack_dir


def errors(root):
    return validate(load_pack(root))


def set_topics(root, *topics):
    edit_course(root, lambda c: c.__setitem__("topics", list(topics)))


def test_topic_pack_is_valid(topic_pack):
    assert errors(topic_pack) == []


def test_course_order_is_main_tree_then_topics(topic_pack):
    pack = load_pack(topic_pack)
    assert [u["id"] for u in all_units(pack.course)] == ["u1", "u2", "cibo-u1", "viaggio-u1"]
    ids = [s["id"] for _, _, _, s in pack.skills()]
    assert ids.index("cibo-words") > ids.index("passato")
    trees = skill_topics(pack.course)
    assert trees["greetings"] is None and trees["cibo-more"] == "cibo" and trees["viaggio-words"] == "viaggio"


def test_default_anchor_is_the_deepest_main_tree_requirement(topic_pack):
    c = load_pack(topic_pack).course
    # cibo requires greetings (depth 0) and articles (depth 1)
    assert default_anchor(c, c["topics"][0]) == "articles"
    assert default_anchor(c, c["topics"][1]) == "passato"


def test_compiled_topics(topic_pack, tmp_path):
    out = tmp_path / "it.sqlite"
    compile_pack(load_pack(topic_pack), out, built_at="2026-01-01T00:00:00Z")
    con = sqlite3.connect(out)
    meta = dict(con.execute("SELECT key, value FROM meta"))
    assert meta["schema_minor"] == str(COURSE_DB_SCHEMA_MINOR_TOPICS)
    assert "min_app_version" not in meta   # older apps degrade safely (see test_old_app_view)
    rows = con.execute("SELECT id, ord, title, short_title, description, icon, anchor FROM topics ORDER BY ord").fetchall()
    assert [(r[0], r[1], r[6]) for r in rows] == [("cibo", 0, "articles"), ("viaggio", 1, "passato")]
    assert json.loads(rows[0][2]) == {"en": "Food and cooking", "nl": "Eten en koken"}
    assert json.loads(rows[0][3]) == {"en": "Food", "nl": "Eten"}
    assert json.loads(rows[1][3]) == {} and json.loads(rows[1][4]) == {} and rows[1][5] is None
    assert dict(con.execute("SELECT unit_id, topic_id FROM topic_units")) == {"cibo-u1": "cibo", "viaggio-u1": "viaggio"}
    units = con.execute("SELECT id, ord FROM units ORDER BY ord").fetchall()
    assert units == [("u1", 0), ("u2", 1), ("cibo-u1", 2), ("viaggio-u1", 3)]
    # topic skills are ordinary skills with facets, prerequisites and items
    assert con.execute("SELECT unit_id FROM skills WHERE id = 'cibo-more'").fetchone() == ("cibo-u1",)
    assert set(con.execute("SELECT requires_id FROM skill_requires WHERE skill_id = 'cibo-words'")) == {
        ("greetings",), ("articles",)}
    facets = {r[0] for r in con.execute("SELECT facet_id FROM skill_facets WHERE skill_id = 'cibo-more'")}
    # a main-tree word in a topic keeps its id: one progress
    assert {"it:pizza#rec", "it:pizza#prod", "it:pane#rec", "it:vino#prod"} <= facets


def test_old_app_view(topic_pack, tmp_path):
    """What an app before schema minor 3 reads: every unit (topics last, by ord) and every skill
    with a known unit; no skill depends on a topic, so the main tree plays as before."""
    out = tmp_path / "it.sqlite"
    compile_pack(load_pack(topic_pack), out, built_at="2026-01-01T00:00:00Z")
    con = sqlite3.connect(out)
    units = [r[0] for r in con.execute("SELECT id FROM units ORDER BY ord")]
    assert units[-2:] == ["cibo-u1", "viaggio-u1"]
    skill_units = {r[0] for r in con.execute("SELECT unit_id FROM skills")}
    assert skill_units <= set(units)
    topic_skills = {r[0] for r in con.execute(
        "SELECT s.id FROM skills s JOIN topic_units t ON t.unit_id = s.unit_id")}
    main_reqs = {r[0] for r in con.execute(
        "SELECT r.requires_id FROM skill_requires r JOIN skills s ON s.id = r.skill_id "
        "WHERE s.unit_id NOT IN (SELECT unit_id FROM topic_units)")}
    assert not (main_reqs & topic_skills)


def test_pack_without_topics_keeps_its_minor(mini_pack_dir, tmp_path):
    out = tmp_path / "it.sqlite"
    compile_pack(load_pack(mini_pack_dir), out, built_at="2026-01-01T00:00:00Z")
    con = sqlite3.connect(out)
    assert dict(con.execute("SELECT key, value FROM meta"))["schema_minor"] == "1"
    assert con.execute("SELECT COUNT(*) FROM topics").fetchone() == (0,)


def test_explicit_anchor(topic_pack):
    set_topics(topic_pack, food_topic(anchor="greetings"), travel_topic())
    errs = errors(topic_pack)
    # articles (depth 1) is required, and comes after greetings (depth 0)
    assert any("['articles'] that come after its anchor 'greetings'" in e for e in errs), errs
    # a sibling at the same depth is fine: articles and present-are both follow greetings
    set_topics(topic_pack, food_topic(anchor="present-are"), travel_topic())
    assert errors(topic_pack) == []
    set_topics(topic_pack, food_topic(anchor="passato"), travel_topic())
    assert errors(topic_pack) == []


def test_sentences_across_trees_take_each_trees_home(topic_pack):
    """A sentence with a topic word and a later main-tree tense is valid when the main tree's home
    skill allows the tense: the app shows it only once both skills are started."""
    from pipeline.content import read_jsonl
    p = topic_pack / "sentences" / "u1.jsonl"
    recs = [r for _, r in read_jsonl(p)]
    recs.append({"id": "s:90", "text": "Noi abbiamo mangiato il pane.", "tr": {"en": "We ate the bread.", "nl": "Wij aten het brood."},
                 "tokens": [{"t": "Noi", "lex": "it:noi"}, {"t": "abbiamo", "pre": " ", "lex": "it:avere", "form": "presente.noi"},
                            {"t": "mangiato", "pre": " ", "lex": "it:mangiare", "form": "passato_prossimo.noi"},
                            {"t": "il", "pre": " ", "lex": "it:il"}, {"t": "pane", "pre": " ", "lex": "it:pane"},
                            {"t": ".", "is_word": False}]})
    write_jsonl(p, recs)
    edit_course(topic_pack, lambda c: c.__setitem__("base_features", ["tense:presente"]))
    assert errors(topic_pack) == []
    # (with one home skill in course order, the topic skill cibo-words, it was an error)
    from pipeline import features
    pack = load_pack(topic_pack)
    tagger, graph = features.build(pack.course, pack.items, pack.verbs)
    s = next(x for x in pack.sentences if x["id"] == "s:90")
    assert graph.home(s["tokens"], tagger.tag(s["tokens"])) == "cibo-words"
    assert "tense:passato_prossimo" not in graph.allowed["cibo-words"]


def test_anchor_must_be_a_main_tree_skill(topic_pack):
    set_topics(topic_pack, food_topic(anchor="nope"), travel_topic())
    assert any("anchor 'nope' is no skill" in e for e in errors(topic_pack))
    set_topics(topic_pack, food_topic(), travel_topic(anchor="cibo-words"))
    assert any("anchor 'cibo-words' is a skill of topic 'cibo'" in e for e in errors(topic_pack))


def test_topic_needs_an_anchor(topic_pack):
    t = travel_topic()
    t["units"][0]["skills"][0].pop("requires")
    set_topics(topic_pack, food_topic(), t)
    assert any("topic viaggio: no anchor" in e for e in errors(topic_pack))
    set_topics(topic_pack, food_topic(), {**t, "anchor": "greetings"})
    assert errors(topic_pack) == []


def test_main_tree_cannot_require_a_topic(topic_pack):
    edit_course(topic_pack, lambda c: skill(c, "passato")["requires"].append("cibo-words"))
    assert any("main-tree skill passato requires 'cibo-words' of topic 'cibo'" in e for e in errors(topic_pack))


def test_topic_cannot_require_another_topic(topic_pack):
    t = travel_topic()
    t["units"][0]["skills"][0]["requires"] = ["passato", "cibo-words"]
    set_topics(topic_pack, food_topic(), t)
    assert any("requires 'cibo-words' of another topic 'cibo'" in e for e in errors(topic_pack))


def test_main_tree_cannot_use_a_topics_words(topic_pack):
    edit_course(topic_pack, lambda c: skill(c, "articles").__setitem__("items", {"pos": "noun", "min": 2}))
    errs = errors(topic_pack)
    assert any("main-tree skill articles uses it:pane, which is introduced in topic 'cibo'" in e for e in errs), errs


def test_topics_share_words(topic_pack):
    """A topic may train a word another topic introduces (one item id, one progress)."""
    t = travel_topic()
    t["units"][0]["skills"][0]["items"] = {"lemmas": ["libro", "vino"], "min": 2}
    set_topics(topic_pack, food_topic(), t)
    assert errors(topic_pack) == []


def test_ids_unique_over_every_tree(topic_pack):
    t = travel_topic()
    t["units"][0]["skills"][0]["id"] = "greetings"
    set_topics(topic_pack, food_topic(), t)
    assert any("duplicate skill ids ['greetings']" in e for e in errors(topic_pack))
    t = travel_topic()
    t["units"][0]["id"] = "u1"
    set_topics(topic_pack, food_topic(), t)
    assert any("duplicate unit ids" in e for e in errors(topic_pack))
    set_topics(topic_pack, food_topic(), travel_topic(id="cibo"))
    assert any("duplicate topic id 'cibo'" in e for e in errors(topic_pack))


def test_no_cycles_across_trees(topic_pack):
    t = food_topic()
    t["units"][0]["skills"][0]["requires"] = ["greetings", "articles", "cibo-more"]
    set_topics(topic_pack, t, travel_topic())
    assert any("prerequisite cycle" in e for e in errors(topic_pack))


def test_topic_schema(topic_pack):
    set_topics(topic_pack, {**food_topic(), "colour": "red"})
    assert any("schema" in e and "colour" in e for e in errors(topic_pack))
    t = food_topic()
    t.pop("units")
    set_topics(topic_pack, t)
    assert any("schema" in e and "'units' is a required property" in e for e in errors(topic_pack))
