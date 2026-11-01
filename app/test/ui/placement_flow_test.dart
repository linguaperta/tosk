// Placement in the app: "New to Italian?" when a course is added, the
// placement test (progress without verdicts, no intros, "place me now",
// leaving), the word check ("Check the words you already know": reveal and
// self-grade, typing, a good sample's offer, skipping a unit, stopping), the
// result card (grammar per unit, words per word), "Skip ahead without a
// test", "Find my level again" in Settings, and "Reset this skill" with Undo.
// Black & white pixel scans and overflow at phone to desktop sizes, large
// text, dark, semantics, keyboard.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:tosk/engine/engine.dart' show FocusPresets;
import 'package:tosk/ui/lesson/intro/exercise_intro_view.dart';
import 'package:tosk/ui/lesson/intro/exercise_intros.dart' show exerciseIntrosEnabledProvider;
import 'package:tosk/ui/placement/word_check.dart';
import 'package:tosk/ui/settings/learner_settings.dart' show LearnerSettingKeys;
import 'package:tosk/providers.dart';
import 'package:tosk/ui/lesson/player_screen.dart';
import 'package:tosk/ui/lesson/session_request.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/placement/placement_ui.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import '../engine/fixtures/italian_course.dart';
import '../fixtures/topic_course.dart' show TopicCourseCatalog;
import 'bw_helpers.dart';
import 'helpers.dart';

Finder key(String k) => find.byKey(ValueKey(k));

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byKey(appRootKey)));

Future<Map<String, SkillStats>> stats(WidgetTester tester) => containerOf(tester).read(skillStatsProvider.future);

/// The real engine (focus presets without the asset bundle).
final _engine = [focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults)];

CheckboxListTile checkbox(WidgetTester tester, String k) =>
    tester.widget<CheckboxListTile>(find.descendant(of: key(k), matching: find.byType(CheckboxListTile)));

const _u1 = ['greetings', 'food', 'articles', 'family'];

