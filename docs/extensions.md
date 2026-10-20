# Expansions: topics and books

*Design agreed with the owner, 20 October 2026. Scope now: **topic expansions**. Books (a guided e-reader) and moving the stories into that model come later.*

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
    anchor: it.skill.food-basics   # the last required skill in the main tree
    icon: food
    units: [...]                    # same unit/skill structure as the main tree
```

- A topic's skills may require skills from the main tree (the anchor is the last required one) and from earlier skills in the same topic.
- `anchor` defaults to the deepest main-tree skill among the topic's requirements.
- Validator: the anchor exists and is in the main tree (or the base course for an extension pack); no requirement cycles across trees; topic skill ids unique in the family.

## In the app

**On the main tree**, at the anchor skill, a **side branch leaves the map**: it grows off the anchor node and runs out of the screen edge (on very wide screens it fades out instead).
- Along the branch, an arrow and the topic's name are **carved or painted into the bark itself** (not a separate sign): an incised/painted arrow following the branch's curve towards the edge, with the name lettered along it in the storybook style. In B/W it's black incised lines; it must stay legible at phone size (fall back to a short name).
- A clear button next to it: **Go to Food and cooking**.
- Several topics on one anchor: several branches with their carved arrows, alternating sides when space allows.
- Before the anchor is reached, the branch and its carving are shown locked (the topic can still be opened and browsed).

**A topic tree** is its own map, drawn by the same branch-map painter (units as boughs, skills as nodes, tiers, decay, twinkles). Its root shows where it grows from ("from Italian · Food basics") and tapping it goes back.

**Switching trees:** a selector at the top of the map (the app bar title becomes a menu): *Italian (main tree)*, then the topics, each with its progress. The main tree is always first.

**Progress:** words already known from the main tree or another topic count as known (lessons don't reintroduce them); a topic's skill sheet says "34 of 120 words already known".

## Tidying the existing courses

Move self-contained vocabulary clusters out of the main trees into built-in topics, so the main tree stays focused on grammar and core vocabulary. Rule of thumb: a vocab skill whose words no later grammar skill needs, and whose theme forms a coherent group (food, animals, clothes, weather, hobbies, travel, work, home…), becomes a topic anchored at its last requirement. Ids stay the same, so existing progress is kept. The split per course is proposed in a review doc for the owner before it ships.

## Books (later)

Same attachment on the tree (a branch leaving the map with a carved arrow and "Go to <book>"), but it opens a guided e-reader prepared by the pack: chapters, reading readiness per chapter, new words before each chapter, tap-for-gloss while reading. Personal book packs may include the text (never shared) or only word lists and exercises (shareable). `pack from-text` builds them. The current stories move to this model.
