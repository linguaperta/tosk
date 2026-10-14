import 'package:tosk/core/core.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/lesson/player_screen.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:tosk/ui/map/skill_map_view.dart';
import 'package:tosk/ui/map/skill_node.dart';
import 'package:tosk/ui/map/skill_sheet.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/theme/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

final sheetScrollable = find.descendant(of: find.byType(SkillSheet), matching: find.byType(Scrollable)).first;

void main() {
  testWidgets('map shows every skill of the course in unit bands', (tester) async {
    await pumpApp(tester);
    final course = buildDemoItalian();
    for (final s in course.skills) {
      expect(find.byKey(ValueKey('skill-node-${s.id}')), findsOneWidget, reason: s.id);
    }
    expect(find.text('Basics'), findsOneWidget);
    expect(find.text('The past'), findsOneWidget);
    expect(find.text('Italian'), findsOneWidget);
    expect(find.byKey(const ValueKey('unverified-badge')), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('tap a node starts a lesson with the default focus', (tester) async {
    await pumpApp(tester);
    await tapKey(tester, 'skill-node-greetings');
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-progress')), findsOneWidget);
  });

  testWidgets('long-press opens the sheet with grammar note, items and focus chooser', (tester) async {
    await pumpApp(tester, size: const Size(400, 900));
    final node = find.byKey(const ValueKey('skill-node-present-are'));
    await tester.ensureVisible(node);
    await tester.longPress(node);
    await tester.pumpAndSettle();
    expect(find.byType(SkillSheet), findsOneWidget);
    // Focus and length choosers, Start lesson and Test out come first.
    expect(find.byKey(const ValueKey('length-chooser')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-out')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Present tense of -are verbs'), 200, scrollable: sheetScrollable);
    expect(find.text('Present tense of -are verbs'), findsOneWidget); // markdown heading
    expect(find.byType(Table), findsOneWidget); // markdown table
    await tester.scrollUntilVisible(find.text('comprare'), 200, scrollable: sheetScrollable);
    expect(find.text('to buy'), findsOneWidget); // gloss in source language
    await tapIt(tester, find.text('comprare'));
    expect(find.text('compriamo'), findsOneWidget); // forms of the skill's tense

    // Focus chooser then start.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('focus-chooser')), -200, scrollable: sheetScrollable);
    await tapIt(tester, find.text('Grammar').last);
    await tapKey(tester, 'start-lesson');
    expect(find.byType(PlayerScreen), findsOneWidget);
    final ex = currentExercise(tester);
    expect({
      ExerciseType.conjPick,
      ExerciseType.conjGrid,
      ExerciseType.cloze,
      ExerciseType.transform,
      ExerciseType.spotError,
    }, contains(ex.type));
  });

  testWidgets('item sheet shows articles and glosses in the chosen source language', (tester) async {
    await pumpApp(tester, store: TestProgressStore(settings: {SettingKeys.sourceLang: 'nl'}));
    final node = find.byKey(const ValueKey('skill-node-food'));
    await tester.ensureVisible(node);
    await tester.longPress(node);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text("l'acqua"), 200, scrollable: sheetScrollable);
    expect(find.text('il pane'), findsOneWidget);
    expect(find.text('brood'), findsOneWidget);
  });

  testWidgets("what's fading: hidden on a fresh profile, starts a mixed session", (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('fading-button')), findsNothing);
    final store = TestProgressStore();
    await seedDemoProgress(store, buildDemoItalian(), testNow);
    await pumpApp(tester, store: store);
    await tapKey(tester, 'fading-button');
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.text("What's fading"), findsNothing); // title only shown on summary
  });

  testWidgets('course switcher changes course and shows the unverified badge', (tester) async {
    final store = await pumpApp(tester);
    await tapKey(tester, 'course-switcher');
    await tapIt(tester, find.text('Dutch').last);
    expect(find.byKey(const ValueKey('skill-node-groeten')), findsOneWidget);
    expect(find.byKey(const ValueKey('skill-node-greetings')), findsNothing);
    expect(find.byKey(const ValueKey('unverified-badge')), findsOneWidget);
    expect(store.settings[SettingKeys.course], 'nl');
  });

  testWidgets('zoom buttons widen the map and allow horizontal scrolling', (tester) async {
    await pumpApp(tester, size: const Size(360, 700));
    expect(find.byKey(const ValueKey('map-hscroll')), findsNothing);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('map-hscroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nodes reflect stats: ring, days, locked, fading', (tester) async {
    final course = buildDemoItalian();
    final store = TestProgressStore();
    await seedDemoProgress(store, course, testNow);
    await pumpApp(tester, store: store);
    SkillNode node(String id) => tester.widget<SkillNode>(
      find.ancestor(of: find.byKey(ValueKey('skill-node-$id')), matching: find.byType(SkillNode)),
    );
    expect(node('greetings').stats.daysSince(testNow), 4);
    expect(find.text('4d'), findsOneWidget);
    expect(node('passato').stats.tier, MapTier.locked);
    expect(node('articles').stats.decay, greaterThan(node('greetings').stats.decay));
  });

  test('fadeColor desaturates proportionally', () {
    const c = Color(0xFF2E7D32);
    expect(fadeColor(c, 0), c);
    final s0 = HSLColor.fromColor(c).saturation;
    final s1 = HSLColor.fromColor(fadeColor(c, 0.5)).saturation;
    final s2 = HSLColor.fromColor(fadeColor(c, 1)).saturation;
    expect(s1, lessThan(s0));
    expect(s2, lessThan(s1));
  });

  testWidgets('SkillMapView alone: callbacks and geometry', (tester) async {
    final course = buildDemoItalian();
    final layout = layoutSkillMap(course.units, course.skills);
    String? tapped, held;
    setSurface(tester, const Size(320, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SkillMapView(
              course: course,
              layout: layout,
              stats: const {},
              style: const DefaultSkin().mapStyle(ThemeData().colorScheme),
              lang: 'en',
              now: testNow,
              onTap: (s) => tapped = s.id,
              onLongPress: (s) => held = s.id,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('skill-node-greetings')));
    expect(tapped, 'greetings');
    await tester.longPress(find.byKey(const ValueKey('skill-node-food')));
    expect(held, 'food');
    final g = MapGeometry(layout: layout, availableWidth: 320, zoom: 1);
    expect(g.width, 320); // fits at phone width
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a locked skill opens its sheet with what to do first', (tester) async {
    await pumpApp(tester);
    final node = find.byKey(const ValueKey('skill-node-present-are'));
    expect(
      tester.widget<SkillNode>(find.ancestor(of: node, matching: find.byType(SkillNode))).stats.tier,
      MapTier.locked,
    );
    await tester.ensureVisible(node);
    await tester.pumpAndSettle();
    await tester.tap(node);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(SkillSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('skill-locked-hint')), findsOneWidget);
    await tapKey(tester, 'start-lesson');
    expect(find.byType(PlayerScreen), findsOneWidget);
  });
}
