// Topic trees (schema minor 3; docs/extensions.md, docs/ui.md "Topic trees"):
// the course model and loader, the branch planner, and the map: branches with
// a carved name on the main tree that open their topic (tap, press feedback,
// semantics, keyboard), a topic's own map with its root, the tree selector,
// per-tree scroll positions, "already known" words, black & white, reduce
// motion and phone to desktop widths.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:tosk/ui/map/skill_map_view.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/map/topic_branch.dart';
import 'package:tosk/ui/map/tree_selector.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/theme/bw_skin.dart' show kBwBlack;
import 'package:tosk/ui/theme/skin.dart' show MapInk;

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

MapPlan _plan(WidgetTester tester) => (tester.state(find.byType(SkillMapView)) as dynamic).plan as MapPlan;

BranchPlan _branch(WidgetTester tester, String id) => _plan(tester).branches.firstWhere((b) => b.branch.id == id);

/// A point of the map (map coordinates) on screen.
Offset _onScreen(WidgetTester tester, Offset mapPoint) =>
    tester.getTopLeft(find.byKey(const ValueKey('map-content'))) + mapPoint;

/// Scrolls topic [id]'s branch into view and returns where its carving is on screen.
Future<Offset> _showBranch(WidgetTester tester, String id) async {
  await tester.ensureVisible(find.byKey(ValueKey('topic-branch-$id')));
  await tester.pumpAndSettle();
  return _onScreen(tester, _branch(tester, id).tapPoint);
}

/// Opens topic [id] with a tap on its branch.
Future<void> _openTopic(WidgetTester tester, String id) async {
  await tester.tapAt(await _showBranch(tester, id));
  await tester.pumpAndSettle();
}

