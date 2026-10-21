"""Graded mini-stories (`content/{course}/stories/u{n}.yaml`, written by Claude, `src: claude-gen`).

Each unit has a few short stories (5-10 sentences) that use only the vocabulary taught up to that
unit and only the grammar features allowed there, plus comprehension questions. They are compiled
into `stories`, `story_sentences` (the sentences themselves go into `sentences` + `tokens`, so the
app's tap-for-translation works) and `story_questions` (schema/course_db.sql).

File format (one YAML list per unit file; the file name is only for readability, `unit` decides):

    - id: u1-bar                      # permanent, unique in the course
      unit: u1                        # the unit whose vocabulary and grammar it uses (unlock unit)
      title: {it: "Al bar", en: "At the bar", nl: "In de bar"}
      new_words: [cameriere]          # lemmas taught after the unit (at most one), glossed in the app
      names: [Bella]                  # extra names (besides generate.NAMES) the story may use
      sentences:
        - {it: "Marco è al bar.", en: "Marco is at the bar.", nl: "Marco is in de bar."}
      questions:
        - q: {en: "Where is Marco?", nl: "Waar is Marco?"}   # in the source language
          prompt: "Dove è Marco?"                            # optional: the question in the target language
          options: ["al bar", "a casa", "a scuola"]          # target-language strings ...
          # options: [{en: "At the bar", nl: "In de bar"}, ...]   # ... or source-language i18n
          answer: 0                                          # index of the correct option
          why: {en: "Sentence 1.", nl: "Zin 1."}             # optional explanation

Checks (`validate_stories`, part of `validate`):

* every target-language text (title, sentences, target-language prompts and options) tokenizes, and
  every word is aligned to a lexicon item or is a name (generate.NAMES + `names`) or a number;
* every aligned item is taught in the story's unit or earlier (the unit of the first skill selecting
  it), except at most one *new word* per story (distinct lemma, any number of times), which must be
  listed in `new_words`;
* the grammar features (features.py) of each text are allowed at the unit: the base features plus
  everything the skills of this and earlier units introduce;
* (pack format 1.2) for a story in a topic unit, "earlier" means the topic's units up to its own
  and the main tree's units up to the last one that the topic's skills so far require
  (transitively);
* (the fairness rule, docs/extensions.md) a story may also use up to MAX_TOPIC_WORDS words that
  another tree's topic introduces (for a main-tree story: any topic's words): a learner who skipped
  that topic reads them as unknown words, glossed in the app like the new word. Unknown grammar is
  never allowed. A story that needs more of a topic's words belongs in that topic's units;
* 5-10 sentences of at most 14 words, every course translation present and passing trcheck.py;
* 3-5 questions with 3-4 options, all options non-empty and distinct after folding case,
  punctuation and accents (like the engine's OptionPicker), `answer` in range, i18n options and
  prompts complete for every translation language.

Story sentence ids are `st:{storyId}.{n}` (n = 1-based position); the compiler tags them like any
sentence, and the app keeps them out of the exercise pool (docs/ARCHITECTURE.md, "Stories").
"""
from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

import yaml

from . import features, query, trcheck
from .align import Aligner
from .content import all_units, required_translations, unit_topics
from .lang import get_lang
from .tokens import tokenize
from .topics import anchor_of

SRC = "claude-gen"
MIN_SENTENCES, MAX_SENTENCES = 5, 10
MAX_WORDS = 14
MIN_QUESTIONS, MAX_QUESTIONS = 3, 5
MIN_OPTIONS, MAX_OPTIONS = 3, 4
MAX_NEW_WORDS = 1
# Words of topics the reader may have skipped (the fairness rule: some unknown words are fine,
# unknown grammar never): at most this many distinct items per story, besides its new word.
MAX_TOPIC_WORDS = 3


def load_stories(root: Path) -> list[dict]:
    """All stories of a course, in file order (u1.yaml, u2.yaml, ... by unit number)."""
    d = Path(root) / "stories"
    if not d.exists():
        return []
    out = []

    def key(p: Path):
        m = re.search(r"(\d+)", p.stem)
        return (int(m.group(1)) if m else 1 << 30, p.name)

    for p in sorted(d.glob("*.yaml"), key=key):
        data = yaml.safe_load(p.read_text(encoding="utf-8")) or []
        if not isinstance(data, list):
            raise ValueError(f"{p}: expected a list of stories")
        for s in data:
            s = dict(s)
            s["_file"] = f"stories/{p.name}"
            out.append(s)
    return out


