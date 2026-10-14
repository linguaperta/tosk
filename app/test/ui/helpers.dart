import 'package:tosk/app.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/progression/calendar.dart';
import 'package:tosk/ui/lesson/exercises/exercise_view.dart';
import 'package:tosk/ui/router.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fakes/demo_session.dart';

final testNow = DateTime.utc(2026, 10, 13, 12);

/// Wraps the app in `pumpApp`, for screenshots and pixel checks of the whole screen.
const appRootKey = ValueKey('app-root');

/// The data layer's in-memory FSRS store with preset settings and a readable
/// settings map (what `progressStoreProvider` defaults to, minus the presets).
///
/// Both demo courses count as added ("my courses") unless [fresh] is true
/// (a first run, which opens the course picker).
class TestProgressStore extends InMemoryProgressStore {
  TestProgressStore({Map<String, String>? settings, bool fresh = false})
    : _settings = {if (!fresh) SettingKeys.coursesAdded: 'it,nl', ...?settings};

  final Map<String, String> _settings;

  /// Settings as stored.
  Map<String, String> get settings => Map.unmodifiable(_settings);

  @override
  Future<Map<String, String>> allSettings() async => Map.of(_settings);

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      _settings.remove(key);
    } else {
      _settings[key] = value;
    }
  }
}

void setSurface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

