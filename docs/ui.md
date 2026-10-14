# App screens (Phase 4) and integration

The UI lives in `app/lib/ui/`, plus `app/lib/main.dart`, `app/lib/app_bootstrap.dart`, `app/lib/app.dart` and `app/lib/providers.dart`.
Every dependency goes through a Riverpod provider. The app runs on the real data layer, exercise engine and progression; the demo courses in `app/lib/ui/demo/` are only a fallback when no course pack is installed.

## Start-up (`main.dart`, `app_bootstrap.dart`)

`main()` calls `bootApp()`, which calls the data layer's `openAppData()` and returns an `AppBoot` whose `overrides` go into the root `ProviderScope`:

| Override | Value |
| --- | --- |
| `appDataProvider` | the `AppData` |
| `progressStoreProvider` | `AppData.progress` (drift `ProgressRepo`, FSRS) |
| `courseCatalogProvider` | `PackCourseCatalog(app, fallback: DemoCourseCatalog())` (`ui/pack_course_catalog.dart`) |

- **Packs installed** (bundled `assets/courses/*.sqlite` count; they are installed on first use): the catalog lists them (summary metas from `PackInfo`, without loading the packs) and opens them with `AppData.openCourse`. Progress goes to `progress.sqlite`.
- **No packs**: the demo courses, labelled with a **Demo** chip next to the course title (and "Demo content" in settings). Their progress goes to a separate `progress-demo.sqlite`, seeded once with some history (`ui/demo/demo_seed.dart`), so demo practice never mixes with real progress. When packs appear (an app update with bundled packs), the next start uses them automatically.
- If the data layer can't be opened at all, `main()` logs the error and runs on the defaults (demo courses, in-memory progress).

Without overrides (most widget tests) the providers default to the demo courses and the data layer's in-memory FSRS `InMemoryProgressStore`.

## Screens and routes

go_router, in `ui/router.dart`. Path builders are in `ui/routes.dart`.