def sentence_id(story_id: str, n: int) -> str:
    return f"st:{story_id}.{n}"


def fold(s: str) -> str:
    """Case, punctuation, spacing and accents folded (like the app's option comparison)."""
    s = unicodedata.normalize("NFD", s.lower().replace("’", "'"))
    s = "".join(ch for ch in s if unicodedata.category(ch) != "Mn")
    s = re.sub(r"[^\w\s]", " ", s)
    return " ".join(s.split())


class StoryChecker:
    """Aligns and checks the stories of one pack. `checked[story_id]` holds the aligned sentences."""

    def __init__(self, pack):
        from .generate import NAMES, PLACES
        self.pack = pack
        c = pack.course
        self.code = c["id"]
        self.translations = list(c["translations"])
        # optional translations (course.yaml required_translations) are used and checked where given
        self.required = required_translations(c)
        self.units = [u["id"] for u in all_units(c)]
        self.items = {it["id"]: it for it in pack.items}
        resolved = {s["id"]: query.resolve(s, pack.items, pack.verbs, query.course_persons(c))
                    for _, _, _, s in pack.skills()}
        self.tagger = features.FeatureTagger(c, pack.items, pack.verbs)
        self.graph = features.SkillGraph(c, resolved, self.tagger)
        skill_unit = {s["id"]: ui for ui, _, _, s in pack.skills()}
        # unit index at which each item is taught, and the topic that introduces it (main tree: none)
        self.item_unit = {iid: skill_unit[sid] for iid, sid in self.graph.item_skill.items()}
        self.item_topic = {iid: self.graph.tree.get(sid) for iid, sid in self.graph.item_skill.items()
                           if self.graph.tree.get(sid) is not None}
        self.unit_topic = unit_topics(c)
        # features allowed at each unit: base + everything introduced in this or an earlier unit
        self.allowed: list[set[str]] = []
        acc = set(self.graph.base)
        n_main = len(c.get("units") or [])
        for unit in (c.get("units") or []):
            for s in unit.get("skills") or []:
                acc |= self.graph.introduces[s["id"]]
            self.allowed.append(set(acc))
        # A story in a topic unit (pack format 1.2) is read once that unit's skills are practised:
        # it may use the topic's words up to its unit, and the main tree's words and grammar up to
        # the last main-tree unit those skills require (the anchor and late requirements alike).
        # `taught[ui]`: the unit indexes whose words a story of unit `ui` may use (None for a
        # main-tree unit: every unit up to it).
        self.taught: list[set[int] | None] = [None] * n_main
        main_unit = {s["id"]: ui for ui, _, _, s in pack.skills() if ui < n_main}
        unit_index = {u["id"]: i for i, u in enumerate(all_units(c))}
        for t in c.get("topics") or []:
            seen: list[str] = []
            own: set[int] = set()
            for unit in t.get("units") or []:
                seen += [s["id"] for s in unit.get("skills") or []]
                own.add(unit_index[unit["id"]])
                reach = max((main_unit[x] for sid in seen for x in self.graph.closure(sid) if x in main_unit),
                            default=main_unit.get(anchor_of(c, t), 0))
                self.taught.append(set(range(reach + 1)) | own)
                self.allowed.append(self.allowed[reach] | {f for sid in seen for f in self.graph.introduces[sid]})
        self.names = set(NAMES.get(self.code, set()))
        self.places = set(PLACES)
        self.aligner = Aligner(get_lang(self.code), pack.items, pack.verbs)
        self.lemmas: dict[str, set[str]] = {}
        for it in pack.items:
            self.lemmas.setdefault(it["lemma"], set()).add(it["id"])

    # -------------------------------------------------------------------------------- one text
    def _align(self, text: str, en: str | None) -> list[dict]:
        return self.aligner.align(tokenize(text, self.code), translation=en)

    def _text_problems(self, al: list[dict], ui: int, names: set[str], later: dict[str, str],
                       where: str) -> list[str]:
        out = []
        for t in al:
            if not t["is_word"]:
                continue
            if t.get("unsure"):
                out.append(f"{where}: the mood of {t['t']!r} is unclear (indicative or subjunctive after 'che')")
            if t["t"] in names:          # a name, even when it is also a lexicon item (Roma)
                continue
            if t["lex"]:
                u = self.item_unit.get(t["lex"])
                taught = self.taught[ui]
                if u is None or (u > ui if taught is None else u not in taught):
                    topic = self.item_topic.get(t["lex"])
                    if topic is not None and topic != self._story_topic:
                        # a word of a topic the reader may have skipped (the fairness rule)
                        self._topic_words.setdefault(t["lex"], t["t"])
                    else:
                        later.setdefault(t["lex"], t["t"])
                continue
            if t["t"].isdigit() or t["t"] in names:
                continue
            out.append(f"{where}: unaligned word {t['t']!r}")
        if self.graph.enforced:
            extra = self.tagger.tag(al) - self.allowed[ui]
            if extra:
                out.append(f"{where}: features {sorted(extra)} not allowed at unit {self.units[ui]}")
        return out

    # -------------------------------------------------------------------------------- one story
    def check(self, s: dict) -> tuple[dict | None, list[str]]:
        """(compiled story, problems)."""
        sid = s.get("id")
        where0 = f"{self.code}/{s.get('_file', 'stories')}: story {sid}"
        problems: list[str] = []
        if not sid or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", str(sid)):
            return None, [f"{where0}: bad or missing id"]
        unit = s.get("unit")
        if unit not in self.units:
            return None, [f"{where0}: unknown unit {unit!r}"]
        ui = self.units.index(unit)
        names = self.names | set(s.get("names") or [])
        later: dict[str, str] = {}
        self._story_topic = self.unit_topic.get(unit)
        self._topic_words: dict[str, str] = {}

        title = s.get("title") or {}
        if not isinstance(title, dict) or not title.get(self.code):
            problems.append(f"{where0}: title needs the {self.code} text")
        title_tr = {l: str(title.get(l) or "").strip() for l in self.translations}
        for l, v in title_tr.items():
            if not v and l in self.required:
                problems.append(f"{where0}: title needs a {l} translation")
        title_tr = {l: v for l, v in title_tr.items() if v}
        if title.get(self.code):
            try:
                al = self._align(title[self.code], title_tr.get("en"))
                problems += self._text_problems(al, ui, names, later, f"{where0} title")
            except ValueError as e:
                problems.append(f"{where0} title: {e}")

        raw = s.get("sentences") or []
        if not MIN_SENTENCES <= len(raw) <= MAX_SENTENCES:
            problems.append(f"{where0}: {len(raw)} sentences (want {MIN_SENTENCES}-{MAX_SENTENCES})")
        sentences = []
        for n, r in enumerate(raw, 1):
            where = f"{where0} sentence {n}"
            text = " ".join(str((r or {}).get(self.code) or "").split())
            tr = {l: " ".join(str(r.get(l) or "").split()) for l in self.translations}
            if not text:
                problems.append(f"{where}: no {self.code} text")
                continue
            for l, v in tr.items():
                if not v and l in self.required:
                    problems.append(f"{where}: no {l} translation")
            tr = {l: v for l, v in tr.items() if v}
            try:
                al = self._align(text, tr.get("en"))
            except ValueError as e:
                problems.append(f"{where}: {e}")
                continue
            words = [t for t in al if t["is_word"]]
            if len(words) > MAX_WORDS:
                problems.append(f"{where}: {len(words)} words (max {MAX_WORDS})")
            problems += self._text_problems(al, ui, names, later, where)
            tr_names = names - self.places
            for l, v in tr.items():
                if v:
                    why = trcheck.mismatch(al, self.items, self.code, v, l, tr_names if l == "en" else frozenset())
                    if why:
                        problems.append(f"{where}: {l} translation: {why}")
            sentences.append({"id": sentence_id(sid, n), "text": text, "tr": tr, "tokens": al,
                              "features": sorted(self.tagger.tag(al))})

        questions = []
        raw_q = s.get("questions") or []
        if not MIN_QUESTIONS <= len(raw_q) <= MAX_QUESTIONS:
            problems.append(f"{where0}: {len(raw_q)} questions (want {MIN_QUESTIONS}-{MAX_QUESTIONS})")
        for n, q in enumerate(raw_q, 1):
            where = f"{where0} question {n}"
            q = q or {}
            prompt_tr = {l: str((q.get("q") or {}).get(l) or "").strip() for l in self.translations}
            for l, v in prompt_tr.items():
                if not v and l in self.required:
                    problems.append(f"{where}: no {l} question")
            prompt_tr = {l: v for l, v in prompt_tr.items() if v}
            prompt = " ".join(str(q.get("prompt") or "").split()) or None
            if prompt:
                try:
                    problems += self._text_problems(self._align(prompt, prompt_tr.get("en")), ui, names, later,
                                                    f"{where} prompt")
                except ValueError as e:
                    problems.append(f"{where} prompt: {e}")
            options = q.get("options") or []
            if not MIN_OPTIONS <= len(options) <= MAX_OPTIONS:
                problems.append(f"{where}: {len(options)} options (want {MIN_OPTIONS}-{MAX_OPTIONS})")
            kinds = {isinstance(o, dict) for o in options}
            if len(kinds) > 1:
                problems.append(f"{where}: mixes target-language and translated options")
            out_opts: list = []
            if kinds == {True}:
                langs = [l for l in self.translations
                         if l in self.required or any(str(o.get(l) or "").strip() for o in options)]
                for l in langs:
                    vals = [str(o.get(l) or "").strip() for o in options]
                    if any(not v for v in vals):
                        problems.append(f"{where}: an option lacks its {l} text")
                    elif len({fold(v) for v in vals}) != len(vals):
                        problems.append(f"{where}: duplicate {l} options {vals}")
                out_opts = [{l: str(o.get(l) or "").strip() for l in langs} for o in options]
            else:
                vals = [" ".join(str(o or "").split()) for o in options]
                if any(not v or not fold(v) for v in vals):
                    problems.append(f"{where}: empty option")
                elif len({fold(v) for v in vals}) != len(vals):
                    problems.append(f"{where}: duplicate options {vals}")
                for k, v in enumerate(vals):
                    if v:
                        try:
                            problems += self._text_problems(self._align(v, None), ui, names, later,
                                                            f"{where} option {k + 1}")
                        except ValueError as e:
                            problems.append(f"{where} option {k + 1}: {e}")
                out_opts = vals
            answer = q.get("answer")
            if not isinstance(answer, int) or not 0 <= answer < len(options):
                problems.append(f"{where}: answer {answer!r} is not an option index")
            why = q.get("why") or {}
            explanation = {l: str(why.get(l) or "").strip() for l in self.translations if why.get(l)}
            if why and not all(l in explanation for l in self.required):
                problems.append(f"{where}: explanation needs every translation language")
            questions.append({"prompt": prompt, "prompt_tr": prompt_tr, "options": out_opts,
                              "correct": answer, "explanation_tr": explanation})

        declared = [str(w) for w in (s.get("new_words") or [])]
        if len(declared) > MAX_NEW_WORDS:
            problems.append(f"{where0}: {len(declared)} new words (max {MAX_NEW_WORDS})")
        declared_ids = set()
        for w in declared:
            ids = self.lemmas.get(w)
            if not ids:
                problems.append(f"{where0}: new word {w!r} is no lexicon item")
            declared_ids |= ids or set()
        topic_words = self._topic_words
        for i in declared_ids & set(topic_words):      # a declared topic word is the story's new word
            later[i] = topic_words.pop(i)
        used = set(later)
        undeclared = sorted(f"{later[i]} ({i})" for i in used if i not in declared_ids)
        if undeclared:
            problems.append(f"{where0}: words taught after unit {unit}: {undeclared}"
                            + ("" if declared else " (declare at most one in new_words)"))
        if len(used) > MAX_NEW_WORDS:
            problems.append(f"{where0}: {len(used)} new words {sorted(later.values())} (max {MAX_NEW_WORDS})")
        for w in declared:
            if not (self.lemmas.get(w, set()) & used):
                problems.append(f"{where0}: new word {w!r} is not used")
        if len(topic_words) > MAX_TOPIC_WORDS:
            problems.append(f"{where0}: {len(topic_words)} words of topics "
                            f"{sorted(f'{v} ({self.item_topic[i]})' for i, v in topic_words.items())} "
                            f"(max {MAX_TOPIC_WORDS}); a story about a topic belongs in that topic's units")
        if problems:
            return None, problems
        return {"id": sid, "unit": unit, "title": title[self.code].strip(), "title_tr": title_tr,
                # the new word and the topic words, glossed before the story in the app
                "new_words": sorted(used | set(topic_words)), "topic_words": sorted(topic_words),
                "sentences": sentences, "questions": questions, "src": f"{SRC} (story)"}, []

    def check_all(self) -> tuple[list[dict], list[str]]:
        stories, problems = [], []
        seen: set[str] = set()
        for s in self.pack.stories:
            if s.get("id") in seen:
                problems.append(f"{self.code}: duplicate story id {s.get('id')}")
                continue
            seen.add(s.get("id"))
            rec, p = self.check(s)
            problems += p
            if rec:
                stories.append(rec)
        return stories, problems


