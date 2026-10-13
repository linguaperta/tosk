# Exercise engine (Phase 3)

`app/lib/engine/` generates, grades and sequences exercises from a `CourseData`. It is pure Dart (no Flutter, no drift) and depends only on `core/`. Import everything through `package:tosk/engine/engine.dart`.

## Layout

| File | What it does |
| --- | --- |
| `template.dart` | The `ExerciseTemplate` contract, `OptionPicker` (wrong-option filter), shared grading helpers |
| `templates/*.dart` | The nine templates, plus `alterations.dart` (one-word sentence errors shared by spot-the-error and multiple choice) |
| `course_index.dart` | Cached derived lookups: verb-form and article occurrences in sentences, synonyms, distractor pools, pro-drop and compound-contiguity statistics |
| `gen_context.dart` | `GenContext` (course, options, seeded `Random`, facet states, skill) and `FacetStage` / `StagePolicy` |
| `selector.dart` | Picks the exercise type for a facet (stage affinity × focus weight × restrictions) and generates it |
| `focus_presets.dart` | Focus weights, parsed from `assets/config/focus_presets.json`, with identical embedded defaults |
| `grading/rating.dart` | `RatingPolicy` (result → FSRS rating, fast-answer table) and `GradeOptions` |
| `text/normalize.dart` | NFC, case, punctuation, apostrophes, accent folding, `matchAnswer` |
| `session/` | `EngineSession` (serve, grade, record, re-queue, result stream), the builders, and `EngineSessionFactory` |
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

`lesson`, `lab`, `nonStop` and `fading` return `LessonSession`, `LabSession`, `NonStopSession` and `FadingSession`, all `EngineSession`s. Beyond `PracticeSession` they offer `results` (a broadcast stream of `AnswerEvent`), `mistakeContext(exerciseId)`, and on non-stop `unlockedSkills()` and `enqueueBonus(types:, count:)`.

UI notes on the exercise contract:

- **Conjugation pick:** an empty ending (Dutch `ik werk` = `werk` + '') is shown as the option `–` (`kNoEnding`).
- **Conjugation grid:** `tiles` holds one tile per asked cell, so a form shared by several cells (`werken` for wij, jullie and zij) appears once per cell, plus the distractors. A UI that consumes tiles works, and so does one that reuses them. Tapped tiles are graded with exact diacritics, typed ones by the accent setting. `cellCorrect` gives per-cell feedback.
- **Cloze:** `options == null` means free text (a `TextAnswer`, which may carry ink `candidates`).
- **Spot the error:** render with `tokenPre[i] + tokens[i]`, or use `renderSpotError`.
- **Article multiple choice:** the prompt is `___ ragazzo` and `hint` is the meaning.
- **Lenient accents:** `Result.accentSlip` means "accepted, but watch the accent".

## Facets, templates and stages

| Facet | Templates |
| --- | --- |
| `#rec` | flashcard, multiple choice (word or sentence → meaning), match pairs |
| `#prod` | flashcard, multiple choice (meaning → word, translation → sentence), sentence builder, cloze |
| `#form:{tense}` | conjugation pick, conjugation grid, cloze, spot the error, transform |
| `#article` | multiple choice (`___ noun` over `meta.articles`), cloze (the article token), spot the error |

`Skill.exercises` restricts the types for a skill. Lessons respect it; the lab overrides it, because choosing types is the point of the lab.

**Stages** (`StagePolicy`): a facet is *fresh* when it has never been reviewed, *learning* while its stability is under 5 days, and *stable* after that. `kStageAffinity` weights the types per stage: fresh facets get flashcards, multiple choice, conjugation pick and a grid with prefilled cells; stable facets get the sentence builder, cloze, a full grid, transform and spot the error. The selector multiplies that weight by the focus weight and draws one type. If no type has weight under the focus (say, a vocabulary focus on a pure grammar skill), it ignores the focus, and as a last resort it tries every allowed type.

Cloze uses free text when the preferred input is keyboard or ink, or once the facet is very stable (`freeTextDays` = 21). Otherwise it stays tap-first.

## Template rules

Every wrong option goes through `OptionPicker`. It rejects an option that is empty, that equals a correct answer after folding case, punctuation and diacritics, or that duplicates another option, so the correct answer appears exactly once. What counts as "correct" for each template:

- **Flashcard:** the front is the lemma with its article (`il ragazzo`) and the back is all glosses. Graded by self-grade only.
- **Multiple choice:**
  - *Word, recognize:* wrong meanings come from items of the same POS (shared tag first, then similar frequency) that are not synonyms. A synonym is an item with an overlapping gloss in any language, parenthesized parts ignored, or the same spelling. No meaning of the target or of any synonym is offered (`dag` also means `hi`, through `hallo`).
  - *Word, produce:* no spelling of the target or of a synonym.
  - *Sentence:* other sentences whose aligned items and forms are not equivalent (synonyms count as equal), with distinct translations. Producing a sentence also offers the same sentence with one verb form or article swapped.
  - *Article:* the course's other articles.
