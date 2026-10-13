# Language App: Core Feature Plan

*Updated 13 October 2026*

## Scope

Version 1 is the learning core: local content, a skill map, lessons and exercises, all offline with no server. It has three courses. Italian and Dutch come first and Sarnami shortly after. Dutch is included so you can check the harder exercises in a language you know well. Everything is free: no hearts, no energy, no ads.

In v1:

- **Courses:** Italian, Dutch, and Sarnami after them. Packs store translations in both English and Dutch, and the source language is a setting. Sarnami is Dutch-only.
- **Content source:** packs load from local files first. Downloading them from GitHub comes later.
- **Skill map:** generated from the pack, showing each skill's strength and decay.
- **Exercises:** 9 types (listening comes later, with audio), generated from the data, with a heavy focus on conjugation.
- **Three ways to practice:**
  - Lessons with a focus you pick: mixed, vocabulary or grammar
  - An exercise lab where you choose the skills and exercise types yourself
  - A non-stop mode
- **Progression, once the core works:** XP, levels, a streak heatmap, bronze, silver and gold skills, and combos and bonuses in non-stop mode.
- **Hooks only, built later:** handwriting with e-ink mode, and AI explanations.

Not in v1: accounts, a backend, leaderboards, speech recognition, the RPG layer, personalized vocabulary, and the handwriting and AI features themselves.

## Architecture

The app is built in Flutter: one codebase covers Android (as an APK), Boox, iOS, desktop and web, and everything runs on the device.

- **Stack:** Flutter and Dart. Custom painting handles the map and the handwriting canvas, animations are smooth, and `flutter build apk` produces the APK. Flutter was chosen over Kotlin Multiplatform on 13 October.
- **Local storage:** SQLite through the drift library, in two separate files.
  - Each course is a read-only database that the pipeline compiles ahead of time and the app opens directly, so installing it parses nothing.
  - Progress is its own database holding the review log, card states and XP, so replacing a pack never touches your progress.
  - The data is small, a few MB per language, so every query takes well under a millisecond. Indexes on due date, tag and frequency cover the hot queries, and each lesson's queue is loaded into memory once.
- **Content hosting:** a public GitHub repo. Built packs are attached to GitHub Releases or served from GitHub Pages. The app fetches `index.json`, compares versions, and downloads each course as one compiled SQLite file. It is free, served from a CDN, and needs no server.
- **Sync:** Google Drive's `appDataFolder`, a hidden folder in the user's own Drive for the app's data. What syncs is an append-only review log. Merging takes the union of the events and recomputes card states, so conflicts can't happen by design. On desktop and web, export and import a file instead.
- **Pack updates:** item IDs never change, so an updated pack never orphans progress. Items removed from a pack simply stop being scheduled.
- **Content pipeline:** Python scripts on your desktop, not part of the app. They build packs from open data:
  - Wiktionary, via kaikki.org's wiktextract dumps, for lemmas, translations and full conjugation tables
  - Tatoeba for example sentences
  - A frequency list to order the words
  - Claude to help group skills and write grammar notes
- **Licensing:** Wiktionary is CC BY-SA and Tatoeba is CC BY, so the pack repo should be CC BY-SA, with attribution.

## Content pack format

The map comes straight from each course's `course.yaml` file. Units group skills, and each skill's `requires` field lists the skills it depends on. The app lays the skills out in layers by how many prerequisites deep they sit, so adding a language means adding a folder and an entry in `index.json`, with no app update. Italian is used below only as an example.

```
courses/
  index.json              # every course with its version and download URLs
  it/
    course.yaml           # units, skills and prerequisites (this becomes the map)
    lexicon/u1.jsonl      # words, one file per unit
    verbs/u1.jsonl        # full conjugation tables
    sentences/u1.jsonl    # example sentences, aligned to words
    grammar/*.md          # rule explanations, available offline
    assets/               # skill icons, optional audio
```

