# Exercise engine (Phase 3)

`app/lib/engine/` generates, grades and sequences exercises from a `CourseData`. It is pure Dart (no Flutter, no drift) and depends only on `core/`. Import everything through `package:tosk/engine/engine.dart`.

## Layout

| File | What it does |
| --- | --- |
| `template.dart` | The `ExerciseTemplate` contract, `OptionPicker` (wrong-option filter), shared grading helpers |
| `templates/*.dart` | The nine templates, plus `alterations.dart` (one-word sentence errors shared by spot-the-error and multiple choice) |
| `course_index.dart` | Cached derived lookups: verb-form and article occurrences in sentences, auxiliary positions, synonyms (through gloss/spelling indexes), distractor pools, sentences by translation, pro-drop and compound-contiguity statistics, and `memo` for templates' `canGenerate` answers |
| `gen_context.dart` | `GenContext` (course, options, seeded `Random`, facet states, skill) and `FacetStage` / `StagePolicy` |
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
- **Cloze:** `options == null` means free text (a `TextAnswer`, which may carry ink `candidates`).
- **Spot the error:** render with `tokenPre[i] + tokens[i]`, or use `renderSpotError`.
- **Article multiple choice:** the prompt is `___ ragazzo` and `hint` is the meaning.
- **Lenient accents:** `Result.accentSlip` means "accepted, but watch the accent".
- **Token alignment (tap-for-gloss).** Exercises that show a target-language sentence carry its tokens as `TokenRef`s (text, whitespace before, aligned item id and `'{tense}.{person}'` form, from `Token.lex` / `Token.form`; `tokenRefsOf(sentence)`): `ClozeExercise.tokens` with `gapFrom..gapTo` (the whole correct sentence; the gap covers those tokens, or only the start of token `gapFrom` for an elided article), `SpotErrorExercise.tokenRefs` (parallel to `tokens`; the wrong word carries the original token's alignment), `MultipleChoiceExercise.sentenceTokens` (sentence variant: the prompt when recognizing, the correct option when producing), `TransformExercise.sourceTokens` and `SentenceBuilderExercise.answerTokens`. All optional (null from hand-made exercises). `glossForTokenRef(course, ref, lang)` resolves one for the UI. The UI never makes the exercise's own item tappable before the answer is checked.

## Facets, templates and stages

| Facet | Templates |
| --- | --- |
| `#rec` | flashcard, multiple choice (word or sentence → meaning), match pairs |
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
- **Spot the error:** one word is replaced, by the matching word of another person's form in the same tense or by a wrong article. Never by another tense: `De leerlingen mochten …` for `mogen` is grammatical and wrong only against the translation. The same exclusions apply (Italian `sono` is io and loro). Elision spacing is fixed through `tokenPre`. The translation is always shown, because in pro-drop sentences the error is defined relative to it (`Mangiate alle otto.` is grammatical on its own).
- **Transform:** built only when the result is reliably constructible:
  1. *Same word count:* the words are replaced in place, wherever they stand.
  2. *Compound → single word:* the finite (first) word is replaced and the rest removed. This is valid for V2 and subordinate clauses.
  3. *Single word → compound:* only when the course's own sentences show that tense's compound forms as contiguous (≥ 90 %, so Italian yes and Dutch no) or the verb ends the sentence, and no clitic pronoun precedes the verb.
  4. *Person changes:* only in pro-drop sentences. The course must usually omit the subject pronoun for both persons (`dropsPronoun`, learned from the data, counting the pronouns of the person key and its labels, `jij/je`: never for Dutch), only adverbs, conjunctions and prepositions may precede the verb, and the sentence may contain no pronoun and no name (`Heeft Tom …`).
  5. *Tense changes* only when every other verb in the sentence is in the source or the target tense and has a known form (`Wie was de filosoof die ooit geleefd heeft?` would mix tenses); not for an auxiliary verb next to a participle (`als ik nee had gezegd`), not into a compound form next to a participle (passive `gezegd werd`), and not from a form spelled like the infinitive (`vertellen` may be an infinitive after a modal). A form written out of order (`opgestaan ben`) is only rewritten into the same tense.

  Gendered alternatives (`sono partito;sono partita`) become extra accepted answers.

**Occurrences.** `CourseIndex.formOccurrences` matches aligned tokens against the cell's accepted forms, in any order (Dutch subordinate `gegeten heeft`). When only the participle is aligned, it finds the auxiliary nearby. A token whose text is not an accepted form of its aligned cell, such as Dutch inverted `Werk jij?` aligned to `jij: werkt`, is never used.

**Compound tenses.** The pipeline aligns a compound form on its participle (`mangiato` → `passato_prossimo.io`, the cell's form being `ho mangiato`) and the auxiliary separately to the auxiliary verb's present (`ho` → `avere`, `presente.io`). `CourseIndex.auxiliaryPositions(sentence)` finds those auxiliaries (the nearest token within 6 that reads the form's other word, for the first accepted spelling whose words are all present). They belong to the compound form: they are never an occurrence of the auxiliary verb's own present (`Zijn jullie … geweest?` is no `zijn` present exercise, and `Ho mangiato` no `avere` one), so cloze, spot the error and transform only touch them through the compound form. The validator applies the same convention independently (`_ownerCell`).

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

- **Transform** can produce a semantically odd sentence when a past-time adverb remains (`Ieri ho mangiato` → `Ieri mangio`). It is grammatical but odd, and it can't be detected without semantic tags. Person changes are rare by design (pro-drop only).
- **Conjugation pick** needs stem/ending splits. Fully irregular tables (essere, avere, zijn, hebben) and compound tenses never get it; the grid and cloze cover them.
- **Spot the error and cloze** rely on the translation for pro-drop person swaps.
- **Person hints** come from the alignment. Where two persons share the form (Dutch `maakt` for jij and hij), a subject far from the verb can be missed; the pipeline then leaves the person open rather than guess, so such sentences are simply not used.
- **Sentence builder** accepts only orders attested in the course: the sentence itself, or another sentence with the same translation.
- **NFC** composition covers Latin letters (U+00C0–U+024F, U+1E00–U+1EFF). Other scripts pass through unnormalized.
- **Instruction strings** are in `engine/strings.dart` (English and Dutch); the UI may later move them to its localization.