/// A fresh install that adds Italian and answers "New to Italian?" with [choice].
Future<TestProgressStore> addItalian(
  WidgetTester tester,
  String choice, {
  Size size = const Size(400, 800),
  Map<String, String> settings = const {},
  List<Override> overrides = const [],
}) async {
  final store = await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(fresh: true, settings: settings),
    engine: true,
    overrides: [..._engine, ...overrides],
  );
  // Large text on a small phone: the picker sheet opens half-way; pull it up first.
  if (key('course-add-it').evaluate().isEmpty) {
    await tester.drag(key('course-picker'), const Offset(0, -500), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
  await tapKey(tester, 'course-add-it');
  expect(key('placement-question'), findsOneWidget);
  expect(find.text('New to Italian?'), findsOneWidget);
  await tapKey(tester, choice);
  return store;
}

/// Answers right until a word check or the summary shows.
Future<void> answerToWordCheck(WidgetTester tester) async {
  for (var i = 0; i < 60 && !inWordCheck() && key('session-summary').evaluate().isEmpty; i++) {
    await answerCurrent(tester);
  }
}

/// The skill of the exercise on screen.
String? currentSkill(WidgetTester tester) => currentExercise(tester).skillId;

/// The bigger fixture course (a skill of 9 words: the word check offers to mark the rest).
final _fixture = [courseCatalogProvider.overrideWithValue(TopicCourseCatalog(italianCourse()))];

void main() {
  group('the placement test', () {
    testWidgets('find my level: no verdicts, the word check, grammar and words in the result', (tester) async {
      final store = await addItalian(tester, 'placement-find');
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(tester.widget<PlayerScreen>(find.byType(PlayerScreen)).request, isA<PlacementRequest>());
      expect(key('placement-progress'), findsOneWidget);
      expect(find.text('Question 1 · at most 40'), findsOneWidget);
      expect(key('placement-place-now'), findsOneWidget);
      await answerCurrent(tester, wrong: true);
      // No score, no retry count: the bar only says how far the test went.
      expect(find.text('Question 2 · at most 40'), findsOneWidget);
      expect(key('retry-count'), findsNothing);
      await answerToWordCheck(tester);
      // The grammar is credited; the words wait for the check.
      expect(key('word-check-title'), findsOneWidget);
      expect(find.text('Check your words'), findsOneWidget);
      expect(find.text('Check the words you already know'), findsOneWidget);
      final plan = tester.widget<WordCheckView>(find.byType(WordCheckView)).run.plan;
      final planned = {for (final u in plan.units) for (final sk in u.skills) for (final w in sk.words) w.itemId};
      final creditedBefore = {for (final e in await store.log()) if (e.isCredit) e.facetId};
      expect(creditedBefore, isNotEmpty);
      // (An article is grammar: credited with its unit.)
      expect(creditedBefore.any((f) => planned.any((i) => f == '$i#prod' || f == '$i#rec')), isFalse);
      await tapKey(tester, 'word-check-start');
      expect(key('word-check-prompt'), findsOneWidget);
      expect(key('word-check-progress'), findsOneWidget);
      expect(key('word-check-answer'), findsNothing);
      await tapKey(tester, 'word-check-reveal');
      expect(key('word-check-answer'), findsOneWidget);
      await tapKey(tester, 'word-check-knew');
      await doWordCheck(tester, knew: (_) => true);
      expect(key('placement-result'), findsOneWidget);
      expect(key('placement-headline'), findsOneWidget);
      expect(find.textContaining('Grammar of Units 1–3 marked as known'), findsOneWidget);
      final words = tester.widget<Text>(key('placement-words')).data!;
      expect(words, matches(RegExp(r'^(\d+) of \1 words checked as known')));
      expect(key('placement-review'), findsOneWidget);
      expect(find.textContaining('comes back tomorrow'), findsOneWidget);
      final credits = (await store.log()).where((e) => e.isCredit).toList();
      expect(credits.every((e) => e.mode == 'placement' && !e.isSelfDeclared), isTrue);
      expect(credits.any((e) => planned.any((i) => e.facetId.startsWith('$i#'))), isTrue, reason: 'checked words');
      await tapKey(tester, 'summary-done');
      final s = await stats(tester);
      expect(s['greetings']!.tier, MapTier.bronze);
    });

    testWidgets('no first-time intros during the test', (tester) async {
      await addItalian(tester, 'placement-find', overrides: [exerciseIntrosEnabledProvider.overrideWithValue(true)]);
      expect(find.byType(ExerciseIntroView), findsNothing);
      expect(key('placement-progress'), findsOneWidget);
    });

    testWidgets('"place me now" places with what the answers show, then the word check', (tester) async {
      final store = await addItalian(tester, 'placement-find');
      // The middle unit (2) first: answer right until unit 3 begins.
      for (var i = 0; i < 20 && !{'passato', 'time'}.contains(currentSkill(tester)); i++) {
        await answerCurrent(tester);
      }
      await tapKey(tester, 'placement-place-now');
      expect(find.text('Stop here and place me?'), findsOneWidget);
      await tapKey(tester, 'place-now-confirm');
      expect(key('word-check-title'), findsOneWidget);
      await tapKey(tester, 'word-check-skip-all');
      expect(key('placement-result'), findsOneWidget);
      expect(find.text('You placed into Unit 3: The past'), findsOneWidget);
      expect(find.textContaining('Grammar of Units 1, 2 marked as known'), findsOneWidget);
      expect(tester.widget<Text>(key('placement-words')).data, matches(RegExp(r'^\d+ of \d+ words checked')));
      final credited = {for (final e in await store.log()) if (e.isCredit) e.facetId};
      final course = await containerOf(tester).read(courseDataProvider.future);
      final u12 = {
        for (final s in course.skills)
          if (s.unitId == 'u1' || s.unitId == 'u2')
            for (final f in course.skillFacets(s.id)) f.facetId,
      };
      expect(credited.every(u12.contains), isTrue);
    });

    testWidgets('nothing passed: start at the beginning, no word check', (tester) async {
      await addItalian(tester, 'placement-find');
      await answerCurrent(tester);
      await tapKey(tester, 'placement-place-now');
      await tapKey(tester, 'place-now-confirm');
      expect(inWordCheck(), isFalse);
      expect(find.text('Start at the beginning: Unit 1: Basics'), findsOneWidget);
      expect(key('placement-words'), findsNothing);
    });

    testWidgets('leaving: keep going, place me now, or quit without placing', (tester) async {
      final store = await addItalian(tester, 'placement-find');
      await answerCurrent(tester);
      await tapKey(tester, 'player-close');
      expect(find.text('Leave the test?'), findsOneWidget);
      await tapKey(tester, 'exit-cancel');
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tapKey(tester, 'player-close');
      await tapKey(tester, 'exit-confirm');
      expect(find.byType(PlayerScreen), findsNothing);
      expect((await store.log()).where((e) => e.isCredit), isEmpty);
    });
  });

  group('the word check', () {
    testWidgets('a good sample: mark the rest as known; leave a unit as new', (tester) async {
      final store = await addItalian(tester, 'placement-find', overrides: _fixture);
      await answerToWordCheck(tester);
      await tapKey(tester, 'word-check-start');
      // Unit 1 (no grammar, counted with the units after it): People has 9 words.
      for (var i = 0; i < 40 && key('word-check-offer').evaluate().isEmpty; i++) {
        await tapKey(tester, 'word-check-reveal');
        await tapKey(tester, 'word-check-knew');
      }
      expect(key('word-check-offer'), findsOneWidget);
      expect(find.textContaining('You knew 6 of 6 words of'), findsOneWidget);
      final rest = tester.widget<WordCheckView>(find.byType(WordCheckView)).run.restCount;
      expect(find.text('Mark $rest words as known'), findsOneWidget);
      await tapKey(tester, 'word-check-mark-rest');
      expect(key('word-check-offer'), findsNothing);
      // A unit left as new.
      final unit = tester.widget<WordCheckView>(find.byType(WordCheckView)).run.unit!.unitId;
      await tapKey(tester, 'word-check-skip-unit');
      expect(tester.widget<WordCheckView>(find.byType(WordCheckView)).run.unit?.unitId, isNot(unit));
      await doWordCheck(tester, knew: (_) => false);
      expect(key('placement-result'), findsOneWidget);
      final credited = {for (final e in await store.log()) if (e.isCredit) e.facetId};
      expect(credited, contains('it:ragazzo#prod'));
      expect(credited, contains('it:ragazzo#rec'));
    });

    testWidgets('typing mode: type the word; stopping early keeps what was marked', (tester) async {
      final store = await addItalian(tester, 'placement-find', settings: {LearnerSettingKeys.answerInput: 'type'});
      await answerToWordCheck(tester);
      await tapKey(tester, 'word-check-start');
      expect(key('word-check-input'), findsOneWidget);
      expect(key('word-check-reveal'), findsNothing);
      final run = tester.widget<WordCheckView>(find.byType(WordCheckView)).run;
      final first = run.word!;
      await tester.enterText(key('word-check-input'), first.answer);
      await tester.pumpAndSettle();
      await tapKey(tester, 'word-check-check');
      expect(find.text('Right'), findsOneWidget);
      await tapKey(tester, 'word-check-next');
      await tester.enterText(key('word-check-input'), 'xyzzy');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Not quite'), findsOneWidget);
      expect(key('word-check-answer'), findsOneWidget);
      // Enter continues.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(run.answered, 2);
      // Stop: what was marked counts, the rest stays new.
      await tapKey(tester, 'player-close');
      expect(find.text('Stop checking words?'), findsOneWidget);
      await tapKey(tester, 'word-check-keep');
      expect(inWordCheck(), isTrue);
      await tapKey(tester, 'player-close');
      await tapKey(tester, 'word-check-stop');
      expect(key('placement-result'), findsOneWidget);
      final credited = {for (final e in await store.log()) if (e.isCredit) e.facetId};
      expect(credited, contains('${first.itemId}#prod'));
      final o = tester.widget<PlacementResultCard>(find.byType(PlacementResultCard)).outcome;
      expect(o.wordsKnown, lessThan(o.wordsTotal));
    });

    testWidgets("keyboard: Enter reveals, 1 knew it, 2 didn't; Esc asks before stopping", (tester) async {
      await addItalian(tester, 'placement-find');
      await answerToWordCheck(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter); // Start
      await tester.pumpAndSettle();
      final run = tester.widget<WordCheckView>(find.byType(WordCheckView)).run;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter); // Show the word
      await tester.pumpAndSettle();
      expect(key('word-check-answer'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pumpAndSettle();
      expect(run.answered, 2);
      expect(run.known.length, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Stop checking words?'), findsOneWidget);
      await tapKey(tester, 'word-check-keep');
    });

    testWidgets('semantics: the title is a header, skipping a unit says which', (tester) async {
      final handle = tester.ensureSemantics();
      await addItalian(tester, 'placement-find');
      await answerToWordCheck(tester);
      expect(tester.getSemantics(key('word-check-title')), matchesSemantics(isHeader: true, label: 'Check the words you already know'));
      await tapKey(tester, 'word-check-start');
      expect(find.bySemanticsLabel(RegExp(r"^Skip the rest of Unit \d: .*I'll learn these words as new$")), findsOneWidget);
      for (final k in ['word-check-reveal', 'word-check-skip-unit']) {
        expect(tester.getSize(key(k)).height, greaterThanOrEqualTo(48), reason: k);
      }
      await tapKey(tester, 'word-check-reveal');
      for (final k in ['word-check-knew', 'word-check-didnt']) {
        expect(tester.getSize(key(k)).height, greaterThanOrEqualTo(48), reason: k);
      }
      handle.dispose();
    });

    for (final size in const [Size(320, 568), Size(1280, 800)]) {
      testWidgets('black & white at ${size.width.toInt()}: the offer and every word screen, grayscale, no overflow', (tester) async {
        await addItalian(tester, 'placement-find', size: size, settings: {SettingKeys.display: 'bw'}, overrides: _fixture);
        await answerToWordCheck(tester);
        await expectGrayscale(tester, 'intro');
        await tapKey(tester, 'word-check-start');
        for (var i = 0; i < 40 && key('word-check-offer').evaluate().isEmpty; i++) {
          if (i == 0) await expectGrayscale(tester, 'card');
          await tapKey(tester, 'word-check-reveal');
          if (i == 0) await expectGrayscale(tester, 'revealed');
          await tapKey(tester, 'word-check-knew');
        }
        await expectGrayscale(tester, 'offer');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('text 1.5 at 320, dark: the word check and its offer without overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await addItalian(tester, 'placement-find', size: const Size(320, 568), settings: {SettingKeys.themeMode: 'dark'}, overrides: _fixture);
      await answerToWordCheck(tester);
      expect(tester.takeException(), isNull, reason: 'intro');
      await tapKey(tester, 'word-check-start');
      for (var i = 0; i < 40 && key('word-check-offer').evaluate().isEmpty; i++) {
        await tapKey(tester, 'word-check-reveal');
        expect(tester.takeException(), isNull, reason: 'revealed');
        await tapKey(tester, 'word-check-knew');
      }
      expect(key('word-check-offer'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'offer');
    });
  });

  group('skip ahead without a test', () {
    testWidgets('tick units (earlier ones too), self-declared credits, the result', (tester) async {
      final store = await addItalian(tester, 'placement-skip');
      expect(find.byType(SkipAheadScreen), findsOneWidget);
      expect(key('skip-ahead-warning'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(key('skip-ahead-confirm')).onPressed, isNull);
      await tapKey(tester, 'skip-unit-u2');
      expect(checkbox(tester, 'skip-unit-u1').value, isTrue);
      expect(checkbox(tester, 'skip-unit-u2').value, isTrue);
      expect(checkbox(tester, 'skip-unit-u3').value, isFalse);
      expect(find.text('Mark 2 units as known'), findsOneWidget);
      await tapKey(tester, 'skip-unit-u1'); // untick one
      expect(find.text('Mark 1 unit as known'), findsOneWidget);
      await tapKey(tester, 'skip-unit-u1');
      await tapKey(tester, 'skip-ahead-confirm');
      expect(key('placement-result'), findsOneWidget);
      expect(find.text('You skipped ahead to Unit 3: The past'), findsOneWidget);
      expect(find.textContaining('come back for review tomorrow'), findsOneWidget);
      final credits = (await store.log()).where((e) => e.isCredit).toList();
      expect(credits, isNotEmpty);
      expect(credits.every((e) => e.isSelfDeclared), isTrue);
      await tapKey(tester, 'skip-ahead-done');
      expect(find.byType(SkipAheadScreen), findsNothing);
      final s = await stats(tester);
      for (final id in _u1) {
        expect(s[id]!.tier, MapTier.bronze, reason: id);
      }
    });

    testWidgets('Settings: find my level again offers the test or skipping ahead', (tester) async {
      await pumpApp(tester, engine: true, overrides: _engine);
      await goTab(tester, 'Settings');
      await tapKey(tester, 'find-level-again');
      expect(find.text('Find your level again'), findsOneWidget);
      expect(key('placement-scratch'), findsNothing);
      await tapKey(tester, 'placement-cancel');
      expect(key('placement-question'), findsNothing);
      await tapKey(tester, 'find-level-again');
      await tapKey(tester, 'placement-skip');
      expect(find.byType(SkipAheadScreen), findsOneWidget);
      await tapKey(tester, 'skip-ahead-close');
      await tapKey(tester, 'find-level-again');
      await tapKey(tester, 'placement-find');
      expect(tester.widget<PlayerScreen>(find.byType(PlayerScreen)).request, isA<PlacementRequest>());
    });
  });

  group('reset this skill', () {
    testWidgets('confirm, the tier drops, Undo brings it back; a whole unit', (tester) async {
      await addItalian(tester, 'placement-skip');
      await tapKey(tester, 'skip-unit-u1');
      await tapKey(tester, 'skip-ahead-confirm');
      await tapKey(tester, 'skip-ahead-done');
      expect((await stats(tester))['food']!.tier, MapTier.bronze);

      await tapKey(tester, 'skill-node-food');
      await scrollToFind(tester, key('skill-reset'));
      await tapKey(tester, 'skill-reset');
      expect(find.text('Reset Food?'), findsOneWidget);
      expect(key('skill-reset-explain'), findsOneWidget);
      expect(find.textContaining('your answer history is kept'), findsOneWidget);
      await tapKey(tester, 'skill-reset-cancel');
      expect((await stats(tester))['food']!.tier, MapTier.bronze);

      await tapKey(tester, 'skill-reset');
      await tapKey(tester, 'skill-reset-confirm');
      expect(key('skill-reset-done'), findsOneWidget);
      expect((await stats(tester))['food']!.tier.index, lessThan(MapTier.started.index));
      expect((await stats(tester))['greetings']!.tier, MapTier.bronze);
      await tapKey(tester, 'skill-reset-undo');
      await tester.pumpAndSettle();
      expect((await stats(tester))['food']!.tier, MapTier.bronze);

      // The whole unit.
      await tapKey(tester, 'skill-node-food');
      await scrollToFind(tester, key('skill-reset'));
      await tapKey(tester, 'skill-reset');
      await tapKey(tester, 'skill-reset-unit');
      expect(find.text('Reset Unit 1: Basics?'), findsOneWidget);
      await tapKey(tester, 'skill-reset-confirm');
      final s = await stats(tester);
      for (final id in _u1) {
        expect(s[id]!.tier.index, lessThan(MapTier.bronze.index), reason: id);
      }
    });

    testWidgets('not offered before the skill was studied', (tester) async {
      await pumpApp(tester, store: TestProgressStore(settings: {SettingKeys.coursesAdded: 'it'}), engine: true, overrides: _engine);
      await tapKey(tester, 'skill-node-greetings');
      expect(key('skill-words'), findsOneWidget);
      expect(find.byKey(const ValueKey('skill-reset'), skipOffstage: false), findsNothing);
    });
  });

  group('black & white and sizes', () {
    const sizes = {
      'small phone 320x568': Size(320, 568),
      'phone 360x640': Size(360, 640),
      'e-reader 6in 572x772': Size(572, 772),
      'desktop 1280x800': Size(1280, 800),
    };
    for (final entry in sizes.entries) {
      testWidgets('grayscale and no overflow at ${entry.key}', (tester) async {
        await addItalianBw(tester, entry.value);
      });
    }

    for (final scale in const [1.3, 1.5]) {
      for (final size in const [Size(320, 568), Size(1280, 800)]) {
        testWidgets('text $scale at ${size.width.toInt()}, colour and dark: no overflow', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          for (final theme in const ['light', 'dark']) {
            await walkPlacement(tester, size, {SettingKeys.themeMode: theme}, (what) async {
              expect(tester.takeException(), isNull, reason: '$what ($theme)');
            });
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }

    testWidgets('choices and buttons are at least 48 dp tall; semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: const Size(320, 568), store: TestProgressStore(fresh: true), engine: true, overrides: _engine);
      await tapKey(tester, 'course-add-it');
      for (final k in ['placement-scratch', 'placement-find', 'placement-skip']) {
        expect(tester.getSize(key(k)).height, greaterThanOrEqualTo(48), reason: k);
      }
      await tapKey(tester, 'placement-find');
      expect(find.bySemanticsLabel(RegExp('Placement test, question 1, at most 40')), findsOneWidget);
      expect(find.byTooltip('Stop here — place me now'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('keyboard: Esc asks before leaving the test', (tester) async {
      await addItalian(tester, 'placement-find');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Leave the test?'), findsOneWidget);
      await tapKey(tester, 'exit-cancel');
      expect(find.byType(PlayerScreen), findsOneWidget);
    });
  });
}

/// Every placement screen in black & white at [size]: grayscale, no overflow.
Future<void> addItalianBw(WidgetTester tester, Size size) => walkPlacement(tester, size, {SettingKeys.display: 'bw'}, (
  what,
) async {
  await expectGrayscale(tester, what);
  expect(tester.takeException(), isNull, reason: what);
});

/// Walks the placement screens ([check] on each): the choice, the test with
/// its progress, the leave dialog, the result; skip ahead and its result; the
/// reset dialog and its snackbar.
Future<void> walkPlacement(
  WidgetTester tester,
  Size size,
  Map<String, String> settings,
  Future<void> Function(String what) check,
) async {
  await pumpApp(tester, size: size, store: TestProgressStore(fresh: true, settings: settings), engine: true, overrides: _engine);
  // Large text on a small phone: the picker sheet opens half-way; pull it up first.
  if (key('course-add-it').evaluate().isEmpty) {
    await tester.drag(key('course-picker'), const Offset(0, -500), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
  await tapKey(tester, 'course-add-it');
  await check('choice');
  await tapKey(tester, 'placement-find');
  await check('test');
  // Unit 2 (the middle) passes; then a word check for units 1-2.
  for (var i = 0; i < 20 && !{'passato', 'time'}.contains(currentExercise(tester).skillId); i++) {
    await answerCurrent(tester);
    if (i == 0) await check('test, a placement item');
  }
  await tapKey(tester, 'player-close');
  await check('leave dialog');
  await tapKey(tester, 'exit-place-now');
  await check('word check intro');
  await tapKey(tester, 'word-check-start');
  await check('word check card');
  await tapKey(tester, 'word-check-reveal');
  await check('word check answer');
  await tapKey(tester, 'word-check-knew');
  await tapKey(tester, 'player-close');
  await check('word check stop dialog');
  await tapKey(tester, 'word-check-stop');
  await check('result');
  await tapKey(tester, 'summary-done');
  await goTab(tester, 'Settings');
  await tapKey(tester, 'find-level-again');
  await check('choice again');
  await tapKey(tester, 'placement-skip');
  await check('skip ahead');
  // Unit 2's grammar is learned now (its tile is fixed); tick unit 3.
  await scrollToFind(tester, key('skip-unit-u3'));
  await tapKey(tester, 'skip-unit-u3');
  await tapKey(tester, 'skip-ahead-confirm');
  await check('skip ahead result');
  await tapKey(tester, 'skip-ahead-done');
  await goTab(tester, 'Map');
  await tapKey(tester, 'skill-node-food');
  await scrollToFind(tester, key('skill-reset'));
  await tapKey(tester, 'skill-reset');
  await check('reset dialog');
  await tapKey(tester, 'skill-reset-confirm');
  await check('reset snackbar');
}
