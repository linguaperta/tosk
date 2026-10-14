# Exercise engine (Phase 3)

`app/lib/engine/` generates, grades and sequences exercises from a `CourseData`. It is pure Dart (no Flutter, no drift) and depends only on `core/`. Import everything through `package:tosk/engine/engine.dart`.

## Layout

| File | What it does |
| --- | --- |
| `template.dart` | The `ExerciseTemplate` contract, `OptionPicker` (wrong-option filter), shared grading helpers |
| `templates/*.dart` | The ten templates (`listen_pick` since v0.5), plus `alterations.dart` (one-word sentence errors shared by spot-the-error and multiple choice) |
| `course_index.dart` | Cached derived lookups: verb-form and article occurrences in sentences, auxiliary positions, synonyms (through gloss/spelling indexes), distractor pools, sentences by translation, pro-drop and compound-contiguity statistics, and `memo` for templates' `canGenerate` answers |
| `gen_context.dart` | `GenContext` (course, options, seeded `Random`, facet states, skill, gate, sentence history) and `FacetStage` / `StagePolicy` |
| `gating.dart` | `SentenceGate` (grammar gating and the unknown-word cap) and `SentenceHistory` (recently seen sentences) |
| `selector.dart` | Picks the exercise type for a facet (stage affinity × focus weight × restrictions) and generates it |
| `focus_presets.dart` | Focus weights, parsed from `assets/config/focus_presets.json`, with identical embedded defaults |
| `grading/rating.dart` | `RatingPolicy` (result → FSRS rating, fast-answer table) and `GradeOptions` |
| `text/normalize.dart` | NFC, case, punctuation, apostrophes, accent folding, `matchAnswer` |
| `session/` | `EngineSession` (serve, grade, record, re-queue, result stream), the builders, `assessment.dart` (test out, placement, tough words), and `EngineSessionFactory` |
| `reference.dart` | Lookups for the UI's reference and word popovers: `glossForToken` (lemma, person, tense label, article, glosses), `CourseReference` (accent-insensitive search, verb tables with irregular forms, skills teaching an item, examples) |
| `debug/exercise_printer.dart` | `exercisePrompt` (stored with mistakes), `formatExercise`, `sampleExercises` |

## Using it from the UI

```dart
final factory = EngineSessionFactory(
  course: courseData,                 // InMemoryCourseData from the data layer
  store: progressRepo,                // ProgressStore
  scheduler: fsrsScheduler,           // Scheduler: retrievability orders filler and fading
  options: SessionOptions(sourceLang: 'en', accents: AccentStrictness.lenient),
  presets: FocusPresets.fromJsonString(await rootBundle.loadString('assets/config/focus_presets.json')),
);
final session = await factory.lesson('present-are', focus: LessonFocus.grammar);
session.results.listen((event) { /* XP, combos, streak: event.streak */ });
for (var e = await session.next(); e != null; e = await session.next()) {
  final result = await session.submit(e, answer, elapsed: stopwatch.elapsed);
  if (!result.correct) explainer.explain(session.mistakeContext(e.id)!);
}
final summary = session.summary();
```

`lesson`, `lab`, `nonStop`, `fading`, `review`, `testOut`, `placement` and `toughWords` return `LessonSession`, `LabSession`, `NonStopSession`, `FadingSession`, `MistakeReviewSession`, `TestOutSession`, `PlacementSession` and `ToughWordsSession`, all `EngineSession`s. Beyond `PracticeSession` they offer `results` (a broadcast stream of `AnswerEvent`), `mistakeContext(exerciseId)`, and on non-stop `unlockedSkills()` and `enqueueBonus(types:, count:)`. Test out and placement are `AssessmentSession`s with an `outcome` once they end. `lesson(length:)` takes the lesson length (the UI offers `SessionLength` quick 5, normal 12, long 20).

UI notes on the exercise contract:

