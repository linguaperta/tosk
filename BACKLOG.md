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

- [x] JSON Schemas: `course.yaml`, lexicon, verbs and sentences JSONL
- [x] Download/cache layer (kaikki, Tatoeba, frequency lists), streaming, never committed
- [x] kaikki importer for Italian and Dutch: lemma, POS, gender, article, plural, translations, conjugation tables (stem and ending split)
- [x] Dutch glosses for Italian (and other pivots) when kaikki has none: the strategy is documented and the gaps are filled
- [x] Tatoeba importer: it–en, it–nl and nl–en pairs
- [x] Frequency lists, giving the freq rank per lemma
- [x] Token alignment: sentence tokens linked to items and forms, with unmatched tokens left unlinked
- [x] Stable ID registry (`ids.tsv`)
- [x] `course.yaml` for it: 3 units and about 8 skills (-are, -ere and -ire present, essere/avere, articles, vocab)
- [x] `course.yaml` for nl: 3 units and about 8 skills (present, perfectum with hebben or zijn, de/het, vocab)
- [x] Grammar notes (en and nl) for every grammar skill
- [x] Compiler: JSONL and YAML into `course.sqlite`, following the DDL, with a schema version
- [x] Validator: unique IDs, no cycles, tokens point to real items, grammar skills have enough complete tables
- [x] Report: item and facet counts per skill
- [x] `index.json` and `ATTRIBUTION.md` in tosk-data
- [x] `python -m pipeline build it nl [--install]` works end to end and is tested with pytest
- [ ] Thin sentence coverage: sparire (1), impazzire (3), nl leven (4); nl perfectum-zijn covers 73% of person slots
- [ ] About 17% of Italian distractor-pool items lack a Dutch gloss
- [ ] Dutch separable verbs split in a sentence aren't aligned
- [x] Compound-tense exercises are wrong on the real packs (auxiliary and participle tokens); generation is slow on the full packs. Fixed in the engine and the alignment; the validity suite went from 7 min to 5 s.
- [x] Dutch sample review (`docs/samples/nl_exercises.txt`): clause rules, inversion, imperatives and passives fixed
- [x] Curriculum expansion: it 9 units, 40 skills, ~740 words; nl 8 units, 35 skills, ~710 words (packs 1.1.0)

## Phase 2: Local database layer (`app/lib/data`)

- [x] drift setup: read-only course DB (native file and web bytes) and progress DB
- [x] `CourseRepo`: units, skills, skill items and facets, verb forms, sentences by word or form, notes, meta
- [x] `ProgressRepo`: `review_log` (append-only), `facet_state`, `settings`; `record()`
- [x] FSRS scheduler, tested against reference values
- [x] `rebuildStates()` from the log, which must reproduce the stored states exactly
- [x] Skill strength (mean predicted recall) and last-practiced date
- [x] `PackSource` and `LocalPackSource` (bundled assets, documents folder, file picker)
- [x] Debug screen: courses, skills, item counts, strength

## Phase 3: Exercise engine (`app/lib/engine`)

- [x] `ExerciseTemplate` interface and the sealed `Exercise` and `Result` types
- [x] Templates: flashcard, multiple_choice, match_pairs, conj_pick, conj_grid, sentence_builder, cloze, spot_error, transform
- [x] Distractor generator (same tense with other persons, same tag, similar freq), checked against all valid answers
- [x] Answer normalization (case, punctuation, variants, accent strictness)
- [x] Exercise-type choice by facet stability (new items get recognition and choice, stable items get production)
- [x] `LessonBuilder` (due, then up to 5 new, then filler; about 12 exercises), `LabBuilder`, `NonStopQueue`, "what's fading" mixed practice
- [x] Focus presets config (mixed, vocab, grammar) with weights per exercise type
- [x] Mistakes return later in the same lesson and are logged for mistake review
- [x] Grading mapped to FSRS ratings and written with `ProgressRepo.record()`
- [x] Hooks: `AnswerInput`, `Explainer` and `NullExplainer`, `MistakeContext` stored on wrong answers
- [x] Sample command: 20 exercises per skill and type (`app/tool/sample_exercises.dart`; switch it to the real packs at integration)
- [x] Test: every template generates at least 20 valid exercises for every skill in both courses, with no duplicate options and the correct answer present exactly once (fixtures; `runTemplateValidity`)
- [x] Run `runTemplateValidity` on the real it/nl packs (`test/engine/real_pack_validity_test.dart`) and a perf test
- [x] Free-text cloze only when the input preference is keyboard or ink (spec: typing is never required)

