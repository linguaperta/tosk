# Architecture and contracts

This file holds the decisions every part of the codebase depends on. `docs/SPEC.md` is the product spec, and `BACKLOG.md` tracks the work.
Change a contract here first, then in code.

## Repositories

| Repo | Contents | License |
| --- | --- | --- |
| `tosk` (this repo) | `app/` Flutter app, `pipeline/` Python content pipeline, `schema/` JSON Schemas and the compiled-DB DDL, `docs/` | app code: MIT |
| `tosk-data` (sibling checkout at `../tosk-data`) | `content/{it,nl}/` JSONL source packs, `course.yaml`, grammar notes; `dist/` built packs and `index.json`; `ATTRIBUTION.md` | CC BY-SA 4.0 |

- **Sarnami:** the scraped Sarnami data (`hns`) is all rights reserved. It must **never** be committed to either public repo; it lives in an untracked local folder.
- **Caches:** raw downloads (kaikki dumps, Tatoeba exports, frequency lists) go in a cache outside both repos, `%LOCALAPPDATA%/tosk-cache` by default, overridable with `TOSK_CACHE`.
- **Bundled packs:** the built packs are copied into `app/assets/courses/{id}.sqlite` (via `python -m pipeline build ... --install`), so v1 works fully offline without downloads.

## Toolchain (this machine)

- Flutter is in `C:\Users\timo\dev\flutter\bin` (stable 3.47.x, Dart 3.13), and it is not on PATH by default. Use the full path or prepend it.
- `JAVA_HOME=C:\Users\timo\dev\jdk-17.0.20.1+1` and `ANDROID_HOME=C:\Users\timo\dev\android`.
- The pipeline runs on Python 3.13 with a venv at `pipeline/.venv`.

## Compiled course database

The DDL in `schema/course_db.sql` is the authoritative definition. The key points:

- Skill membership (`skill_items`) and skill facets (`skill_facets`) are resolved **at compile time** from the `course.yaml` queries. The app never interprets queries, so it needs no grammar knowledge.
- Persons, tenses, tense labels and article options live in `meta` as JSON. The app reads them, and nothing in the app is language-specific.
- The course database is opened read-only. The progress database is a separate file.

## Identifiers (permanent)

- **Course id:** the target language code (`it`, `nl`, `hns`).
- **Item id:** `{course}:{lemma}`. A homograph that needs separate entries (for example a different POS) gets `{course}:{lemma}.{n}` with `n = 2, 3, …`. IDs are recorded in `content/{course}/ids.tsv` (id, lemma, pos, sense-key), and the importer reuses existing IDs. An ID is never reassigned to a different word or reused after deletion.
- **Sentence id:** `s:{tatoebaId}` for Tatoeba sentences. Other sources get their own prefix (`sil:…`, `x:…`).
- **Facet id:**
  - `{itemId}#rec`: recognize, from target to meaning
  - `{itemId}#prod`: produce, from meaning to target
  - `{itemId}#form:{tense}`: one verb's forms in one tense, for example `it:mangiare#form:presente`
  - `{itemId}#article`: a noun's article or gender (extends the spec for the de/het and article skills)
- **Skill id and unit id:** unique within a course. In the progress DB, skill-level records are keyed `{course}/{skillId}`.

Which facets a skill trains is decided by the pipeline:

| Skill kind | Facets |
| --- | --- |
| vocab | `#rec` and `#prod` for each item |
| grammar with `verbs: {tense: T}` | `#form:T` for each verb (and `#rec` for verbs not yet seen elsewhere is NOT added; recognition belongs to vocab skills) |
| grammar with `items:` and `facet: article` | `#article` for each noun |

## Exercise type ids

`flashcard`, `multiple_choice`, `match_pairs`, `conj_pick`, `conj_grid`, `sentence_builder`, `cloze`, `spot_error`, `transform`. `listen_pick` is reserved for later and not in v1.

These ids appear in `course.yaml` (`exercises:`), in `skills.exercises`, in `review_log.exercise_type`, and in the focus-preset config (`app/assets/config/focus_presets.json`).

`review_log.exercise_type` may also hold `test_out` (`kTestOutCreditType`): a **test-out credit**, not an answer. Passing a test out or a placement writes one per not-yet-learned facet of the credited skills (rating Easy, correct, mode `testOut` or `placement`). Credits graduate the facets (the skill is learned and what follows unlocks) and sync like any event; progression gives them no XP and doesn't count them as reviews. See `docs/engine.md`.

It may also hold `override` (`kOverrideType`): an **answer override** ("I was right"). The learner says an answer graded wrong was right; the app appends an event on the same facet, later in time, with rating Good, `correct`, input `self`, `responseMs` 0 and the overridden event's id in `answer`. **Replay rule** (`applyOverrides` in `core/models/progress.dart`, applied by every replay: `ProgressRepo.record`/`importEvents`/`rebuildStates`, `InMemoryProgressStore`, progression's `LogReplay`): the override rewrites its target's rating and verdict in place, at the target's time, and is itself skipped. So the facet's state, XP and challenges are exactly those of a right answer, `rebuildStates()` stays exact, the override earns no XP and is no review, and the log stays append-only (it syncs like any event). An override whose target isn't in the log yet does nothing until it arrives; of several overrides of one event the last in `(at, id)` order wins. `openMistakes` treats an overridden mistake as resolved.

## FSRS ratings