- **Conjugation pick:** an empty ending (Dutch `ik werk` = `werk` + '') is shown as the option `–` (`kNoEnding`).
- **Conjugation grid:** `tiles` holds one tile per asked cell, so a form shared by several cells (`werken` for wij, jullie and zij) appears once per cell, plus the distractors. A UI that consumes tiles works, and so does one that reuses them. Tapped tiles are graded with exact diacritics, typed ones by the accent setting. `cellCorrect` gives per-cell feedback.
- **Cloze:** `options == null` means free text (a `TextAnswer`, which may carry ink `candidates`; for keyboard and ink learners). The hint of a `#prod` or `#article` gap is the gloss that matches the translation (`lo` in "I know it": `it`), or all glosses when none does (`it, the`).
- **Spot the error:** render with `tokenPre[i] + tokens[i]`, or use `renderSpotError`.
- **Article multiple choice:** the prompt is `___ ragazzo` and `hint` is the meaning.
- **Lenient accents:** `Result.accentSlip` means "accepted, but watch the accent".
- **Listen and pick (v0.5):** speak `text` in `languageCode` (the course's `meta.target`) with text-to-speech; never show `text` before checking. `options` are target-language sentences (or words when `isSentence` is false); `translation` and `tokens` (the right sentence, tap-for-gloss) are for after checking.
- **Token alignment (tap-for-gloss).** Exercises that show a target-language sentence carry its tokens as `TokenRef`s (text, whitespace before, aligned item id and `'{tense}.{person}'` form, from `Token.lex` / `Token.form`; `tokenRefsOf(sentence)`): `ClozeExercise.tokens` with `gapFrom..gapTo` (the whole correct sentence; the gap covers those tokens, or only the start of token `gapFrom` for an elided article), `SpotErrorExercise.tokenRefs` (parallel to `tokens`; the wrong word carries the original token's alignment), `MultipleChoiceExercise.sentenceTokens` (sentence variant: the prompt when recognizing, the correct option when producing), `TransformExercise.sourceTokens` and `SentenceBuilderExercise.answerTokens`. All optional (null from hand-made exercises). `glossForTokenRef(course, ref, lang)` resolves one for the UI. The UI never makes the exercise's own item tappable before the answer is checked.

## Facets, templates and stages

| Facet | Templates |
| --- | --- |
| `#rec` | flashcard, multiple choice (word or sentence → meaning), match pairs, listen and pick (only with `SessionOptions.listening`) |
| `#prod` | flashcard, multiple choice (meaning → word, translation → sentence), sentence builder, cloze |
| `#form:{tense}` | conjugation pick, conjugation grid, cloze, spot the error, transform |
| `#article` | multiple choice (`___ noun` over `meta.articles`), cloze (the article token), spot the error |

`Skill.exercises` restricts the types for a skill. Lessons respect it; the lab overrides it, because choosing types is the point of the lab.

**Stages** (`StagePolicy`): a facet is *fresh* when it has never been reviewed, *learning* while its stability is under 5 days, and *stable* after that. `kStageAffinity` weights the types per stage: fresh facets get flashcards, multiple choice, conjugation pick and a grid with prefilled cells; stable facets get the sentence builder, cloze, a full grid, transform and spot the error. The selector multiplies that weight by the focus weight and draws one type. If no type has weight under the focus (say, a vocabulary focus on a pure grammar skill), it ignores the focus, and as a last resort it tries every allowed type.

Cloze uses free text only when the preferred input is keyboard or ink ("typing is never required": with tap input it always offers choices). For keyboard and ink, `StagePolicy.freeTextDays` (default 0, meaning always) can hold free text back until the facet reaches that stability.

## Template rules

Every wrong option goes through `OptionPicker`. It rejects an option that is empty, that equals a correct answer after folding case, punctuation and diacritics, or that duplicates another option, so the correct answer appears exactly once. What counts as "correct" for each template:

- **Flashcard:** the front is the lemma with its article (`il ragazzo`) and the back is all glosses. Graded by self-grade only.
- **Multiple choice:**
  - *Word, recognize:* wrong meanings come from items of the same POS (shared tag first, then similar frequency) that are not synonyms. A synonym is an item with an overlapping gloss in any language, parenthesized parts ignored, or the same spelling. No meaning of the target or of any synonym is offered (`dag` also means `hi`, through `hallo`).
  - *Word, produce:* no spelling of the target or of a synonym.
  - *Sentence:* other sentences whose aligned items and forms are not equivalent (synonyms count as equal), with distinct translations. Producing a sentence also offers the same sentence with one verb form or article swapped.
  - *Article:* the course's other articles.
- **Match pairs:** five `#rec` facets, from the skill first, then from other skills. No two items on the board may overlap, and no displayed meaning may be a meaning of another board item or of its synonyms. Each pair grades its own facet.
- **Conjugation pick:** only cells with a stem/ending split and a single word. Wrong endings come from other persons in the same tense, then other tenses, then same-class verbs, then any verb; another verb's ending only when its stem ends like this one (both in a vowel or both in a consonant: `ga` + `n`, never `denk` + `n`). An ending is never offered when stem + ending is an accepted form of the asked cell, which covers homographs such as Dutch `eet` (ik = jij = hij) and alternative spellings.
- **Conjugation grid:** distractors that match no form of any cell. In priority order:
  - the person-dependent word of a compound form swapped with another verb's (`sono mangiato`), skipped when the verb's `auxiliary` has a `|` because both would be right;
  - the stem with another class's ending (`mangete`, only from a stem that ends alike) or another person's ending (`maaken`);
  - the verb's other tenses with the same word count;
  - other verbs' forms.
- **Sentence builder:** the sentence's word tiles, the first one (and the first of a later sentence in the text, `"Was Bill in Japan?" "Ja, …"`) lower-cased unless it looks like a proper noun, plus wrong tiles: other persons' verb forms, wrong articles and related words. A wrong tile is never a word of the sentence or of another sentence with the same translation (`Come stai?` / `Come sta?`), a spelling of a synonym, or a word of an accepted verb form in the sentence. Accepted answers are the sentence plus any other sentence with the same translation whose words fit the tiles. Grading joins the words, so `l'` + `acqua` and `l'acqua` are equal.
- **Cloze:** the gap is an aligned token, rendered so that `before + expected + after == sentence.text`.
  - `#form`: a contiguous multi-word form is one gap. For a split form (`heb … gegeten`) only the person-dependent word is gapped. Options of another tense must have the gap's word count (`Ik ga` would fit the gap of `Ik ben gegaan`).
  - `#prod`: verbs offer the same cell of other verbs; other words their lemma or plural.
  - `#article`: an elided article inside a token (`l’acqua`) can be gapped too.
  - Wrong forms exclude every accepted form of the cell and of persons that share its pronoun (Dutch `hij/zij` and `zij`).
- **Listen and pick** (`templates/listen_pick.dart`, v0.5): only when `SessionOptions.listening` (the UI sets it when the device has a text-to-speech voice for the course language; Sarnami never), so `canGenerate` is false otherwise and the selector picks another type. Fresh facets hear the word (the lemma; wrong options are other lemmas of the same part of speech, similar ones first: within two letters in length and sharing the first letter or the last two, never a spelling of the item or a synonym); other facets hear a sentence with the item (`sentenceShare` 0.75), chosen like every gated sentence (`sentenceOk`, `prefer`, `useSentence`). Wrong sentences: at most one copy of the sentence with one verb form or article swapped (`formSwaps`, tenses only when `tenseShowable`, never right after an elided word: `c'siamo`), then other sentences whose grammar the learner knows (`featuresKnown`; their words may be new), not equivalent, within two words and 0.6–1.6× the length, sharing an aligned word first. **No two options may sound alike:** options are compared by `soundKey` (`foldAnswer`, then per word a silent `h` dropped, final `d`/`dt` read as `t`, `ij`/`y` as `ei`/`i`, doubled letters collapsed, words joined), so `ha`/`a`, `è`/`e` or Dutch `wordt`/`word` never stand side by side. Grading is `gradeChoice`; the fast-answer threshold is 8 s (listening takes time).
- **Spot the error:** one word is replaced, by the matching word of another person's form in the same tense or by a wrong article. Never by another tense: `De leerlingen mochten …` for `mogen` is grammatical and wrong only against the translation. The same exclusions apply (Italian `sono` is io and loro). Elision spacing is fixed through `tokenPre`. The translation is always shown, because in pro-drop sentences the error is defined relative to it (`Mangiate alle otto.` is grammatical on its own).
- **Transform:** built only when the result is reliably constructible:
  1. *Same word count:* the words are replaced in place, wherever they stand.
  2. *Compound → single word:* the finite (first) word is replaced and the rest removed. This is valid for V2 and subordinate clauses.
  3. *Single word → compound:* only when the course's own sentences show that tense's compound forms as contiguous (≥ 90 %, so Italian yes and Dutch no) or the verb ends the sentence, and no clitic pronoun precedes the verb.
  4. *Person changes:* only in pro-drop sentences. The course must usually omit the subject pronoun for both persons (`dropsPronoun`, learned from the data, counting the pronouns of the person key and its labels, `jij/je`: never for Dutch), only adverbs, conjunctions and prepositions may precede the verb, and the sentence may contain no pronoun and no name (`Heeft Tom …`). Also not:
     - from a form another person shares (`sono`: io and loro, so `Dove sono i vostri nipoti?` may be misaligned);
     - from a third person when the sentence has a noun (it may be the subject), or from the third person singular when a translation says "it", "there" or "het" (impersonal: `Sembra ieri`, `È ora di …`);
     - singular ↔ plural when an adjective or participle may agree with the subject (`Dice di essere bravo`) or the verb is "to be" (`Non siamo parenti`).
  5. *Tense changes* only when every other verb in the sentence is in the source or the target tense and has a known form (`Wie was de filosoof die ooit geleefd heeft?` would mix tenses); not for an auxiliary verb next to a participle (`als ik nee had gezegd`), not into a compound form next to a participle (passive `gezegd werd`), and not from a form spelled like the infinitive (`vertellen` may be an infinitive after a modal). A form written out of order (`opgestaan ben`) is only rewritten into the same tense. A form shared by another person is only rewritten when that person's target form is the same (`werken` → `werkten` yes, `sono` → `ero`/`erano` no).
  6. *One finite verb:* the transformed verb (with its auxiliary) must be the sentence's only finite verb, or the other one keeps its tense or person (`Il dolore va e viene` → `va e è venuto`).
  7. *Time adverbs* (course data: `meta.time_adverbs`, from course.yaml `time_adverbs`, adverb → the tenses it fits, matched as whole folded words, multi-word keys allowed): a tense change never produces a tense the sentence's adverbs don't fit (`Adesso mangio` never becomes a past, `Ieri ho mangiato` never the present).
  8. A changed word after an elided one must start with a vowel or `h` (`l'ha fatto` → `l'faceva` is not built).

  Gendered alternatives (`sono partito;sono partita`) become extra accepted answers. A third-person target form with gendered alternatives is not built when the sentence has a noun or a translation with "it" (`Le cose succedono` → `sono successi`, `Come va?` → `è andato`).

**Grammar gating of wrong options.** Under a gate, wrong options and tiles never show a form of a tense the learner has not met (`SentenceGate.tenseShowable`: the tense is known, and so are its irregular forms when the course teaches them as a feature, `irregular:futuro`): cloze options of another tense, conjugation-grid distractors from the verb's other tenses, conjugation-pick endings of other tenses, sentence-builder tiles and multiple-choice sentence alterations swapped into another tense. Wrong target-language sentences in multiple choice use only known grammar features (their words may be new).

**Occurrences.** `CourseIndex.formOccurrences` matches aligned tokens against the cell's accepted forms, in any order (Dutch subordinate `gegeten heeft`). When only the participle is aligned, it finds the auxiliary nearby. A token whose text is not an accepted form of its aligned cell, such as Dutch inverted `Werk jij?` aligned to `jij: werkt`, is never used, and neither is a compound form whose later word follows a determiner (`Hebben dieren een geweten?`: a noun).

**Compound tenses.** The pipeline aligns a compound form on its participle (`mangiato` → `passato_prossimo.io`, the cell's form being `ho mangiato`) and the auxiliary separately to the auxiliary verb's present (`ho` → `avere`, `presente.io`). `CourseIndex.auxiliaryPositions(sentence)` finds those auxiliaries (the nearest token within 6 that reads the form's other word, for the first accepted spelling whose words are all present). They belong to the compound form: they are never an occurrence of the auxiliary verb's own present (`Zijn jullie … geweest?` is no `zijn` present exercise, and `Ho mangiato` no `avere` one), so cloze, spot the error and transform only touch them through the compound form. The validator applies the same convention independently (`_ownerCell`).

## Grammar gating and sentence variety

`gating.dart` implements the contract in docs/ARCHITECTURE.md ("Grammar gating"). Every session calls `prepare()` before its first exercise (`next()` does it):

- **Gate** (`SentenceGate`, only when the course has `meta.base_features`; older packs are not gated):
  - *Started skills*: every skill with a reviewed facet (`store.allStates(courseId)`), plus the skills of every facet answered during the session (`markStarted`, so non-stop opens a skill's grammar after its first answer).
  - *Current skills* (`EngineSession.currentSkillIds`): the lesson's skill, the lab's skills; none for non-stop, fading and mistake review.
  - `knownFeatures` = `base_features` ∪ the features of the started and current skills and of their prerequisites (transitively, like the pipeline's home-skill rule).
  - `knownItems` = the items of the started and current skills.
  - A sentence is allowed when its features ⊆ `knownFeatures` and its unknown words ≤ the cap: `SentenceGate.capFor(focus, skill)` = 1 for a grammar focus or a grammar skill, else 2. A word aligned to an unknown item counts 1. An unaligned word counts 0 when it is a name or a number (a capitalized word inside a sentence, a sentence-initial word that also appears capitalized inside one, or digits) and 2 otherwise: in the packs those are rare (125 it / 329 nl sentences) and often an untagged grammar form (passato remoto `Comprai`), so such a sentence never passes the grammar cap.
  - Cloze, spot the error, transform, the sentence builder and sentence multiple choice only use allowed sentences; transform also needs its target tense and the facet skill's features to be known. `canGenerate` answers are memoized in the gate (`GenContext.memo`), so a template without an eligible sentence returns false and the selector picks another type. A lesson never falls back to ungated sentences: conjugation grids and picks, flashcards, word multiple choice and match pairs fill it.
- **Variety** (`SentenceHistory`): a bounded LRU of the last 1000 sentence ids per course, stored as a JSON array in the settings key `engine.recent_sentences.{courseId}` (no schema change). `GenContext.prefer` ranks candidate sentences by 0.75 × unknown words + a recency penalty (0 unseen, 1–3 seen, higher when seen more recently) + a random jitter below 1. Generated sentences (`src` starting with `claude-gen`, written for the course by the pipeline's `gen` command where Tatoeba has too few easy sentences) add `kGeneratedSentenceWeight` = 1, so an unseen real sentence with as many unknown words always comes first, and a generated one ranks about level with a real one seen long ago. Sentences already shown in this session come last, so a session repeats a sentence only when the facet has nothing else. Templates record what they show (`GenContext.useSentence`). The session saves its sentences when `next()` runs out and on `stop()`: read, merge (moving re-seen ids to the end), trim, write, serialized per key, so concurrent sessions keep each other's exposures. A mistake re-ask is a new exercise and usually gets another sentence.
- **Exercise types:** the selector tries the previous exercise's type (or the type a re-asked mistake was missed with) only after every other type of the same weight tier failed, and each of the last three types weighs 0.6× per occurrence.

`test/engine/gated_validity.dart` checks gated exercises against an independent computation of the learner's knowledge. `real_pack_gating_test.dart` runs it on the bundled packs for a fresh learner and for learners who started units 1..k, plays full lessons (every unit-1 skill for a fresh learner, every unit-3 skill after units 1–3) and a non-stop run, and checks variety across lessons. `runTemplateValidity` stays the "everything known" check.

## Grading and recording

`RatingPolicy`: a wrong answer is Again; a right one is Good, or Easy when faster than the type's threshold (`defaultFastMs`, configurable). An answer accepted only through accent folding is capped at Good, and flashcards keep their self-grade. Tapped tiles and choices are compared with exact diacritics. Typed and ink answers follow `AccentStrictness`: strict means exact diacritics; lenient folds them and sets `accentSlip`. Both always normalize NFC, case, punctuation, whitespace and apostrophe variants. Ink answers are accepted when any of the top-k candidates matches.

`submit()` writes `ReviewEvent`s through `ProgressStore.record()`, each with a UUID v4 id, the session id, the mode name, the exercise type, the input mode, the response time and the answer text.

**Re-ask policy (no double penalty).** Per facet, per session:

- The first wrong answer writes one Again event and one `MistakeRecord`, with the same id as the event. The record holds the prompt from `exercisePrompt`, the expected and given answers, the skill and its grammar note.
- After that mistake, wrong answers on the same facet write nothing.
- The first correct answer after the mistake writes one Good, never Easy, as the relearning step.
- Later answers on that facet in the session write nothing.
- Facets with no mistake write an event for every answer.

A wrong facet is re-queued 2–4 exercises later, at most twice per session. Re-queues extend `plannedLength`.

## Sessions

- **Lesson** (`LessonBuilder(skill, focus)`): states are loaded once. About 12 exercises:
  1. due facets, most overdue first;
  2. up to 5 new facets in introduction order;
  3. filler: the weakest or least recently reviewed facets, then repeats of the lesson's new and due facets, without immediate repeats.
- **Lab** (`LabBuilder(skills, types, length)`): due facets, then new ones (round-robin across skills), then the weakest, cycled. Only the chosen types are used, overriding skill restrictions.
- **Non-stop** (`NonStopQueue`): endless. It serves due facets from unlocked skills and mixes in a new facet every 4th exercise; when nothing is due and nothing is new, it takes from the three weakest. A skill is unlocked when every prerequisite is *started* (at least one facet reviewed), re-evaluated after each answer. `enqueueBonus` restricts the next exercises to some types, for a progression bonus round.
- **Fading** (`FadingBuilder`, mode `review`): due facets, then the lowest predicted recall, across all skills. No new facets.
- **Mistake review** (`ReviewBuilder`, `factory.review(length:)`, mode `review`, `session/mistake_review.dart`): one exercise per *open* mistake, up to `length` (default 12). `openMistakes(store:, course:, scheduler:, now:)` lists them (the UI uses it for the count and the list):
  - It scans the latest 300 `MistakeRecord`s of the course and keeps the latest per facet, with a count.
  - **Resolution rule:** a mistake is resolved once its facet is answered correctly in a *later session*: a correct event not before the mistake whose session id differs from the mistake event's (the record id is the event id). The re-ask 2–4 exercises later in the same session does not count. A new mistake on the facet (also during review) opens it again.
  - Facets the course no longer trains (pack update) are skipped.
  - Order: still weak (predicted recall < 0.9, `kMistakeWeakRecall`) first, then the rest; most recent first within each group.
  - Each facet is asked with the exercise type that was missed when the skill allows it and the template can build it (`only: {type}`); flashcard mistakes (a self-graded Again) and types that can't serve the facet fall back to the normal selector. If the restricted generation still fails, the slot is retried unrestricted.

### Test out, placement and tough words (`session/assessment.dart`)

- **Test out** (`TestOutBuilder`, `factory.testOut(skillId, length: 10, passMark: 0.8)`, mode `testOut`): the skill's facets, production first (`#prod`, `#form`, `#article` shuffled, then `#rec`), cycled to `length`. Each slot asks for production-leaning types (`productionTypes`: sentence builder, cloze or multiple choice for `#prod`; grid, cloze, transform or spot the error for `#form`; …); when none can be built it is retried with any `kAssessmentTypes` type (everything auto-graded on one facet: no self-graded flashcards, no multi-facet match pairs). No re-asks (`maxReasks: 0`), so the score is first answers: `correct / answered`. When the last `next()` returns null the session concludes: at `score >= passMark` it **credits** the skill.
- **Placement** (`PlacementBuilder`, `factory.placement(perSkill: 2, passMark: 0.8)`, mode `placement`): unit by unit in course order, `perSkill` production-first facets per skill. A unit passes at the pass mark; the session stops as soon as the current unit can no longer reach it (more wrong answers than `slots × (1 − passMark)`), or after the last unit. Every skill of the units passed before the failure is credited. `outcome`: `passedUnits`, `failedUnit`, `creditedSkills`, the score.
- **Credits** (`kTestOutCreditType`, a core constant): one `ReviewEvent` per facet of the credited skills that is not learned yet (no state, or still in FSRS's learning phase), with `exerciseType: 'test_out'`, `rating: Easy`, `correct: true`, `responseMs: 0`, input `self`, and the session's id and mode, written through `EngineSession.recordExtra`. Easy graduates a new or learning facet straight into review, so the skill meets progression's bronze rule (every facet learned) and the skills requiring it unlock. Because credits are ordinary log events, they sync and replay like answers; progression gives them no XP and doesn't count them as reviews (`docs/progression.md`). A stopped session (Quit) concludes nothing and has no `outcome`. Mistakes made during the quiz are recorded as usual and stay open for mistake review.
- **Tough words** (`ToughWordsBuilder`, `factory.toughWords(length: 12, minLapses: 4)`, mode `review`): `leechFacets` = facets of the course's skills whose state has at least `minLapses` lapses, most lapses first, then lowest recall (progression's `toughWords` uses the same rule for the UI's count). Each one becomes a recognition → production ladder (`leechLadder`): `#prod` = multiple choice on its `#rec` sibling, multiple choice on `#prod`, then cloze or sentence builder; `#rec` = multiple choice, match pairs or multiple choice, then production on its `#prod` sibling; `#form` = conjugation pick or grid, then cloze, transform, spot the error or grid; `#article` = multiple choice, then cloze or spot the error. Ladders are added whole until `length` is reached; a step that can't be built is retried with any type. Mistakes are re-asked as in any session.

## Typing mode, accent letters and overrides (v0.3)

- **Typing ("challenge") mode** is the UI setting "Answer input: Tap / Type" (`lesson.answer_input`), which sets `SessionOptions.preferredInput = keyboard`. The engine changes are small: cloze is free text for keyboard learners (as before, `freeTextDays`), and **conjugation pick grades a `TextAnswer`**: the typed ending (`-`/`–` = the empty ending, a leading hyphen ignored, the whole form accepted too) as `stem + ending` against `ConjPickExercise.accepted` (new optional field: every accepted spelling of the cell) with the accent setting and `accentSlip`. Grids (`GridAnswer(inputMode: keyboard)`, or `ink` with `candidates` per cell since v0.5) and the sentence builder and transform (`TextAnswer` through `gradeTiles`) already graded typed answers with the accent setting. Recognition types (flashcard, multiple choice, match pairs, spot the error) stay tap.
- **`specialLetters(course)`** (`special_letters.dart`): the target language's non-ASCII letters, lower-cased and NFC, counted over every spelling, plural, accepted verb form and sentence word, most frequent first; a letter needs ≥ 3 occurrences and ≥ 0.2 % of the top letter's count (drops loanword letters), at most 12. Real packs: it `è à ò é ì ù`, nl `ë ï é è ü`, hns `ṯ ê ã ṟ õ ḏ î é`. Cached per course.
- **Overrides** ("I was right", `OverridableSession` in `core/interfaces/session.dart`): `EngineSession.canOverride(exerciseId)` / `overrideAnswer(exerciseId)` write one `kOverrideType` event (Good) per wrong facet outcome the answer recorded (see ARCHITECTURE.md for the replay rule), count the answer as correct, drop the facet's queued re-asks and its mistake (so later answers in the session record as usual), and return the events. A wrong re-ask recorded nothing, so it only counts as correct. Tests: `test/engine/override_test.dart`.

## Handwriting and listening (v0.5)

- **Ink answers.** Handwriting is `SessionOptions.preferredInput = ink` (cloze then uses free text, like keyboard). Every free-text grader accepts recognizer candidates: `TextAnswer.candidates` for cloze, conjugation pick (each candidate as an ending or a whole form), the sentence builder and transform (`gradeTiles`), and `GridAnswer.candidates` (one list per cell, parallel to `cells`) for the grid, where a cell is right when its text or any of its candidates matches. Ink follows the accent setting like typing (lenient: an accent-only match is a slip). The UI sends the best reading as `text` and the next two as candidates (sentences written in parts: combinations of the parts' readings, the top five). `RecognizerAnswerInput` (core hook) keeps the top k. Tests: `test/engine/listen_ink_test.dart`.
- **Listening capability.** `SessionOptions.listening` (default false) gates `listen_pick`; sessions, the lab, assessments (`kAssessmentTypes` includes it) and mistake review simply never get the type without it. The validity suites (`runTemplateValidity`, `runGatedValidity`, the real-pack gating test and the sample printer) assume it is available, so `listen_pick` is checked on every course: exactly one option sounds like the spoken text (and is it), no two options sound alike, the sentence contains the item and its translation is the sentence's, the word is the lemma and no wrong option spells the item; under a gate, the spoken sentence and the wrong sentences only use known grammar (`gated_validity.dart`).

## Reference lookups (`reference.dart`)

- `glossForToken(course, itemId:, form:, word:, lang:)` → `WordGloss`: `headline` is `mangiamo → mangiare · noi · present` for verb forms (person key, tense label in the source language; non-finite forms only the tense), `il pane` for nouns (`CourseIndex.withArticle`), the lemma otherwise (the word is left out when it is the lemma).
- `CourseReference.of(course)` (cached per course): `items` and `verbs` sorted by folded lemma; `search(query, lang, verbsOnly:)` over lemmas, variants and plurals, every accepted verb form, and glosses in `lang` (a gloss matches by any of its words, so "eat" finds "to eat"), ignoring case and accents (`foldAnswer`), ranked lemma > inflected form > gloss (or a word of it) > lemma prefix > gloss prefix > anywhere, then by frequency; `verbTable(itemId, lang)` (finite tenses in `meta.tenses` order with persons in `meta.persons` order, then infinitive, participle, gerund); `skillsTeaching(itemId)`; `examples(itemId)` (shortest first).
- **Irregular forms** (`isIrregular`, a highlighting heuristic): only for verbs marked `irregular`. A single-word form is regular when it equals the verb's stem (declared, else its most common form stem) wrapped in a prefix/suffix pattern that at least 10 % of the course's regular verbs of the same class use for that tense and person (all classes when the class has no regular verbs; prefixes cover Dutch `ge…t`). A compound form is irregular when it contains an irregular participle. Without a stem or a pattern nothing is marked.

## Adding a template

1. Add the type id to `ExerciseType` and an `Exercise` subtype in `core/models/exercise.dart`. This is a contract change, so tell the UI side.
2. Implement `ExerciseTemplate` in `templates/your_template.dart`:
   - `kinds`: the facet kinds it serves.
   - `canGenerate`: deterministic and cheap.
   - `generate`: draw randomness only from `ctx.random` and ids only from `ctx.nextId()`, and filter every wrong option through `OptionPicker` with all valid answers as `forbidden`.
   - `grade`: pure.
3. Register it in `defaultTemplates()`, add its kinds to `ExerciseSelectorTypes.templateKinds`, and give it a row in `kStageAffinity`, the focus presets (JSON asset and `kDefaultFocusWeights`) and `RatingPolicy.defaultFastMs`.
4. Add a `case` to `validateExercise` in `test/engine/template_validity.dart` that checks validity against the course data independently of the generator, and list the skills where it must apply in `template_validity_test.dart`.
5. Run `dart run tool/sample_exercises.dart it` and `… nl` and read the output.

## Tests of the v0.3 additions

`test/engine/assessment_test.dart`: test out (production first, no flashcards or match pairs, no re-asks, pass → credits → bronze and the next skill unlocked with no XP and no extra reviews, fail and Quit credit nothing, grammar skills), placement (passes in order, stops early at the first failed unit, credits the passed units, every unit when everything is known), tough words (threshold shared with progression, the ladders, the session's order and types, empty without leeches). `test/engine/reference_test.dart`: glosses (verb forms, nouns with articles, unaligned tokens), search (accents, forms, glosses in both languages, verbs only), verb tables (order, labels, irregular marks), entries, and the token alignment of every template that carries it (cloze gap ranges render back to `before`/`after`).

## Testing against real packs

`runTemplateValidity(CourseData course)` in `test/engine/template_validity.dart` is course-agnostic. `test/engine/real_pack_validity_test.dart` runs it on the bundled packs (`app/assets/courses/*.sqlite`) for every source language: no failures, at least 20 exercises per applicable skill × template, every template used, at least 3 templates per skill (about 5 s for both packs).

`test/engine/real_pack_perf_test.dart` prints and loosely bounds the speed on the real packs (index warm-up, single exercises, 12-exercise lessons). On a desktop: warm-up about 20–130 ms once per course, a single exercise about 0.1 ms median and 2 ms p95, a lesson (generate, grade and record 12 exercises) about 6 ms median.

`tool/sample_exercises.dart` prints examples from a pack: `dart run tool/sample_exercises.dart nl --per 8` (a course id loads `assets/courses/{id}.sqlite`, a path loads that file). The committed samples are `docs/samples/{it,nl}_exercises.txt`; regenerate them after engine or pack changes and read the diff.

## Performance

Generation is synchronous, so everything a template needs repeatedly is cached per course in `CourseIndex` (an `Expando` on the `CourseData`):

- occurrences per verb and per sentence, auxiliary positions, finite forms per verb and tense, word splits and accepted-form keys;
- synonyms through inverted gloss and spelling indexes, meanings per item and language, sentences by normalized translation;
- `memo(key, …)`: templates cache their `canGenerate` answer (deterministic per facet, language and template parameters) and the conjugation grid its candidate groups per facet.

`normalizeAnswer` and `foldAnswer` are memoized (bounded caches), and `InMemoryCourseData.itemsNearFreq` sorts only a window of the frequency-sorted pool instead of the whole part of speech.

## Known limitations

- **Transform** relies on the course's `time_adverbs` list; an adverb missing from it, or a time implied by context, can still give an odd but grammatical sentence. Person changes are rare by design (pro-drop only). Italian imperatives that look like present forms are left without a form by the pipeline (`Chiedi a un poliziotto!`, translations starting with *Ask …* / *Let's …*); one without `!` or such a translation can still be aligned as a present.
- **Conjugation pick** needs stem/ending splits. Fully irregular tables (essere, avere, zijn, hebben) and compound tenses never get it; the grid and cloze cover them.
- **Spot the error and cloze** rely on the translation for pro-drop person swaps.
- **Person hints** come from the alignment. Where two persons share the form (Dutch `maakt` for jij and hij), a subject far from the verb can be missed; the pipeline then leaves the person open rather than guess, so such sentences are simply not used.
- **Sentence builder** accepts only orders attested in the course: the sentence itself, or another sentence with the same translation.
- **NFC** composition covers Latin letters (U+00C0–U+024F, U+1E00–U+1EFF). Other scripts pass through unnormalized.
- **Instruction strings** are in `engine/strings.dart` (English and Dutch); the UI may later move them to its localization.
