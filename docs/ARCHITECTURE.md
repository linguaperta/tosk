# Architecture and contracts

This file holds the decisions every part of the codebase depends on. `docs/SPEC.md` is the product spec, and `BACKLOG.md` tracks the work.
Change a contract here first, then in code. The pack format as a standalone spec for pack makers (source layout, ids, facets, compiled pack, catalogs, versioning, validator rules) is `docs/pack-format.md`; keep the two in step.

## Repositories

| Repo | Contents | License |
| --- | --- | --- |
| `tosk` (this repo) | `app/` Flutter app, `pipeline/` Python content pipeline, `schema/` JSON Schemas and the compiled-DB DDL, `docs/` | app code: MIT |
| `tosk-data` (sibling checkout at `../tosk-data`) | `content/{it,nl}/` JSONL source packs, `course.yaml`, grammar notes; `dist/` built packs and `index.json`; `ATTRIBUTION.md` | CC BY-SA 4.0 |

- **Sarnami:** the Sarnami data (`hns`) is all rights reserved. It must **never** be committed to either public repo; its importer is a private pipeline plugin and its data lives in a private repo or an untracked local folder (`pipeline/pipeline/restricted.py` enforces this).
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

- **Course id:** the target language code (`it`, `nl`, `hns`); an expansion is `<base>.<name>` (`it.cucina`). Ids name files, so the app accepts only `isValidCourseId` ids (`core/course_id.dart`: lower-case ASCII letters, digits, `-`, `_`, at most one dot; docs/data-layer.md).
- **Item id:** `{course}:{lemma}`. A homograph that needs separate entries (for example a different POS) gets `{course}:{lemma}.{n}` with `n = 2, 3, …`. IDs are recorded in `content/{course}/ids.tsv` (id, lemma, pos, sense-key), and the importer reuses existing IDs. An ID is never reassigned to a different word or reused after deletion.
- **Sentence id:** `s:{tatoebaId}` for Tatoeba sentences. Other sources get their own prefix (`gen:…`, `x:…`).
- **Facet id:**
  - `{itemId}#rec`: recognize, from target to meaning
  - `{itemId}#prod`: produce, from meaning to target
  - `{itemId}#form:{tense}`: one verb's forms in one tense, for example `it:mangiare#form:presente`
  - `{itemId}#article`: a noun's article or gender (extends the spec for the de/het and article skills)
  - `{itemId}#infl:{table}`: one inflection table of a non-verb, for example `it:gatto#infl:number` (plural), `it:bello#infl:agreement` (m.sg/f.sg/m.pl/f.pl), `nl:huis#infl:diminutive` (schema minor 1; see "Inflection tables")
- **Skill id and unit id:** unique within a course. In the progress DB, skill-level records are keyed `{course}/{skillId}`.

Which facets a skill trains is decided by the pipeline:

| Skill kind | Facets |
| --- | --- |
| vocab | `#rec` and `#prod` for each item |
| grammar with `verbs: {tense: T}` | `#form:T` for each verb (and `#rec` for verbs not yet seen elsewhere is NOT added; recognition belongs to vocab skills) |
| grammar with `items:` and `facet: article` | `#article` for each noun |
| grammar with `items:`, `facet: infl` and `inflections: {table: T}` | `#infl:T` for each item whose table T has at least two different forms (the query keeps only those) |
| any `items:` skill with `inflections: {table: T}` and no `facet` | `#rec` and `#prod` for each item, plus `#infl:T` for each item that inflects |

## Inflection tables (schema minor 1)

Verbs have conjugation tables (`verb_forms`). Every other part of speech can have **inflection tables**, generic over the language (additive to `schema/course_db.sql`; `meta.schema_minor = 1`, the major version stays 1):

```sql
CREATE TABLE inflections (item_id, tbl, cell, form, stem, ending, alts, wrong, PRIMARY KEY (item_id, tbl, cell));
-- meta 'inflection_tables': {table: {pos, cells (display order), base, agreement, title, labels}}
```