def validate_stories(pack) -> list[str]:
    if not pack.stories:
        return []
    return StoryChecker(pack).check_all()[1]


def _j(v) -> str:
    return json.dumps(v, ensure_ascii=False, separators=(",", ":"))


def _tr_json(tr: dict, order: list[str]) -> str:
    return _j({k: tr[k] for k in [*order, *sorted(set(tr) - set(order))] if k in tr})


def compile_stories(con, pack) -> dict:
    """Writes the stories into an open course database (schema already created). Assumes the pack
    validated. Returns counts."""
    if not pack.stories:
        return {"stories": 0, "story_sentences": 0, "story_questions": 0}
    checker = StoryChecker(pack)
    stories, problems = checker.check_all()
    if problems:
        raise ValueError("stories do not validate:\n" + "\n".join(problems))
    order = checker.translations
    ords: dict[str, int] = {}
    n_sent = n_q = 0
    for st in stories:
        o = ords.get(st["unit"], 0)
        ords[st["unit"]] = o + 1
        con.execute("INSERT INTO stories(id, unit_id, ord, title, title_tr, src, new_words) VALUES (?,?,?,?,?,?,?)",
                    (st["id"], st["unit"], o, st["title"], _tr_json(st["title_tr"], order), st["src"],
                     _j(st["new_words"])))
        for i, s in enumerate(st["sentences"]):
            con.execute("INSERT INTO sentences(id, text, tr, src, unit_id) VALUES (?,?,?,?,?)",
                        (s["id"], s["text"], _tr_json(s["tr"], order), f"{SRC} (story: {st['id']})", st["unit"]))
            for k, t in enumerate(s["tokens"]):
                con.execute("INSERT INTO tokens(sentence_id, idx, t, pre, is_word, lex, form) VALUES (?,?,?,?,?,?,?)",
                            (s["id"], k, t["t"], t.get("pre") or "", 1 if t["is_word"] else 0, t.get("lex"),
                             t.get("form")))
            for f in s["features"]:
                con.execute("INSERT INTO sentence_features(sentence_id, feature) VALUES (?, ?)", (s["id"], f))
            con.execute("INSERT INTO story_sentences(story_id, idx, sentence_id) VALUES (?,?,?)", (st["id"], i, s["id"]))
            n_sent += 1
        for i, q in enumerate(st["questions"]):
            con.execute("INSERT INTO story_questions(story_id, idx, prompt, prompt_tr, options, correct, explanation_tr)"
                        " VALUES (?,?,?,?,?,?,?)",
                        (st["id"], i, q["prompt"], _tr_json(q["prompt_tr"], order),
                         _j([o if isinstance(o, str) else {k: o[k] for k in order if k in o} for o in q["options"]]),
                         q["correct"], _tr_json(q["explanation_tr"], order)))
            n_q += 1
    return {"stories": len(stories), "story_sentences": n_sent, "story_questions": n_q}