| Route | Screen | Notes |
| --- | --- | --- |
| `/` | `MapScreen` (`ui/map/`) | Home. Course switcher in the app bar (the user's courses, then "Add or remove courses"), with the demo and unverified badges. Level/streak header (tap: progress page). Zoom in and out. "What's fading" button, with "Review mistakes (N)" above it while mistakes are open (starts a mistake review). |
| `/practice?tab=nonstop\|lab` | `PracticeScreen` (`ui/practice/`) | Two tabs. **Non-stop** (`NonStopScreen(embedded: true)`, `ui/nonstop/`): description and best run, Start pinned at the bottom. **Lab** (`LabScreen(embedded: true)`, `ui/lab/`): skills multi-select grouped by unit (tri-state checkbox per unit), exercise types (9), length chips 5/10/20/30/50, Start pinned at the bottom. `/lab` and `/nonstop` redirect here. |
| `/reference?tab=lookup\|grammar&q=` | `ReferenceScreen` (`ui/reference/`) | Two tabs. **Lookup**: results above, the search field and an "All words / Verbs" filter pinned at the bottom (thumb zone); a hit opens `/word/:itemId`. **Grammar** (`GrammarLibraryView`): every grammar note of the course, grouped by unit, in the source language; each expands to the note and "Practice this skill" (a lesson, grammar focus for grammar skills). |
| `/word/:itemId` | `WordScreen` (`ui/reference/word_screen.dart`) | Root route, so it opens over anything (the player too, from a word popover). Glosses, part of speech, gender, plural, variants, auxiliary, tags, "Taught in" (skill chips open the skill sheet), the full conjugation table for verbs (`VerbTenseCard` per tense: persons in course order, tense labels in the source language, irregular forms **bold and underlined** with a legend, alternatives in parentheses; infinitive, participle and gerund under "Other forms"), and example sentences (tappable words, translation). |
| `/progress` | `ProgressScreen` (`ui/progress/`) | Level and XP, streak with freezes, the 26-week heatmap, the verb collection entry, the mistakes entry ("Review mistakes (N)"), "Tough words (N)" when there are any (starts `/play/tough`), weekly and monthly challenges, badges. |
| `/mistakes` | `MistakesScreen` (`ui/mistakes/`) | Open mistakes (`openMistakesProvider`), one card each: facet label, skill · missed type · when · count, the stored prompt, "You answered" / "Correct", an excerpt of the skill's grammar note (`noteExcerpt`) with a "Grammar note" link to the skill sheet, and the "Why?" slot (shown only when the explainer is available, or a cached explanation exists). Pinned at the bottom: "Tough words (N)" (when any) and "Review N mistakes" (`/play/review`). Empty state when nothing is open. |
| `/progress/verbs` | `VerbCollectionScreen` (`ui/progress/`) | `VerbCollectionView`: one card per verb, tense pills light up with mastery. A card opens the verb's reference page; the app bar's search icon opens Lookup. |
| `/settings` | `SettingsScreen` (`ui/settings/`) | My courses (switch) and "Add or remove courses", source language, default focus, accents, display (color or black & white), theme (color only), reduce motion, the debug link, and at the end **Practice**: default lesson length (Quick 5 / Normal 12 / Long 20) and the tough-word threshold (3–6 lapses). |
| `/skill/:id` | `SkillSheet` as a modal bottom sheet (`BottomSheetPage`) | Opened by long-press or right-click on a node. Focus chooser and **length chooser** (5 / 12 / 20, default from Settings; side by side from 520 px, stacked below), Start lesson, **Test out** (while the skill is below bronze), the grammar note (markdown, in the source language), and the item list (article + lemma, gloss, and the forms in the skill's tense for verbs). |
| `/play/lesson/:skillId?focus=&length=` | `PlayerScreen(LessonRequest)` | Tapping a node starts a lesson with the default focus and length. |
| `/play/testout/:skillId` | `PlayerScreen(TestOutRequest)` | `SessionFactory.testOut`. The summary shows `AssessmentResultCard`: "Tested out!" (score, pass mark, what is now learned and unlocked) or "Not yet". |
| `/play/placement` | `PlayerScreen(PlacementRequest)` | `SessionFactory.placement`. The summary card says how many units are done and where to continue. |
| `/play/tough` | `PlayerScreen(ToughWordsRequest)` | `SessionFactory.toughWords` with the threshold from Settings; "No tough words right now" when empty. |
| `/play/fading` | `PlayerScreen(FadingRequest)` | |
| `/play/review` | `PlayerScreen(ReviewRequest)` | Mistake review (`SessionFactory.review`, see `docs/engine.md`); "No mistakes to review" when nothing is open. |
| `/play/lab?skills=&types=&length=` | `PlayerScreen(LabRequest)` | |
| `/play/nonstop` | `PlayerScreen(NonStopRequest)` | Endless. The title shows a running count, and Stop leads to the summary. |
| `/debug` | `DebugRoute` (`ui/debug/debug_route.dart`) | The data layer's `DebugScreen` over `appDataProvider` (packs, add a pack, rebuild states, per-skill stats). Leaving it re-lists the courses and bumps `progressRevisionProvider`. Without a data layer it shows `DemoDebugScreen`. |

The five top-level screens (**Map, Practice, Reference, Progress, Settings**; until v0.3 the second and third were Lab and Non-stop, now the two tabs of Practice) sit in a `StatefulShellRoute` (`ui/shell/app_shell.dart`). Below 600 px wide that shell uses a bottom `NavigationBar` (labels clamp their text scale on narrow phones, so "Reference" fits at 320 px). At 600 px and wider it uses a `NavigationRail`, extended with labels from 1100 px. The player, the sheets, the word page and the debug screen open on the root navigator, full screen. The tabs inside Practice and Reference switch an `IndexedStack` through a `TabController` (no swipeable page view: nothing slides on e-ink, no accidental swipes, both pages keep their state).

### Course picker (`ui/courses/course_picker.dart`)

`showCoursePicker(context, firstRun:)` opens a bottom sheet listing **every available course** (`availableCoursesProvider`: bundled and installed packs, a local Sarnami pack included, or the demo courses), each as a card with:

- the title, Demo / Unverified badges, source languages and version, "Added" in the subtitle and a 3 px border when added (never color alone);
- **+** (`IconButton.filled`, "Add to my courses") or **−** (`IconButton.outlined`, "Remove from my courses"; disabled for the last course: the app keeps at least one);
- **Preview** (expands in place, `coursePreviewProvider(id)` opens the course without making it active): the description (meta key `description`, now `CourseMeta.description`), "Learn Italian (it) · translations in English, Nederlands", counts (words, verbs, sentences, units, skills), the unit and skill outline, six sample words with glosses, and a sample sentence with its translation.

Done is pinned at the bottom. "My courses" is the setting `courses.added` (comma-separated, in the order added). **The rest of the app only shows those**: the course switcher, Settings and `activeCourseIdProvider` (the saved course among mine, else my first) go through `myCoursesProvider`. Removing a course only removes it from the list; its progress stays in the log, and adding it back finds it again. Installs from before the picker (no `courses.added`) count their active course as added (`AppSettings.myCourseIds`).

**First run:** with no course added (`needsCoursePickerProvider`), the shell opens the picker once ("Choose your course"). Closing it without adding anything adds the course shown underneath, so the app always has one. **Placement offer:** adding a course with no events in the log asks "Start from scratch" or "Find my level"; the latter makes it active, closes the picker and opens `/play/placement`.

### Word popovers: tap a word for its translation (`ui/common/word_popover.dart`)

Target-language sentences show their aligned words (the engine's `TokenRef`s, see `docs/engine.md`) with a dotted underline; tapping one opens a small popover anchored under (or above) the word, kept on screen: the headline from `glossForToken` (`mangiamo → mangiare · noi · present`, nouns with their article: `il pane`), the glosses in the source language, and "Open in reference" (`/word/:itemId`). It is a `PopupRoute` on the root navigator: no barrier color, no transition, dismissed by a tap outside or Back; in black & white a white card with a 3 px black border and no shadow. Unaligned words and punctuation stay plain text.

| Exercise | Where |
| --- | --- |
| cloze | the words before and after the gap (`tokenSpans` around the gap widget); after checking, the filled gap too |
| spot the error | **after checking only** (before, a tap is the answer): the word tiles; the wrong word shows the correct word's gloss |
| multiple choice, sentence → meaning | the prompt sentence |
| multiple choice, meaning → sentence | after checking, the correct option's sentence |
| transform | the source sentence |
| sentence builder | after checking, the answer sentence ("answer-sentence" row under the prompt) |
| reference | example sentences on the word page |

**Never the answer:** before checking, no word aligned to the exercise's own item is tappable (`hideItemUntilAnswered`): not the gapped verb's other words (`heb … gegeten`), not the noun of an article question, not the asked word in a sentence. Options and tiles are never tappable. The feedback panel itself is unchanged (it belongs to the AI-explanation work); the correct sentence is tappable in the exercise area instead (cloze gap, MC option, sentence builder row).

### Test out, placement and tough words (UI)

- The skill sheet's **Test out** runs `/play/testout/:skillId` (about 10 exercises, no re-asks). The summary's `AssessmentResultCard` (`ui/lesson/assessment_result.dart`, shown through `SessionSummaryView(header:)` for any `AssessmentSession` with an `outcome`) shows the verdict with an icon and words (✓ "Tested out!" / ↻ "Not yet"), the score and the pass mark. Passing credits the skill (see `docs/engine.md`), so the map shows it learned and the next skills unlocked after the session's progress bump.
- **Placement** comes from the course picker's "Find my level" (see above).
- **Tough words** (`toughWordsProvider`, progression's `toughWords` over the facet states with the Settings threshold): "Tough words (N)" on the Progress page (with the first three words) and in the mistakes screen's bottom bar, both starting `/play/tough`.

### Lesson player (`ui/lesson/`)

- `PlayerScreen` drives a `PracticeSession` through these phases: loading → exercise → Check → feedback banner → Continue → … → summary. There are also empty and error states.
  - The progress bar is `answered / plannedLength`. Endless sessions show "N answered · M correct" instead.
  - Exit asks for confirmation (the close button, Esc, or system back). In non-stop, exiting stops the run and shows the summary.
  - Desktop shortcuts: 1–9 pick options or tiles. Enter checks, continues, or reveals a flashcard. Esc leaves. Shortcuts are ignored while a text field has focus.
  - After a session (finished or quit) the player bumps `progressRevisionProvider`, which refreshes the map stats, the header and the progress pages.
  - **Non-stop scoring.** The player keeps a progression `NonStopRun` and feeds it one graded exercise at a time from the engine's `EngineSession.results` stream: `run = run.applyResult(event.exercise, event.result, at: toStoredTime(event.events.first.at))`. When a run starts a bonus round (`NonStopSignal.bonusRoundStarted`) it calls `NonStopSession.enqueueBonus(types: run.preferredTypes, count: round.targetAnswers)`; `_advance` waits for the result event of the last submit before drawing the next exercise, so the bonus applies to the very next one. The HUD (`NonStopHudSlot`) shows the run.
  - **Contract (engine ↔ progression ↔ UI).** The engine records every facet outcome of one exercise with the same `at` (`env.now()`), the session id and mode `nonstop`; the UI feeds `NonStopRun` with that recorded `at` (UTC, whole milliseconds, as stored). The best run replayed from the log (`bestNonStopRunProvider`) then equals the live score. One known gap: a wrong *re-ask* after a mistake records no event, so the live run breaks the combo while the replay doesn't see that answer.
  - **"Why?"** uses the core `Explainer` (`explainerProvider`, `NullExplainer` in v1, so the button is hidden). The context is `EngineSession.mistakeContext(exercise.id)`, or one built from the exercise for other sessions.
- **Thumb zone.** Every exercise widget returns an `ExerciseLayout(prompt:, controls:)` (`exercises/exercise_layout.dart`, a small render object). The player gives the exercise at least the visible height of its scroll view, so the prompt sits at the top and the interactive part (options, endings, tiles and answer line, the grid and its tile bank, the match columns, the flashcard buttons, the spot-the-error sentence) at the bottom, just above Check / the feedback panel. Taller content stacks and scrolls. The column is centered and at most 640 px wide. Options, tiles and grid cells are at least 48 px tall (tiles also 48 px wide). `test/ui/thumb_zone_test.dart` checks every type at 400×800 and 1280×800.
- `exercises/`: one widget per type, all subclasses of `ExerciseWidget<E>`.
  - Each widget reports a draft `Answer?` through `onChanged`.
  - Flashcard (self-grade) and match pairs (once everything is matched) submit themselves through `onSubmit`.
  - With `result` set, a widget shows its marks: right and wrong options, per-cell ✓/✗ with the expected form for grids, and the correction for spot-the-error.

  | Type | Widget | Answer |
  | --- | --- | --- |
  | flashcard | `FlashcardView` (Show answer, then Again/Hard/Good/Easy) | `SelfGradeAnswer` |
  | multiple_choice | `MultipleChoiceView` (the optional `hint` under the prompt, e.g. the meaning in `___ ragazzo`) | `ChoiceAnswer` |
  | match_pairs | `MatchPairsView` (either order; a wrong pair flashes red and counts as missed) | `MatchAnswer(matches, missed)` |
  | conj_pick | `ConjPickView` (`mang___`, person and tense chips, ending options; the empty ending is the engine's `kNoEnding` `–` and fills nothing) | `ChoiceAnswer` |
  | conj_grid | `ConjGridView` (tap a cell, then a tile; prefilled cells greyed; tap a filled cell to return its tile; tiles may repeat, one per asked cell) | `GridAnswer` (`''` for prefilled cells) |
  | sentence_builder | `SentenceBuilderView` (tiles to the answer line and back) | `TilesAnswer` |
  | cloze | `ClozeView` (option chips, or an `AnswerInputWidget` when `options == null`, which the engine only does for keyboard/ink learners) | `ChoiceAnswer` / `TextAnswer` |
  | spot_error | `SpotErrorView` (word tokens are tappable; tokens are grouped by the engine's `tokenPre`, so `l'acqua` and `fredda.` render without gaps; without it punctuation sticks to its word) | `TokenAnswer` |
  | transform | `TransformView` (source sentence, its `translation`, target chip, tiles) | `TilesAnswer` |

- `answer_input.dart`: `AnswerInputWidget` is the free-text input abstraction. `KeyboardAnswerField` ships now (renamed from `KeyboardAnswerInput`, which is now the core hook in `core/interfaces/hooks.dart`). A handwriting widget (Phase 8) implements the same class, reports `TextAnswer(inputMode: ink, candidates: [...])`, and plugs in through `answerInputBuilderProvider`.
- `feedback_banner.dart`: right or wrong, `result.expected`, "Watch the accent: …" when `result.accentSlip`, an **actions row**, and Continue (full width, last). It slides up unless motion is reduced. It takes at most 60 % of the screen height; the details scroll above a pinned Continue (long answers at large text sizes).
  - The actions row (`feedback-actions`, a `Wrap` of outlined `FeedbackAction` buttons, 48 px tall) holds "Why?" (only when `explainerAvailableProvider` and the answer was wrong) and then `extraActions`. That is the slot for later answer-panel actions such as "Explain with AI" or "Flag exercise": pass them as `FeedbackBanner(extraActions: [...])` from the player.
  - `why_sheet.dart`: `showWhySheet(context, stream)`, shared by the player and the mistakes list.
- `session_summary_view.dart`: answered, accuracy and time, a mistakes list (facet ids rendered as "il pane · produce") and the `SummaryProgressSlot`, scrolling above a pinned Done button.

### Skill map (`ui/map/`)

- `map_layout.dart` is pure and unit-tested:
  - **layer** is the longest prerequisite path. Unknown prerequisites are ignored, and back edges are skipped, so a cycle can't hang the layout.
  - Each **unit is a horizontal band**, stacked in unit order. Within a band, the distinct layers of its skills become rows.
  - Rows are centered on the widest row.
  - Crossings are reduced with the **barycenter heuristic**: alternating down and up sweeps, keeping the ordering with the fewest crossings.
  - **`pos` override**: `posY` sets the row inside the unit band and `posX` the column. A pinned node is fixed, and free nodes in the same row take the remaining columns.
- `skill_map_view.dart`:
  - `MapGeometry` turns the layout into pixels. Cells are 64–112 px wide, fitted to the width, and multiplied by the zoom.
  - `MapEdgesPainter` draws the edges through the skin's `EdgePainter`. An edge whose straight path would pass behind another node (typically one skipping a unit) detours through the nearest free lane between columns (`detourLane`). Unit titles and node titles sit on the band color above the edges, so no edge runs through text.
  - Cells are 64–144 px wide, so long skill titles fit on two lines.
  - `test/ui/map_big_course_test.dart` runs a 10-unit, 30-skill course (`test/fixtures/big_map_course.dart`) at 320 px to desktop and text 1.3: every node reachable with a 48 px target and a semantics label, every band title present, no horizontal scroll, and no edge behind a node.
  - The map scrolls vertically, and horizontally only when it is wider than the screen (zoomed in). There's no horizontal overflow at 320 px.
- Tapping a **locked** skill opens its sheet ("Recommended first: …. You can start this one anyway." and Start lesson) instead of starting a lesson. "What's fading" is hidden until something was practiced.
- `skill_node.dart`:
  - The strength ring is 0..1, colored by tier from bronze up.
  - The icon comes from `skill.icon` through `ui/theme/skill_icons.dart`, which has per-kind defaults.
  - The tier badge goes through `TierBadgeSlot`.
  - Below the node: the title and the days since practice ("4d").
  - **Fading**: the node color is desaturated and lightened in proportion to `decay`, which is progression's `fading` signal (falls back to `1 - strength`). Locked nodes are greyed.
  - Pressing scales the node down, unless motion is reduced.
- `skill_stats.dart` has `SkillStats` (strength, lastPracticed, tier, fading, practiced/total facets) and `MapTier`: locked, available, started, bronze, silver, gold (the same names and order as progression's `SkillTier`; `mapTier` / `skillTierOf` in `providers.dart` convert). `available` means unlocked but never practiced.

### Theme and skin (`ui/theme/`)

`Skin` builds the Material 3 `ThemeData` for light and dark from a seed color. Its `MapStyle` holds the node colors, ring, edges, band backgrounds, tier colors, node shape and `EdgePainter`. `DefaultSkin` ships now. A forest skin later implements `Skin` and overrides `skinProvider`. Theme mode comes from settings. With reduce motion on, page transitions and the theme animation are switched off.

### E-ink / black & white mode

For e-ink readers (the user's Boox is black and white only). **Settings → Display: Color / Black & white** (`ui.display` = `color` | `bw`, `DisplayMode` in `app_settings.dart`).

- **Providers.** `bwProvider`; `skinProvider` returns `BwSkin` (`ui/theme/bw_skin.dart`); `themeModeProvider` is always light; `reduceMotionProvider` is forced on (no page transitions, slides, fades, `AnimatedSize`, progress tweens or theme animation). Haptics and sounds (`fxProvider`) follow only the "Reduce motion" setting, so black & white doesn't silence them. The Theme setting is hidden while black & white is on.
- **Palette.** `kBwBlack` `#000`, `kBwWhite` `#FFF`, and one gray `kBwGray` `#767676` (4.54:1 on white, AA) for disabled states, unseen items, empty slots, locked skills and progress tracks. `kBwScheme` sets every `ColorScheme` role to one of the three: containers are white with black content, except `secondaryContainer` (the "selected" role: navigation indicator, segmented buttons, selected options), which is inverted.
- **Theme (`bwTheme()`).** No splashes, highlights, hover or focus overlays (`NoSplash`), no shadows, no elevation, no surface tints, no dimming barrier behind sheets and dialogs (they get a 3 px border instead; `BottomSheetPage` takes the barrier color from the theme). Borders are at least 2 px (`kBwBorder`) on buttons, cards, chips, inputs, FABs, map nodes and unit bands; text buttons are bold and underlined; the app bar and the bottom navigation have a 2 px rule.
- **Nothing relies on color.** Widgets check `isMonochrome(scheme)` / `isBw(context)`:
  - Options and tiles (`optionLook` in `exercises/common.dart`): idle = 2 px outline; selected = inverted (black fill, white text); correct = 3.5 px border, bold text and a ✓; wrong = 2 px border, struck-through text and a ✗; dimmed = gray. Semantics hints say "correct answer" / "wrong answer".
  - Feedback panel: white with a 3 px top rule, ✓ / ✗ icon and "Correct!" / "Not quite"; Continue is solid black.
  - Conjugation grid: the selected cell has a 3.5 px border; wrong cells show the given form struck through, the expected form and ✗; right cells are bold with ✓; prefilled cells are gray.
  - Map: white nodes with a black 2.5 px border (locked: gray border and icon, plus the lock badge); the strength ring is a black arc on a dotted track; a fading skill (`decay ≥ 0.35`) gets a dashed border instead of a washed-out color; tiers are letter medals, B / S / G inside 1 / 2 / 3 rings (`MedalRingsPainter`); edges are black (locked: gray).
  - Heatmap: cells are outlined and filled with a black square growing with the level (`HeatDot`), with the same legend; today has a 2 px border; frozen days show the snowflake.
  - Streak flame: filled when practiced today, outlined when not. Verb pills: unseen gray outline, learning thin, known thick with ✓, mastered inverted with ✦. Progress bars and rings are black on the gray track. Badges ("Demo", "Unverified") are outlined text. Light tints (`ProgressionColors.tint`) become white plus a border.
- **Tests.**
  - `test/ui/bw_mode_test.dart`: every `ColorScheme` role and the main `ThemeData` colors are black, white, the gray or fully transparent; no splash, no shadows, 2 px borders, AA gray; black & white forces reduced motion and keeps fx; the Display setting persists; then every screen (map, skill sheet, lab, non-stop, progress, verb collection, settings, debug, mistakes, the non-stop HUD in a bonus round, the accent-slip banner) and every exercise type (new, wrong feedback, right, summary) are rendered and checked **pixel by pixel**: `bw_helpers.dart` renders the app's root `RepaintBoundary` to an image and fails on any pixel whose channels differ by more than 6 (black, white and gray only ever blend into grays, so any colored pixel is a widget still painting a color; the failure lists the pixel and the widget under it). A white pixel next to an open sheet proves there is no dimming overlay. The same file runs layout (overflow) and grayscale checks at 360×640, 320×568, a 6" e-reader (572×772), a 7" e-reader (674×896), the 10.3" Boox Note Air (1404×1872 at 226 dpi = 1003×1337), 768×1024 and 1280×800, for every exercise type.
  - `test/ui/bw_golden_test.dart`: committed goldens (`test/ui/goldens/bw_*.png`, test font) of the map, progress, settings and four exercise types before and after a wrong answer. Update with `flutter test --update-goldens test/ui/bw_golden_test.dart`.
  - Real-font screenshots for review: `docs/screenshots/bw/` (from `test/qa/qa_walkthrough.dart`).
- **ONYX auto-suggest: not done.** Detecting the device maker needs `device_info_plus` (or a platform channel), which is more than this needs; the setting is one tap. Documented here so it can be added later.

### Polish

`ui/common/fx.dart` handles feedback:

- `Fx` plays haptics (`HapticFeedback`) and system sounds (`SystemSound`): click on correct, alert on wrong.
- `Motion` holds the durations, which collapse to zero when motion is reduced.
- `motionProvider` derives from `reduceMotionProvider` (the setting, forced on in black & white); `fxProvider` from the setting only.
- With reduced motion, no `AnimatedSize` is used at all (a zero-duration `AnimatedSize` re-dirties itself during layout and asserts; the flashcard back hit that).

### Markdown

`ui/common/markdown.dart` is a small renderer written for this, with no dependency. It handles:

- headings
- paragraphs
- `-`/`*`/`+` and numbered lists
- block quotes
- fenced code
- pipe tables (scroll horizontally on narrow screens)
- `---` rules
- inline **bold**, *italic*, `code` and ~~strike~~

I chose this over `flutter_markdown_plus` and `gpt_markdown` because grammar notes are bundled, trusted content that uses only these features. It adds no package, so it can't cause pubspec merge conflicts, and it keeps the web bundle small.

## Providers (`lib/providers.dart`)

| Provider | Type | Value |
| --- | --- | --- |
| `clockProvider` | `DateTime Function()` | `DateTime.now` (tests override it) |
| `calendarProvider` | `LocalCalendar` | `LocalCalendar.system()` (tests use `LocalCalendar.utc`) |
| `appDataProvider` | `AppData?` | Set by `main.dart`; null on the defaults |
| `schedulerProvider` | `Scheduler` | `AppData.scheduler`, else a new `FsrsScheduler` |
| `courseCatalogProvider` | `CourseCatalog` (`listCourses()`, `open(id)`, `isDemo(id)`) | `PackCourseCatalog` from `main.dart`; default `DemoCourseCatalog` |
| `progressStoreProvider` | `ProgressStore` | `AppData.progress` (drift `ProgressRepo`) from `main.dart`; default the data layer's in-memory FSRS store |
| `settingsProvider` | `AsyncNotifierProvider<SettingsController, AppSettings>` | Reads and writes `ProgressStore` settings, so they persist in the progress DB |
| `bwProvider`, `themeModeProvider`, `reduceMotionProvider`, `motionProvider`, `fxProvider` | Derived from settings | Black & white forces light and reduced motion; fx follow only "Reduce motion" |
| `skinProvider` | `Skin` | `BwSkin` in black & white, else `DefaultSkin`; forest skin later |
| `availableCoursesProvider` | `Future<List<CourseMeta>>` | From the catalog (pack listings carry id, version, title, unverified; the opened course has the full meta) |
| `myCoursesProvider` | `Future<List<CourseMeta>>` | The installed courses among `courses.added`, in the order added |
| `needsCoursePickerProvider` | `bool` | No course added yet (a fresh install): the shell opens the picker |
| `coursePreviewProvider(id)` | `Future<CoursePreview>` | The picker's preview (meta, outline, counts, samples) of a course that need not be active |
| `activeCourseIdProvider` | `Future<String>` | The saved course among mine, else my first; before any is added, the first installed |
| `activeCourseIsDemoProvider` | `bool` | Whether the active course is demo content (the Demo chip) |
| `courseDataProvider` | `Future<CourseData>` | `catalog.open(activeId)` |
| `sourceLangProvider` | `String` | The setting, restricted to `meta.translations` |
| `mapLayoutProvider` | `Future<MapLayout>` | `layoutSkillMap(units, skills)` |
| `sessionOptionsProvider` | `SessionOptions` | Source language + accent strictness (preferred input: tap) |
| `focusPresetsProvider` | `Future<FocusPresets>` | `assets/config/focus_presets.json`, else the engine's defaults |
| `sessionFactoryProvider` | `Future<SessionFactory>` | `EngineSessionFactory(course, progress store, scheduler, options, presets, clock)`; rebuilt when the course or settings change. Works on packs and on the demo course |
| `explainerProvider` | `Explainer` (core hook) | `NullExplainer` |
| `explainerAvailableProvider` | `bool` | `explainer.isAvailable` (false: "Why?" hidden) |
| `answerInputBuilderProvider` | `AnswerInputBuilder` | Keyboard (`KeyboardAnswerField`); ink in Phase 8 |
| `openMistakesProvider` | `Future<List<OpenMistake>>` | The engine's `openMistakes` for the active course (map button count, progress entry, mistakes list); watches `progressRevisionProvider` |
| `toughWordsProvider` | `Future<List<ToughWord>>` | Progression's `toughWords` for the active course with the `lesson.leech_lapses` threshold; watches `progressRevisionProvider` |
| `progressRevisionProvider` | `int` (Notifier, `bump()`) | Bumped after every session and when leaving the debug screen; every progress-derived provider watches it |
| `progressionServiceProvider` | `Future<ProgressionService>` | For the active course (store, scheduler, clock, calendar); caches its log replay |
| `skillStatsProvider` | `Future<Map<String, SkillStats>>` | Strength and last practice from the data layer's `SkillStatsService.forCourse`, tier and fading from `ProgressionService.skillTiers` (`mapSkillStats`) |
| `progressProfileProvider`, `heatmapProvider`, `challengeBoardProvider`, `verbCollectionProvider`, `bestNonStopRunProvider` | Futures | The matching `ProgressionService` queries |
| `sessionProgressSummaryProvider(sessionId)` | `Future<SessionProgressSummary?>` | `ProgressionService.sessionSummary` |
| `routerProvider` (`ui/router.dart`) | `GoRouter` | |

### Progression slots (`ui/slots/progression_slots.dart`)

The hosting screens only know the slots; each slot reads the progression providers and renders the widgets from `lib/ui/progression/`:

- `MapHeaderSlot` (top of the map): `LevelBadge`, level and today's XP, `StreakCounter`. Tapping it opens `/progress`.
- `TierBadgeSlot` (each node): progression's `TierBadge` on a surface disc; nothing for `available`.
- `SummaryProgressSlot` (session summary): `SessionSummaryCard` (XP, level-up, improved words, tier changes) from `sessionProgressSummaryProvider(summary.sessionId)`.
- `NonStopHudSlot` (above the non-stop player): `NonStopHud` with the player's `NonStopRun` and the best run as the target.
- `NonStopRecordSlot` (non-stop start screen): the best run (score, combo, accuracy, date), or a hint before the first run.

## Settings keys (`ui/settings/setting_keys.dart`)

Every setting is stored through `ProgressStore.getSetting/setSetting`, as a string:

| Key | Values |
| --- | --- |
| `course.active` | Course id |
| `ui.source_lang` | `en` or `nl` |
| `lesson.default_focus` | `mixed`, `vocab` or `grammar` |
| `lesson.accent_strictness` | `strict` or `lenient` |
| `ui.theme_mode` | `light`, `dark` or `system` |
| `ui.reduce_motion` | `true` or `false` (also silences haptics and sounds) |
| `ui.display` | `color` or `bw` (black & white for e-ink; forces reduced motion and the light black & white theme) |
| `lesson.default_length` | `quick` (5), `normal` (12) or `long` (20): `SessionLength` |
| `lesson.leech_lapses` | Lapses from which a facet is a "tough word" (integer, default 4) |
| `courses.added` | "My courses": comma-separated course ids, in the order added (absent until first used) |

Unknown or missing values fall back to the defaults. They live in the progress database, so they survive a restart (in demo mode, in `progress-demo.sqlite`).

## Tests

`test/qa/qa_walkthrough.dart` (no `_test` suffix, so not in the default run) walks the app on the **real packs with real fonts** and saves a PNG of every step: `QA_OUT=<dir> flutter test test/qa/qa_walkthrough.dart`. It covers both courses, every exercise type through the lab, a lesson with feedback states, the progress pages, mistakes, settings, dark mode at 320 px and text 1.3, desktop, a 30-skill map, and black & white at phone, 6" e-reader and Boox sizes. The desktop app can run on a separate profile with `flutter run -d windows --dart-define=TOSK_DATA_DIR=<dir>`.

`app/test/ui/` runs the app on the defaults (demo courses, in-memory FSRS store, fixed clock, UTC calendar). `pumpApp` overrides `sessionFactoryProvider` with the test fake `fakes/demo_session.dart` (hand-made exercises, a fixed one per type) so layout and flow tests are deterministic; `pumpApp(engine: true)` uses the real engine. `app/test/app/` runs the real wiring over the data layer's fixture course.

| File | Covers |
| --- | --- |
| `ui/map_layout_test` | Layers, bands, centering, `pos` override, pinned/free columns, barycenter crossing removal, unknown units, cycles |
| `ui/markdown_test` | Block and inline parsing, widget rendering |
| `ui/demo_session_test` | The fake factory's grading and sessions; `skillStatsProvider` on FSRS (tiers, locking, fading) |
| `ui/exercise_widgets_test` | Each of the 9 widgets: render, interact, the produced `Answer`, result marks, digit keys, a pluggable ink input; engine fields (MC hint, `kNoEnding`, `tokenPre`, transform translation, accent slip) |
| `ui/progress_pages_test` | Map header → progress page, heatmap, challenges, verb collection, tier badges, non-stop HUD and best-run record |
| `app/boot_test` | `bootApp` on a temp dir: demo fallback with its own seeded DB and settings surviving a restart, pack mode, the real bundled packs with the engine on every course, the app booting to the map, settings round-trip on an on-disk `ProgressRepo` |
| `app/engine_lesson_test` | A full lesson through the engine and an on-disk `ProgressRepo` on the fixture course: wrong then right answers, review_log rows, the mistake record, the summary and the map afterwards |
| `app/engine_nonstop_test` | Non-stop through the engine: the HUD fed from `results`, the bonus round enqueued in the engine (conj_pick next), the replayed best run equal to the live score |
| `app/debug_route_test` | `/debug` opens the data layer's `DebugScreen`; leaving it refreshes progress |
| `progression/fsrs_determinism_test` | Progression on `FsrsScheduler`: identical results across stores and insertion orders, incremental = fresh replay, replay states = stored states, late sync merges |
| `ui/map_screen_test` | Nodes, tap → lesson, long-press → sheet (note, table, items, forms, focus), fading, course switch + unverified badge, zoom, node stats |
| `ui/lesson_flow_test` | Full lesson → summary → map with refreshed stats, wrong answers and re-queue, progress bar, exit confirmation (button and system back), keyboard shortcuts, the "Why?" hook, reduce motion, empty and error states |
| `ui/lab_nonstop_settings_test` | Lab selection → session, non-stop count/stop, settings persistence and read-back, default focus, source-language restriction, navigation rail, debug route, default providers |
| `ui/mistake_review_test` | Map "Review mistakes (N)" after a mistake → review session → resolved; progress → mistakes list (prompt, answers, note excerpt, note link, review button, empty list); "Why?" on a mistake with an explainer; empty review session; the feedback actions row with an extra action |
| `ui/thumb_zone_test` | Controls of every exercise type in the lower part of the screen (phone and desktop, centered column), 48 px targets, `ExerciseLayout` geometry |
| `ui/overflow_test` | Every screen (including progress and verb pages, both Practice tabs and both Reference tabs) and every exercise type (wrong → retry → summary) at 360×640, 320×568, 768×1024 and 1280×800, in dark mode, and with text scale 1.3; every exercise type at text scale 1.5 on the two phone sizes; the mistakes list and the map with its mistakes button. Any layout overflow fails the test |
| `ui/v03_features_test` | Word popovers (cloze before/after checking, the gap, "Open in reference" over the player; spot the error after checking only; sentence MC without the asked word; the sentence builder's answer row), the course picker (first run, preview, add with the placement question, remove, the last course kept, progress kept, "Find my level" → placement → units learned), the five tabs at 320 px and the `/lab` redirect, lookup (form, gloss, verbs only, word page tables), the grammar library and "Practice this skill", the verb collection link, session length (sheet and setting), test out (pass → learned, fail, no test out once learned), tough words (progress and mistakes entries, the drill, the threshold) |
| `ui/v03_bw_test` | The new screens (lookup, word page, grammar library, both Practice tabs, progress with tough words, course picker with preview, skill sheet with length and test out), word popovers and the test-out verdict, pixel-scanned in black & white and checked for overflow at every e-ink harness size; the same walk in color, dark, text 1.3 at 320×568, 360×640 and 1280×800 |
