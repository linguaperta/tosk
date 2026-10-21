// Tosk (the "continue here" marker) never covers a topic branch's "Go to …"
// button on the real restructured courses (docs/topic-split.md): many topics
// grow from early main-tree skills, so the learner's current stone often has a
// branch just above it. For a learner at every main-tree skill in turn (every
// earlier one started), on a phone-wide map with real fonts.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/widgets.dart' show SizedBox, Size, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import '../engine/real_packs.dart';
import '../fixtures/topic_course.dart' show TopicCourseCatalog;
import '../qa/brand_preview.dart' show loadQaFonts;
import 'helpers.dart';

Map<String, SkillStats> _upTo(CourseTrees trees, int stop) => {
  for (final (i, s) in trees.mainSkills.indexed)
    s.id: i < stop
        ? SkillStats(tier: MapTier.bronze, strength: 0.8, lastPracticed: testNow, practicedFacets: 10, totalFacets: 10)
        : SkillStats(tier: i == stop ? MapTier.available : MapTier.locked),
  for (final t in trees.topics)
    for (final s in trees.skillsOf(t.id)) s.id: const SkillStats(tier: MapTier.locked),
};

void main() {
  // real fonts (Roboto, Gelasio): the buttons as wide as on a phone
  setUpAll(loadQaFonts);

  for (final id in bundledPackIds()) {
    final path = 'assets/courses/$id.sqlite';
    testWidgets('real pack $id: Tosk keeps clear of the topic buttons', (tester) async {
      final course = loadCourseFile(path);
      final trees = CourseTrees.of(course);
      final problems = <String>[];
      for (final (i, s) in trees.mainSkills.indexed) {
        await tester.pumpWidget(const SizedBox()); // a fresh ProviderScope for each learner
        await pumpApp(
          tester,
          size: const Size(390, 844),
          store: TestProgressStore(settings: {SettingKeys.coursesAdded: id}),
          overrides: [
            courseCatalogProvider.overrideWithValue(TopicCourseCatalog(course)),
            skillStatsProvider.overrideWith((ref) async => _upTo(trees, i)),
          ],
        );
        final marker = find.byKey(const ValueKey('tosk-marker'));
        await tester.ensureVisible(marker);
        await tester.pumpAndSettle();
        final origin = tester.getTopLeft(find.byKey(const ValueKey('map-content')));
        final m = tester.getRect(marker).shift(-origin);
        for (final t in trees.topics) {
          final go = find.byKey(ValueKey('topic-go-${t.id}'));
          if (go.evaluate().isEmpty) continue;
          final b = tester.getRect(go).shift(-origin);
          final overlap = m.intersect(b);
          if (overlap.width > 2 && overlap.height > 2) problems.add('at ${s.id}: Tosk $m covers Go to ${t.id} $b');
        }
      }
      expect(problems, isEmpty);
    }, skip: !File(path).existsSync());
  }
}
