// v0.3.2 screens in black & white (pixel scan) and their layout (no overflow)
// at every e-ink harness size, plus color, dark and large text: the skill
// sheet opened by a tap (next tier, note and word list expanded), the
// per-language progress page with its account-wide streak section, the map's
// course title, and the match-pairs mix-ups after a wrong pair.
import 'package:tosk/core/core.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSizes;
import 'helpers.dart';

typedef Check = Future<void> Function(String what);

Future<TestProgressStore> _seeded(Map<String, String> settings) async {
  final store = TestProgressStore(settings: settings);
  await seedDemoProgress(store, buildDemoItalian(), testNow);
  return store;
}

Future<void> walk(WidgetTester tester, Size size, Map<String, String> settings, Check check) async {
  await pumpApp(tester, size: size, store: await _seeded(settings));
  expect(find.byKey(const ValueKey('course-title')), findsOneWidget);
  await check('map with the course title');
  await tapKey(tester, 'skill-node-greetings');
  expect(find.byKey(const ValueKey('skill-next-tier')), findsOneWidget);
  await check('skill sheet after a tap');
  await tapKey(tester, 'skill-words');
  await check('skill sheet: word list');
  await tester.pumpWidget(const SizedBox());

  await pumpApp(
    tester,
    size: size,
    store: await _seeded(settings),
    initialLocation: Routes.skill('present-are', section: 'note'),
  );
  await check('skill sheet: grammar note');
  await tester.pumpWidget(const SizedBox());

  await pumpApp(tester, size: size, store: await _seeded(settings), initialLocation: Routes.progress);
  expect(find.byKey(const ValueKey('progress-course')), findsOneWidget);
  await check('progress: course level');
  await scrollToFind(tester, find.byKey(const ValueKey('progress-streak')));
  await tester.ensureVisible(find.byKey(const ValueKey('progress-streak')));
  await tester.pumpAndSettle();
  await check('progress: streak and goal, all courses');
  await tester.pumpWidget(const SizedBox());

  final skills = buildDemoItalian().skills.map((s) => s.id).toList();
  await pumpApp(
    tester,
    size: size,
    store: TestProgressStore(settings: settings),
    initialLocation: Routes.labPlay(skills: skills, types: [ExerciseType.matchPairs], length: 1),
  );
  await answerCurrentNoContinue(tester, wrong: true);
  await scrollToFind(tester, find.byKey(const ValueKey('match-mixups')));
  expect(find.byKey(const ValueKey('match-mixups')), findsOneWidget);
  await check('match pairs: both cards of the wrong pair, mix-ups listed');
  await tester.pumpWidget(const SizedBox());
}

void main() {
  for (final entry in bwSizes.entries) {
    testWidgets('black & white ${entry.key}', (tester) async {
      await walk(tester, entry.value, {SettingKeys.display: 'bw'}, (what) async {
        await expectGrayscale(tester, what);
        expect(tester.takeException(), isNull, reason: what);
      });
    });
  }
  for (final size in const [Size(320, 568), Size(360, 640), Size(1280, 800)]) {
    testWidgets('color, dark, text 1.3 at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await walk(tester, size, {SettingKeys.themeMode: 'dark'}, (what) async {
        expect(tester.takeException(), isNull, reason: what);
      });
    });
  }
}