/// The fake session factory over hand-made exercises (a fixed exercise per type).
final fakeSessionFactoryOverride = sessionFactoryProvider.overrideWith((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  await ref.watch(settingsProvider.future);
  return DemoSessionFactory(
    course: course,
    store: ref.watch(progressStoreProvider),
    options: ref.watch(sessionOptionsProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Pumps the whole app with demo data, a fixed clock and an in-memory store.
/// Sessions come from the fake factory unless [engine] is true (the real engine).
Future<TestProgressStore> pumpApp(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  TestProgressStore? store,
  String? initialLocation,
  bool engine = false,
  List<Override> overrides = const [],
}) async {
  setSurface(tester, size);
  final s = store ?? TestProgressStore();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        progressStoreProvider.overrideWithValue(s),
        clockProvider.overrideWithValue(() => testNow),
        calendarProvider.overrideWithValue(LocalCalendar.utc),
        if (!engine) fakeSessionFactoryOverride,
        if (initialLocation != null)
          routerProvider.overrideWith((ref) => buildRouter(initialLocation: initialLocation)),
        ...overrides,
      ],
      child: const RepaintBoundary(key: appRootKey, child: ToskApp()),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

/// Taps a destination in the bottom navigation bar. 'Lab' and 'Non-stop'
/// are tabs inside Practice, 'Lookup' and 'Grammar' inside Reference.
Future<void> goTab(WidgetTester tester, String label) async {
  const inner = {
    'Lab': ('Practice', 'practice-tab-lab'),
    'Non-stop': ('Practice', 'practice-tab-nonstop'),
    'Lookup': ('Reference', 'reference-tab-lookup'),
    'Grammar': ('Reference', 'reference-tab-grammar'),
  };
  final dest = inner[label]?.$1 ?? label;
  final nav = find.byKey(const ValueKey('bottom-nav'));
  final rail = find.byKey(const ValueKey('nav-rail'));
  final bar = nav.evaluate().isNotEmpty ? nav : rail;
  await tester.tap(find.descendant(of: bar, matching: find.text(dest)).first);
  await tester.pumpAndSettle();
  final tab = inner[label]?.$2;
  if (tab != null) {
    await tester.tap(find.byKey(ValueKey(tab)));
    await tester.pumpAndSettle();
  }
}

/// When [finder] matches nothing (a lazy list built it away), scrolls the
/// vertical scrollables up, then down, until it appears.
Future<void> scrollToFind(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && (w.axisDirection == AxisDirection.down || w.axisDirection == AxisDirection.up),
  );
  for (final element in vertical.evaluate().toList()) {
    final scrollable = find.byElementPredicate((e) => e == element);
    for (final dy in const [300.0, -300.0]) {
      for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
        final pos = (element as StatefulElement).state as ScrollableState;
        final before = pos.position.pixels;
        await tester.drag(scrollable, Offset(0, dy), warnIfMissed: false);
        await tester.pumpAndSettle();
        if (pos.position.pixels == before) break;
      }
      if (finder.evaluate().isNotEmpty) return;
    }
  }
}

/// Scrolls [finder] into view, taps it and settles.
Future<void> tapIt(WidgetTester tester, Finder finder) async {
  await scrollToFind(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) => tapIt(tester, find.byKey(ValueKey(key)));

/// A tap on a map node opens the skill's sheet; Start lesson starts it.
Future<void> startLessonFromMap(WidgetTester tester, String skillId) async {
  await tapKey(tester, 'skill-node-$skillId');
  await tapKey(tester, 'start-lesson');
}

Exercise currentExercise(WidgetTester tester) => tester.widget<ExerciseView>(find.byType(ExerciseView)).exercise;

int _freeTile(List<String> tiles, String word, Set<int> used) {
  for (var t = 0; t < tiles.length; t++) {
    if (!used.contains(t) && tiles[t] == word) return t;
  }
  throw StateError('No tile "$word" in $tiles');
}

/// Answers the current exercise in the player correctly (or wrongly with [wrong]),
/// checks it, and continues past the feedback.
Future<void> answerCurrent(WidgetTester tester, {bool wrong = false}) async {
  if (await answerCurrentNoContinue(tester, wrong: wrong)) {
    expect(find.byKey(const ValueKey('feedback-banner')), findsOneWidget);
    await tapKey(tester, 'continue-button');
  }
}

/// Answers and checks the current exercise, leaving the feedback banner up.
/// Returns false for self-submitting types (flashcard, match pairs), which advance by themselves.
Future<bool> answerCurrentNoContinue(WidgetTester tester, {bool wrong = false}) async {
  final ex = currentExercise(tester);
  Future<void> check() => tapKey(tester, 'check-button');
  switch (ex) {
    case FlashcardExercise():
      await tapKey(tester, 'flashcard-reveal');
      await tapKey(tester, wrong ? 'grade-again' : 'grade-good');
      return false; // flashcards advance by themselves
    case MultipleChoiceExercise e:
      await tapKey(tester, 'option-${wrong ? (e.correctIndex + 1) % e.options.length : e.correctIndex}');
      await check();
    case MatchPairsExercise e:
      if (wrong) {
        final other = (e.solution[0]! + 1) % e.right.length;
        await tapKey(tester, 'match-left-0');
        await tapKey(tester, 'match-right-$other');
        await tester.pump(const Duration(seconds: 1));
      }
      for (var i = 0; i < e.left.length; i++) {
        await tapKey(tester, 'match-left-$i');
        await tapKey(tester, 'match-right-${e.solution[i]}');
      }
      return find.byKey(const ValueKey('continue-button')).evaluate().isNotEmpty;
    case ConjPickExercise e:
      final typedPick = find.byKey(const ValueKey('conj-pick-typed'));
      if (typedPick.evaluate().isNotEmpty) {
        final ending = e.fullForm.substring(e.stem.length);
        await typeInto(tester, typedPick, wrong ? 'xyz' : (ending.isEmpty ? '-' : ending));
      } else {
        await tapKey(tester, 'ending-${wrong ? (e.correctIndex + 1) % e.endings.length : e.correctIndex}');
      }
      await check();
    case ConjGridExercise e:
      final used = <int>{};
      final asked = [
        for (var i = 0; i < e.cells.length; i++)
          if (!e.cells[i].prefilled) i,
      ];
      final words = [for (final i in asked) e.cells[i].expected];
      if (wrong) words.setAll(0, [words[1], words[0]]);
      if (find.byKey(ValueKey('grid-input-${asked.first}')).evaluate().isNotEmpty) {
        for (var k = 0; k < asked.length; k++) {
          await typeInto(tester, find.byKey(ValueKey('grid-input-${asked[k]}')), words[k]);
        }
        await check();
        return true;
      }
      for (var k = 0; k < asked.length; k++) {
        final t = _freeTile(e.tiles, words[k], used);
        used.add(t);
        await tapKey(tester, 'grid-cell-${asked[k]}');
        await tapKey(tester, 'grid-tile-$t');
      }
      await check();
    case SentenceBuilderExercise(:final tiles, :final answers) || TransformExercise(:final tiles, :final answers):
      if (find.byKey(const ValueKey('answer-input')).evaluate().isNotEmpty) {
        await typeInto(tester, find.byKey(const ValueKey('answer-input')), wrong ? 'xxx' : answers.first.join(' '));
        await check();
        return true;
      }
      final used = <int>{};
      final words = List.of(answers.first);
      if (wrong) words.removeLast();
      for (final w in words) {
        final t = _freeTile(tiles, w, used);
        used.add(t);
        await tapKey(tester, 'tile-$t');
      }
      await check();
    case ClozeExercise e:
      if (e.options != null && find.byKey(const ValueKey('answer-input')).evaluate().isEmpty) {
        await tapKey(tester, 'cloze-option-${wrong ? (e.correctIndex! + 1) % e.options!.length : e.correctIndex}');
      } else {
        await tester.enterText(find.byKey(const ValueKey('answer-input')), wrong ? 'xyz' : e.expected);
        await tester.pumpAndSettle();
      }
      await check();
    case SpotErrorExercise e:
      final idx = wrong ? (e.errorIndex == 0 ? 1 : 0) : e.errorIndex;
      await tapKey(tester, 'token-$idx');
      await check();
    case ListenPickExercise e:
      await tapKey(tester, 'option-${wrong ? (e.correctIndex + 1) % e.options.length : e.correctIndex}');
      await check();
  }
  return true;
}

/// Types [text] into the text field at (or inside) [finder].
Future<void> typeInto(WidgetTester tester, Finder finder, String text) async {
  final field = find.descendant(of: finder, matching: find.byType(EditableText), matchRoot: true);
  await tester.ensureVisible(field.first);
  await tester.pumpAndSettle();
  await tester.enterText(field.first, text);
  await tester.pumpAndSettle();
}

/// Answers until the summary shows (with a safety cap).
Future<int> playToSummary(WidgetTester tester, {int cap = 60}) async {
  var n = 0;
  while (find.byKey(const ValueKey('session-summary')).evaluate().isEmpty) {
    if (n++ > cap) fail('Session did not end after $cap exercises');
    await answerCurrent(tester);
  }
  return n;
}
