# App screens (Phase 4)

The UI lives in `app/lib/ui/`, plus `app/lib/main.dart`, `app/lib/app.dart` and `app/lib/providers.dart`.
It is built only against the contracts in `app/lib/core/`. Until integration it runs on demo implementations in `app/lib/ui/demo/`. Every dependency goes through a Riverpod provider, so swapping in the real implementations is a provider change.

## Screens and routes

go_router, in `ui/router.dart`. Path builders are in `ui/routes.dart`.

| Route | Screen | Notes |
| --- | --- | --- |
| `/` | `MapScreen` (`ui/map/`) | Home. Course switcher in the app bar, with the unverified badge. Zoom in and out. "What's fading" button. |
| `/lab` | `LabScreen` (`ui/lab/`) | Skills multi-select grouped by unit, with a tri-state checkbox per unit. Exercise types multi-select (9). Length chips 5/10/20/30/50. |
| `/nonstop` | `NonStopScreen` (`ui/nonstop/`) | Start screen with a slot for the best run. |
| `/settings` | `SettingsScreen` (`ui/settings/`) | Course, source language, default focus, accents, theme, reduce motion, and a link to the debug screen. |
| `/skill/:id` | `SkillSheet` as a modal bottom sheet (`BottomSheetPage`) | Opened by long-press or right-click on a node. Shows a focus chooser and Start, the grammar note (markdown, in the source language), and the item list (article + lemma, gloss, and the forms in the skill's tense for verbs). |
| `/play/lesson/:skillId?focus=` | `PlayerScreen(LessonRequest)` | Tapping a node starts a lesson with the default focus. |
| `/play/fading` | `PlayerScreen(FadingRequest)` | |
| `/play/lab?skills=&types=&length=` | `PlayerScreen(LabRequest)` | |
| `/play/nonstop` | `PlayerScreen(NonStopRequest)` | Endless. The title shows a running count, and Stop leads to the summary. |
| `/debug` | `DebugPlaceholderScreen` | **TODO(integration):** point it to `lib/ui/debug/debug_screen.dart`. |

The four top-level screens sit in a `StatefulShellRoute` (`ui/shell/app_shell.dart`). Below 600 px wide that shell uses a bottom `NavigationBar`. At 600 px and wider it uses a `NavigationRail`, extended with labels from 1100 px. The player, the sheet and the debug screen open on the root navigator, full screen.

### Lesson player (`ui/lesson/`)

- `PlayerScreen` drives a `PracticeSession` through these phases: loading → exercise → Check → feedback banner → Continue → … → summary. There are also empty and error states.
  - The progress bar is `answered / plannedLength`. Endless sessions show "N answered · M correct" instead.
  - Exit asks for confirmation (the close button, Esc, or system back). In non-stop, exiting stops the run and shows the summary.
  - Desktop shortcuts: 1–9 pick options or tiles. Enter checks, continues, or reveals a flashcard. Esc leaves. Shortcuts are ignored while a text field has focus.
- `exercises/`: one widget per type, all subclasses of `ExerciseWidget<E>`.
  - Each widget reports a draft `Answer?` through `onChanged`.
  - Flashcard (self-grade) and match pairs (once everything is matched) submit themselves through `onSubmit`.
  - With `result` set, a widget shows its marks: right and wrong options, per-cell ✓/✗ with the expected form for grids, and the correction for spot-the-error.

  | Type | Widget | Answer |
  | --- | --- | --- |
  | flashcard | `FlashcardView` (Show answer, then Again/Hard/Good/Easy) | `SelfGradeAnswer` |
  | multiple_choice | `MultipleChoiceView` | `ChoiceAnswer` |
  | match_pairs | `MatchPairsView` (either order; a wrong pair flashes red and counts as missed) | `MatchAnswer(matches, missed)` |
  | conj_pick | `ConjPickView` (`mang___`, person and tense chips, ending options; an empty ending shows as ∅) | `ChoiceAnswer` |
  | conj_grid | `ConjGridView` (tap a cell, then a tile; prefilled cells greyed; tap a filled cell to return its tile) | `GridAnswer` (`''` for prefilled cells) |
  | sentence_builder | `SentenceBuilderView` (tiles to the answer line and back) | `TilesAnswer` |
  | cloze | `ClozeView` (option chips, or an `AnswerInputWidget` when `options == null`) | `ChoiceAnswer` / `TextAnswer` |
  | spot_error | `SpotErrorView` (word tokens are tappable; punctuation sticks to its word) | `TokenAnswer` |
  | transform | `TransformView` (source sentence, target chip, tiles) | `TilesAnswer` |

- `answer_input.dart`: `AnswerInputWidget` is the free-text input abstraction. `KeyboardAnswerInput` ships now. A handwriting widget (Phase 8) implements the same class, reports `TextAnswer(inputMode: ink, candidates: [...])`, and plugs in through `answerInputBuilderProvider`.
- `feedback_banner.dart`: right or wrong, `result.expected`, an optional "Why?" button, and Continue. It slides up unless motion is reduced.
- `session_summary_view.dart`: answered, accuracy and time, plus a mistakes list (facet ids rendered as "il pane · produce") and the `SummaryProgressSlot`.
- `why_explainer.dart`: the placeholder `WhyExplainer` and `WhyContext`, plus `UnavailableWhyExplainer`. The "Why?" button is hidden while `explainerAvailableProvider` is false.

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
  - **Fading**: the node color is desaturated and lightened in proportion to `decay = 1 - strength`. Locked nodes are greyed.
  - Pressing scales the node down, unless motion is reduced.
- `skill_stats.dart` has `SkillStats` (strength, lastPracticed, tier) and `MapTier`: locked, available, started, bronze, silver, gold. `available` means unlocked but never practiced.

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

| Provider | Type | Now | At integration |
| --- | --- | --- | --- |
| `clockProvider` | `DateTime Function()` | `DateTime.now` | Keep (tests override it) |
| `courseCatalogProvider` | `CourseCatalog` (`ui/course_catalog.dart`: `listCourses()`, `open(id)`) | `DemoCourseCatalog` (`it` and `nl` demo courses; `nl` flagged unverified) | Adapter over the data layer's `LocalPackSource` + course repo that returns `InMemoryCourseData` |
| `progressStoreProvider` | `ProgressStore` | `InMemoryProgressStore` (main.dart seeds demo history) | Drift `ProgressRepo`. If opening it is async, open it in `main()` and use `overrideWithValue` |
| `settingsProvider` | `AsyncNotifierProvider<SettingsController, AppSettings>` | Reads and writes `ProgressStore` settings | Unchanged |
| `themeModeProvider`, `reduceMotionProvider`, `motionProvider`, `fxProvider` | Derived from settings | | Unchanged. E-ink mode can override `reduceMotionProvider` |
| `skinProvider` | `Skin` | `DefaultSkin` | Forest skin later |
| `availableCoursesProvider` | `Future<List<CourseMeta>>` | From the catalog | Unchanged |
| `activeCourseIdProvider` | `Future<String>` | The saved course if installed, else the first | Unchanged |
| `courseDataProvider` | `Future<CourseData>` | `catalog.open(activeId)` | Unchanged |
| `sourceLangProvider` | `String` | The setting, restricted to `meta.translations` | Unchanged |
| `mapLayoutProvider` | `Future<MapLayout>` | `layoutSkillMap(units, skills)` | Unchanged |
| `sessionOptionsProvider` | `SessionOptions` | Source language + accent strictness | Unchanged |
| `sessionFactoryProvider` | `Future<SessionFactory>` | `DemoSessionFactory`: hand-made exercises of all 9 types, correct grading (`DemoGrader`), records to the store, re-queues mistakes once | **The engine's factory** (course data + progress store + scheduler + options) |
| `explainerProvider` | `WhyExplainer` | `UnavailableWhyExplainer` | The engine's `Explainer` from `core/interfaces/hooks.dart`. Replace or adapt `WhyExplainer`/`WhyContext` with `Explainer`/`MistakeContext`, and make `explainerAvailableProvider` = `explainer is! NullExplainer` |
| `explainerAvailableProvider` | `bool` | `false` | See above |
| `answerInputBuilderProvider` | `AnswerInputBuilder` | Keyboard | Ink input in Phase 8 |
| `skillStatsProvider` | `Future<Map<String, SkillStats>>` | `computeDemoSkillStats` (demo forgetting curve; tiers from the spec thresholds; locked = a prerequisite was never practiced) | Data layer skill strength + progression tiers mapped to `MapTier`. The player invalidates it after every session |
| `routerProvider` (`ui/router.dart`) | `GoRouter` | | Unchanged |

Integration should mostly mean editing the provider bodies marked `TODO(integration)` and the demo wiring in `main.dart`. `grep -rn "TODO(integration)" app/lib` lists every spot.

### Progression slots (`ui/slots/progression_slots.dart`)

Each slot renders nothing (or a simple default) until progression's widgets from `lib/ui/progression/` replace the slot body:

- `MapHeaderSlot` (top of the map): level/XP bar and the streak heatmap
- `TierBadgeSlot` (each node): a simple medal or lock by default
- `SummaryProgressSlot` (session summary): XP earned and tier changes
- `NonStopHudSlot` (above the non-stop player): combo and bonus HUD
- `NonStopRecordSlot` (non-stop start screen): best run

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

Unknown or missing values fall back to the defaults.

## Tests (`app/test/ui/`)

| File | Covers |
| --- | --- |
| `map_layout_test` | Layers, bands, centering, `pos` override, pinned/free columns, barycenter crossing removal, unknown units, cycles |
| `markdown_test` | Block and inline parsing, widget rendering |
| `demo_session_test` | Grading of every type, accents, ratings, lesson/lab/non-stop sessions, demo stats |
| `exercise_widgets_test` | Each of the 9 widgets: render, interact, the produced `Answer`, result marks, digit keys, a pluggable ink input |
| `map_screen_test` | Nodes, tap → lesson, long-press → sheet (note, table, items, forms, focus), fading, course switch + unverified badge, zoom, node stats |
| `lesson_flow_test` | Full lesson → summary → map with refreshed stats, wrong answers and re-queue, progress bar, exit confirmation (button and system back), keyboard shortcuts, the "Why?" hook, reduce motion, empty and error states |
| `lab_nonstop_settings_test` | Lab selection → session, non-stop count/stop, settings persistence and read-back, default focus, source-language restriction, navigation rail, debug route, default providers |
| `overflow_test` | Every screen and every exercise type (wrong → retry → summary) at 360×640, 320×568, 768×1024 and 1280×800, in dark mode, and with text scale 1.3. Any layout overflow fails the test |