## Phase 4: App screens (`app/lib/ui`)

- [x] App shell: Riverpod, go_router, theme (light and dark), swappable skin
- [x] Skill map: layered layout by longest prerequisite path, unit bands, `pos` override, strength ring, days since practice, tier, fading color
- [x] Map node interactions: tap starts a lesson, long-press shows the grammar note (markdown) and the item list
- [x] Lesson player with one widget per exercise type (tap-first), instant feedback, a "Why?" button hidden for `NullExplainer`, and an end summary
- [x] Exercise lab: multi-select skills and types, and a session length
- [x] Non-stop mode: an endless player with a running count
- [x] Mixed practice ("what's fading") entry on the map
- [x] Settings: course, source language, default focus, accent strictness, theme, reduce motion
- [x] Polish: haptics, sounds and animations behind `reduceMotion`
- [x] Widget tests for every exercise widget and overflow tests at 4 screen sizes
- [x] Full-lesson integration tests: engine with an on-disk `ProgressRepo`, non-stop with a bonus round, boot on the real bundled packs (`test/app/`)
- [x] Replace demo fakes with real data, engine and progression (integration); demo course only as a no-packs fallback
- [x] Builds: Windows, web, and a signed release APK (split per ABI; preview 1 sent on 13 October). iOS needs a Mac and is documented only.
- [x] Mistake review mode: practice saved `MistakeRecord`s (`SessionMode.review`), with an entry point on the map or progress page
- [x] Exploratory QA pass on the running app (Windows/web): full flows on both courses, UX polish

## Phase 5: Progression (`app/lib/progression`)

- [x] XP per answer, weighted by facet state, with bonuses for due and lapsed facets; levels on an increasing curve
- [x] Skill tiers (locked, started, bronze, silver, gold) with decay, shown on the map
- [x] Streaks and heatmap, with freezes earned from reviews; tests cover time zones, midnight and freezes
- [x] Weekly and monthly challenges with badges
- [x] Verb collection page
- [x] Non-stop extras: combo multiplier, bonus rounds (conjugation blitz every 25 correct), best-run record
- [x] Session summary: XP, improved words, tier changes
- [x] Recomputing from the log gives the same XP and tiers (test)
- [x] Wire progression into the map, summary, non-stop HUD, profile and verb-collection screens (integration)

## v0.3 (user feedback, 13 October)

