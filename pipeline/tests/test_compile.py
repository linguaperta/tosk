import json
import re
import sqlite3

from pipeline.compile import COURSE_DB_SCHEMA_VERSION, compile_pack
from pipeline.content import load_pack
from pipeline.paths import DDL_PATH

REQUIRED_META = ["schema_version", "course_id", "version", "title", "target", "translations", "persons",
                 "tenses", "tense_labels", "articles", "unverified", "built_at", "attribution"]


def ddl_tables():
    """table -> column names, parsed from the DDL by executing it in memory."""
    con = sqlite3.connect(":memory:")
    con.executescript(DDL_PATH.read_text(encoding="utf-8"))
    out = {}
    for (name,) in con.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
        out[name] = [r[1] for r in con.execute(f"PRAGMA table_info({name})")]
    idx = sorted(r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='index' AND sql IS NOT NULL"))
    return out, idx


def build(mini_pack_dir, tmp_path, built_at="2026-01-01T00:00:00Z"):
    pack = load_pack(mini_pack_dir)
    out = tmp_path / "it.sqlite"
    stats = compile_pack(pack, out, built_at=built_at)
    return out, stats


def test_schema_matches_ddl(mini_pack_dir, tmp_path):
    out, _ = build(mini_pack_dir, tmp_path)
    con = sqlite3.connect(out)
    tables, idx = ddl_tables()
    got = {name: [r[1] for r in con.execute(f"PRAGMA table_info({name})")]
           for (name,) in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert got == tables
    got_idx = sorted(r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='index' AND sql IS NOT NULL"))
    assert got_idx == idx
    assert con.execute("PRAGMA user_version").fetchone()[0] == COURSE_DB_SCHEMA_VERSION
    assert "PRAGMA user_version = %d" % COURSE_DB_SCHEMA_VERSION in DDL_PATH.read_text(encoding="utf-8")


def test_meta(mini_pack_dir, tmp_path):
    out, _ = build(mini_pack_dir, tmp_path)
    meta = dict(sqlite3.connect(out).execute("SELECT key, value FROM meta"))
    for k in REQUIRED_META:
        assert k in meta, k
    assert meta["schema_version"] == "1"
    assert meta["course_id"] == "it"
    assert json.loads(meta["persons"]) == ["io", "tu", "lui/lei", "noi", "voi", "loro"]
    assert json.loads(meta["tenses"]) == ["presente", "passato_prossimo"]
    assert json.loads(meta["title"]) == {"en": "Italian (test)", "nl": "Italiaans (test)"}
    assert json.loads(meta["tense_labels"])["presente"]["nl"] == "tegenwoordige tijd"
    assert meta["unverified"] == "0"
    assert meta["built_at"] == "2026-01-01T00:00:00Z"
    assert "CC BY-SA" in meta["attribution"]


def test_units_skills_and_requires(mini_pack_dir, tmp_path):
    out, _ = build(mini_pack_dir, tmp_path)
    con = sqlite3.connect(out)
    assert con.execute("SELECT id, ord FROM units ORDER BY ord").fetchall() == [("u1", 0), ("u2", 1)]
    rows = {r[0]: r for r in con.execute("SELECT id, unit_id, ord, kind, tense, exercises, pos_x, pos_y, query FROM skills")}
    assert rows["present-are"][1:5] == ("u1", 1, "grammar", "presente")
    assert json.loads(rows["present-are"][5]) == ["conj_pick", "conj_grid", "cloze"]
    assert json.loads(rows["greetings"][5]) == []
    assert rows["passato"][6:8] == (1, 3)
    assert json.loads(rows["articles"][8]) == {"items": {"pos": "noun", "min": 2}, "facet": "article"}
    req = set(con.execute("SELECT skill_id, requires_id FROM skill_requires"))
    assert req == {("present-are", "greetings"), ("articles", "greetings"), ("passato", "present-are"), ("passato", "articles")}
    notes = set(con.execute("SELECT skill_id, lang FROM notes"))
    assert ("present-are", "en") in notes and ("present-are", "nl") in notes


def test_skill_items_and_facets(mini_pack_dir, tmp_path):
    out, _ = build(mini_pack_dir, tmp_path)
    con = sqlite3.connect(out)

    def items(skill):
        return [r[0] for r in con.execute("SELECT item_id FROM skill_items WHERE skill_id=? ORDER BY ord", (skill,))]

    def facets(skill):
        return con.execute("SELECT facet_id, item_id, kind, tense, ord FROM skill_facets WHERE skill_id=? "
                           "ORDER BY ord, facet_id", (skill,)).fetchall()

    # ordered by frequency rank
    assert items("greetings") == ["it:grazie", "it:ciao"]
    assert items("present-are") == ["it:parlare", "it:mangiare", "it:guardare"]
    assert items("articles") == ["it:libro", "it:pizza", "it:zio"]
    assert items("passato") == ["it:mangiare", "it:parlare"]          # explicit list keeps its order
    assert facets("greetings")[:2] == [("it:grazie#prod", "it:grazie", "prod", None, 0),
                                       ("it:grazie#rec", "it:grazie", "rec", None, 0)]
    assert len(facets("greetings")) == 4
    assert json.loads(con.execute("SELECT query FROM skills WHERE id=?", ("greetings",)).fetchone()[0]) == {"items": {"tags": ["greetings"], "min": 2}}
    assert facets("present-are")[0] == ("it:parlare#form:presente", "it:parlare", "form", "presente", 0)
    assert facets("passato")[1] == ("it:parlare#form:passato_prossimo", "it:parlare", "form", "passato_prossimo", 1)
    assert facets("articles")[0] == ("it:libro#article", "it:libro", "article", None, 0)
    # every skill facet's ord matches skill_items.ord of its item
    bad = con.execute("SELECT count(*) FROM skill_facets f JOIN skill_items i ON i.skill_id=f.skill_id "
                      "AND i.item_id=f.item_id WHERE i.ord != f.ord").fetchone()[0]
    assert bad == 0


def test_items_verbs_sentences(mini_pack_dir, tmp_path):
    out, stats = build(mini_pack_dir, tmp_path)
    con = sqlite3.connect(out)
    row = con.execute("SELECT pos, lemma, article, gender, plural, freq, unit_id, tr, variants, tags FROM items WHERE id='it:pizza'").fetchone()
    assert row[:7] == ("noun", "pizza", "la", "f", "pizze", 70, "u2")
    assert json.loads(row[7]) == {"en": ["pizza"], "nl": ["pizza"]}
    assert json.loads(row[8]) == [] and json.loads(row[9]) == []
    assert con.execute("SELECT unit_id FROM items WHERE id='it:essere'").fetchone() == (None,)
    assert set(con.execute("SELECT tag, item_id FROM item_tags")) == {("greetings", "it:ciao"), ("greetings", "it:grazie")}
    assert con.execute("SELECT class, stem, irregular, auxiliary FROM verbs WHERE item_id='it:mangiare'").fetchone() == ("are", "mangi", 0, "avere")
    f = con.execute("SELECT form, stem, ending, alts FROM verb_forms WHERE item_id='it:mangiare' AND tense='presente' AND person='noi'").fetchone()
    assert f == ("mangiamo", "mang", "iamo", "[]")
    f = con.execute("SELECT form, stem, ending FROM verb_forms WHERE item_id='it:mangiare' AND tense='passato_prossimo' AND person='io'").fetchone()
    assert f == ("ho mangiato", None, None)
    f = con.execute("SELECT form, alts FROM verb_forms WHERE item_id='it:essere' AND tense='passato_prossimo' AND person='noi'").fetchone()
    assert f == ("siamo stati", '["siamo state"]')
    assert con.execute("SELECT form FROM verb_forms WHERE item_id='it:essere' AND tense='participle' AND person='_'").fetchone() == ("stato",)
    # stem || ending == form whenever both are set
    assert con.execute("SELECT count(*) FROM verb_forms WHERE stem IS NOT NULL AND stem || ending != form").fetchone()[0] == 0
    # tokens re-render every sentence
    for sid, text in con.execute("SELECT id, text FROM sentences"):
        toks = con.execute("SELECT pre, t FROM tokens WHERE sentence_id=? ORDER BY idx", (sid,)).fetchall()
        assert "".join(p + t for p, t in toks) == text
    tok = con.execute("SELECT t, is_word, lex, form FROM tokens WHERE sentence_id='s:2' ORDER BY idx").fetchall()
    assert tok == [("Noi", 1, "it:noi", None), ("abbiamo", 1, "it:avere", "presente.noi"),
                   ("parlato", 1, "it:parlare", "passato_prossimo.noi"), (".", 0, None, None)]
    assert json.loads(con.execute("SELECT tr FROM sentences WHERE id='s:1'").fetchone()[0]) == \
        {"en": "I eat the pizza.", "nl": "Ik eet de pizza."}
    assert stats["sentences"] == 3


def test_output_is_deterministic(mini_pack_dir, tmp_path):
    a, _ = build(mini_pack_dir, tmp_path)
    data_a = a.read_bytes()
    b, _ = build(mini_pack_dir, tmp_path)
    assert b.read_bytes() == data_a
    c, _ = build(mini_pack_dir, tmp_path, built_at="2027-01-01T00:00:00Z")
    con = sqlite3.connect(c)
    assert dict(con.execute("SELECT key, value FROM meta"))["built_at"] == "2027-01-01T00:00:00Z"


def test_ddl_is_executed_verbatim():
    # guard: the compiler must not carry its own copy of the schema
    from pipeline import compile as comp
    src = open(comp.__file__, encoding="utf-8").read()
    assert "CREATE TABLE" not in src
    assert re.search(r"DDL_PATH", src)


def test_meta_tts_flag(mini_pack_dir, tmp_path):
    """course.yaml `tts: false` (no voice for the target language) -> meta.tts '0'; absent by default."""
    out, _ = build(mini_pack_dir, tmp_path)
    assert "tts" not in dict(sqlite3.connect(out).execute("SELECT key, value FROM meta"))
    pack = load_pack(mini_pack_dir)
    pack.course["tts"] = False
    out2 = tmp_path / "it2.sqlite"
    compile_pack(pack, out2, built_at="2026-01-01T00:00:00Z")
    assert dict(sqlite3.connect(out2).execute("SELECT key, value FROM meta"))["tts"] == "0"
