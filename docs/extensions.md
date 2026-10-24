# Expansions: topics and books

*Design agreed with the owner, 20 October 2026. Scope now: **topic expansions**. Books (a guided e-reader) and moving the stories into that model come later.*

**Status (21 October 2026): built-in topics are implemented**: pack format 1.2 (`topics:` in course.yaml, compiled `topics` / `topic_units`, schema minor 3, docs/pack-format.md 3.3), the validator rules, and the app (branches with a carved name on the main tree, the branch itself opening the topic, topic maps, the tree menu, "N of M words already known"; docs/ui.md "Topic trees"). Not yet: extension packs with `extends` (separately installed topics), books. **Amended 21 October** (owner decisions): a topic's anchor is its entry point, and later skills of a topic may require later main-tree skills (late requirements; locked with a "needs …" note until started). **The real courses are restructured** (owner decisions of 21 October, packs it 1.5.0, nl 1.4.0, es 1.1.0): a slim main tree of grammar and core vocabulary plus themed topics, under the fairness rule below; see [topic-split.md](topic-split.md). (The strict split before it, it 1.4.0 and nl 1.3.0, is in that file's history.)

An expansion adds content to a base course (e.g. Italian) **and shares the learner's progress with it**: a word the base course already taught keeps its progress in the expansion, and a word two expansions share has one progress.

## Kinds

| Kind | What it is | Opens as | Status |
| --- | --- | --- | --- |
| **Topic** | A themed set of skills (food and cooking, travel, work, medicine, football…) | Its own **tree**, drawn like the main map | now |
| **Book** | A pack prepared for reading one book (chapters, new words, readiness) | A **guided e-reader** (prepared by the pack) | later |
| Stories | Today's graded mini-stories | Same model as books | later |

## Backend (agreed)

- **Same ids = shared progress.** Progress is stored per facet id, and the review log only records facet ids, so an expansion that reuses the base course's item ids shares progress and sync automatically.
- **`extends: <base> >= <version>`** in `course.yaml` for an expansion shipped as its own pack; the app requires the base to be installed. An expansion's id is `<base>.<name>` (e.g. `it.cucina`). Expansions join the base's **course family**: XP, level, streak and mistakes are kept per family.
- **Ids for words the base doesn't have** are derived from the word: `<lang>~<lemma>.<pos>` (e.g. `it~commissario.n`), so two independently built expansions share them, and a later base version that adds the word reuses the same id. Dialect variants are their own items with `variant_of: <base item>` (they start as "familiar").
- **Grammar comes from the base:** expansion skills may require base skills; gating uses the learner's base progress.
- **Topics inside a pack:** a pack can also contain topic trees directly (built-in topics). Built-in and separately installed topics behave the same in the app.
- **Sync:** progress syncs as today (facet events). Which expansion packs are installed syncs as a setting; personal pack files themselves don't sync (another device asks for the file).

## Data model

```yaml
# course.yaml (base or expansion)
topics:
  - id: cucina
    title: {en: "Food and cooking"}
    anchor: it.skill.food-basics   # where the topic starts: the last main-tree skill its first skill requires
    icon: food
    units: [...]                    # same unit/skill structure as the main tree
```

- A topic's skills may require skills from the main tree and from earlier skills in the same topic.
- The **anchor is the topic's entry point**: the last main-tree skill its first skill requires (`anchor` defaults to the deepest of those). A later skill of the topic may require a later main-tree skill (a **late requirement**): it stays locked, with a note on its node and in its sheet ("needs Condizionale · unit 12", which leads there), until that skill is started.
- Validator: the anchor exists and is in the main tree (or the base course for an extension pack); no requirement cycles across trees; topic skill ids unique in the family. As built: every other main-tree requirement of the topic's first skill is a prerequisite of the anchor or a sibling no deeper than it (later skills may have late requirements); main-tree skills require no topic skill and use no topic's words; a sentence touching several trees has one home skill per tree.

## In the app