The course file declares its own grammar dimensions, such as persons and tenses. Skills select their items with a query rather than listing them one by one.

```yaml
id: it
version: 1.3.0
translations: [en, nl]
target: it
persons: [io, tu, lui/lei, noi, voi, loro]
tenses: [presente, passato_prossimo, imperfetto, futuro]
units:
  - id: u1
    title: Basics
    skills:
      - id: greetings
        kind: vocab
        icon: wave
        items: {tags: [greetings]}
      - id: present-are
        kind: grammar
        requires: [greetings]
        note: grammar/present-are.md
        verbs: {class: are, tense: presente, top: 30}
        exercises: [conj_pick, conj_grid, cloze]
        pos: {x: 2, y: 1}   # optional: override the automatic layout
```

The item files are JSONL, one record per line:

```json
{"id":"it:mangiare","pos":"verb","lemma":"mangiare","tr":{"en":["to eat"]},"freq":312,"tags":["food"],"class":"are"}
{"id":"it:mangiare","stem":"mang","irregular":false,"forms":{"presente":{"io":"mangio","tu":"mangi","noi":"mangiamo"}}}
{"id":"s:4821","it":"Mangiamo alle otto.","en":"We eat at eight.","tokens":[{"t":"Mangiamo","lex":"it:mangiare","form":"presente.noi"}],"src":"tatoeba:4821"}
```

Three design rules keep this working:

- **Query-based skills.** New words join the right skills automatically, and `course.yaml` stays short.
- **Full conjugated forms, generated offline.** The app ships every form instead of conjugation rules, so it never needs to know a language's grammar. The stem and ending split feeds the ending-picker exercise.
- **Language-specific details live in the course file.** Persons, tenses and article genders are declared there, so nothing is hardcoded in the app.

A validation script in the pipeline checks that IDs are unique, prerequisites have no cycles, and every sentence token points to a real word.

The JSONL files are the source format: easy to read, to diff in git, and for Claude to generate. The pipeline compiles each course into a single `course.sqlite`, which the app reads.

Translations are stored per language (`tr.en`, `tr.nl`), so one Italian pack serves both English and Dutch speakers. Course IDs are the target language's code: `it`, `nl`, and `hns` for Sarnami (Caribbean Hindustani).

Sarnami is a Dutch–Sarnami course. Its pack has only Dutch translations (`tr.nl`), and its source language is always Dutch. The main source is [source] Suriname's [Nederlands–Sarnami woordenboek]([link removed]), which has one page per letter.

- **Scraping it.** Entries follow a fixed pattern: the Dutch headword, its part of speech, the Sarnami gloss, then numbered senses with Dutch–Sarnami example pairs. A scraper can turn these into words and example sentences.
- **Verbs.** The dictionary gives verbs only in their base form (kare, dewe). Conjugated forms appear only inside the examples (karies, tjallie, aaiga). So the conjugation tables have to come from a grammar description, drafted with Claude and marked as unverified.
- **Spelling.** The dictionary itself lists alternative spellings (pahienaawe/pahieraawe), and these go in `variants`. The spelling is Dutch-based (oe, ie, tj, dj), with dots for retroflex sounds (ṯ, ṟ) and tildes for nasals (ã).
- **Copyright.** The dictionary is copyrighted with all rights reserved, by [source] Global through Derivation LLC. Keep the scraped data out of the public content repo until [source] Suriname gives permission. Until then, build the Sarnami pack locally and load it from a file.

## Learning engine

Each item has several facets, and FSRS schedules each facet separately. A skill's strength on the map is the average predicted recall across its facets. FSRS is an open-source spaced-repetition algorithm, ported to most languages.

- **Facets:**
  - Recognize: from the target language to the meaning
  - Produce: from the meaning to the target language
  - One facet per group of verb forms, for example mangiare in the presente
  - Handwritten answers count as produce
