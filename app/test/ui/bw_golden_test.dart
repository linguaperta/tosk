// Golden images of key screens in black & white (e-ink) mode, so visual
// regressions show up in review. Rendered with the test font (Ahem: glyphs are
// boxes), which keeps them stable across machines; layout, borders, marks and
// patterns are what they guard. Update with:
//   flutter test --update-goldens test/ui/bw_golden_test.dart
import 'package:tosk/core/core.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _bw = {SettingKeys.display: 'bw'};

Future<TestProgressStore> _seeded() async {
  final store = TestProgressStore(settings: _bw);
  await seedDemoProgress(store, buildDemoItalian(), testNow);
  return store;
}

Future<void> _golden(WidgetTester tester, String name) =>
    expectLater(find.byKey(appRootKey), matchesGoldenFile('goldens/bw_$name.png'));

void main() {
  final allSkills = buildDemoItalian().skills.map((s) => s.id).toList();

  testWidgets('map', (tester) async {
    await pumpApp(tester, store: await _seeded());
    await _golden(tester, 'map');
  });

  testWidgets('progress', (tester) async {
    await pumpApp(tester, store: await _seeded(), initialLocation: Routes.progress);
    await _golden(tester, 'progress');
  });

  testWidgets('settings', (tester) async {
    await pumpApp(tester, store: TestProgressStore(settings: _bw), initialLocation: Routes.settings);
    await _golden(tester, 'settings');
  });

  for (final type in [
    ExerciseType.multipleChoice,
    ExerciseType.conjGrid,
    ExerciseType.sentenceBuilder,
    ExerciseType.spotError,
  ]) {
    testWidgets('${type.id}: question and wrong answer', (tester) async {
      await pumpApp(
        tester,
        store: TestProgressStore(settings: _bw),
        initialLocation: Routes.labPlay(skills: allSkills, types: [type], length: 1),
      );
      await _golden(tester, type.id);
      await answerCurrentNoContinue(tester, wrong: true);
      await _golden(tester, '${type.id}_wrong');
    });
  }
}
