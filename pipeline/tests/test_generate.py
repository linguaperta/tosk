"""Generated sentences (pipeline/generate.py), the gap report (gaps.py) and how the importer
keeps generated files, skips their texts and applies the seed's uncountable/article flags."""
import json

import yaml

from pipeline.content import load_pack, read_jsonl
from pipeline.gaps import analyze, summary
from pipeline.generate import Generator, parse_src
from pipeline.validate import validate


def _gated(root):
    """The mini course with grammar gating, and 'io', 'il', 'noi' taught in the first skill."""
    c = yaml.safe_load((root / "course.yaml").read_text(encoding="utf-8"))
    c["base_features"] = ["tense:presente"]
    (root / "course.yaml").write_text(yaml.safe_dump(c, allow_unicode=True, sort_keys=False), encoding="utf-8")
    pool = root / "lexicon" / "pool.jsonl"
    out = []
    for _, r in read_jsonl(pool):
        if r["lemma"] in ("io", "il", "noi"):
            r.update(unit="u1", tags=["greetings"], tr={**r["tr"], "nl": [r["lemma"]]})
        out.append(json.dumps(r, ensure_ascii=False))
    pool.write_text("\n".join(out) + "\n", encoding="utf-8")
    return root


GOOD = {"skill": "present-are", "target": "guardare presente.io", "text": "Io guardo la pizza.",
        "en": "I look at the pizza.", "nl": "Ik kijk naar de pizza."}


def test_check_accepts_a_good_draft_and_explains_rejects(mini_pack_dir):
    g = Generator(_gated(mini_pack_dir))
    rec, problems = g.check(GOOD)
    assert problems == [] and rec["src"] == "claude-gen (present-are: guardare presente.io)"
    assert rec["tr_src"] == {"en": "claude-gen", "nl": "claude-gen"}
    assert rec["unit"] == "u2"                                     # pizza is a unit-2 item
    assert [t.get("form") for t in rec["tokens"] if t["t"] == "guardo"] == ["presente.io"]

    def why(**kw):
        return "; ".join(g.check({**GOOD, **kw})[1])
    assert "unaligned word 'e'" in why(text="Io guardo il libro e la pizza.")
    assert "words taught after present-are" in why(text="Io guardo il libro e la pizza.")
    assert "not allowed at present-are" in why(text="Noi abbiamo mangiato la pizza.", target=None)
    assert "target guardare presente.io not aligned" in why(text="Noi guardiamo la pizza.")
    assert "duplicate of s:1" in why(text="Io mangio la pizza!", target="mangiare presente.io")
    assert "no nl translation" in why(nl="")
    assert "en translation: numbers" in why(text="Io guardo 2 pizze.", en="I look at 3 pizzas.")
    assert "unknown skill" in why(skill="nope")


def test_add_assigns_stable_ids_and_refresh_keeps_them(mini_pack_dir):
    root = _gated(mini_pack_dir)
    g = Generator(root)
    acc, rej = g.add([GOOD, dict(GOOD), {**GOOD, "text": "Noi abbiamo parlato.", "target": None}])
    assert len(acc) == 1 and len(rej) == 2                         # in-batch duplicate, existing text
    recs = [r for _, r in read_jsonl(root / "sentences" / "gen-u2.jsonl")]
    assert [r["id"] for r in recs] == ["g:it:1"]
    assert (root / "sentence_ids.tsv").read_text(encoding="utf-8").splitlines()[1].startswith("g:it:1\t")
    assert parse_src(recs[0]["src"]) == ("present-are", "guardare presente.io")
    assert validate(load_pack(root), check_notes=False) == []
    # a second run gives the next id and keeps the first
    g = Generator(root)
    acc, _ = g.add([{**GOOD, "text": "Io guardo il libro.", "en": "I look at the book.", "nl": "Ik kijk naar het boek."}])
    assert acc[0]["id"] == "g:it:2"
    assert Generator(root).refresh() == []
    ids = sorted(r["id"] for p in (root / "sentences").glob("gen-*.jsonl") for _, r in read_jsonl(p))
    assert ids == ["g:it:1", "g:it:2"]


def test_gap_report_counts_easy_slots(mini_pack_dir):
    root = _gated(mini_pack_dir)
    before = analyze(load_pack(root))
    row = next(s for s in before["skills"] if s["skill"] == "present-are")
    assert row["slots"][("guardare", "io")] == 0
    Generator(root).add([GOOD])
    after = analyze(load_pack(root))
    row = next(s for s in after["skills"] if s["skill"] == "present-are")
    assert row["slots"][("guardare", "io")] == 1
    assert summary(after)["slot_deficit"] == summary(before)["slot_deficit"] - 1


def test_importer_keeps_generated_files_and_applies_seed_flags(import_env):
    from pipeline.importer import run_import
    root = import_env / "it"
    seed = yaml.safe_load((root / "seed.yaml").read_text(encoding="utf-8"))
    seed["uncountable"] = ["pizza"]
    for it in seed["items"]:
        if it["lemma"] == "libro":
            it["article"] = "il|lo"
    (root / "seed.yaml").write_text(yaml.safe_dump(seed, allow_unicode=True, sort_keys=False), encoding="utf-8")
    (root / "sentences").mkdir(parents=True, exist_ok=True)
    gen = {"id": "g:it:1", "text": "Noi parliamo molto!", "tr": {"en": "We talk a lot!"}, "src": "claude-gen (x)",
           "unit": "u1", "tokens": [{"t": "Noi parliamo molto!"}]}
    (root / "sentences" / "gen-u1.jsonl").write_text(json.dumps(gen) + "\n", encoding="utf-8")
    run_import("it", str(import_env))
    assert (root / "sentences" / "gen-u1.jsonl").exists()
    texts = [r["text"] for p in (root / "sentences").glob("u*.jsonl") for _, r in read_jsonl(p)]
    assert "Noi parliamo molto." not in texts                     # same text as the generated one
    lex = {r["lemma"]: r for p in (root / "lexicon").glob("*.jsonl") for _, r in read_jsonl(p)}
    assert "plural" not in lex["pizza"]
    assert lex["libro"]["article"] == "il|lo"
