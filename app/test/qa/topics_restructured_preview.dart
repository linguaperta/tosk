// Review screenshots of the restructured courses (docs/topic-split.md: a slim
// main tree plus themed topics) with real fonts (no `_test` suffix, so not in
// the default run):
//   QA_OUT=<dir> [QA_RATIO=1] flutter test test/qa/topics_restructured_preview.dart
// Uses the bundled packs (app/assets/courses/{it,nl,es}.sqlite) at phone width,
// in colour and black & white: each course's main tree at the stretches where
// several topic branches grow (a learner partway through the course: earlier
// branches open, later ones locked), one topic's own tree, and the tree menu.
// The committed renders are in docs/screenshots/topics-restructured/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import '../fixtures/topic_course.dart' show TopicCourseCatalog;
import '../ui/helpers.dart';
import 'brand_preview.dart' show loadQaFonts;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-topics-restructured');
final _ratio = double.tryParse(Platform.environment['QA_RATIO'] ?? '') ?? 2;
const _phone = Size(390, 844);

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(appRootKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    _out.createSync(recursive: true);
    File('${_out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

final Map<String, CourseData> _courses = {};

CourseData _course(String id) => _courses[id] ??= () {
  final db = sqlite3.open('assets/courses/$id.sqlite', mode: OpenMode.readOnly);
  try {
    return loadCourseFromSqlite(db);
  } finally {
    db.close();
  }
}();

/// A learner who has worked through the main tree up to [upTo] (exclusive,
/// [upTo] itself started): medals early on, started near the end, every later
/// skill locked. Topic skills are available once their prerequisites are
/// started; the first skill of the first two open topics is started too.
Map<String, SkillStats> _progress(CourseData course, String upTo) {
  final trees = CourseTrees.of(course);
  final main = trees.mainSkills;
  final stop = main.indexWhere((s) => s.id == upTo);
  final out = <String, SkillStats>{};
  for (final (i, s) in main.indexed) {
    if (i < stop) {
      out[s.id] = i / stop < 0.85
          ? SkillStats(
              tier: const [MapTier.gold, MapTier.silver, MapTier.bronze, MapTier.silver][i % 4],
              strength: 0.85,
              lastPracticed: testNow.subtract(Duration(days: 1 + i % 9)),
              fading: (i % 5) * 0.12,
              practicedFacets: 20,
              totalFacets: 20,
            )
          : SkillStats(
              tier: MapTier.started,
              strength: 0.5,
              lastPracticed: testNow.subtract(Duration(days: i % 3)),
              practicedFacets: 8,
              totalFacets: 20,
            );
    } else if (i == stop) {
      out[s.id] = SkillStats(tier: MapTier.started, strength: 0.3, lastPracticed: testNow, practicedFacets: 3, totalFacets: 20);
    } else {
      out[s.id] = const SkillStats(tier: MapTier.locked);
    }
  }
  var startedTopics = 0;
  for (final t in trees.topics) {
    for (final (i, s) in trees.skillsOf(t.id).indexed) {
      final open = s.requires.every((r) => (out[r]?.tier.index ?? 0) >= MapTier.started.index);
      if (open && i == 0 && startedTopics < 2) {
        startedTopics++;
        out[s.id] = SkillStats(tier: MapTier.bronze, strength: 0.8, lastPracticed: testNow, practicedFacets: 20, totalFacets: 20);
      } else {
        out[s.id] = SkillStats(tier: open ? MapTier.available : MapTier.locked);
      }
    }
  }
  return out;
}

Future<void> _pump(WidgetTester tester, String courseId, Map<String, SkillStats> stats, Map<String, String> settings) =>
    pumpApp(
      tester,
      size: _phone,
      store: TestProgressStore(settings: {SettingKeys.coursesAdded: courseId, ...settings}),
      overrides: [
        courseCatalogProvider.overrideWithValue(TopicCourseCatalog(_course(courseId))),
        skillStatsProvider.overrideWith((ref) async => stats),
      ],
    );

/// Scrolls the main map so the topic's "Go to" button sits [above] px from the top.
Future<void> _scrollTo(WidgetTester tester, String key, {double above = 330}) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  final y = tester.getTopLeft(f).dy;
  await tester.drag(find.byKey(const ValueKey('map-scroll')), Offset(0, -(y - above)));
  await tester.pumpAndSettle();
}

/// (course, learner's current skill, [(shot name, topic whose "Go to" button to centre, offset)],
/// topic tree to show)
const _plans = [
  ('it', 'imperfetto', [('a', 'salute', 300.0), ('b', 'moda', 360.0), ('c', 'servizi', 380.0), ('d', 'crimine', 420.0)], 'natura'),
  ('nl', 'verleden-tijd-weak', [('a', 'gezondheid', 330.0), ('b', 'natuur', 420.0)], 'kleding'),
  ('es', 'indefinido', [('a', 'salud', 330.0), ('b', 'cocina', 360.0), ('c', 'naturaleza', 420.0)], 'compras'),
];

void main() {
  setUpAll(loadQaFonts);

  for (final (mode, settings) in [('colour', <String, String>{}), ('bw', {SettingKeys.display: 'bw'})]) {
    for (final (course, upTo, mains, topic) in _plans) {
      for (final (name, branch, above) in mains) {
        testWidgets('$course main tree $name ($branch), $mode', (tester) async {
          await _pump(tester, course, _progress(_course(course), upTo), settings);
          await _scrollTo(tester, 'topic-go-$branch', above: above);
          await _shot(tester, '$course-main-$name-$mode');
        });
      }

      testWidgets('$course topic tree $topic, $mode', (tester) async {
        await _pump(tester, course, _progress(_course(course), upTo), settings);
        await tapKey(tester, 'tree-selector');
        await tapKey(tester, 'tree-item-$topic');
        await _shot(tester, '$course-topic-$topic-$mode');
      });

      testWidgets('$course tree menu, $mode', (tester) async {
        await _pump(tester, course, _progress(_course(course), upTo), settings);
        await tester.tap(find.byKey(const ValueKey('tree-selector')));
        await tester.pumpAndSettle();
        await _shot(tester, '$course-menu-$mode');
      });
    }
  }
}
