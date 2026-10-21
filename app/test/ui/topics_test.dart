// Topic trees (schema minor 3; docs/extensions.md, docs/ui.md "Topic trees"):
// the course model and loader, the branch planner, and the map: branches with
// a carved name and "Go to …" on the main tree, a topic's own map with its
// root, the tree selector, per-tree scroll positions, "already known" words,
// black & white, reduce motion and phone to desktop widths.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:tosk/ui/map/skill_map_view.dart';
import 'package:tosk/ui/map/topic_branch.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import '../fixtures/course_fixture.dart';
import '../fixtures/topic_course.dart';
import '../qa/topics_preview.dart' show topicStats;
import 'bw_helpers.dart';
import 'helpers.dart';

Future<TestProgressStore> _pump(WidgetTester tester, {Size size = const Size(390, 844), Map<String, String> settings = const {}}) =>
    pumpApp(
      tester,
      size: size,
      store: TestProgressStore(settings: {SettingKeys.coursesAdded: 'it', ...settings}),
      overrides: [
        courseCatalogProvider.overrideWithValue(TopicCourseCatalog()),
        skillStatsProvider.overrideWith((ref) async => topicStats()),
      ],
    );

SkillMapView _mapView(WidgetTester tester) => tester.widget<SkillMapView>(find.byType(SkillMapView));

