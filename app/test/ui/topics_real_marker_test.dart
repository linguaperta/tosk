// Every topic branch carries its name, and Tosk (the "continue here" marker)
// never covers a topic branch's carving on the real restructured courses (docs/topic-split.md): many topics
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
import 'package:tosk/ui/map/skill_map_view.dart' show MapPlan, SkillMapView;
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
  // real fonts (Roboto, Gelasio): the carvings as long as on a phone
  setUpAll(loadQaFonts);

  for (final id in bundledPackIds()) {
    final path = 'assets/courses/$id.sqlite';
    testWidgets('real pack $id: every branch carries its name; Tosk keeps clear of the carvings', (tester) async {
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
        final plan = (tester.state(find.byType(SkillMapView)) as dynamic).plan as MapPlan;
        // With no button any more the carving is the branch's only name: every branch has one.
        if (i == 0) {
          for (final b in plan.branches) {
            if (b.carving?.text.isNotEmpty != true) problems.add('${b.branch.id}: no name carved on its branch');
          }
          expect(plan.branches.length, trees.topics.length);
        }
        for (final b in plan.branches) {
          final c = b.carving;
          if (c == null) continue;
          final overlap = m.intersect(c.bounds);
          if (overlap.width > 2 && overlap.height > 2) problems.add('at ${s.id}: Tosk $m covers ${b.branch.id} ${c.bounds}');
        }
      }
      expect(problems, isEmpty);
    }, skip: !File(path).existsSync());
  }
}