`1 = Again`, `2 = Hard`, `3 = Good`, `4 = Easy`. Auto-graded results: a wrong answer is Again, a right answer is Good, and a right answer faster than the type's fast-answer threshold is Easy. Flashcards use self-grade buttons (Again, Hard, Good, Easy).

## App layout (`app/lib/`)

```
core/          domain models + interfaces shared by every layer (no Flutter imports, no drift)
  models/      Course, Unit, Skill, Item, Verb, VerbForm, Sentence, Token, FacetId, ...
  interfaces/  PackSource, SyncBackend, AnswerInput, Explainer (+ ExplainContext, MistakeContext),
               ExplanationCache, FlagStore (feedback.dart)
data/          drift databases + repositories (Phase 2)
  course/      CourseDb (read-only), CourseRepo
  progress/    ProgressDb, ProgressRepo, settings
  fsrs/        scheduler (pure Dart)
  packs/       LocalPackSource (+ asset bootstrap)
engine/        exercise engine, pure Dart (Phase 3): templates, distractors, normalization, sessions, grading
progression/   XP, levels, tiers, streaks, challenges, combos, pure functions over the review log (Phase 5)
ai/            AI explanations (v0.3): ClaudeExplainer, OpenAiExplainer, CachingExplainer, prompts, AiConfig, SecretStore
feedback/      exercise snapshots, answer context, flags JSON Lines export (v0.3)
audio/         SoundService over audioplayers (v0.3); the sounds come from tool/make_sounds.py
ui/            Flutter screens and widgets (Phase 4): map, lesson player, lab, non-stop, settings, debug, ai/, feedback/
  theme/       skins (default skin now, forest later)
app.dart, main.dart, providers.dart (Riverpod wiring)
```

Dependency direction: `ui → engine, progression, data → core`. `ai`, `feedback` and `audio` sit beside `data`: they use `core`, and `feedback` also uses the engine's `exercisePrompt`. `docs/feedback.md` describes AI explanations, flags and sounds. `engine` and `progression` depend only on `core`, with data access through small interfaces such as `CourseData` and `ProgressReader`. That keeps them pure Dart and testable with in-memory fixtures. `data` implements those interfaces.

## Testing

- `pipeline/`: pytest. Tests use small fixture JSONL and dump snippets checked into `pipeline/tests/fixtures`, never the network.
- `app/`: `flutter test`. Engine and progression tests run on in-memory fixtures, data tests use in-memory SQLite, and there are integration tests against the real bundled packs in `app/assets/courses/`.
- Every phase ends with tests passing and `flutter analyze` clean.

## Grammar gating: learn a concept before meeting it (added for v0.3)

The rule: a learner should not meet a grammar construct in exercises (for example *ho mangiato*) before starting the skill that teaches it. Some new **vocabulary** is fine, even in grammar exercises, but only a little, since the focus there is grammar.

Contract (additive to `schema/course_db.sql`, schema version stays 1.x):

```sql
-- Grammar features each sentence uses, derived by the pipeline from token alignment plus language rules.
CREATE TABLE sentence_features (sentence_id TEXT NOT NULL, feature TEXT NOT NULL, PRIMARY KEY (sentence_id, feature));
-- Features a skill introduces. Grammar skills introduce their tense or construct.
CREATE TABLE skill_features (skill_id TEXT NOT NULL, feature TEXT NOT NULL, PRIMARY KEY (skill_id, feature));
-- meta key 'base_features': JSON array of features allowed from the start (e.g. the present tense of very common verbs).
```

- **Feature names:** these are course data, not app code: `tense:{tense}` (`tense:passato_prossimo`, `tense:imperfetto`, `tense:verleden_tijd`, …) plus construct features the course declares (`aux:essere`, `reflexive`, `modal`, `prep:articulated`, `separable`, …).
  - `course.yaml` lists `base_features`, and each skill can add an `introduces: [...]` list.
  - A grammar skill with `verbs: {tense: T}` introduces `tense:T` automatically.
- **Pipeline:** tags every sentence with the features its tokens show. A compound form tags its tense, and the auxiliary is not tagged as present. The validator checks that every feature used by a skill's own sentences is introduced by that skill, one of its prerequisites (transitively), or the base set.
- **Engine** (`app/lib/engine/gating.dart`; details in docs/engine.md, "Grammar gating and sentence variety"):
  - At session start, compute `knownFeatures` = base ∪ the features of every skill the learner has *started* ∪ the current skill's features (lesson: its skill; lab: the chosen skills; non-stop, fading, review: none). Prerequisites of started and current skills count too (their sentences are built on them), and a skill answered during the session counts as started from then on.
  - Sentence-based templates only use sentences whose features ⊆ `knownFeatures`; transform's target tense must be known too, and wrong options never show forms of an unknown tense.
  - Unknown vocabulary is capped: counted over word tokens aligned to items outside the learner's started (and current) skills, at most 2 per sentence for vocab focus and 1 for grammar focus or a grammar skill. An unaligned word counts 0 when it is a name or a number and 2 otherwise. Sentences with fewer unknown words are preferred.
  - A template that finds no eligible sentence returns `canGenerate == false`, and another template is used. Packs without `base_features` are not gated.
  - Variety: sentences not seen recently are preferred (a 1000-id LRU per course in the settings key `engine.recent_sentences.{course}`), a session never repeats a sentence while the facet has others, and the previous exercise type is avoided when another type can serve the facet.
- **Time adverbs** (`meta.time_adverbs`, optional JSON `{adverb: [tense, ...]}` from course.yaml `time_adverbs`): the tenses a time adverb fits. The transform exercise never rewrites a sentence with one into another tense.