- **Grading:** automatically graded exercises map to Again or Good, or to Easy if you answered fast. Flashcards use self-grade buttons.
- **Lesson:** about 12 exercises, around 3 minutes, in this order:
  1. Due facets in the chosen skill
  2. Up to 5 new items
  3. Filler items to complete the set
- **Picking the exercise type:** it depends on how stable the facet is. New items get recognition and choice exercises; stable items get production.
- **Mixed practice:** a "what's fading" session from the map that pulls due facets across all skills.
- **Mastery tiers:** locked, then started, then three tiers.
  - Bronze: every item has been learned.
  - Silver: every facet has predicted recall of at least 0.85 and stability of at least 7 days.
  - Gold: the same, raised to 0.9 and about 21 days.

  A skill drops a tier when recall falls below its threshold, so decay on the map reflects real forgetting.
- **Mistakes:** they come back later in the same lesson and again the next day, and are logged for the mistake review.

**Modes.** There are three ways to practice, and all of them write to the same scheduler, so every answer counts.

- **Lesson:** about 12 exercises from one skill, with a focus preset that changes which exercise types appear:
  - Mixed
  - Vocabulary: flashcards, match pairs, multiple choice and sentence builder
  - Grammar: conjugation pick, conjugation grid, cloze, transform and spot the error

  The default focus is a setting, and you can change it for any lesson.
- **Exercise lab:** pick any skills and any exercise types, and set the session length. This is the place to drill one kind of exercise or test a new exercise template.
- **Non-stop:** an endless queue that takes due facets from every unlocked skill and mixes in new items. It runs until you stop.
  - v1: the queue and a running count.
  - The progression phase adds a combo multiplier, bonus rounds (for example a timed conjugation blitz every 25 correct answers), and a record for your best run.

## Exercise types

Every exercise is generated from pack data by a template, so a new language gets all of them automatically. Typing is never required: tapping is the default, and handwriting is an option for production.

| Exercise | What you do | Input | Trains |
| --- | --- | --- | --- |
| Flashcard | See the word, reveal it, grade yourself | Tap | Recognize, produce |
| Multiple choice | Pick the translation of a word or sentence | Tap | Recognize |
| Match pairs | Pair 5 words with their meanings | Tap | Recognize |
| Conjugation pick | The stem is shown; pick the ending for a person and tense (`mang___`, noi, presente) | Tap | Verb forms |
| Conjugation grid | Fill a whole tense table, cell by cell | Tap or handwrite | Verb forms |
| Sentence builder | Build the translation from word tiles | Tap | Produce |
| Cloze | Fill a gap in a real sentence, with choices at first and handwriting later | Tap or handwrite | Produce, verb forms |
| Spot the error | Tap the wrong word in a sentence | Tap | Grammar |
| Transform | Rebuild a sentence in another tense or person from tiles | Tap | Grammar |
| Listen and pick | Later, not in v1: on-device text-to-speech reads a sentence; pick what you heard | Tap | Recognize |

Wrong answer options are chosen to be plausible: other persons of the same tense, words with the same tag, and words with a similar frequency rank.

## Map, progression, handwriting and AI

**Map.** The map is rendered from the skill dependency graph in `course.yaml`. Skills sit in layers by prerequisite depth, with units as horizontal bands.

- Each skill node shows a strength ring, the days since you last practiced it, and its tier.
- Tap a node to start a lesson. Long-press it to see the grammar note and the item list.
- Fading skills lose color; bronze, silver and gold skills each show their tier.
- The visual style is a swappable skin, so the forest theme can be added later.

**Progression (the phase after the core).**

- XP for each graded answer, weighted so that due and hard facets earn more
- Levels on an increasing curve
- A streak heatmap, with streak freezes you earn by doing reviews
- Weekly and monthly challenges with badges
- A verb collection page where conjugation tables light up as you master them

**Handwriting (later; the hook ships in v1).**