- **Match pairs:** five `#rec` facets, from the skill first, then from other skills. No two items on the board may overlap, and no displayed meaning may be a meaning of another board item or of its synonyms. Each pair grades its own facet.
- **Conjugation pick:** only cells with a stem/ending split and a single word. Wrong endings come from other persons in the same tense, then other tenses, then same-class verbs, then any verb. An ending is never offered when stem + ending is an accepted form of the asked cell, which covers homographs such as Dutch `eet` (ik = jij = hij) and alternative spellings.
- **Conjugation grid:** distractors that match no form of any cell. In priority order:
  - the person-dependent word of a compound form swapped with another verb's (`sono mangiato`), skipped when the verb's `auxiliary` has a `|` because both would be right;
  - the stem with another class's ending (`mangete`) or another person's ending (`maaken`);
  - the verb's other tenses with the same word count;
  - other verbs' forms.
- **Sentence builder:** the sentence's word tiles, the first one lower-cased unless it looks like a proper noun, plus wrong tiles: other persons' verb forms, wrong articles and related words. A wrong tile is never a word of the sentence, a spelling of a synonym, or a word of an accepted verb form in the sentence. Accepted answers are the sentence plus any other sentence with the same translation whose words fit the tiles. Grading joins the words, so `l'` + `acqua` and `l'acqua` are equal.
- **Cloze:** the gap is an aligned token, rendered so that `before + expected + after == sentence.text`.
  - `#form`: a contiguous multi-word form is one gap. For a split form (`heb … gegeten`) only the person-dependent word is gapped.
  - `#prod`: verbs offer the same cell of other verbs; other words their lemma or plural.
  - `#article`: an elided article inside a token (`l’acqua`) can be gapped too.
  - Wrong forms exclude every accepted form of the cell and of persons that share its pronoun (Dutch `hij/zij` and `zij`).
- **Spot the error:** one word is replaced, by the matching word of another person's form (then another tense's) or by a wrong article. The same exclusions apply (Italian `sono` is io and loro). Elision spacing is fixed through `tokenPre`. The translation is always shown, because in pro-drop sentences the error is defined relative to it (`Mangiate alle otto.` is grammatical on its own).
- **Transform:** built only when the result is reliably constructible:
  1. *Same word count:* the words are replaced in place, wherever they stand.
  2. *Compound → single word:* the finite (first) word is replaced and the rest removed. This is valid for V2 and subordinate clauses.
  3. *Single word → compound:* only when the course's own sentences show that tense's compound forms as contiguous (≥ 90 %, so Italian yes and Dutch no) or the verb ends the sentence, and no clitic pronoun precedes the verb.
  4. *Person changes:* only in pro-drop sentences. The course must usually omit the subject pronoun for both persons (`dropsPronoun`, learned from the data: never for Dutch), only adverbs, conjunctions and prepositions may precede the verb, and the sentence may contain no pronoun.

  Gendered alternatives (`sono partito;sono partita`) become extra accepted answers.

**Occurrences.** `CourseIndex.formOccurrences` matches aligned tokens against the cell's accepted forms, in any order (Dutch subordinate `gegeten heeft`). When only the participle is aligned, it finds the auxiliary nearby. A token whose text is not an accepted form of its aligned cell, such as Dutch inverted `Werk jij?` aligned to `jij: werkt`, is never used.

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

## Testing against real packs

`runTemplateValidity(CourseData course)` in `test/engine/template_validity.dart` is course-agnostic. Once the data layer's loader exists, a real-pack test is:

```dart
final report = runTemplateValidity(await loadCourseFile('assets/courses/it.sqlite'));
expect(report.failures, isEmpty);
expect(report.shortfalls(20), isEmpty);
```

`tool/sample_exercises.dart` currently runs on the fixtures. Switch its `_load` to `loadCourseFile(path)` after the merge.

## Known limitations

- **Transform** can produce a semantically odd sentence when a past-time adverb remains (`Ieri ho mangiato` → `Ieri mangio`). It is grammatical but odd, and it can't be detected without semantic tags. Person changes are rare by design (pro-drop only).
- **Conjugation pick** needs stem/ending splits. Fully irregular tables (essere, avere, zijn, hebben) and compound tenses never get it; the grid and cloze cover them.
- **Spot the error and cloze** rely on the translation for pro-drop person swaps.
- **Sentence builder** accepts only orders attested in the course: the sentence itself, or another sentence with the same translation.
- **NFC** composition covers Latin letters (U+00C0–U+024F, U+1E00–U+1EFF). Other scripts pass through unnormalized.
- **Instruction strings** are in `engine/strings.dart` (English and Dutch); the UI may later move them to its localization.