- [x] Grammar-first curriculum: a construct is taught by its own skill before other exercises use it
- [x] Grammar gating data: `sentence_features`, `skill_features` and `base_features` in the pipeline and compiler, with a validator check (home-skill rule)
- [x] Grammar gating in the engine: only sentences whose features are known; unknown vocabulary capped (≤1 for grammar focus, ≤2 for vocab)
- [x] Bottom-aligned exercise controls (one-handed use)
- [x] "Explain answer with AI" after every checked answer (Claude or OpenAI key in Settings; no button without a key), streamed and cached
- [x] Flag an exercise (reason and comment); Submit saves locally with a `.jsonl` export; "Confer with AI" checks the complaint
- [x] Sounds: correct, wrong, lesson complete, muted select tick; toggle in Settings
- [x] Tap a word in any exercise sentence for its gloss; verbs show lemma, person and tense
- [x] Progress backup: export and import the review log (Settings), until Drive sync in v0.4
- [x] Test out of a skill (short quiz marks it learned and unlocks what follows) + optional placement at course start
- [x] Conjugation and word lookup: searchable reference of all pack verbs (full tables) and words; extends the verb collection
- [x] Daily goal (lessons or XP) + local reminder notification at a chosen time; goal line on the heatmap
- [x] Typing mode toggle ("challenge mode": production exercises take typed answers)
- [x] "I was right" override after a wrong verdict: re-rates as correct and auto-creates a flag
- [x] Accent keyboard bar for typing mode (letters from course data)
- [x] Grammar library tab: all notes browsable, each with "practice this"
- [x] Leech handling: facets with ≥4 lapses → "tough words" drill and mistake review (+ AI mnemonic when configured)
- [x] Session length options: quick (5) / normal (12) / long (20)
- [x] Pipeline: AI-generated example sentences for thin slots (verb × person × tense < 5 sentences), under gating constraints, validated by the aligner, `src: claude-gen`, reviewed in samples
- [x] Sentence variety: log the sentence id with each answer; the engine prefers unseen or least-recently-seen sentences
- [x] Sentence floor: generation tops up every verb×person×tense slot and every vocab topic to ≥8–10 distinct sentences
- [x] Course picker as a pop-up menu: +/- to add or remove each course, a preview per course (description, units/skills, sample words and sentences, unverified badge); the app only shows courses you've added
- [x] Black & white (e-ink) mode for the Boox: pure B/W skin, nothing conveyed by color (icons, labels, patterns, inverted fills), reduce motion forced on. Tested: grayscale-only assertions on every screen and exercise type, goldens, overflow at Boox and phone sizes
- [x] QA leftovers: `ciao` MC offers "hello" as a distractor (synonym data); instruction can slide under the app bar on tall exercises; a "jump to current unit" button on long maps
- [x] Exercises for the item-only grammar skills (plurals, adjective agreement, split separable verbs): needs `#plural`/declension facets (see the declension extension) and alignment of split separable verbs
- [ ] Italian reflexive/pronominal verbs (excluded by the pipeline today)
- [x] B/W bug: some TextButton labels render as black blocks (course picker "Preview")
- [x] Windows build needs ATL because of flutter_secure_storage_windows; replace it with a Dart-only Credential Manager implementation
- [x] Content fixes: nl perfect + double infinitive tagged, "laat" adjective, uncountables, de|het nouns, it imperatives, translation sanity check (dropped 643 it / 249 nl bad pairs)
- [x] Remaining sentence gaps: nl 298 → 19 slots < 8, it 61 → 4 (1,576 nl + 100 it generated sentences, all checked)
- [ ] Last slots: nl `redden` past plural (same spelling as the present), `gebeuren.zij`, `sterven` perfect 1st/2nd person; it `sparire.noi`, `gestire.noi`, `soffrire.noi/.loro`
- [ ] Lexicon gaps from the writers: quel/quella/questa/molti/buon, "thuis"; "zeven" (number) loses to the verb "zeven" (to sift); nevicare has no verb table
- [ ] Italian "noun before a non-3rd-person verb" alignment rule is too strict ("Cosa dici?"); apply it only to the present tense
- [ ] Test on real devices: notifications and permissions, the boot receiver, save/pick dialogs (Android), Boox B/W mode
- [x] Preview 3 APK (v0.3.0, 14 October)


## v0.3.2: user testing feedback (14 October)