- Production exercises can take input on a drawing canvas. Google ML Kit Digital Ink recognizes it on the device, using a per-language model that works offline once downloaded. An answer is accepted if the expected text is among the top few candidates, so recognition doesn't need to be perfect.
- On the Boox, the app runs as a normal Android app and the stylus works. Standard Android drawing lags on e-ink, though. Onyx's pen SDK draws strokes with low latency and can be added later.
- E-ink mode: no animations or fades, high contrast, and a full screen refresh after each lesson.
- ML Kit covers Android and iOS. On desktop and web, typing is the fallback.

**AI explanations (later; the hook ships in v1).**

- An optional Claude API key goes in Settings and is kept in the device's secure storage.
- A "Why?" button on a wrong answer sends the exercise, the expected answer, your answer and the relevant grammar note. It uses a small, fast model and streams the reply.
- Replies are cached per item and error, so they're available offline afterwards and in mistake review.
- When you're offline, the app shows the bundled grammar note instead.

## Milestones and decisions

The build order is content and the local database first, then exercises and the three modes, then progression. Downloads, sync, Sarnami, handwriting and AI come after that. Part 2 (Build phases) has the version for a coding agent, with tasks and done criteria for each phase.

1. **Content format and pipeline:** Dutch and Italian, 3 units each, compiled to SQLite.
2. **Local database layer:** course and progress databases, repositories and FSRS.
3. **Exercise engine:** templates, generation, wrong-answer options, grading, and the hook interfaces.
4. **App screens:** the map, lessons, the exercise lab, non-stop mode and settings.
5. **Progression:** XP, levels, tiers, streaks, and combos and bonuses in non-stop mode.
6. **Sarnami course.**
7. **Pack downloads from GitHub and Google Drive sync.**
8. **Handwriting with e-ink mode, and AI explanations,** built into the existing hooks.

Decisions (13 October 2026):

- **Framework:** Flutter.
- **Platforms in v1:** Android (the APK, also on the Boox), iOS, desktop and web. Building for iOS needs a Mac.
- **Audio:** none in v1, so the listen-and-pick exercise waits.
- **Sarnami review:** no speaker yet. Content comes from [source]'s Dutch–Sarnami dictionary plus a grammar description, and the app marks the course as unverified until someone checks it.

## Parked for later

- **Forest and RPG layer:**
  - Regions are themes, and decay shows as overgrowth and fog.
  - Gold skills become lit lanterns.
  - Grammar topics are dungeons, each ending in a boss: a mixed test of using the tense in real sentences.
  - The verb collection becomes a spellbook.
  - Mistakes are seedlings in a garden that grow back as you get them right.
  - Amber is a currency separate from XP that drops from reviews.
  - Gear has perks that never skip learning: a lantern for hints, a cloak as a streak freeze.
  - The map is drawn in an ink style that also suits e-ink.
- **Personalized vocabulary:** Claude on your desktop picks words from your interests and turns them into a custom pack.
- **Reading readiness:** shows what share of the words in a target book you already know, for example the Fantasia series.
- **Ghost race:** compete against your own past week.
- **Monetization, if it ever happens:** optional ads, with a small one-time fee to remove them for good.

---

# Part 2: Build phases

Hand one phase at a time to the coding agent, starting each phase with the brief. Each phase ends with something you can run and check before the next one starts.

## Brief for the agent

You are building a free, offline-first language-learning app in the style of Duolingo, with a strong focus on grammar and conjugation. Part 1 of this document is the full spec, so read it before starting a phase.

- **Stack:** Flutter (stable channel) and Dart, with drift for SQLite. Riverpod for state and go_router for navigation are suggestions. The content pipeline is Python 3.11 or later.
- **Targets:** Android (the APK, also on the Boox), iOS, desktop and web, all in v1. Test on Android first, and keep platform-specific code behind interfaces. iOS builds need a Mac.
- **Repo layout (monorepo):**

```
app/        Flutter app
pipeline/   Python: open data -> JSONL -> course.sqlite
content/    JSONL source packs: it/, nl/, later hns/
schema/     JSON Schemas for course.yaml and the JSONL files
```

