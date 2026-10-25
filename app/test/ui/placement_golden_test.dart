// Golden images of placement: "New to Italian?", the test's progress line,
// the result card, "Skip ahead" and the reset dialog, in black & white, and
// the choice and result in colour. Test font (Ahem), like bw_golden_test.dart.
// Update with:
//   flutter test --update-goldens test/ui/placement_golden_test.dart
// Rendered on Windows; CI (Linux) skips them with --exclude-tags golden.
@Tags(['golden'])
library;

import 'package:flutter/widgets.dart' show Size, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/engine/engine.dart' show FocusPresets;
import 'package:tosk/providers.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import 'helpers.dart';

Future<void> _golden(WidgetTester tester, String name) async {
  // Tosk's PNGs load on real futures.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
  await expectLater(find.byKey(appRootKey), matchesGoldenFile('goldens/placement_$name.png'));
}

Future<void> _pump(WidgetTester tester, Map<String, String> settings) => pumpApp(
  tester,
  size: const Size(390, 844),
  engine: true,
  store: TestProgressStore(fresh: true, settings: settings),
  overrides: [focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults)],
);

void main() {
  testWidgets('black & white', (tester) async {
    await _pump(tester, {SettingKeys.display: 'bw'});
    await tapKey(tester, 'course-add-it');
    await _golden(tester, 'bw_choice');
    await tapKey(tester, 'placement-find');
    expect(find.byKey(const ValueKey('placement-progress')), findsOneWidget);
    await answerCurrent(tester);
    await answerCurrent(tester);
    await tapKey(tester, 'placement-place-now');
    await tapKey(tester, 'place-now-confirm');
    await _golden(tester, 'bw_result');
    await tapKey(tester, 'summary-done');
    await goTab(tester, 'Settings');
    await tapKey(tester, 'find-level-again');
    await tapKey(tester, 'placement-skip');
    await tapKey(tester, 'skip-unit-u2');
    await _golden(tester, 'bw_skip_ahead');
    await tapKey(tester, 'skip-ahead-confirm');
    await tapKey(tester, 'skip-ahead-done');
    await goTab(tester, 'Map');
    await tapKey(tester, 'skill-node-food');
    await scrollToFind(tester, find.byKey(const ValueKey('skill-reset')));
    await tapKey(tester, 'skill-reset');
    await _golden(tester, 'bw_reset');
  });

  testWidgets('colour', (tester) async {
    await _pump(tester, const {});
    await tapKey(tester, 'course-add-it');
    await _golden(tester, 'choice');
    await tapKey(tester, 'placement-find');
    await answerCurrent(tester);
    await answerCurrent(tester);
    await tapKey(tester, 'placement-place-now');
    await tapKey(tester, 'place-now-confirm');
    await _golden(tester, 'result');
  });
}