**On the main tree**, at the anchor skill, a **side branch leaves the map**: it grows off the anchor node and runs out of the screen edge (on very wide screens it fades out instead).
- Along the branch, an arrow and the topic's name are **carved or painted into the bark itself** (not a separate sign): an incised/painted arrow following the branch's curve towards the edge, with the name lettered along it in the storybook style. In B/W it's black incised lines; it must stay legible at phone size (fall back to a short name).
- The branch itself is the way in: a tap on it (a band at least 48 dp thick along it, with press feedback) opens the topic; for screen readers and the keyboard it is a button, **Go to Food and cooking**. (A separate "Go to" button under the branch was dropped on 24 October: the carved name is enough.)
- Several topics on one anchor: several branches with their carved arrows, alternating sides when space allows.
- Before the anchor is reached, the branch and its carving are shown locked (the topic can still be opened and browsed).

**A topic tree** is its own map, drawn by the same branch-map painter (units as boughs, skills as nodes, tiers, decay, twinkles). Its root shows where it grows from ("from Italian · Food basics") and tapping it goes back.

**Switching trees:** a selector at the top of the map (the app bar title becomes a menu): *Italian (main tree)*, then the topics, each with its progress. The main tree is always first.

**Progress:** words already known from the main tree or another topic count as known (lessons don't reintroduce them); a topic's skill sheet says "34 of 120 words already known".

## Tidying the existing courses

Move themed vocabulary out of the main trees into built-in topics, so the main tree stays focused on grammar and core vocabulary and a learner may skip a theme. Ids stay the same, so existing progress is kept.

**The structure (owner decision, 21 October):** grammar skills depend only on **core vocabulary** (people, family, numbers, time, home, everyday verbs, adjectives, basic food, city and travel basics, little words and connectors). Themed vocabulary (weather, animals, clothes, hobbies, more food, media, nature, health, services, money, emotions and character, society, reading) leaves the main chain and becomes topics that branch off where their needs are met: the anchor is the entry point, and inner skills of a topic may require later main-tree skills. The main tree never requires a topic skill. (It replaces the strict rule of 20–21 October, under which a skill moved only when nothing below it needed it: Italian `crime` and Dutch `clothes`.)

**The fairness rule: never unknown grammar; some unknown words are fine.**

- **Grammar is gated strictly everywhere**, main tree and topics: a sentence is shown only when every grammar feature it uses belongs to a started skill or its prerequisites (pack-format 12.4). Nothing about topics loosens this.
- **Words of a skipped topic are unknown words.** They may appear in main-tree lessons within the app's existing cap (at most 1 unknown word per sentence with a grammar focus or in a grammar skill, 2 otherwise); the hint glosses them. A main-tree story (or another topic's story) may use up to **three** words of topics outside its tree besides its one new word; they are glossed before the story. A story that is mainly about a theme lives in that topic's units instead.
- **Every main-tree grammar skill keeps its sentence floor for the learner who skipped every topic**: enough easy sentences (40), 8 per verb × person slot, 3 per item, counting topic words as unknown. Where the restructure made a pool thin, validated generated sentences (`src: claude-gen`) from core vocabulary top it up.
- **Where it lives.** Pipeline: `stories.MAX_TOPIC_WORDS` and the story checker (topic words in `topic_words`, compiled into `new_words`); `gaps.fairness_report` (`python -m pipeline gen floor <course>`), run by every build and validate of a gated pack with topics: a floor lost only to topic words fails the build (pack-format 16, rule 14c). Tests: `pipeline/tests/test_topics.py` (topic words in stories, the floor check), and in the app `real_pack_gating_test.dart` ("fairness": a learner who skipped every topic gets full, gated lessons and at least 40 usable sentences in every main-tree grammar skill) and `real_pack_stories_test.dart` (2–3 stories per main unit, at most one new word plus three topic words). The app itself needed no change: its gating and unknown-word cap already treat a skipped topic's words as unknown.

## Books (later)

Same attachment on the tree (a branch leaving the map with a carved arrow and "Go to <book>"), but it opens a guided e-reader prepared by the pack: chapters, reading readiness per chapter, new words before each chapter, tap-for-gloss while reading. Personal book packs may include the text (never shared) or only word lists and exercises (shareable). `pack from-text` builds them. The current stories move to this model.
