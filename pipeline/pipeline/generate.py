"""Generated example sentences for the Italian and Dutch courses (`src: "claude-gen ..."`).

Real Tatoeba sentences come first (the importer fills every quota it can); where a skill still has
too few *easy* sentences (gaps.py: grammar slots, vocabulary items, unit-1 skills), Claude writes
short everyday sentences with their translations. They are built into the pack like any other
sentence, so the app needs nothing special (it only ranks them after unseen Tatoeba sentences).

Drafts (JSON lines, written by Claude):

    {"skill": "present-are", "target": "parlare presente.noi", "text": "Parliamo con la nonna.",
     "en": "We talk to grandma.", "nl": "We praten met oma."}

`target` is `LEMMA TENSE.PERSON` (a verb form the sentence must show, aligned exactly), `LEMMA` (an
item the sentence must contain) or absent (the sentence must touch the skill). Every draft is
checked mechanically and rejected with a reason when it fails:

* it tokenizes and has 2-10 words (like Tatoeba sentences; 4-9 is the aim, greetings are shorter); every word aligns to a lexicon item, except names from
  NAMES (not sentence-initial) and numbers;
* the target aligns to the intended item and form (`Werk jij?` gets no form and fails);
* its grammar features are allowed at the skill and the validator's home-skill rule accepts it;
* at most one word is taught after the skill (or never): it is *easy* there (gaps.py);
* the translations exist for every course translation language and pass trcheck.py;
* its text is new (no Tatoeba or generated sentence with the same normalized text).

Accepted sentences get a permanent id `g:{course}:{n}` from `sentence_ids.tsv` (append-only, keyed
by the normalized text, like ids.tsv) and go to `sentences/gen-{unit}.jsonl` (`unit` = the latest
unit of the skill items they touch, as for Tatoeba sentences). The importer keeps these files and
skips Tatoeba sentences with the same text; `refresh` re-aligns them after a new import.

Commands: `python -m pipeline gen {gaps,context,check,add,refresh} ...` (see __main__.py).
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from . import gaps, trcheck
from .align import Aligner
from .content import Pack, load_pack, read_jsonl, write_jsonl
from .importer import dedupe_key
from .lang import get_lang
from .tokens import tokenize

REGISTRY = "sentence_ids.tsv"
SRC = "claude-gen"
MIN_WORDS, MAX_WORDS = 2, 10
# Names a generated sentence may use (unaligned, never sentence-initial).
NAMES = {
    "it": {"Marco", "Luca", "Giulia", "Anna", "Paolo", "Sara", "Maria", "Giovanni", "Francesca", "Roberto",
           "Elena", "Lucia", "Tom", "Roma", "Milano", "Napoli", "Firenze", "Venezia", "Italia"},
    "nl": {"Tom", "Anna", "Sanne", "Daan", "Lieke", "Pieter", "Emma", "Bram", "Sophie", "Jan", "Eva", "Lisa",
           "Amsterdam", "Utrecht", "Rotterdam", "Nederland"},
}
# Place names that English writes differently (not compared by the translation check).
PLACES = {"Roma", "Milano", "Napoli", "Firenze", "Venezia", "Italia", "Nederland"}


def is_generated(s: dict) -> bool:
    return str(s.get("src") or "").startswith(SRC)


def parse_src(src: str) -> tuple[str | None, str | None]:
    """(skill, target) from 'claude-gen (skill: target)'."""
    m = re.match(r"claude-gen \(([^:)]+)(?::\s*([^)]*))?\)", src or "")
    if not m:
        return None, None
    return m.group(1).strip(), (m.group(2) or "").strip() or None


class Registry:
    """Permanent sentence ids g:{course}:{n}, keyed by the normalized text (append-only)."""

    def __init__(self, code: str, path: Path):
        self.code, self.path = code, path
        self.by_key: dict[str, str] = {}
        self.rows: list[tuple[str, str]] = []
        self.n = 0
        if path.exists():
            for line in path.read_text(encoding="utf-8").splitlines()[1:]:
                if line.strip():
                    sid, key = line.split("\t", 1)
                    self.rows.append((sid, key))
                    self.by_key[key] = sid
                    self.n = max(self.n, int(sid.rsplit(":", 1)[1]))
        self.added = 0

    def get(self, key: str) -> str:
        if key not in self.by_key:
            self.n += 1
            sid = f"g:{self.code}:{self.n}"
            self.by_key[key] = sid
            self.rows.append((sid, key))
            self.added += 1
        return self.by_key[key]

    def save(self) -> None:
        lines = ["id\tkey"] + [f"{a}\t{b}" for a, b in self.rows]
        self.path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


class Generator:
    def __init__(self, root: Path):
        self.root = Path(root)
        self.pack: Pack = load_pack(self.root)
        self.code = self.pack.code
        self.lang = get_lang(self.code)
        self.mat = gaps.Material(self.pack)
        self.graph = self.mat.graph
        self.aligner = Aligner(self.lang, self.pack.items, self.pack.verbs)
        self.items = {it["id"]: it for it in self.pack.items}
        self.by_lemma: dict[str, list[str]] = defaultdict(list)
        for it in sorted(self.pack.items, key=lambda i: (i.get("freq") is None, i.get("freq") or 0, i["id"])):
            self.by_lemma[it["lemma"]].append(it["id"])
        self.translations = list(self.pack.course["translations"])
        self.unit_order = [u["id"] for u in self.pack.course["units"]]
        self.skill_items = set(self.graph.item_skill)
        self.keys = {dedupe_key(s["text"]): s["id"] for s in self.pack.sentences}
        self.registry = Registry(self.code, self.root / REGISTRY)
        self.names = NAMES.get(self.code, set())

    # -- checks -----------------------------------------------------------------------------------
    def _target_ok(self, al: list[dict], skill: str, target: str | None) -> str | None:
        sk = self.graph.skill[skill]
        ids = set(self.mat.resolved[skill])
        if not target:
            if any(t["lex"] in ids for t in al):
                return None
            if "verbs" in sk:
                tense = sk["verbs"]["tense"]
                if any(t["lex"] in ids and (t["form"] or "").startswith(tense + ".") for t in al):
                    return None
            return f"touches no item of {skill}"
        parts = [target] if target in self.by_lemma else target.split()   # "per favore" is one lemma
        lemma = parts[0]
        cands = [i for i in self.by_lemma.get(lemma, []) if i in ids] or self.by_lemma.get(lemma, [])
        if not cands:
            return f"target {lemma!r} is no lexicon item"
        if len(parts) > 1:
            want = parts[1]
            if "verbs" in sk and not want.startswith(sk["verbs"]["tense"] + "."):
                return f"target form {want} is not in the skill's tense {sk['verbs']['tense']}"
            got = [t["form"] for t in al if t["lex"] in cands]
            if want not in got:
                return f"target {lemma} {want} not aligned (got {got or 'nothing'})"
            return None
        if not any(t["lex"] in cands for t in al):
            return f"target {lemma!r} not aligned"
        return None

    def check(self, d: dict, allow_existing: str | None = None) -> tuple[dict | None, list[str]]:
        """(record, problems) for a draft; record is None when there are problems."""
        problems: list[str] = []
        skill = d.get("skill")
        if skill not in self.graph.skill:
            return None, [f"unknown skill {skill!r}"]
        text = " ".join(str(d.get("text") or "").split())
        tr = {l: " ".join(str(d.get(l) or (d.get("tr") or {}).get(l) or "").split()) for l in self.translations}
        for l, v in tr.items():
            if not v:
                problems.append(f"no {l} translation")
        try:
            toks = tokenize(text, self.code)
        except ValueError as e:
            return None, [str(e)]
        al = self.aligner.align(toks, translation=tr.get("en"))
        words = [t for t in al if t["is_word"]]
        if not MIN_WORDS <= len(words) <= MAX_WORDS:
            problems.append(f"{len(words)} words")
        for i, t in enumerate(words):
            if t["lex"] or t["t"].isdigit():
                continue
            if i > 0 and t["t"] in self.names:
                continue
            problems.append(f"unaligned word {t['t']!r}")
        p = self._target_ok(al, skill, d.get("target"))
        if p:
            problems.append(p)
        feats = self.mat.tagger.tag(al)
        extra = feats - self.graph.allowed[skill]
        if extra:
            problems.append(f"features {sorted(extra)} not allowed at {skill}")
        problems += self.graph.problems(al, feats)
        here = self.graph.pos[skill]
        later = [t["t"] for t in al if t["is_word"] and (t["lex"] or not t["t"][:1].isupper())
                 and not t["t"][:1].isdigit()
                 and (self.graph.pos[self.graph.item_skill[t["lex"]]] if t["lex"] in self.graph.item_skill
                      else self.mat.never) > here]
        if len(later) > 1:
            problems.append(f"words taught after {skill}: {later}")
        key = dedupe_key(text)
        if key in self.keys and self.keys[key] != allow_existing:
            problems.append(f"duplicate of {self.keys[key]}")
        names = set(self.names) - PLACES                # Roma = Rome, Nederland = the Netherlands
        for l, v in tr.items():
            if v:
                why = trcheck.mismatch(al, self.items, self.code, v, l, names if l == "en" else frozenset())
                if why:
                    problems.append(f"{l} translation: {why}")
        if problems:
            return None, problems
        touched = {t["lex"] for t in al if t["lex"] in self.skill_items}
        units = [self.items[i]["unit"] for i in touched if self.items[i].get("unit")]
        unit = max(units, key=self.unit_order.index) if units else self._skill_unit(skill)
        toks_out = []
        for t in al:
            o: dict = {"t": t["t"]}
            if t["pre"]:
                o["pre"] = t["pre"]
            if not t["is_word"]:
                o["is_word"] = False
            if t["lex"]:
                o["lex"] = t["lex"]
            if t["form"]:
                o["form"] = t["form"]
            toks_out.append(o)
        target = d.get("target")
        rec = {"id": allow_existing or "", "text": text, "tr": {l: tr[l] for l in sorted(tr)},
               "tr_src": {l: SRC for l in sorted(tr)},
               "src": f"{SRC} ({skill}: {target})" if target else f"{SRC} ({skill})",
               "unit": unit, "tokens": toks_out}
        return rec, []

    def _skill_unit(self, skill: str) -> str:
        for _, unit, _, s in self.pack.skills():
            if s["id"] == skill:
                return unit["id"]
        return self.unit_order[0]

    # -- files ------------------------------------------------------------------------------------
    def gen_records(self) -> list[dict]:
        out = []
        for p in sorted((self.root / "sentences").glob("gen-*.jsonl")):
            out += [r for _, r in read_jsonl(p)]
        return out

    def write(self, records: list[dict]) -> None:
        d = self.root / "sentences"
        for p in d.glob("gen-*.jsonl"):
            p.unlink()
        groups: dict[str, list[dict]] = defaultdict(list)
        for r in sorted(records, key=lambda r: int(r["id"].rsplit(":", 1)[1])):
            groups[r["unit"]].append(r)
        for unit, recs in groups.items():
            write_jsonl(d / f"gen-{unit}.jsonl", recs)
        self.registry.save()

    def add(self, drafts: list[dict], dry_run: bool = False) -> tuple[list[dict], list[tuple[dict, list[str]]]]:
        """Check drafts; unless dry_run, append the accepted ones. Returns (accepted, rejected)."""
        accepted, rejected = [], []
        batch: set[str] = set()
        for d in drafts:
            rec, problems = self.check(d)
            key = dedupe_key(rec["text"]) if rec else None
            if rec and key in batch:
                rec, problems = None, ["duplicate within the drafts"]
            if rec is None:
                rejected.append((d, problems))
                continue
            batch.add(key)
            accepted.append(rec)
        if not dry_run and accepted:
            existing = self.gen_records()
            for rec in accepted:
                rec["id"] = self.registry.get(dedupe_key(rec["text"]))
                self.keys[dedupe_key(rec["text"])] = rec["id"]
            self.write(existing + accepted)
        return accepted, rejected

    def refresh(self, drop: bool = False) -> list[tuple[dict, list[str]]]:
        """Re-align every generated sentence (after an import); returns the failures (dropped with
        drop=True, else kept unchanged)."""
        out, failed = [], []
        for r in self.gen_records():
            skill, target = parse_src(r.get("src", ""))
            d = {"skill": skill, "target": target, "text": r["text"], **r["tr"]}
            rec, problems = self.check(d, allow_existing=r["id"])
            if rec is None:
                failed.append((r, problems))
                if not drop:
                    out.append(r)
                continue
            out.append(rec)
        self.write(out)
        return failed

    def remaining(self, accepted: list[dict]) -> list[str]:
        """What the skills of these (checked) sentences would still lack once they are added."""
        rep = gaps.analyze(self.pack, self.mat)
        skills = {parse_src(r["src"])[0] for r in accepted}
        lemma = {it["id"]: it["lemma"] for it in self.pack.items}
        out = []
        for row in rep["skills"]:
            sid = row["skill"]
            if sid not in skills:
                continue
            mine = [r for r in accepted if parse_src(r["src"])[0] == sid]
            ids = set(self.mat.resolved[sid])
            easy = row["easy"] + sum(1 for r in mine if any(t.get("lex") in ids for t in r["tokens"]))
            line = f"REMAINING {sid}: easy {easy}/{row['target']}"
            if "slots" in row:
                add = Counter((lemma[t["lex"]], t["form"].split(".", 1)[1]) for r in mine for t in r["tokens"]
                              if t.get("lex") in ids and (t.get("form") or "").startswith(row["tense"] + "."))
                low = {k: v + add[k] for k, v in row["slots"].items() if v + add[k] < gaps.SLOT_TARGET}
                line += f"; slots below {gaps.SLOT_TARGET}: " + (", ".join(
                    f"{v}.{p} needs {gaps.SLOT_TARGET - n}" for (v, p), n in low.items()) or "none")
            else:
                add = Counter(lemma[t["lex"]] for r in mine for t in r["tokens"] if t.get("lex") in ids)
                low = {k: v + add[k] for k, v in row["items"].items() if v + add[k] < gaps.ITEM_TARGET}
                line += f"; items below {gaps.ITEM_TARGET}: " + (", ".join(
                    f"{k} needs {gaps.ITEM_TARGET - n}" for k, n in low.items()) or "none")
            out.append(line)
        return out

    # -- context for writing ----------------------------------------------------------------------
    def context(self, skill: str) -> str:
        g = self.graph
        sk = g.skill[skill]
        rep = gaps.analyze(self.pack, self.mat)
        row = next(s for s in rep["skills"] if s["skill"] == skill)
        lines = [f"# {self.code} skill {skill} ({sk['kind']}), unit {row['unit']}",
                 f"allowed grammar features: {sorted(g.allowed[skill])}",
                 "(present tense always allowed; any feature not listed must NOT appear: e.g. no perfect/past/"
                 "future forms, no modal+infinitive, no articulated prepositions / separable verbs unless listed)",
                 f"easy sentences now: {row['easy']} (target {row['target']})"]
        if "slots" in row:
            lines.append(f"tense: {row['tense']}; slots (verb.person: easy sentences now, need {gaps.SLOT_TARGET}):")
            lines.append("  " + ", ".join(f"{v}.{p} {n}" for (v, p), n in row["slots"].items()))
            tense = row["tense"]
            lines.append("forms of the skill's verbs in this tense:")
            for iid in self.mat.resolved[skill]:
                t = (self.pack.verbs.get(iid) or {}).get("forms", {}).get(tense, {})
                cells = []
                for p in self.pack.course["persons"]:
                    v = t.get(p) or {}
                    f = v.get("form") if isinstance(v, dict) else v
                    alts = v.get("alts", []) if isinstance(v, dict) else []
                    cells.append(f"{p}: {f}" + (f" (/{'/'.join(alts)})" if alts else ""))
                lines.append(f"  {self.items[iid]['lemma']} ({', '.join(self.items[iid]['tr'].get('en', [])[:2])}): "
                             + "; ".join(cells))
        else:
            lines.append(f"items (easy sentences now, need {gaps.ITEM_TARGET}): "
                         + ", ".join(f"{k} {v}" for k, v in row["items"].items()))
        lines.append("")
        lines.append("vocabulary a learner knows at this skill (lemma/pos: gloss), by skill:")
        here = g.pos[skill]
        for sid in g.order[: here + 1]:
            ids = [i for i in self.mat.resolved[sid] if g.item_skill.get(i) == sid]
            if ids:
                lines.append(f"  [{sid}] " + "; ".join(
                    f"{self.items[i]['lemma']}/{self.items[i]['pos']}: {', '.join(self.items[i]['tr'].get('en', [])[:2])}"
                    for i in ids))
        lines.append(f"names allowed (not sentence-initial): {', '.join(sorted(self.names))}")
        return "\n".join(lines)


# ------------------------------------------------------------------------------------------- CLI
def load_drafts(path: Path) -> list[dict]:
    out = []
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        try:
            out.append(json.loads(line))
        except ValueError as e:
            out.append({"_error": f"{path.name}:{n}: {e}"})
    return out


def run(cmd: str, code: str, content_root, args) -> int:
    from .paths import content_dir
    root = content_dir(content_root) / code
    if cmd == "gaps":
        pack = load_pack(root)
        print(gaps.format_gaps(gaps.analyze(pack), verbose=not args.quiet))
        return 0
    gen = Generator(root)
    if cmd == "context":
        text = gen.context(args.skill)
        if args.out:
            Path(args.out).write_text(text + "\n", encoding="utf-8")
        else:
            print(text)
        return 0
    if cmd in ("check", "add"):
        drafts = []
        for f in args.files:
            drafts += load_drafts(Path(f))
        bad = [d for d in drafts if "_error" in d]
        drafts = [d for d in drafts if "_error" not in d]
        for d in bad:
            print("REJECT", d["_error"])
        acc, rej = gen.add(drafts, dry_run=(cmd == "check"))
        for d, problems in rej:
            print(f"REJECT [{d.get('skill')}: {d.get('target')}] {d.get('text')!r}: {'; '.join(problems)}")
        per = Counter(parse_src(r["src"])[0] for r in acc)
        if cmd == "check":
            for line in gen.remaining(acc):
                print(line)
        print(f"{'checked' if cmd == 'check' else 'added'} {len(acc)} accepted, {len(rej) + len(bad)} rejected; "
              + ", ".join(f"{k} {v}" for k, v in sorted(per.items())), file=sys.stderr)
        return 0 if not rej and not bad else 3
    if cmd == "refresh":
        failed = gen.refresh(drop=args.drop)
        for r, problems in failed:
            print(f"FAIL {r['id']} {r['text']!r}: {'; '.join(problems)}")
        print(f"refreshed {len(gen.gen_records())} generated sentences, {len(failed)} failures"
              + (" dropped" if args.drop else " kept unchanged"), file=sys.stderr)
        return 0 if not failed else 3
    return 1