- **Rules:**
  - Never hardcode a language. Persons, tenses, scripts and accent handling come from the course database.
  - Item IDs are permanent and never reused.
  - The course database is read-only inside the app, and progress lives in a separate database.
  - Build the interfaces for later features now (`AnswerInput`, `Explainer`, `PackSource`, `SyncBackend`), but implement only the local or null versions.
  - Every phase ends with unit tests passing, `flutter analyze` clean, and the README updated.
  - Ask before adding any heavy dependency.

## Phase 1: Content format and pipeline

Goal: one command builds `it.sqlite` and `nl.sqlite` from open data.

- **Schemas.** Write JSON Schemas for `course.yaml` and for the lexicon, verb and sentence JSONL files. They include `tr.en` and `tr.nl`, `variants`, `freq`, `tags`, verb `class`, the stem and ending split, and the course's own lists of persons and tenses.
- **Importers.**
  - kaikki.org wiktextract dumps for Italian and Dutch: lemmas, part of speech, gender, translations and conjugation tables
  - Tatoeba sentence pairs (it–en, it–nl, nl–en)
  - A frequency list for each language
- **Token alignment.** Link each sentence token to a lemma and form by looking the inflected form up in the conjugation tables. Tokens that don't match stay unlinked.
- **Course files.** Write a `course.yaml` for each language with 3 units and about 8 skills, mixing vocabulary and grammar skills.
  - Italian: the regular present of -are, -ere and -ire verbs, essere and avere, articles
  - Dutch: the present tense, the perfectum with hebben or zijn, de or het
- **Compiler.** Turn the JSONL and YAML into a `course.sqlite` with indexes and a schema version number.
- **Validator.** Check that: IDs are unique; prerequisites form no cycle; every token's word exists; every grammar skill has enough verbs with complete tables for its tense.
- **Attribution.** An attribution file for the CC BY-SA and CC BY sources.

Done when: `python -m pipeline build it nl` produces both databases, the validator passes, and a report prints item counts for each skill.

## Phase 2: Local database layer

Goal: the app opens course databases from local files and records every answer in the progress database.

- **Project setup.** The Flutter project and drift. Open each course database read-only from the app's documents folder. During development, load it from assets or a file picker.
- **`CourseRepo`.** Units, skills, a skill's items resolved from its query, verb forms, and sentences by word or by form.
- **`ProgressRepo`, with this schema:**
  - `review_log`, append-only: UUID, facet ID, timestamp, rating, exercise type, input mode, response time in milliseconds, the answer given
  - `facet_state`: stability, difficulty, due date, last review, number of reviews, number of lapses
  - `settings`
- **Facet IDs.** Use the scheme `{itemId}#rec`, `{itemId}#prod` and `{itemId}#form:{tense}`.
- **FSRS.** Use an existing Dart implementation if it matches the reference test values; otherwise port the reference one. `rebuildStates()` recomputes every `facet_state` from `review_log`, so the log is the single source of truth.
- **Skill strength.** The mean predicted recall across a skill's facets, computed by a query.
- **`PackSource` interface.** Implement only `LocalPackSource` for now.
- **Debug screen.** Lists courses and skills with item counts and strength.

Done when: FSRS tests match the reference values; rebuilding states from a sample log reproduces the stored states exactly; the debug screen shows both courses.

## Phase 3: Exercise engine

Goal: generate and grade all 9 exercise types from the data, in pure Dart with no UI.