- [x] Bottom controls hidden behind the Android nav bar on flashcards and match pairs (edge-to-edge inset); preview 3.1
- [~] Match pairs: stale selection on fast taps, correct pairs dropped, both cards of a wrong pair shown red; stress tests
- [~] Spot the error: tapping the error word shows correct (green), tapping a wrong token shows wrong
- [~] Map: tapping a skill opens an info sheet first (description, tier, strength, what's needed for the next tier, then Start / Test out / Note / Words)
- [~] Progress per course: XP, level, challenges, badges, verb collection, mistakes, best run. Account-wide: daily goal, streak, freezes, heatmap
- [~] Remove the course switcher from the map (Settings only)
- [~] All practice modes advance skills (non-stop introduces new facets; the map refreshes after every mode)
- [~] First-time intro for every exercise type, re-openable via (?)
- [~] Transform renamed "Change the tense" / "Change the person", with a from → to chip

## v0.4 (in progress, started 14 October)

- [x] GitHub pack source: index.json from GitHub Releases, download, update, sha256 check, atomic swap; publish tooling (`python -m pipeline publish`); "Add course from file" in the course picker
- [x] Repos pushed to GitHub (tosk private, tosk-data public); first pack release `packs-20261014` (it/nl 1.2.0, min app 0.4.0); stable index URL verified end to end
- [ ] Web: pack downloads probably blocked by CORS on GitHub release redirects; needs a CORS-friendly mirror (Pages) and persistent web pack storage
- [ ] nl: generated sentences for diminutives; a skill for the `comparison` table; drill split separable verbs (#form facets on the separable skill)
- [-] Google Drive sync: skipped for now (user, 14 October); backup export/import covers it
- [x] Inflection tables for any POS + `#infl:` facets: plurals, adjective agreement, possessives, split separable verbs

- [ ] Bookmarks: star words, sentences or exercises; "Starred" practice session
- [ ] Graded mini-stories per unit (pipeline-generated with only known vocab and grammar), with tap-for-translation and comprehension questions
- [ ] Pronunciation button (on-device TTS); review forecast and stats (accuracy per type and tense)
- [ ] AI conversation practice limited to unlocked grammar and vocab (needs an API key)
- [x] Schema: generalize `verb_forms` into inflection tables for any POS, with a declension facet kind (unlocks German and Slavic noun/adjective cases)
- [-] Optional on-the-fly AI sentences in the lab ("more like this"), clearly labelled as unvalidated

## v0.6: new full-size courses (the "easy" languages)

Each one at the expanded it/nl scale: 8–10 units, ~30 skills, ~1000 taught words, grammar-first gating, tr.en + tr.nl, grammar notes in en and nl, sentence floor via generation, a native-level sample review, and the real-pack validity and perf tests passing.

- [~] Spanish (`es`), built first as the pilot, to measure the per-language cost and fix generic pipeline gaps
- [ ] Portuguese, Brazilian (`pt-BR`)
- [ ] Portuguese, European (`pt-PT`) (user: add both varieties)
- [ ] French (`fr`): elision, partitive articles, passé composé with être/avoir
- [ ] Esperanto (`eo`)
- [ ] Swedish (`sv`)
- [ ] Norwegian Bokmål (`nb`)
- [ ] Danish (`da`)
- [ ] `index.json` listing all courses (the course picker itself is in v0.3)

## Later (not v1)

- [x] Phase 6: Sarnami (`hns`): 9 units, 35 skills, 394 taught words, 742 verb tables, 3,004 sentences. Sources: [source] dictionary, [source] 1991, [source]� 1985 (checking), [source], NT (checking only), plus Claude-drafted/generated material, with per-record `src` and a SOURCES manifest. Local-only (copyright), unverified; see `docs/sarnami.md`.
- [ ] Sarnami: review by a speaker (open questions in `docs/sarnami.md`); [source]�'s past habitual/conditional not modelled; [source] readers blocked by a bot challenge
- [-] Phase 7: `GitHubPackSource`, `DriveSyncBackend`. Interfaces only in v1.
- [ ] v0.5: ink `AnswerInput` (ML Kit Digital Ink) + Onyx pen SDK behind an ONYX device check (user approved, 14 October); e-ink full refresh; listen_pick with on-device TTS. The AI explainer and the B/W e-ink mode moved up to v0.3.
- [-] `listen_pick` exercise (needs audio/TTS)