- **Tables are course data.** `course.yaml` declares them (`inflection_tables`), the pipeline fills them per item (`pipeline/pipeline/inflect.py`, one builder per language and table), the app reads the cells and labels from meta. Italian: `number` (`sg`/`pl`) and `agreement` (`m.sg`/`f.sg`/`m.pl`/`f.pl`, adjectives and determiners such as the possessives). Dutch: `number`, `agreement` (`base`/`infl`: *groot*/*grote*), `comparison` (`base`/`comparative`/`superlative`, imported but not trained yet) and `diminutive` (`sg`/`dim`). German and Slavic cases are the same shape (`nom.sg` … `gen.pl`).
- **`base`** is the cell equal to the lemma: given, never asked by the ending picker.
- **`agreement: true`** means the cell follows from the sentence (the adjective agrees with its noun), so in an aligned sentence every other cell of the item is a wrong option. Otherwise the cells differ in meaning (singular vs plural, a diminutive), and sentence exercises only offer the cell's **`wrong`** forms: plausible learner errors that the pipeline checked are no word of the language (`katen`, `huisen`, `wite`, `huistje`), so they can never be right against the translation.
- **Token forms:** an aligned inflected non-verb has `Token.form = 'infl:{table}.{cell}'` (`infl:number.pl`, `infl:agreement.f.sg`). The `infl:` prefix keeps these apart from verb keys `'{tense}.{person}'` (tense keys never contain a colon); the cell is everything after the first dot. `Token.tense`/`person` are null for them. The pipeline sets an agreement cell only where its language rules found the controlling noun (Italian: the adjacent noun or the noun before a copula with a fixed gender and a known number; Dutch: the attributive rule de/het + (in)definite, or predicative at the clause end) and the attested form matches, so `Sono stanca` (the speaker's gender is unknown) gets no form.
- **Verbs** stay in `verb_forms`; conceptually a verb table is the special case table = tense, cell = person.
- **Old apps:** apps before 0.4.0 failed on `kind = 'infl'` (`FacetKind.parse`); from this version on the loader skips facet kinds it doesn't know. The compiler therefore writes `meta.min_app_version = 0.4.0` into packs that train inflection tables, and `publish` copies it into the pack index, so older apps are offered an app update instead of the pack.

## Topic trees (schema minor 3, pack format 1.2)

A course has a main tree and optionally built-in **topics**: themed side trees attached to the main tree at an anchor skill (docs/extensions.md; source format and rules in docs/pack-format.md 3.3).

```sql
CREATE TABLE topics (id, ord, title, short_title, description, icon, anchor);
CREATE TABLE topic_units (unit_id, topic_id);
```

- Topic units and skills are ordinary `units` / `skills` rows, ordered after every main-tree unit, so course order is the main tree, then each topic. Facets are shared by id, so progress, stats, XP and gating need nothing new.
- **Old apps** ignore the two tables and show the topic units as further units at the end of the main tree, locked by their prerequisites: safe, so topic packs set no `min_app_version`.
- **App:** `CourseTrees` (`core/trees.dart`) splits the trees; the map draws the main tree with a branch per topic and each topic as its own map (docs/ui.md "Topic trees").

## Exercise type ids

`flashcard`, `multiple_choice`, `match_pairs`, `conj_pick`, `conj_grid`, `sentence_builder`, `cloze`, `spot_error`, `transform`, and since v0.5 `listen_pick` (on-device text-to-speech; generated only when the device has a voice for the course language, `SessionOptions.listening`).

These ids appear in `course.yaml` (`exercises:`), in `skills.exercises`, in `review_log.exercise_type`, and in the focus-preset config (`app/assets/config/focus_presets.json`).

`review_log.exercise_type` may also hold `test_out` (`kTestOutCreditType`): a **test-out credit**, not an answer. Passing a test out writes one per not-yet-learned facet of the credited skills (rating Easy, correct, mode `testOut`); a placement writes two (Good, then Easy 1 ms later, mode `placement`), and "Skip ahead without a test" two Good ones marked `answer = 'self-declared'`. Credits graduate the facets (the skill is learned and what follows unlocks) and sync like any event; progression gives them no XP and doesn't count them as reviews. See `docs/engine.md`.

It may also hold `override` (`kOverrideType`): an **answer override** ("I was right"). The learner says an answer graded wrong was right; the app appends an event on the same facet, later in time, with rating Good, `correct`, input `self`, `responseMs` 0 and the overridden event's id in `answer`. **Replay rule** (`applyOverrides` in `core/models/progress.dart`, applied by every replay: `ProgressRepo.record`/`importEvents`/`rebuildStates`, `InMemoryProgressStore`, progression's `LogReplay`): the override rewrites its target's rating and verdict in place, at the target's time, and is itself skipped. So the facet's state, XP and challenges are exactly those of a right answer, `rebuildStates()` stays exact, the override earns no XP and is no review, and the log stays append-only (it syncs like any event). An override whose target isn't in the log yet does nothing until it arrives; of several overrides of one event the last in `(at, id)` order wins. `openMistakes` treats an overridden mistake as resolved.

It may also hold `reset` (`kResetType`) and `reset_undo` (`kResetUndoType`): **skill resets** ("Reset this skill") and their undos. A reset clears its facet's state at its instant (later events start from scratch); an undo names a reset's id in `answer` and cancels it; both are skipped as answers (no XP, no review). **Replay rule** (`resolveResets` and `replayStep` in core, with overrides as `replayable`, applied by every replay as above): so `rebuildStates()`, sync merges in any order and progression agree. See `docs/engine.md`, "Skill reset".

It may also hold `story` (`kStoryReadType`): a **story read**, see "Stories" below.

## FSRS ratings

`1 = Again`, `2 = Hard`, `3 = Good`, `4 = Easy`. Auto-graded results: a wrong answer is Again, a right answer is Good, and a right answer faster than the type's fast-answer threshold is Easy. Flashcards use self-grade buttons (Again, Hard, Good, Easy).

`review_log.correct` is whether the *answer* was right for that facet; the rating is what FSRS learns. They differ in one case: a **partly right sentence answer** whose tested word was right records that facet with rating Good and `correct = false` (per-facet credit: no lapse for the right word, but the answer counts as a mistake for XP, accuracy, perfect lessons, the non-stop replay and mistake resolution). The wrong words of such an answer get their own Again events when the learner already studies them. Retries of a mistake later in the same session record only the facet's relearning step. Details: `docs/engine.md`, "Retries" and "Partly right sentence answers".

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
sync/          cloud sync (v0.7): SyncEngine (union merge, LWW settings), Firebase Auth + Firestore over REST, SyncService (docs/data-layer.md, "Cloud sync")
ai/            AI explanations (v0.3): ClaudeExplainer, OpenAiExplainer, CachingExplainer, prompts, AiConfig, SecretStore;
               AI conversation practice (v0.4): tutor.dart
ink/           handwriting recognition (v0.5): InkRecognizer (+ ML Kit Digital Ink), model language tags
speech/        text-to-speech (v0.5): Speaker (+ flutter_tts), voice locale choice, providers
device/        device extras (v0.5): DeviceInfo (ONYX detection), EinkScreen (full refresh), PenSurface (Onyx pen raw drawing), providers
feedback/      exercise snapshots, answer context, flags JSON Lines export (v0.3)
audio/         SoundService over audioplayers (v0.3); the sounds come from tool/make_sounds.py
ui/            Flutter screens and widgets (Phase 4): map, lesson player, lab, non-stop, settings, debug, ai/, feedback/
  theme/       skins: ToskSkin (the storybook palette, Gelasio headings), BwSkin (e-ink)
  brand/       Tosk the mascot (poses, wordmark, lock-up) over assets/brand/ (docs/brand-overhaul.md)
  map/         the course map: layout, storybook branch and node painters (ink_art, branch_style)
app.dart, main.dart, providers.dart (Riverpod wiring)
```

Dependency direction: `ui → engine, progression, data → core`. `sync`, `ai`, `feedback`, `audio`, `ink`, `speech` and `device` sit beside `data`: they use `core`, and `feedback` also uses the engine's `exercisePrompt`. `docs/feedback.md` describes AI explanations, flags and sounds. `engine` and `progression` depend only on `core`, with data access through small interfaces such as `CourseData` and `ProgressReader`. That keeps them pure Dart and testable with in-memory fixtures. `data` implements those interfaces.

## Trust boundaries

Course packs, course indexes and backup files may come from anyone (sharing packs is the intended direction), so they are treated as untrusted input:

- **Packs:** opened read-only, with `trusted_schema` off and a schema check (tables and indexes only) before any table is read; integrity-checked when added from outside; size-capped; their course id validated before it names a file (docs/data-layer.md, "Course packs").
- **Indexes and downloads:** `https` only (loopback excepted for development), also after redirects; sha256 and size checked; size caps on the index, packs and gzip output (docs/data-layer.md, "Downloads").
- **Backups:** merge only, never delete; only whitelisted learner preferences are imported, never `ai.*` (docs/data-layer.md, "Progress backup").
- **AI:** the key lives in platform secure storage and is sent only to the configured provider, over `https` (plain `http` only to this device or the local network, `core/net_policy.dart`). AI output is rendered as plain Markdown text (no HTML, links or images).
- **Web:** a Content-Security-Policy in `web/index.html` (docs/release.md, "Web app and pack mirror").
- **Android:** no cloud backup or device transfer of app data.

Reporting a vulnerability: `SECURITY.md`.

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
  - At session start, compute `knownFeatures` = base ∪ the features of every skill the learner has *started* (practised a facet the skill introduces, i.e. whose first skill it is) ∪ the current skill's features (lesson: its skill; lab: the chosen skills; non-stop, fading, review: none). Prerequisites of started and current skills count too (their sentences are built on them), and a skill answered during the session counts as started from then on.
  - Sentence-based templates only use sentences whose features ⊆ `knownFeatures`; transform's target tense must be known too, and wrong options never show forms of an unknown tense.
  - Unknown vocabulary is capped: counted over word tokens aligned to items outside the learner's started (and current) skills, at most 2 per sentence for vocab focus and 1 for grammar focus or a grammar skill. An unaligned word counts 0 when it is a name or a number and 2 otherwise. Sentences with fewer unknown words are preferred.
  - A template that finds no eligible sentence returns `canGenerate == false`, and another template is used. Packs without `base_features` are not gated.
  - Variety: real (Tatoeba) sentences come before generated ones (`src: claude-gen`, written by the pipeline where real ones are scarce) while unseen; sentences not seen recently are preferred (a 1000-id LRU per course in the settings key `engine.recent_sentences.{course}`), a session never repeats a sentence while the facet has others, and the previous exercise type is avoided when another type can serve the facet.
- **Time adverbs** (`meta.time_adverbs`, optional JSON `{adverb: [tense, ...]}` from course.yaml `time_adverbs`): the tenses a time adverb fits. The transform exercise never rewrites a sentence with one into another tense.

## Stories: graded reading per unit (added 14 Oct 2026)

Each unit has 2–3 short stories (5–10 sentences) written by Claude (`src: claude-gen`) that use only what the learner has met by the end of that unit, with 3–5 multiple-choice comprehension questions.

- **Source** (`content/{course}/stories/u{n}.yaml`, `pipeline/stories.py`; format and checks in `pipeline/README.md`): title, sentences with `tr.en` (+ `tr.nl` for Italian), questions, and at most one `new_words` lemma. The build aligns every text with the importer's tokenizer and aligner and fails when a word is neither aligned nor a name or number, an item is taught after the story's unit (except the one declared new word), a grammar feature is not allowed at the unit (base ∪ everything introduced by this or an earlier unit), a translation fails `trcheck.py`, or a question is malformed (3–4 options, distinct after folding case, punctuation and accents, the answer index in range, i18n complete). `python -m pipeline stories it [--show u3]` checks only the stories.
- **Contract** (additive to `schema/course_db.sql`, schema version stays 1): `stories(id, unit_id, ord, title, title_tr, src, new_words)`, `story_sentences(story_id, idx, sentence_id)`, `story_questions(story_id, idx, prompt, prompt_tr, options, correct, explanation_tr)`. Story sentences are ordinary `sentences` + `tokens` + `sentence_features` rows with ids `st:{storyId}.{n}` (tap-for-translation works unchanged). `options` is a JSON array of target-language strings or source-language i18n objects; `prompt` is the optional target-language question. Packs without the tables load with no stories.
- **App data**: `CourseData.stories` / `story(id)` (`core/models/story.dart`). The loader keeps story sentences **out of the exercise pool** (`sentencesFor`, `sentence`): their vocabulary rule (one new word per story, plus up to three words of topics outside the story's tree: docs/extensions.md, the fairness rule) is looser than gating's and they depend on their context.
- **Unlock**: a unit's stories open once every skill of the unit that trains facets is started (practiced or tested out), i.e. the learner has met the unit's words and grammar (`storyUnitsUnlocked`). A locked story can still be read as a preview (a note says so), like starting a locked skill anyway.
- **Log convention**: finishing a story's questions appends one `ReviewEvent` with `exerciseType: 'story'` (`kStoryReadType`) on the story's own pseudo-facet `{course}:story:{storyId}#story` (`storyFacetId`): rating Good, `correct` true, input `tap`, mode `story`, `responseMs` the reading time, `answer` the score `'{correct}/{total}'`. The pseudo-facet is in no skill, so no lesson, map statistic, gating or real facet's FSRS state ever sees it (reading is no graded recall of any word, so it must not move word schedules). Replays fold it like any facet, so `rebuildStates()` stays exact without special cases, and it syncs and backs up like any event. Progression: light fixed XP (5 + 1 per correct answer on the first read, 2 per reread; docs/progression.md), so stories count toward the daily goal and streak; challenges count them only as practice days and XP. Which stories were read, and the best score, are derived from these events (`storyRecordsOf`).
