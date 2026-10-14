// The v0.3 screens in black & white (pixel scan) and their layout (no
// overflow) at every size of the e-ink harness, plus color, dark mode and
// large text on phones: reference (lookup, word page, grammar), practice tabs,
// course picker with a preview, the lesson sheet's length chooser and test
// out, word popovers, the test-out verdict and the tough-words entries.
import 'package:tosk/core/core.dart';
import 'package:tosk/ui/map/skill_sheet.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSizes, bwStore;
import 'helpers.dart';
import 'v03_features_test.dart' show seedLeech;

/// Scrolls [scrollable] to its end in steps.
Future<void> scrollDown(WidgetTester tester, Finder scrollable, {int steps = 4}) async {
  for (var i = 0; i < steps; i++) {
    await tester.drag(scrollable, const Offset(0, -400), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

Finder scrollableIn(String key) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Scrollable)).first;

/// Walks every new screen; [check] runs on each (grayscale and/or no overflow).
Future<void> walkScreens(WidgetTester tester, Future<void> Function(String what) check) async {
  await goTab(tester, 'Lookup');
  await check('lookup');
  await tester.enterText(find.byKey(const ValueKey('lookup-field')), 'mangi');
  await tester.pumpAndSettle();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
  await check('lookup results');
  await tapKey(tester, 'lookup-hit-it:mangiare');
  await check('word page');
  await scrollDown(tester, find.byKey(const ValueKey('word-list')));
  await check('word page (examples)');
  await tester.pageBack();
  await tester.pumpAndSettle();
  await goTab(tester, 'Grammar');
  await tapKey(tester, 'grammar-note-present-are');
  await check('grammar library');
  await scrollDown(tester, find.byKey(const ValueKey('grammar-list')));
  await check('grammar library (scrolled)');
  await goTab(tester, 'Non-stop');
  await check('practice: non-stop');
  await goTab(tester, 'Lab');
  await check('practice: lab');
  await goTab(tester, 'Progress');
  await scrollDown(tester, find.byKey(const ValueKey('progress-list')), steps: 2);
  await check('progress with tough words');
  await goTab(tester, 'Map');
  await tapKey(tester, 'course-switcher');
  await tapKey(tester, 'manage-courses');
  await tapKey(tester, 'course-preview-it');
  await check('course picker with preview');
  await scrollDown(tester, scrollableIn('course-picker'));
  await check('course picker (scrolled)');
  await tapKey(tester, 'course-picker-done');
  final node = find.byKey(const ValueKey('skill-node-present-are'));
  await tester.ensureVisible(node);
  await tester.pumpAndSettle();
  await tester.longPress(node);
  await tester.pumpAndSettle();
  expect(find.byType(SkillSheet), findsOneWidget);
  await check('skill sheet (length, test out)');
}

Future<TestProgressStore> storeWithLeech(Map<String, String> settings) async {
  final store = settings.isEmpty ? TestProgressStore() : await bwStore();
  await seedLeech(store, 'it:mangiare#form:presente');
  return store;
}

void main() {
  for (final entry in bwSizes.entries) {
    group('black & white ${entry.key}', () {
      testWidgets('reference, practice, progress, course picker, skill sheet', (tester) async {
        await pumpApp(tester, size: entry.value, store: await storeWithLeech({SettingKeys.display: 'bw'}));
        await walkScreens(tester, (what) async {
          await expectGrayscale(tester, what);
          expect(tester.takeException(), isNull, reason: what);
        });
      });

      testWidgets('word popovers and the test-out verdict', (tester) async {
        await pumpApp(
          tester,
          size: entry.value,
          store: TestProgressStore(settings: {SettingKeys.display: 'bw'}),
          initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
        );
        await tapKey(tester, 'word-0');
        await expectGrayscale(tester, 'popover');
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        await answerCurrentNoContinue(tester, wrong: true);
        await tapKey(tester, 'word-2');
        expect(find.byKey(const ValueKey('word-popover-reference')), findsOneWidget);
        await expectGrayscale(tester, 'popover after a wrong answer');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());

        await pumpApp(
          tester,
          size: entry.value,
          store: TestProgressStore(settings: {SettingKeys.display: 'bw'}),
          initialLocation: Routes.testOut('present-are'),
        );
        await playToSummary(tester);
        expect(find.byKey(const ValueKey('assessment-result')), findsOneWidget);
        await expectGrayscale(tester, 'test-out verdict');
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('color, dark and large text', () {
    for (final size in const [Size(320, 568), Size(360, 640), Size(1280, 800)]) {
      testWidgets('new screens at ${size.width.toInt()}x${size.height.toInt()}, text 1.3, dark', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = await storeWithLeech(const {});
        await store.setSetting(SettingKeys.themeMode, 'dark');
        await pumpApp(tester, size: size, store: store);
        await walkScreens(tester, (what) async => expect(tester.takeException(), isNull, reason: what));
      });
    }
  });
}
