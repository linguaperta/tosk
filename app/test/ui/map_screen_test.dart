import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart' show NextTierNeeds, SkillTier;
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/lesson/player_screen.dart';
import 'package:tosk/ui/lesson/session_request.dart';
import 'package:tosk/ui/map/map_layout.dart';
import 'package:tosk/ui/map/skill_map_view.dart';
import 'package:tosk/ui/map/skill_node.dart';
import 'package:tosk/ui/map/skill_sheet.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/routes.dart';
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

  testWidgets('tap a node: the sheet first (what it is, tier, next tier), then Start lesson', (tester) async {
    await pumpApp(tester, store: TestProgressStore(settings: {SettingKeys.defaultFocus: 'vocab'}));
    await tapKey(tester, 'skill-node-greetings');
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(SkillSheet), findsOneWidget);
    expect(find.text('Basics · Vocabulary'), findsOneWidget);
    expect(find.byKey(const ValueKey('skill-description')), findsOneWidget);
    expect(find.text('New'), findsOneWidget); // the tier chip
    // A fresh skill: learn all of its words for bronze.
    final next = tester.widget<Text>(find.byKey(const ValueKey('skill-next-tier'))).data!;
    expect(next, matches(RegExp(r'^Learn all \d+ words to reach Bronze\.$')));
    // The note and the word list are actions (collapsed).
    expect(find.byKey(const ValueKey('skill-words')), findsOneWidget);
    expect(find.text('ciao'), findsNothing);
    await tapKey(tester, 'start-lesson');
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-progress')), findsOneWidget);
    expect((tester.widget<PlayerScreen>(find.byType(PlayerScreen)).request as LessonRequest).focus, LessonFocus.vocab);
  });

  testWidgets('the sheet says what the next tier needs as the skill progresses', (tester) async {
    final course = buildDemoItalian();
    final store = TestProgressStore();
    await seedDemoProgress(store, course, testNow);
    await pumpApp(tester, store: store);
    await tapKey(tester, 'skill-node-greetings');
    final tier = tester.widget<SkillNode>(
      find.ancestor(of: find.byKey(const ValueKey('skill-node-greetings')), matching: find.byType(SkillNode)),
    );
    final next = tester.widget<Text>(find.byKey(const ValueKey('skill-next-tier'))).data!;
    switch (tier.stats.tier) {
      case MapTier.started:
        expect(next, matches(RegExp(r'^Learn \d+ more words? to reach Bronze\.$')));
      case MapTier.bronze:
        expect(next, contains('85% recall and 7-day stability for Silver'));
      case MapTier.silver:
        expect(next, contains('for Gold'));
      default:
        expect(next, isNotEmpty);
    }
  });

  testWidgets('grammar note and word list sections; the mistakes link opens the note', (tester) async {
    await pumpApp(tester, size: const Size(400, 900), initialLocation: Routes.skill('present-are', section: 'note'));
    expect(find.text('Present tense of -are verbs'), findsOneWidget); // expanded
    expect(find.text('comprare'), findsNothing); // word list collapsed
    await tapKey(tester, 'skill-words');
    await scrollToFind(tester, find.text('comprare'));
    expect(find.text('comprare'), findsOneWidget);
    // Locked on a fresh profile: what to do first instead of the next tier.
    expect(find.byKey(const ValueKey('skill-locked-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('skill-next-tier')), findsNothing);
  });

  test('next-tier texts and descriptions', () {
    const fresh = NextTierNeeds(tier: SkillTier.available, next: SkillTier.bronze, remaining: 8, total: 8);
    expect(nextTierText(fresh), 'Learn all 8 words to reach Bronze.');
    const started = NextTierNeeds(tier: SkillTier.started, next: SkillTier.bronze, remaining: 6, total: 8);
    expect(nextTierText(started), 'Learn 6 more words to reach Bronze.');
    expect(nextTierText(started, noun: 'verb'), 'Learn 6 more verbs to reach Bronze.');
    const bronze = NextTierNeeds(tier: SkillTier.bronze, next: SkillTier.silver, remaining: 4, total: 8);
    expect(nextTierText(bronze), startsWith('Get every word to 85% recall and 7-day stability for Silver — 4 words to go.'));
    const silver = NextTierNeeds(tier: SkillTier.silver, next: SkillTier.gold, remaining: 1, total: 8);
    expect(nextTierText(silver), 'Get every word to 90% recall and 21-day stability for Gold — 1 word to go.');
    const gold = NextTierNeeds(tier: SkillTier.gold, next: null, remaining: 0, total: 8);
    expect(nextTierText(gold), startsWith('Gold'));

    final it = buildDemoItalian();
    expect(skillItemNoun(it.skillFacets('present-are')), 'verb');
    expect(skillItemNoun(it.skillFacets('greetings')), 'word');
    // The note's first line of text (no heading, no markdown); else sample words.
    expect(skillDescription('# Title\n\nThe **present** of `-are` verbs.\n\n| a | b |', const [], 'en'),
        'The present of -are verbs.');
    expect(skillDescription(null, it.skillItems('greetings'), 'en'), startsWith('Words: '));
    expect(skillDescription(null, const [], 'en'), isNull);
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
    await tapKey(tester, 'skill-note');
    await tester.scrollUntilVisible(find.text('Present tense of -are verbs'), 200, scrollable: sheetScrollable);
    expect(find.text('Present tense of -are verbs'), findsOneWidget); // markdown heading
    expect(find.byType(Table), findsOneWidget); // markdown table
    await tapKey(tester, 'skill-words');
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
    await tapKey(tester, 'skill-words');
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

  testWidgets('the map shows the course title (not a switcher); Settings switches the course', (tester) async {
    final store = await pumpApp(tester);
    expect(find.byKey(const ValueKey('course-switcher')), findsNothing);
    expect(find.byKey(const ValueKey('course-title')), findsOneWidget);
    expect(find.text('Italian'), findsOneWidget);
    // Tapping the title does nothing.
    await tester.tap(find.byKey(const ValueKey('course-title')));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    await goTab(tester, 'Settings');
    await tapKey(tester, 'course-nl');
    await goTab(tester, 'Map');
    expect(find.text('Dutch'), findsOneWidget);
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
              style: const ToskSkin().mapStyle(ThemeData().colorScheme),
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
