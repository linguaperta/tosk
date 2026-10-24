// Review screenshots of the real courses' topics with real fonts (no `_test`
// suffix, so not in the default run):
//   QA_OUT=<dir> [QA_RATIO=1] flutter test test/qa/topics_real_preview.dart
// Uses the bundled packs (app/assets/courses/{it,nl}.sqlite, pack format 1.2
// with the split of docs/topic-split.md) at phone width, in colour and black
// & white: the Italian main tree around the "Crime and investigation" branch
// (locked: the passato remoto isn't started yet; and open), the Dutch main
// tree around the "Clothes" branch, the Italian topic's own tree with its
// locked skill and its "needs …" note, that skill's sheet, and the tree menu.
// The committed renders are in docs/screenshots/topics-real/.
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
import 'topics_preview.dart' show scrollToTopicBranch;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa-topics-real');
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

/// A learner who has worked through the main tree up to [upTo] (exclusive):
/// medals and some fading early on, started near the end; [upTo] itself is
/// available (Tosk sits there) when [startUpTo] is false, else started; every
/// later skill locked. Topic skills follow their prerequisites.
Map<String, SkillStats> _progress(CourseData course, String upTo, {bool startUpTo = false}) {
  final trees = CourseTrees.of(course);
  final main = trees.mainSkills;
  final stop = main.indexWhere((s) => s.id == upTo);
  final out = <String, SkillStats>{};
  for (final (i, s) in main.indexed) {
    if (i < stop) {
      final f = i / stop;
      out[s.id] = f < 0.85
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
      out[s.id] = startUpTo
          ? SkillStats(tier: MapTier.started, strength: 0.3, lastPracticed: testNow, practicedFacets: 3, totalFacets: 20)
          : const SkillStats(tier: MapTier.available);
    } else {
      out[s.id] = const SkillStats(tier: MapTier.locked);
    }
  }
  for (final t in trees.topics) {
    for (final s in trees.skillsOf(t.id)) {
      final open = s.requires.every((r) => (out[r]?.tier.index ?? 0) >= MapTier.started.index);
      out[s.id] = SkillStats(tier: open ? MapTier.available : MapTier.locked);
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

/// Scrolls the main map so the topic's carving sits [above] px from the top.
Future<void> _scrollTo(WidgetTester tester, String id, {double above = 290}) =>
    scrollToTopicBranch(tester, id, above: above);

void main() {
  setUpAll(loadQaFonts);

  for (final (mode, settings) in [('colour', <String, String>{}), ('bw', {SettingKeys.display: 'bw'})]) {
    testWidgets('it main tree, branch locked, $mode', (tester) async {
      await _pump(tester, 'it', _progress(_course('it'), 'passato-remoto'), settings);
      await _scrollTo(tester, 'crimine');
      await _shot(tester, 'it-main-locked-$mode');
    });

    testWidgets('it main tree, branch open, $mode', (tester) async {
      await _pump(tester, 'it', _progress(_course('it'), 'passato-remoto', startUpTo: true), settings);
      await _scrollTo(tester, 'crimine');
      await _shot(tester, 'it-main-open-$mode');
    });

    testWidgets('nl main tree, $mode', (tester) async {
      await _pump(tester, 'nl', _progress(_course('nl'), 'city', startUpTo: true), settings);
      await _scrollTo(tester, 'kleding');
      await _shot(tester, 'nl-main-$mode');
    });

    testWidgets('it topic tree with a locked skill, $mode', (tester) async {
      await _pump(tester, 'it', _progress(_course('it'), 'passato-remoto'), settings);
      await tapKey(tester, 'tree-selector');
      await tapKey(tester, 'tree-item-crimine');
      expect(find.byKey(const ValueKey('skill-needs-crime')), findsOneWidget);
      await _shot(tester, 'it-topic-locked-$mode');
      await tapKey(tester, 'skill-node-crime');
      await _shot(tester, 'it-topic-sheet-$mode');
    });

    testWidgets('it topic tree open, $mode', (tester) async {
      await _pump(tester, 'it', _progress(_course('it'), 'passato-remoto', startUpTo: true), settings);
      await tapKey(tester, 'tree-selector');
      await tapKey(tester, 'tree-item-crimine');
      expect(find.byKey(const ValueKey('skill-needs-crime')), findsNothing);
      await _shot(tester, 'it-topic-open-$mode');
    });

    testWidgets('it tree menu, $mode', (tester) async {
      await _pump(tester, 'it', _progress(_course('it'), 'passato-remoto', startUpTo: true), settings);
      await tester.tap(find.byKey(const ValueKey('tree-selector')));
      await tester.pumpAndSettle();
      await _shot(tester, 'it-menu-$mode');
    });
  }
}
