// Placement in the app: "New to Italian?" when a course is added, the
// placement test (progress without verdicts, "place me now", leaving), the
// result card, "Skip ahead without a test", "Find my level again" in
// Settings, and "Reset this skill" with Undo. Black & white pixel scans and
// overflow at phone to desktop sizes, large text, dark.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart' show FocusPresets;
import 'package:tosk/providers.dart';
import 'package:tosk/ui/lesson/player_screen.dart';
import 'package:tosk/ui/lesson/session_request.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/placement/placement_ui.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

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
}) async {
  final store = await pumpApp(tester, size: size, store: TestProgressStore(fresh: true, settings: settings), engine: true, overrides: _engine);
  await tapKey(tester, 'course-add-it');
  expect(key('placement-question'), findsOneWidget);
  expect(find.text('New to Italian?'), findsOneWidget);
  await tapKey(tester, choice);
  return store;
}

void main() {
  group('the placement test', () {
    testWidgets('find my level: progress without verdicts, the result, light-review credits', (tester) async {
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
      await playToSummary(tester);
      expect(key('placement-result'), findsOneWidget);
      expect(key('placement-headline'), findsOneWidget);
      expect(key('placement-learned'), findsOneWidget);
      expect(key('placement-review'), findsOneWidget);
      final credits = (await store.log()).where((e) => e.isCredit).toList();
      expect(credits, isNotEmpty);
      expect(credits.every((e) => e.mode == 'placement' && !e.isSelfDeclared), isTrue);
      await tapKey(tester, 'summary-done');
      final s = await stats(tester);
      expect(s['greetings']!.tier, MapTier.bronze);
    });

    testWidgets('"place me now" places with what the answers show', (tester) async {
      final store = await addItalian(tester, 'placement-find');
      await answerCurrent(tester);
      await answerCurrent(tester);
      await tapKey(tester, 'placement-place-now');
      expect(find.text('Stop here and place me?'), findsOneWidget);
      await tapKey(tester, 'place-now-confirm');
      expect(key('placement-result'), findsOneWidget);
      expect(find.text('You placed into Unit 2: Present tense'), findsOneWidget);
      expect(find.textContaining('Marked as learned: Unit 1 (4 skills)'), findsOneWidget);
      final credited = {for (final e in await store.log()) if (e.isCredit) e.facetId};
      final course = await containerOf(tester).read(courseDataProvider.future);
      final u1Facets = {for (final s in _u1) for (final f in course.skillFacets(s)) f.facetId};
      expect(credited.every(u1Facets.contains), isTrue);
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
      expect(find.textContaining('about 2 days'), findsOneWidget);
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
  await answerCurrent(tester);
  await tapKey(tester, 'player-close');
  await check('leave dialog');
  await tapKey(tester, 'exit-place-now');
  await check('result');
  await tapKey(tester, 'summary-done');
  await goTab(tester, 'Settings');
  await tapKey(tester, 'find-level-again');
  await check('choice again');
  await tapKey(tester, 'placement-skip');
  await check('skip ahead');
  await scrollToFind(tester, key('skip-unit-u2'));
  await tapKey(tester, 'skip-unit-u2');
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
