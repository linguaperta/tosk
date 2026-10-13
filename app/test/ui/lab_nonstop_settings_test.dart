import 'package:tosk/app.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/lab/lab_screen.dart';
import 'package:tosk/ui/lesson/player_screen.dart';
import 'package:tosk/ui/lesson/session_request.dart';
import 'package:tosk/ui/nonstop/nonstop_screen.dart';
import 'package:tosk/ui/settings/app_settings.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> goTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byKey(const ValueKey('bottom-nav')), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  group('Exercise lab', () {
    testWidgets('pick skills (by unit) and types, choose length, play to summary', (tester) async {
      await pumpApp(tester, size: const Size(400, 900));
      await goTab(tester, 'Lab');
      expect(find.byType(LabScreen), findsOneWidget);
      // Nothing selected yet: start disabled.
      FilledButton start() => tester.widget<FilledButton>(
        find.ancestor(of: find.text('Start'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
      );
      expect(start().onPressed, isNull);

      await tapKey(tester, 'lab-unit-u1'); // all of unit 1
      await tapKey(tester, 'lab-skill-articles'); // ...minus articles
      // Only multiple choice.
      await tapIt(tester, find.text('Clear').last);
      await tapKey(tester, 'lab-type-multiple_choice');
      await tapKey(tester, 'lab-length-5');
      expect(find.text('3 skills · 1 types · 5 exercises'), findsOneWidget);

      await tapKey(tester, 'lab-start');
      final player = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
      final req = player.request as LabRequest;
      expect(req.skillIds, ['greetings', 'food', 'family']);
      expect(req.types, [ExerciseType.multipleChoice]);
      expect(req.length, 5);

      for (var i = 0; i < 5; i++) {
        expect(currentExercise(tester).type, ExerciseType.multipleChoice);
        expect(['greetings', 'food', 'family'], contains(currentExercise(tester).skillId));
        await answerCurrent(tester);
      }
      expect(find.byKey(const ValueKey('session-summary')), findsOneWidget);
      await tapKey(tester, 'summary-done');
      expect(find.byType(LabScreen), findsOneWidget);
    });

    test('LabRequest parses its query', () {
      final r = LabRequest.fromQuery({'skills': 'a,b', 'types': 'cloze,bogus,flashcard', 'length': '7'});
      expect(r.skillIds, ['a', 'b']);
      expect(r.types, [ExerciseType.cloze, ExerciseType.flashcard]);
      expect(r.length, 7);
      expect(LabRequest.fromQuery({}).length, 12);
    });
  });

  group('Non-stop', () {
    testWidgets('endless run with running count; stop shows the summary', (tester) async {
      await pumpApp(tester);
      await goTab(tester, 'Non-stop');
      expect(find.byType(NonStopScreen), findsOneWidget);
      await tapKey(tester, 'nonstop-start');
      expect(find.byKey(const ValueKey('lesson-progress')), findsNothing);
      expect(find.text('0 answered · 0 correct'), findsOneWidget);
      for (var i = 0; i < 15; i++) {
        await answerCurrent(tester, wrong: i == 2);
      }
      expect(find.text('15 answered · 14 correct'), findsOneWidget);
      await tapKey(tester, 'nonstop-stop');
      expect(find.text('Run finished'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('stat-answered')), matching: find.text('15')),
        findsOneWidget,
      );
      await tapKey(tester, 'summary-done');
      expect(find.byType(NonStopScreen), findsOneWidget);
    });

    testWidgets('system back during a run stops it (no dialog)', (tester) async {
      await pumpApp(tester);
      await goTab(tester, 'Non-stop');
      await tapKey(tester, 'nonstop-start');
      await answerCurrent(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Run finished'), findsOneWidget);
    });
  });

  group('Settings', () {
    testWidgets('changes persist to the progress store and are read back', (tester) async {
      final store = await pumpApp(tester, size: const Size(400, 1400));
      await goTab(tester, 'Settings');
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tapKey(tester, 'setting-theme-Dark');
      await tapKey(tester, 'setting-focus-Grammar');
      await tapKey(tester, 'setting-accents-Strict');
      await tapKey(tester, 'setting-source-lang-Nederlands');
      await tapIt(tester, find.byKey(const ValueKey('reduce-motion')));

      expect(store.settings[SettingKeys.themeMode], 'dark');
      expect(store.settings[SettingKeys.defaultFocus], 'grammar');
      expect(store.settings[SettingKeys.accents], 'strict');
      expect(store.settings[SettingKeys.sourceLang], 'nl');
      expect(store.settings[SettingKeys.reduceMotion], 'true');
      expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness, Brightness.dark);

      // A fresh app over the same store starts with the saved settings.
      await tester.pumpWidget(const SizedBox());
      final container = ProviderContainer.test(overrides: [progressStoreProvider.overrideWithValue(store)]);
      final s = await container.read(settingsProvider.future);
      expect(s.themeMode, ThemeMode.dark);
      expect(s.defaultFocus, LessonFocus.grammar);
      expect(s.accents, AccentStrictness.strict);
      expect(s.sourceLang, 'nl');
      expect(s.reduceMotion, isTrue);
      expect(container.read(reduceMotionProvider), isTrue);
      expect(container.read(fxProvider).enabled, isFalse);
    });

    testWidgets('default focus setting is used when tapping a node', (tester) async {
      await pumpApp(tester, store: TestProgressStore(settings: {SettingKeys.defaultFocus: 'vocab'}));
      await tapKey(tester, 'skill-node-greetings');
      final req = tester.widget<PlayerScreen>(find.byType(PlayerScreen)).request as LessonRequest;
      expect(req.focus, LessonFocus.vocab);
    });

    testWidgets('source language choices are limited to the course translations', (tester) async {
      await pumpApp(
        tester,
        size: const Size(400, 1200),
        store: TestProgressStore(settings: {SettingKeys.course: 'nl', SettingKeys.sourceLang: 'nl'}),
      );
      await goTab(tester, 'Settings');
      expect(find.byKey(const ValueKey('setting-source-lang-English')), findsOneWidget);
      expect(find.byKey(const ValueKey('setting-source-lang-Nederlands')), findsNothing);
      expect(find.text('This course only has English'), findsOneWidget);
    });

    testWidgets('switching course in settings', (tester) async {
      final store = await pumpApp(tester, size: const Size(400, 1200));
      await goTab(tester, 'Settings');
      await tapKey(tester, 'course-nl');
      expect(store.settings[SettingKeys.course], 'nl');
      await goTab(tester, 'Map');
      expect(find.byKey(const ValueKey('skill-node-presens')), findsOneWidget);
    });

    test('AppSettings load falls back to defaults for unknown values', () async {
      final store = TestProgressStore(settings: {SettingKeys.themeMode: 'neon', SettingKeys.defaultFocus: ''});
      final s = await AppSettings.load(store);
      expect(s, const AppSettings());
    });

    test('effectiveSourceLang', () {
      const meta = CourseMeta(
        id: 'x',
        version: '1',
        title: {},
        target: 'x',
        translations: ['nl'],
        persons: [],
        tenses: [],
      );
      expect(effectiveSourceLang('en', meta), 'nl');
      expect(effectiveSourceLang('nl', meta), 'nl');
      expect(effectiveSourceLang('en', null), 'en');
    });
  });

  testWidgets('wide layout uses a navigation rail; debug screen opens from settings', (tester) async {
    await pumpApp(tester, size: const Size(1280, 800));
    expect(find.byKey(const ValueKey('nav-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-nav')), findsNothing);
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-debug')),
      300,
      scrollable: find.descendant(of: find.byKey(const ValueKey('settings-list')), matching: find.byType(Scrollable)),
    );
    await tapKey(tester, 'open-debug');
    expect(find.text('Debug'), findsWidgets);
    expect(find.textContaining('present-are'), findsOneWidget);
  });

  testWidgets('app builds with the default (unoverridden) providers', (tester) async {
    setSurface(tester, const Size(400, 800));
    await tester.pumpWidget(const ProviderScope(child: ToskApp()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skill-node-greetings')), findsOneWidget);
  });
}
