# Feature backlog

The living task list for v1, derived from [docs/SPEC.md](docs/SPEC.md). Contracts are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Status: `[ ]` todo · `[~]` in progress · `[x]` done (tests pass) · `[-]` dropped or deferred (with reason).
Each item says what "done" means. Add newly discovered work at the bottom of its section and keep finished items, so this file doubles as a changelog.

## Phase 0: Foundations

- [x] Spec in repo (`docs/SPEC.md`), architecture and contracts (`docs/ARCHITECTURE.md`), this backlog
- [x] Compiled course DB contract (`schema/course_db.sql`)
- [x] Toolchain: Flutter stable, JDK 17, Android cmdline-tools
- [x] Android SDK 36 (licenses accepted by the user on 13 October), release signing keystore (`docs/release.md`)
- [x] Flutter project skeleton (`app/`), dependencies, `core/` models and interfaces (`core/interfaces/session.dart` is the engine↔UI contract), `check.sh`

## Phase 1: Content format and pipeline (`pipeline/`, `schema/`, `../tosk-data/content`)

- [ ] JSON Schemas: `course.yaml`, lexicon, verbs and sentences JSONL
- [ ] Download/cache layer (kaikki, Tatoeba, frequency lists), streaming, never committed
- [ ] kaikki importer for Italian and Dutch: lemma, POS, gender, article, plural, translations, conjugation tables (stem and ending split)
- [ ] Dutch glosses for Italian (and other pivots) when kaikki has none: the strategy is documented and the gaps are filled
- [ ] Tatoeba importer: it–en, it–nl and nl–en pairs
- [ ] Frequency lists, giving the freq rank per lemma
- [ ] Token alignment: sentence tokens linked to items and forms, with unmatched tokens left unlinked
- [ ] Stable ID registry (`ids.tsv`)
- [ ] `course.yaml` for it: 3 units and about 8 skills (-are, -ere and -ire present, essere/avere, articles, vocab)
- [ ] `course.yaml` for nl: 3 units and about 8 skills (present, perfectum with hebben or zijn, de/het, vocab)
- [ ] Grammar notes (en and nl) for every grammar skill
- [ ] Compiler: JSONL and YAML into `course.sqlite`, following the DDL, with a schema version
- [ ] Validator: unique IDs, no cycles, tokens point to real items, grammar skills have enough complete tables
- [ ] Report: item and facet counts per skill
- [ ] `index.json` and `ATTRIBUTION.md` in tosk-data
- [ ] `python -m pipeline build it nl [--install]` works end to end and is tested with pytest

## Phase 2: Local database layer (`app/lib/data`)

- [ ] drift setup: read-only course DB (native file and web bytes) and progress DB
- [ ] `CourseRepo`: units, skills, skill items and facets, verb forms, sentences by word or form, notes, meta
- [ ] `ProgressRepo`: `review_log` (append-only), `facet_state`, `settings`; `record()`
- [ ] FSRS scheduler, tested against reference values
- [ ] `rebuildStates()` from the log, which must reproduce the stored states exactly
- [ ] Skill strength (mean predicted recall) and last-practiced date
- [ ] `PackSource` and `LocalPackSource` (bundled assets, documents folder, file picker)
- [ ] Debug screen: courses, skills, item counts, strength

## Phase 3: Exercise engine (`app/lib/engine`)

- [ ] `ExerciseTemplate` interface and the sealed `Exercise` and `Result` types
- [ ] Templates: flashcard, multiple_choice, match_pairs, conj_pick, conj_grid, sentence_builder, cloze, spot_error, transform
- [ ] Distractor generator (same tense with other persons, same tag, similar freq), checked against all valid answers
- [ ] Answer normalization (case, punctuation, variants, accent strictness)
- [ ] Exercise-type choice by facet stability (new items get recognition and choice, stable items get production)
- [ ] `LessonBuilder` (due, then up to 5 new, then filler; about 12 exercises), `LabBuilder`, `NonStopQueue`, "what's fading" mixed practice
- [ ] Focus presets config (mixed, vocab, grammar) with weights per exercise type
- [ ] Mistakes return later in the same lesson and are logged for mistake review
- [ ] Grading mapped to FSRS ratings and written with `ProgressRepo.record()`
- [ ] Hooks: `AnswerInput`, `Explainer` and `NullExplainer`, `MistakeContext` stored on wrong answers
- [ ] Sample command: 20 exercises per skill and type
- [ ] Test: every template generates at least 20 valid exercises for every skill in both courses, with no duplicate options and the correct answer present exactly once

## Phase 4: App screens (`app/lib/ui`)

- [ ] App shell: Riverpod, go_router, theme (light and dark), swappable skin
- [ ] Skill map: layered layout by longest prerequisite path, unit bands, `pos` override, strength ring, days since practice, tier, fading color
- [ ] Map node interactions: tap starts a lesson, long-press shows the grammar note (markdown) and the item list
- [ ] Lesson player with one widget per exercise type (tap-first), instant feedback, a "Why?" button hidden for `NullExplainer`, and an end summary
- [ ] Exercise lab: multi-select skills and types, and a session length
- [ ] Non-stop mode: an endless player with a running count
- [ ] Mixed practice ("what's fading") entry on the map
- [ ] Settings: course, source language, default focus, accent strictness, theme, reduce motion
- [ ] Polish: haptics, sounds and animations behind `reduceMotion`
- [ ] Widget tests for every exercise widget, plus a full-lesson integration test on the real packs
- [ ] Builds: signed release APK, Windows desktop, web (iOS needs a Mac and is documented only)

## Phase 5: Progression (`app/lib/progression`)

- [ ] XP per answer, weighted by facet state, with bonuses for due and lapsed facets; levels on an increasing curve
- [ ] Skill tiers (locked, started, bronze, silver, gold) with decay, shown on the map
- [ ] Streaks and heatmap, with freezes earned from reviews; tests cover time zones, midnight and freezes
- [ ] Weekly and monthly challenges with badges
- [ ] Verb collection page
- [ ] Non-stop extras: combo multiplier, bonus rounds (conjugation blitz every 25 correct), best-run record
- [ ] Session summary: XP, improved words, tier changes
- [ ] Recomputing from the log gives the same XP and tiers (test)

## Later (not v1)

- [-] Phase 6: Sarnami (`hns`). Deferred by the spec; local-only data because of the [source] copyright.
- [-] Phase 7: `GitHubPackSource`, `DriveSyncBackend`. Interfaces only in v1.
- [-] Phase 8: ink `AnswerInput`, e-ink mode, `ClaudeExplainer`. Interfaces and `reduceMotion` only in v1.
- [-] `listen_pick` exercise (needs audio/TTS)
