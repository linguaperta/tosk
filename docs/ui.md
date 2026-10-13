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
| `/` | `MapScreen` (`ui/map/`) | Home. Course switcher in the app bar, with the demo and unverified badges. Level/streak header (tap: progress page). Zoom in and out. "What's fading" button. |
| `/lab` | `LabScreen` (`ui/lab/`) | Skills multi-select grouped by unit, with a tri-state checkbox per unit. Exercise types multi-select (9). Length chips 5/10/20/30/50. |
| `/nonstop` | `NonStopScreen` (`ui/nonstop/`) | Start screen with a slot for the best run. |
| `/progress` | `ProgressScreen` (`ui/progress/`) | Level and XP, streak with freezes, the 26-week heatmap, the verb collection entry, weekly and monthly challenges, badges. |
| `/progress/verbs` | `VerbCollectionScreen` (`ui/progress/`) | `VerbCollectionView`: one card per verb, tense pills light up with mastery. |
| `/settings` | `SettingsScreen` (`ui/settings/`) | Course, source language, default focus, accents, theme, reduce motion, and a link to the debug screen. |
| `/skill/:id` | `SkillSheet` as a modal bottom sheet (`BottomSheetPage`) | Opened by long-press or right-click on a node. Shows a focus chooser and Start, the grammar note (markdown, in the source language), and the item list (article + lemma, gloss, and the forms in the skill's tense for verbs). |
| `/play/lesson/:skillId?focus=` | `PlayerScreen(LessonRequest)` | Tapping a node starts a lesson with the default focus. |
| `/play/fading` | `PlayerScreen(FadingRequest)` | |
| `/play/lab?skills=&types=&length=` | `PlayerScreen(LabRequest)` | |
| `/play/nonstop` | `PlayerScreen(NonStopRequest)` | Endless. The title shows a running count, and Stop leads to the summary. |
| `/debug` | `DebugRoute` (`ui/debug/debug_route.dart`) | The data layer's `DebugScreen` over `appDataProvider` (packs, add a pack, rebuild states, per-skill stats). Leaving it re-lists the courses and bumps `progressRevisionProvider`. Without a data layer it shows `DemoDebugScreen`. |

The five top-level screens (Map, Lab, Non-stop, Progress, Settings) sit in a `StatefulShellRoute` (`ui/shell/app_shell.dart`). Below 600 px wide that shell uses a bottom `NavigationBar`. At 600 px and wider it uses a `NavigationRail`, extended with labels from 1100 px. The player, the sheet and the debug screen open on the root navigator, full screen.

### Lesson player (`ui/lesson/`)

- `PlayerScreen` drives a `PracticeSession` through these phases: loading → exercise → Check → feedback banner → Continue → … → summary. There are also empty and error states.
  - The progress bar is `answered / plannedLength`. Endless sessions show "N answered · M correct" instead.
  - Exit asks for confirmation (the close button, Esc, or system back). In non-stop, exiting stops the run and shows the summary.
  - Desktop shortcuts: 1–9 pick options or tiles. Enter checks, continues, or reveals a flashcard. Esc leaves. Shortcuts are ignored while a text field has focus.
  - After a session (finished or quit) the player bumps `progressRevisionProvider`, which refreshes the map stats, the header and the progress pages.
  - **Non-stop scoring.** The player keeps a progression `NonStopRun` and feeds it one graded exercise at a time from the engine's `EngineSession.results` stream: `run = run.applyResult(event.exercise, event.result, at: toStoredTime(event.events.first.at))`. When a run starts a bonus round (`NonStopSignal.bonusRoundStarted`) it calls `NonStopSession.enqueueBonus(types: run.preferredTypes, count: round.targetAnswers)`; `_advance` waits for the result event of the last submit before drawing the next exercise, so the bonus applies to the very next one. The HUD (`NonStopHudSlot`) shows the run.
  - **Contract (engine ↔ progression ↔ UI).** The engine records every facet outcome of one exercise with the same `at` (`env.now()`), the session id and mode `nonstop`; the UI feeds `NonStopRun` with that recorded `at` (UTC, whole milliseconds, as stored). The best run replayed from the log (`bestNonStopRunProvider`) then equals the live score. One known gap: a wrong *re-ask* after a mistake records no event, so the live run breaks the combo while the replay doesn't see that answer.
  - **"Why?"** uses the core `Explainer` (`explainerProvider`, `NullExplainer` in v1, so the button is hidden). The context is `EngineSession.mistakeContext(exercise.id)`, or one built from the exercise for other sessions.
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
- `feedback_banner.dart`: right or wrong, `result.expected`, "Watch the accent: …" when `result.accentSlip`, an optional "Why?" button, and Continue. It slides up unless motion is reduced.
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
  - `MapEdgesPainter` draws the edges through the skin's `EdgePainter`.
  - The map scrolls vertically, and horizontally only when it is wider than the screen (zoomed in). There's no horizontal overflow at 320 px.
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

### Polish

`ui/common/fx.dart` handles feedback:

- `Fx` plays haptics (`HapticFeedback`) and system sounds (`SystemSound`): click on correct, alert on wrong.
- `Motion` holds the durations, which collapse to zero when motion is reduced.
- `fxProvider` and `motionProvider` derive from `reduceMotionProvider`. The future e-ink mode sets that flag.

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
| `themeModeProvider`, `reduceMotionProvider`, `motionProvider`, `fxProvider` | Derived from settings | E-ink mode can override `reduceMotionProvider` |
| `skinProvider` | `Skin` | `DefaultSkin`; forest skin later |
| `availableCoursesProvider` | `Future<List<CourseMeta>>` | From the catalog (pack listings carry id, version, title, unverified; the opened course has the full meta) |
| `activeCourseIdProvider` | `Future<String>` | The saved course if installed, else the first |
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
| `ui.reduce_motion` | `true` or `false` |

Unknown or missing values fall back to the defaults. They live in the progress database, so they survive a restart (in demo mode, in `progress-demo.sqlite`).

## Tests

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
| `ui/overflow_test` | Every screen (including progress and verb pages) and every exercise type (wrong → retry → summary) at 360×640, 320×568, 768×1024 and 1280×800, in dark mode, and with text scale 1.3. Any layout overflow fails the test |
