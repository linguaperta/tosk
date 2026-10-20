// Golden images of key screens in black & white (e-ink) mode, so visual
// regressions show up in review. Rendered with the test font (Ahem: glyphs are
// boxes), which keeps them stable across machines; layout, borders, marks and
// patterns are what they guard. Update with:
//   flutter test --update-goldens test/ui/bw_golden_test.dart
// Pixel goldens are rendered on Windows; other platforms rasterise slightly differently,
// so CI (Linux) skips them with --exclude-tags golden.
@Tags(['golden'])
library;

import 'package:tosk/ai/ai_config.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'v04_bw_test.dart' show starredRepo;
import 'v04_extras_test.dart' show FakeTutorAi, settleAi, tutorOverrides;

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

  testWidgets('stats', (tester) async {
    await pumpApp(tester, store: await _seeded(), initialLocation: Routes.stats);
    await _golden(tester, 'stats');
  });

  testWidgets('starred', (tester) async {
    await pumpApp(
      tester,
      store: TestProgressStore(settings: _bw),
      initialLocation: Routes.starred,
      overrides: [bookmarkRepoProvider.overrideWithValue(await starredRepo())],
    );
    await _golden(tester, 'starred');
  });

  testWidgets('chat', (tester) async {
    final ai = FakeTutorAi();
    await pumpApp(
      tester,
      store: TestProgressStore(settings: {..._bw, AiSettingKeys.provider: 'anthropic'}),
      initialLocation: Routes.chats,
      overrides: tutorOverrides(ai),
    );
    await _golden(tester, 'chat_tab');
    await tester.tap(find.byKey(const ValueKey('chat-start')));
    await settleAi(tester);
    await tester.tap(find.byKey(const ValueKey('chat-translate-0')));
    await tester.pumpAndSettle();
    await _golden(tester, 'chat');
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
    // The option grid (ChoiceGrid): equal 2 x 2 tiles over the full width.
    ExerciseType.cloze,
    ExerciseType.conjPick,
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