- **`ExerciseTemplate` interface,** with three methods: `canGenerate(facet)`; `generate(facet, ctx)`, which returns an `Exercise`; `grade(exercise, answer)`, which returns a `Result`. `Exercise` is a sealed class with one subtype per template.
- **Templates:** flashcard, multiple choice, match pairs, conjugation pick, conjugation grid, sentence builder, cloze, spot the error and transform. Listen and pick is left out because v1 has no audio.
- **Wrong-answer options.** Draw them from other persons in the same tense, words with the same tag, and words with a similar frequency rank. Check every option against all valid forms and translations, so no option is accidentally correct.
- **Answer normalization.** Case, punctuation and spelling variants are handled. Accent strictness (strict or lenient) is a setting.
- **Session builders:** `LessonBuilder(skill, focus)`; `LabBuilder(skills, types, length)`; `NonStopQueue`, an endless stream. The focus presets (mixed, vocabulary, grammar) are a config file of weights per exercise type.
- **Grading to the scheduler.** Map each result to an FSRS rating and write it with `ProgressRepo.record()`.
- **Hooks for later features:** `AnswerInput` (tap and keyboard now, ink later); `Explainer.explain(MistakeContext)`, which returns a `Stream<String>`, with `NullExplainer` as the only implementation for now; a `MistakeContext`, built and stored on every wrong answer: the exercise, the expected answer, the answer given, and the grammar note.
- **Sample command.** Prints 20 example exercises per skill and type, so you can check the Dutch ones by eye.

Done when: tests show every template produces at least 20 valid exercises for every skill in both courses, with no duplicate options and the correct answer present exactly once.

## Phase 4: App screens

Goal: a usable app on Android, fully offline.

- **Map.** Lay skills out in layers by longest prerequisite path, with units as horizontal bands and `pos` overriding the position. Each node has a strength ring and shows the days since it was last practiced. Tap a node to start a lesson. Long-press it to see the grammar note (rendered markdown) and the item list.
- **Lesson player.** One widget per exercise type, tap-first. Instant feedback that shows the correct answer. A "Why?" button connected to `Explainer`, hidden while it's `NullExplainer`. A summary at the end of the session.
- **Exercise lab.** Choose any skills and exercise types (multi-select) and a session length.
- **Non-stop mode.** An endless player with a running count that you can stop at any time.
- **Settings:** course; source language (English or Dutch); default lesson focus; accent strictness; light or dark theme.
- **Polish.** Haptics, sounds and animations, all behind a `reduceMotion` flag that the future e-ink mode will use.
- **Release build.** A signed release APK.

Done when: the APK installs on the phone and the Boox, a full lesson works in airplane mode, you can switch between both courses, and the iOS, desktop and web builds start and run a lesson.

## Phase 5: Progression

Goal: rewards that track real memory, all computed from `review_log`, so that sync later merges cleanly.

- **XP.** Each answer earns XP weighted by its facet's state, with a bonus for due and lapsed facets. Levels follow an increasing curve.
- **Skill tiers.** Bronze, silver and gold on the map, using the thresholds in Part 1, and dropping a tier when recall decays.
- **Streaks.** A heatmap of practice days, with streak freezes earned from reviews.
- **Challenges.** Weekly and monthly challenges with badges.
- **Verb collection page.** Conjugation tables that light up as you master each tense.
- **Non-stop extras.** A combo multiplier, bonus rounds such as a timed conjugation blitz, and a record for your best run.
- **Session summary.** XP earned, words that improved, and skills whose tier changed.

Done when: recomputing from the log gives the same XP and tiers; streak tests cover time zones, midnight and freezes.

## Phases 6 to 8: Later

1. **Sarnami (`hns`), a Dutch–Sarnami course.** Scrape [source] Suriname's Nederlands–Sarnami woordenboek, one page per letter; parse entries; draft verb tables with Claude from a grammar description; packs get an `unverified` flag; the scraped data stays out of the public repo until [source] gives permission.
2. **Downloads and sync.** A `GitHubPackSource` (reads `index.json` from Releases, checks versions and checksums, swaps the course database in atomically) and a `DriveSyncBackend` (Google Drive `appDataFolder`, merges review logs by event ID).
3. **Handwriting and AI.** An ML Kit Digital Ink `AnswerInput` plus the Onyx pen SDK on the Boox; an e-ink mode built on `reduceMotion`; a `ClaudeExplainer` (API key in secure storage, small fast model, streaming, cached per item and error).
