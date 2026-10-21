// Golden images of topic trees: the main tree with its topic branches (the
// carving and "Go to …") and a topic's own map, in colour and black & white.
// Test font (Ahem), like bw_golden_test.dart. Update with:
//   flutter test --update-goldens test/ui/topics_golden_test.dart
// Rendered on Windows; CI (Linux) skips them with --exclude-tags golden.
@Tags(['golden'])
library;

import 'package:flutter/widgets.dart' show Offset, Size, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import '../fixtures/topic_course.dart';
import '../qa/topics_preview.dart' show topicStats;
import 'helpers.dart';

Future<void> _pump(WidgetTester tester, Map<String, String> settings) => pumpApp(
  tester,
  size: const Size(390, 844),
  store: TestProgressStore(settings: {SettingKeys.coursesAdded: 'it', ...settings}),
  overrides: [
    courseCatalogProvider.overrideWithValue(TopicCourseCatalog()),
    skillStatsProvider.overrideWith((ref) async => topicStats()),
  ],
);

Future<void> _toBranch(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('topic-go-cucina')));
  await tester.pumpAndSettle();
  await tester.drag(find.byKey(const ValueKey('map-scroll')), const Offset(0, -150));
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, settings) in [('colour', <String, String>{}), ('bw', {SettingKeys.display: 'bw'})]) {
    testWidgets('main tree with a topic branch, $name', (tester) async {
      await _pump(tester, settings);
      await _toBranch(tester);
      await expectLater(find.byKey(appRootKey), matchesGoldenFile('goldens/topics_main_$name.png'));
    });

    testWidgets('topic tree, $name', (tester) async {
      await _pump(tester, settings);
      await tapKey(tester, 'topic-go-cucina');
      await expectLater(find.byKey(appRootKey), matchesGoldenFile('goldens/topics_tree_$name.png'));
    });
  }
}