def run_check(code: str, content_root=None, show: str | None = None) -> int:
    """`python -m pipeline stories it`: check only the stories (quicker than a full validate)."""
    import sys

    from .content import load_pack
    from .paths import content_dir
    pack = load_pack(content_dir(content_root) / code)
    checker = StoryChecker(pack)
    stories, problems = checker.check_all()
    for p in problems:
        print(p)
    if show:
        for st in stories:
            if show != "all" and st["unit"] != show:
                continue
            print(f"# {st['id']} ({st['unit']}) new words: {st['new_words']}"
                  + (f" (topic words: {st['topic_words']})" if st["topic_words"] else ""))
            for s in st["sentences"]:
                print("  " + " ".join(
                    t["t"] + (f"/{checker.items[t['lex']]['lemma']}" if t.get("lex") else "")
                    + (f"[{t['form']}]" if t.get("form") else "") for t in s["tokens"] if t["is_word"]))
    per: dict[str, int] = {}
    for s in stories:
        per[s["unit"]] = per.get(s["unit"], 0) + 1
    print(f"[{code}] {len(stories)} stories ok, {len(pack.stories) - len(stories)} failing; per unit: "
          + ", ".join(f"{u} {n}" for u, n in per.items()), file=sys.stderr)
    return 0 if not problems else 3