void main() {
  group('course trees', () {
    final course = topicCourse();
    final trees = CourseTrees.of(course);

    test('the main tree first, then each topic', () {
      expect(trees.mainUnits.map((u) => u.id), ['u1', 'u2', 'u3']);
      expect(trees.unitsOf('cucina').map((u) => u.id), ['cucina-u1', 'cucina-u2']);
      expect(trees.skillsOf(null).map((s) => s.id), contains('city-life'));
      expect(trees.skillsOf(null).map((s) => s.id), isNot(contains('cooking')));
      expect(trees.skillsOf('viaggi').map((s) => s.id), ['station', 'hotel', 'sights']);
      expect(trees.treeOf('recipes'), 'cucina');
      expect(trees.treeOf('home'), isNull);
      expect(trees.byAnchor.keys, unorderedEquals(['food-basics', 'city-life']));
      expect(trees.topic('cucina')!.shortTitleIn('en'), 'Food');
    });

    test('a topic skill shares facets with the main tree: introduced there first', () {
      // pane is in food-basics (main) and cooking (topic): course order puts the main tree first.
      expect(CourseIndex.of(course).introducingSkill('it:pane#rec'), 'food-basics');
      expect(CourseIndex.of(course).introducingSkill('it:pentola#rec'), 'cooking');
    });

    test('the short title falls back to the first word', () {
      const t = Topic(id: 'x', ord: 0, title: {'en': 'Football, fans and stadiums'}, anchor: 'a');
      expect(t.shortTitleIn('en'), 'Football');
    });

    test('the main map lays out the main tree only; a topic map hangs from its anchor', () {
      final main = layoutSkillMap(trees.mainUnits, trees.mainSkills);
      expect(main.node('cooking'), isNull);
      final topic = trees.topic('cucina')!;
      final skills = topicMapSkills(trees, topic);
      final l = layoutSkillMap([const Unit(id: kTopicRootUnit, ord: -1, title: {}), ...trees.unitsOf('cucina')], skills);
      expect(l.node('food-basics')!.band, 0);
      expect(l.edges, containsAll([const MapEdge('food-basics', 'cooking'), const MapEdge('food-basics', 'market')]));
      expect(l.edges, contains(const MapEdge('cooking', 'restaurant')));
    });
  });

  group('loader', () {
    test('reads topics and topic units (schema minor 3)', () {
      final db = openFixtureCourseDb(overrideMeta: {'schema_minor': '3'});
      db.execute("INSERT INTO units(id, ord, title) VALUES ('t-u1', 9, '{\"en\":\"In the kitchen\"}')");
      db.execute("INSERT INTO skills(id, unit_id, ord, kind, title) VALUES ('t-cook', 't-u1', 0, 'vocab', '{\"en\":\"Cooking\"}')");
      db.execute("INSERT INTO skill_requires(skill_id, requires_id) VALUES ('t-cook', 'food')");
      db.execute("INSERT INTO topics(id, ord, title, short_title, description, icon, anchor) VALUES "
          "('cucina', 0, '{\"en\":\"Food and cooking\"}', '{\"en\":\"Food\"}', '{}', 'food', 'food')");
      db.execute("INSERT INTO topic_units(unit_id, topic_id) VALUES ('t-u1', 'cucina')");
      final c = loadCourseFromSqlite(db);
      db.close();
      expect(c.topics.single.id, 'cucina');
      expect(c.topics.single.anchor, 'food');
      expect(c.topics.single.shortTitle, {'en': 'Food'});
      expect(c.units.last.topic, 'cucina');
      expect(c.units.first.topic, isNull);
      final trees = CourseTrees.of(c);
      expect(trees.mainSkills.map((s) => s.id), isNot(contains('t-cook')));
      expect(trees.skillsOf('cucina').single.id, 't-cook');
    });

    test('a pack without topic tables has one tree', () {
      final db = sqlite3.openInMemory();
      populateFixtureCourse(db);
      db.execute('DROP TABLE topic_units');
      db.execute('DROP TABLE topics');
      final c = loadCourseFromSqlite(db);
      db.close();
      expect(c.topics, isEmpty);
      expect(CourseTrees.of(c).hasTopics, isFalse);
      expect(CourseTrees.of(c).mainSkills.length, c.skills.length);
    });
  });

  group('branch lanes', () {
    final layout = layoutSkillMap(
      [const Unit(id: 'u', ord: 0, title: {})],
      [
        const Skill(id: 'a', unitId: 'u', ord: 0, kind: SkillKind.vocab, title: {}),
        const Skill(id: 'b', unitId: 'u', ord: 1, kind: SkillKind.vocab, title: {}, requires: ['a']),
      ],
    );
    TopicBranch t(String id, String anchor) => TopicBranch(id: id, anchor: anchor, title: id, shortTitle: id);

    test('topics of one anchor alternate sides, starting with the roomier one', () {
      final lanes = planBranchLanes(
        layout: layout,
        branches: [t('x', 'a'), t('y', 'a'), t('z', 'a')],
        centerX: (n) => 100,
        width: 400,
        maxRun: 300,
      );
      expect([for (final l in lanes) l.side], [1, -1, 1]);
      expect([for (final l in lanes) l.lane], [0, 0, 1]);
      expect(branchLaneCounts(lanes).values.single, 2);
    });

    test('a branch whose anchor is unknown is left out', () {
      expect(planBranchLanes(layout: layout, branches: [t('x', 'nope')], centerX: (n) => 0, width: 400, maxRun: 300), isEmpty);
    });
  });

  group('map', () {
    testWidgets('the main tree has a branch per topic with a carving and a Go to button', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      final view = _mapView(tester);
      expect(view.branches.map((b) => b.id), ['cucina', 'viaggi']);
      expect(view.branches.firstWhere((b) => b.id == 'cucina').locked, isFalse);
      expect(view.branches.firstWhere((b) => b.id == 'viaggi').locked, isTrue); // city-life not started
      for (final id in ['cucina', 'viaggi']) {
        await tester.ensureVisible(find.byKey(ValueKey('topic-go-$id')));
        await tester.pumpAndSettle();
        final size = tester.getSize(find.byKey(ValueKey('topic-go-$id')));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(find.bySemanticsLabel(RegExp(r'^Go to Food and cooking, topic, 1 of 4 skills started$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Go to Travel and holidays, topic, .*, opens after')), findsOneWidget);
      // The carving is in the bough tiles, with the full title where it fits.
      final state = tester.state(find.byType(SkillMapView)) as dynamic;
      final plan = state.plan as MapPlan;
      expect(plan.branches, hasLength(2));
      // The full title where it fits, else the short one (the test font's glyphs are wide).
      final carving = plan.branches.first.carving!;
      expect(carving.text, anyOf('Food and cooking', 'Food'));
      expect(carving.glyphs.length, carving.text.replaceAll(' ', '').length);
      expect(find.byKey(const ValueKey('topic-carving-cucina')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Go to opens the topic map; its root leads back; each tree keeps its scroll', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      final scroll = find.byKey(const ValueKey('map-scroll'));
      await tester.ensureVisible(find.byKey(const ValueKey('topic-go-cucina')));
      await tester.pumpAndSettle();
      final mainOffset = tester.state<ScrollableState>(find.descendant(of: scroll, matching: find.byType(Scrollable))).position.pixels;
      expect(mainOffset, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey('topic-go-cucina')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-scroll-cucina')), findsOneWidget);
      expect(find.text('From Italian · Food basics'), findsOneWidget);
      expect(find.byKey(const ValueKey('tree-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('skill-node-cooking')), findsOneWidget);
      expect(find.byKey(const ValueKey('skill-node-city')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Back to the Italian main tree')), findsOneWidget);
      expect(_mapView(tester).branches, isEmpty);

      // Back through the root: the main tree, where it was.
      await tester.tap(find.byKey(const ValueKey('skill-node-food-basics')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-scroll')), findsOneWidget);
      final back = tester.state<ScrollableState>(
          find.descendant(of: find.byKey(const ValueKey('map-scroll')), matching: find.byType(Scrollable)));
      expect(back.position.pixels, closeTo(mainOffset, 1));
      handle.dispose();
    });

    testWidgets('the tree selector lists the main tree first, then the topics with progress', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('tree-selector')));
      await tester.pumpAndSettle();
      final main = tester.getTopLeft(find.byKey(const ValueKey('tree-item-main'))).dy;
      final food = tester.getTopLeft(find.byKey(const ValueKey('tree-item-cucina'))).dy;
      final travel = tester.getTopLeft(find.byKey(const ValueKey('tree-item-viaggi'))).dy;
      expect(main < food && food < travel, isTrue);
      expect(find.text('Main tree'), findsOneWidget);
      expect(find.text('Topic · 1 of 4 skills started'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tree-item-viaggi')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-scroll-viaggi')), findsOneWidget);
      expect(find.text('From Italian · City life'), findsOneWidget);
    });

    testWidgets('a topic skill sheet says how many words are already known', (tester) async {
      final store = await _pump(tester);
      final course = topicCourse();
      // pane and sale known: pane from the main tree, sale from recipes (another skill).
      for (final f in ['it:pane#rec', 'it:sale#prod']) {
        await tester.runAsync(() => store.record(ReviewEvent(
              id: f,
              facetId: f,
              at: testNow,
              rating: Rating.good,
              correct: true,
              exerciseType: 'flashcard',
              responseMs: 1000,
              inputMode: InputMode.tap,
              mode: 'lesson',
            )));
      }
      expect(course.skillItems('cooking').length, 5);
      await tapKey(tester, 'topic-go-cucina');
      await tapKey(tester, 'skill-node-cooking');
      expect(find.text('Food and cooking · 2 of 5 words already known'), findsOneWidget);
    });

    for (final (name, size) in [('320', const Size(320, 640)), ('412', const Size(412, 915)), ('desktop', const Size(1280, 860))]) {
      testWidgets('no overflow and every branch reachable at $name', (tester) async {
        await _pump(tester, size: size);
        expect(tester.takeException(), isNull);
        final state = tester.state(find.byType(SkillMapView)) as dynamic;
        final plan = state.plan as MapPlan;
        for (final b in plan.branches) {
          // The carving stays inside the map and the button fits its lane.
          if (b.carving case final c?) {
            expect(c.bounds.left, greaterThanOrEqualTo(-1));
            expect(c.bounds.right, lessThanOrEqualTo(plan.geometry.width + 1));
          }
          await tester.ensureVisible(find.byKey(ValueKey('topic-go-${b.branch.id}')));
          await tester.pumpAndSettle();
          final r = tester.getRect(find.byKey(ValueKey('topic-go-${b.branch.id}')));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(size.width + 0.5));
        }
        // On wide maps the branches fade out instead of running to the edge.
        if (size.width >= 1000) expect(plan.branches.any((b) => b.fade != null), isTrue);
        if (size.width <= 412) expect(plan.branches.every((b) => b.fade == null), isTrue);
      });
    }

    testWidgets('black & white: only black, white and gray, also on a topic map', (tester) async {
      await _pump(tester, settings: {SettingKeys.display: 'bw'});
      await tester.ensureVisible(find.byKey(const ValueKey('topic-go-cucina')));
      await tester.pumpAndSettle();
      await expectGrayscale(tester, 'main tree with a topic branch');
      await tapKey(tester, 'topic-go-cucina');
      await expectGrayscale(tester, 'topic map');
    });

    testWidgets('reduce motion: no map ticker, branches static', (tester) async {
      await _pump(tester, settings: {SettingKeys.reduceMotion: 'true'});
      final state = tester.state(find.byType(SkillMapView)) as dynamic;
      expect(state.ticking as bool, isFalse);
      expect((state.plan as MapPlan).branches, hasLength(2));
    });

    testWidgets('a course without topics keeps the plain title and no branches', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const ValueKey('tree-selector')), findsNothing);
      expect(find.byKey(const ValueKey('course-title')), findsOneWidget);
      expect(_mapView(tester).branches, isEmpty);
    });
  });

  test('the carving style is the storybook serif', () {
    final s = carvingTextStyle(14);
    expect(s.fontFamily, 'Gelasio');
    expect(s.fontWeight, FontWeight.w700);

  });
}