TopicBranchTargetState _target(WidgetTester tester, String id) =>
    tester.state<TopicBranchTargetState>(find.byKey(ValueKey('topic-branch-$id')));

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
      // recipes' late main-tree requirement (city) draws no bough to the root
      expect(l.edges.where((e) => e.to == 'recipes').map((e) => e.from), ['restaurant']);
    });

    test('late requirements: a topic skill may need a later main-tree skill', () {
      expect(trees.mainRequirements('recipes'), ['city']);
      expect(trees.mainRequirements('cooking'), ['food-basics']);
      expect(trees.mainRequirements('restaurant'), isEmpty);
      expect(trees.mainRequirements('city'), isEmpty);
      expect(trees.mainUnitNumber('city'), 3);
      expect(trees.mainUnitNumber('recipes'), isNull);
      final stats = topicStats();
      final need = topicSkillNeed(trees, 'recipes', stats)!;
      expect(need.skill.id, 'city');
      expect(topicNeedText(need, 'en'), 'The city · unit 3');
      // the topic's first skill waits for the anchor; open skills wait for nothing
      expect(topicSkillNeed(trees, 'station', stats)!.skill.id, 'city-life');
      expect(topicSkillNeed(trees, 'cooking', stats), isNull);
      expect(topicSkillNeed(trees, 'restaurant', stats), isNull); // locked by its own topic only
      expect(topicSkillNeed(trees, 'city', stats), isNull); // a main-tree skill
      // once city is started, recipes waits for restaurant only
      final started = {...stats, 'city': SkillStats(tier: MapTier.started, lastPracticed: testNow)};
      expect(topicSkillNeed(trees, 'recipes', started), isNull);
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
    testWidgets('the main tree has a branch per topic with a carving; the branch is the button', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      final view = _mapView(tester);
      expect(view.branches.map((b) => b.id), ['cucina', 'viaggi']);
      expect(view.branches.firstWhere((b) => b.id == 'cucina').locked, isFalse);
      expect(view.branches.firstWhere((b) => b.id == 'viaggi').locked, isTrue); // city-life not started
      for (final id in ['cucina', 'viaggi']) {
        await _showBranch(tester, id);
        // The tap band along the branch is at least 48 dp thick.
        final b = _branch(tester, id);
        expect(b.hitHalf * 2, greaterThanOrEqualTo(48));
        expect(b.hits(b.tapPoint), isTrue);
        final p = b.run.points[b.run.length * 3 ~/ 4];
        final n = b.run.normals[b.run.length * 3 ~/ 4];
        expect(b.hits(p + n * 23.5), isTrue);
        expect(b.hits(p - n * 23.5), isTrue);
        expect(b.hits(p + n * (b.hitHalf + 6)), isFalse);
      }
      expect(find.bySemanticsLabel(RegExp(r'^Go to Food and cooking, topic, 1 of 4 skills started$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Go to Travel and holidays, topic, .*, opens after')), findsOneWidget);
      final node = tester.getSemantics(find.byKey(const ValueKey('topic-branch-cucina')));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isFocused, isNot(ui.Tristate.none)); // focusable
      // No button any more: the carving says where it goes.
      final content = find.byKey(const ValueKey('map-content'));
      expect(find.descendant(of: content, matching: find.byType(OutlinedButton)), findsNothing);
      expect(find.descendant(of: content, matching: find.textContaining('Go to')), findsNothing);
      expect(find.byKey(const ValueKey('topic-go-cucina')), findsNothing);
      // The carving is in the bough tiles, with the full title where it fits.
      final state = tester.state(find.byType(SkillMapView)) as dynamic;
      final plan = state.plan as MapPlan;
      expect(plan.branches, hasLength(2));
      // The full title where it fits, else the short one (the test font's glyphs are wide).
      final carving = plan.branches.first.carving!;
      expect(carving.text, anyOf('Food and cooking', 'Food'));
      expect(carving.glyphs.length, carving.text.replaceAll(' ', '').length);
      handle.dispose();
    });

    testWidgets('a tap on the branch opens the topic map; its root leads back; each tree keeps its scroll', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      final scroll = find.byKey(const ValueKey('map-scroll'));
      final at = await _showBranch(tester, 'cucina');
      final mainOffset = tester.state<ScrollableState>(find.descendant(of: scroll, matching: find.byType(Scrollable))).position.pixels;
      expect(mainOffset, greaterThan(0));

      // Next to the branch (beyond its tap band) nothing opens.
      final b = _branch(tester, 'cucina');
      final i = b.run.length * 3 ~/ 4;
      await tester.tapAt(_onScreen(tester, b.run.points[i] + b.run.normals[i] * (b.hitHalf + 8)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-scroll')), findsOneWidget);

      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-scroll-cucina')), findsOneWidget);
      expect(find.text('From Italian · Food basics'), findsOneWidget);
      expect(find.byKey(const ValueKey('tree-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('skill-node-cooking')), findsOneWidget);
      expect(find.byKey(const ValueKey('skill-node-city')), findsNothing);
      // Tosk (on cooking, first row) never covers the unit title's plaque.
      expect(
        tester.getRect(find.byKey(const ValueKey('tosk-marker'))).overlaps(
            tester.getRect(find.byKey(const ValueKey('band-title-cucina-u1')))),
        isFalse,
      );
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

    testWidgets('a locked topic skill says what it needs from the main tree, and goes there', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _openTopic(tester, 'cucina');
      final note = find.byKey(const ValueKey('skill-needs-recipes'));
      await tester.ensureVisible(note);
      await tester.pumpAndSettle();
      expect(find.descendant(of: note, matching: find.text('needs The city')), findsOneWidget);
      expect(find.descendant(of: note, matching: find.text(' · unit 3')), findsOneWidget);
      expect(find.bySemanticsLabel('Needs The city, unit 3: go there in the main tree'), findsOneWidget);
      expect(find.byKey(const ValueKey('skill-needs-cooking')), findsNothing);
      expect(find.byKey(const ValueKey('skill-needs-restaurant')), findsNothing);
      // The note is inside the node's label room: no overlap with the next row.
      expect(tester.takeException(), isNull);
      await tester.tap(note);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-scroll')), findsOneWidget);
      final band = tester.getRect(find.byKey(const ValueKey('band-title-u3')));
      expect(band.top, inInclusiveRange(0, 300));
      handle.dispose();
    });

    testWidgets('the skill sheet of a locked topic skill names the main-tree skill and goes there', (tester) async {
      await _pump(tester);
      await _openTopic(tester, 'cucina');
      await tester.ensureVisible(find.byKey(const ValueKey('skill-node-recipes')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'skill-node-recipes');
      expect(find.text('Needs The city from unit 3 of the main tree. It opens once you have started it.'), findsOneWidget);
      // the other prerequisite (of the topic) is still recommended; the main-tree one isn't repeated
      expect(find.text('Recommended first: At the restaurant. You can start this one anyway.'), findsOneWidget);
      expect(find.text('Go to unit 3'), findsOneWidget);
      await tapKey(tester, 'skill-needs-go');
      expect(find.byKey(const ValueKey('skill-needs')), findsNothing);
      expect(find.byKey(const ValueKey('map-scroll')), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('band-title-u3'))).top, inInclusiveRange(0, 300));
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
      await _openTopic(tester, 'cucina');
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
          // The carving stays inside the map, the tap band fits its lane.
          if (b.carving case final c?) {
            expect(c.bounds.left, greaterThanOrEqualTo(-1));
            expect(c.bounds.right, lessThanOrEqualTo(plan.geometry.width + 1));
          }
          expect(b.hitHalf * 2 + 4, lessThanOrEqualTo(BranchMetrics(plan.geometry.diameter).laneHeight + 0.01));
          final at = await _showBranch(tester, b.branch.id);
          expect(at.dx, inInclusiveRange(0, size.width));
          expect(at.dy, inInclusiveRange(0, size.height));
        }
        // On wide maps the branches fade out instead of running to the edge.
        if (size.width >= 1000) expect(plan.branches.any((b) => b.fade != null), isTrue);
        if (size.width <= 412) expect(plan.branches.every((b) => b.fade == null), isTrue);
      });
    }

    testWidgets('pressing a branch shows the pressed look, which fades again', (tester) async {
      await _pump(tester);
      final at = await _showBranch(tester, 'cucina');
      expect(_target(tester, 'cucina').pressed, 0);
      final before = await _branchPixels(tester, 'cucina');
      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 150)); // past the press timeout
      await tester.pump(const Duration(milliseconds: 100));
      expect(_target(tester, 'cucina').pressed, 1);
      // The overlay paints: the branch looks lighter while pressed.
      final pressed = await _branchPixels(tester, 'cucina');
      expect(pressed, greaterThan(before + 3));
      await gesture.cancel(); // no tap: the look fades out
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_target(tester, 'cucina').pressed, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(_target(tester, 'cucina').pressed, 0);
      expect(find.byKey(const ValueKey('map-scroll')), findsOneWidget);
      expect(await _branchPixels(tester, 'cucina'), closeTo(before, 0.5));
    });

    testWidgets('black & white: only black, white and gray, also pressed and on a topic map', (tester) async {
      await _pump(tester, settings: {SettingKeys.display: 'bw'});
      final at = await _showBranch(tester, 'cucina');
      await expectGrayscale(tester, 'main tree with a topic branch');
      // Pressed: the branch turns black (inverted), at once, no grays fading.
      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 150));
      expect(_target(tester, 'cucina').pressed, 1);
      await expectGrayscale(tester, 'a pressed topic branch');
      await gesture.cancel();
      await tester.pump();
      expect(_target(tester, 'cucina').pressed, 0);
      await _openTopic(tester, 'cucina');
      await expectGrayscale(tester, 'topic map');
    });

    testWidgets('reduce motion: no map ticker, branches static, the pressed look without a fade', (tester) async {
      await _pump(tester, settings: {SettingKeys.reduceMotion: 'true'});
      final state = tester.state(find.byType(SkillMapView)) as dynamic;
      expect(state.ticking as bool, isFalse);
      expect((state.plan as MapPlan).branches, hasLength(2));
      final gesture = await tester.startGesture(await _showBranch(tester, 'cucina'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_target(tester, 'cucina').pressed, 1);
      await gesture.cancel();
      await tester.pump();
      expect(_target(tester, 'cucina').pressed, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('desktop: a branch takes the keyboard focus and Enter opens its topic', (tester) async {
      await _pump(tester, size: const Size(1280, 860));
      await _showBranch(tester, 'cucina');
      _target(tester, 'cucina').focusNode.requestFocus();
      await tester.pump();
      expect(_target(tester, 'cucina').focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-scroll-cucina')), findsOneWidget);
    });

    testWidgets('the anchor stone next to its branch still opens its own skill', (tester) async {
      await _pump(tester);
      await _showBranch(tester, 'cucina');
      await tapKey(tester, 'skill-node-food-basics');
      expect(find.byKey(const ValueKey('map-scroll')), findsOneWidget);
      expect(find.byKey(const ValueKey('map-scroll-cucina')), findsNothing);
    });

    testWidgets('a course without topics keeps the plain title and no branches', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const ValueKey('tree-selector')), findsNothing);
      expect(find.byKey(const ValueKey('course-title')), findsOneWidget);
      expect(_mapView(tester).branches, isEmpty);
    });
  });

  group('carving colours', () {
    test('the letters are very light on the bark, with a dark edge, in both themes', () {
      for (final ink in [MapInk.storybook, MapInk.night]) {
        final c = carvingColours(ink, mono: false);
        expect(c.floor.computeLuminance(), greaterThan(0.75), reason: '$ink');
        expect(c.floor.computeLuminance(), greaterThan(ink.bark.computeLuminance() * 3));
        expect(c.shade.computeLuminance(), lessThan(ink.bark.computeLuminance() / 2));
      }
      final bw = carvingColours(MapInk.storybook, mono: true);
      expect(bw.floor, kBwBlack);
    });
  });

  test('the carving style is the storybook serif', () {
    final s = carvingTextStyle(14);
    expect(s.fontFamily, 'Gelasio');
    expect(s.fontWeight, FontWeight.w700);

  });
}

/// The mean brightness (0–255) of the bark round topic [id]'s carving on screen.
Future<double> _branchPixels(WidgetTester tester, String id) async {
  final b = _branch(tester, id);
  final rect = Rect.fromCenter(center: _onScreen(tester, b.tapPoint), width: 40, height: 12);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(appRootKey));
  var sum = 0.0, n = 0;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (var y = rect.top.floor(); y < rect.bottom; y++) {
      for (var x = rect.left.floor(); x < rect.right; x++) {
        if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
        final i = (y * image.width + x) * 4;
        sum += (data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2)) / 3;
        n++;
      }
    }
    image.dispose();
  });
  return n == 0 ? 0 : sum / n;
}
