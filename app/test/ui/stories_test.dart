// Graded stories in the app: the Practice → Stories list, the unit band's
// book button and sheet on the map, the reader (sentence by sentence, word
// popovers, translations, questions, result), the logged story read (XP), the
// unlock rule, and the new screens in black & white (pixel scan) and without
// overflow at every harness size.
import 'package:tosk/core/core.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/lesson/exercises/common.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/stories/story_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/story_course.dart';
import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSizes;
import 'helpers.dart';

/// One correct answer on the first facet of every skill of [unitId], so the
/// unit's stories unlock.
Future<void> practiceUnit(TestProgressStore store, CourseData course, String unitId) async {
  var n = 0;
  for (final s in course.skills.where((s) => s.unitId == unitId)) {
    final facets = course.skillFacets(s.id);
    if (facets.isEmpty) continue;
    await store.record(ReviewEvent(
      id: 'seed-$unitId-${n++}',
      facetId: facets.first.facetId,
      at: testNow.subtract(const Duration(days: 1)),
      rating: Rating.good,
      exerciseType: 'multiple_choice',
      inputMode: InputMode.tap,
      responseMs: 1000,
      correct: true,
      sessionId: 'seed',
      mode: 'lesson',
    ));
  }
}

Future<(TestProgressStore, CourseData)> pumpStories(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  Map<String, String> settings = const {},
  bool unlockU1 = true,
  String? initialLocation,
}) async {
  final course = storyCourse();
  final store = TestProgressStore(settings: settings);
  if (unlockU1) await practiceUnit(store, course, 'u1');
  await pumpApp(
    tester,
    size: size,
    store: store,
    initialLocation: initialLocation,
    overrides: [courseDataProvider.overrideWith((ref) async => course)],
  );
  return (store, course);
}

Future<void> openStoriesTab(WidgetTester tester) async {
  await goTab(tester, 'Practice');
  await tapKey(tester, 'practice-tab-stories');
}

Future<void> tapOption(WidgetTester tester, String label) =>
    tapIt(tester, find.widgetWithText(OptionButton, label));

/// Reads [storyId] to the end (opening it from the list) and answers every
/// question with its first-listed (correct) option, or a wrong one.
Future<void> readThrough(WidgetTester tester, Story story, {bool wrongFirst = false}) async {
  for (var i = 1; i < story.sentences.length; i++) {
    await tapKey(tester, 'story-next');
  }
  await tapKey(tester, 'story-to-questions');
  for (var q = 0; q < story.questions.length; q++) {
    final question = story.questions[q];
    final pick = wrongFirst && q == 0 ? (question.correct + 1) % question.options.length : question.correct;
    await tapOption(tester, question.options[pick].label('en'));
    await tapKey(tester, 'story-question-next');
  }
}

void main() {
  test('unlock rule: every skill of the unit that trains facets started', () {
    final course = storyCourse();
    final u1 = [for (final s in course.skills) if (s.unitId == 'u1') s.id];
    final started = SkillStats(
      strength: 0.5,
      lastPracticed: testNow,
      tier: MapTier.started,
      practicedFacets: 1,
      totalFacets: 2,
    );
    expect(storyUnitsUnlocked(course, {for (final s in u1.skip(1)) s: started}), isEmpty);
    expect(storyUnitsUnlocked(course, {for (final s in u1) s: started}), {'u1'});
  });

  testWidgets('Practice → Stories lists the stories by unit; locked ones are a preview', (tester) async {
    await pumpStories(tester);
    await openStoriesTab(tester);
    expect(find.byKey(const ValueKey('stories-list')), findsOneWidget);
    expect(find.text('Il pane'), findsOneWidget);
    expect(find.text('The bread'), findsOneWidget);
    expect(find.text('New'), findsOneWidget); // u1 is unlocked
    expect(find.text('Locked · preview'), findsOneWidget); // u2 is not
    expect(find.text('Basics'), findsOneWidget);
  });

  testWidgets('the reader: sentence by sentence, translations, word popovers, questions, result and the log',
      (tester) async {
    final (store, course) = await pumpStories(tester);
    await openStoriesTab(tester);
    await tapKey(tester, 'story-tile-u1-pane');
    expect(find.byKey(const ValueKey('story-preview-note')), findsNothing);
    expect(find.byKey(const ValueKey('story-new-word-it:mangiare')), findsOneWidget);
    expect(find.textContaining('mangiare = to eat'), findsOneWidget);
    expect(find.byKey(const ValueKey('story-sentence-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-sentence-1')), findsNothing);

    // Translation toggle.
    expect(find.text('Hi, mum!'), findsNothing);
    await tapKey(tester, 'story-translate-0');
    expect(find.byKey(const ValueKey('story-translation-0')), findsOneWidget);
    expect(find.text('Hi, mum!'), findsOneWidget);
    await tapKey(tester, 'story-translate-0');
    expect(find.text('Hi, mum!'), findsNothing);

    // Every aligned word is tappable.
    await tapKey(tester, 'word-s0-2');
    expect(find.text('mother'), findsOneWidget);
    await tester.tapAt(const Offset(2, 400));
    await tester.pumpAndSettle();

    // Continue reveals the next sentence.
    await tapKey(tester, 'story-next');
    expect(find.byKey(const ValueKey('story-sentence-1')), findsOneWidget);
    await tapKey(tester, 'story-next');
    await tapKey(tester, 'story-next');
    expect(find.byKey(const ValueKey('story-sentence-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-next')), findsNothing);
    await tapKey(tester, 'story-to-questions');

    // Question 1: wrong, with the explanation; Next is disabled until answered.
    expect(find.text('Question 1 of 2'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('story-question-next'))).onPressed, isNull);
    await tapOption(tester, 'mela');
    expect(find.byKey(const ValueKey('story-verdict-wrong')), findsOneWidget);
    expect(find.text('Sentence 3: Mangiamo pane.'), findsOneWidget);
    await tapKey(tester, 'story-question-next');
    // Question 2: the target-language prompt above the translated one, right.
    expect(find.text('Che cosa dice alla fine?'), findsOneWidget);
    expect(find.text('What does she say at the end?'), findsOneWidget);
    await tapOption(tester, 'Thank you');
    expect(find.byKey(const ValueKey('story-verdict-right')), findsOneWidget);
    await tapKey(tester, 'story-question-next');

    // Result: the score and the XP of a first read (5 + 1 per right answer).
    expect(find.text('1 of 2 questions right'), findsOneWidget);
    expect(find.text('+6 XP'), findsOneWidget);
    final reads = (await store.log(courseId: 'it')).where((e) => e.isStory).toList();
    expect(reads, hasLength(1));
    expect(reads.single.facetId, storyFacetId('it', 'u1-pane'));
    expect(reads.single.answer, '1/2');
    expect(reads.single.mode, kStoryMode);
    expect(reads.single.rating, Rating.good);
    // No real facet was touched.
    expect(await store.state('it:mangiare#form:presente'), isNull);

    await tapKey(tester, 'story-done');
    expect(find.text('Read · best 1/2'), findsOneWidget);

    // A reread earns the light reread XP.
    await tapKey(tester, 'story-tile-u1-pane');
    await readThrough(tester, course.story('u1-pane')!);
    expect(find.text('2 of 2 questions right'), findsOneWidget);
    expect(find.text('+2 XP'), findsOneWidget);
    await tapKey(tester, 'story-done');
    expect(find.text('Read · best 2/2'), findsOneWidget);
  });

  testWidgets('a locked story opens as a preview', (tester) async {
    await pumpStories(tester, unlockU1: false);
    await openStoriesTab(tester);
    expect(find.text('Locked · preview'), findsNWidgets(2));
    await tapKey(tester, 'story-tile-u1-pane');
    expect(find.byKey(const ValueKey('story-preview-note')), findsOneWidget);
  });

  testWidgets('the map: a book button in the unit band opens the unit\'s stories', (tester) async {
    await pumpStories(tester);
    expect(find.byKey(const ValueKey('unit-stories-u1')), findsOneWidget);
    expect(find.byKey(const ValueKey('unit-stories-u2')), findsOneWidget);
    expect(find.byKey(const ValueKey('unit-stories-u3')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('1 story, Basics')), findsOneWidget);
    await tapKey(tester, 'unit-stories-u1');
    expect(find.byKey(const ValueKey('unit-stories-sheet')), findsOneWidget);
    expect(find.text('Il pane'), findsOneWidget);
    expect(find.text('Dormire'), findsNothing);
    await tapKey(tester, 'story-tile-u1-pane');
    expect(find.byKey(const ValueKey('story-sentence-0')), findsOneWidget);
  });

  testWidgets('a course without stories shows an empty Stories tab and no book buttons', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('unit-stories-u1')), findsNothing);
    await openStoriesTab(tester);
    expect(find.text('This course has no stories yet.'), findsOneWidget);
  });

  /// Every new screen; [check] runs on each.
  Future<void> walk(WidgetTester tester, Future<void> Function(String what) check) async {
    await check('map with book buttons');
    await tapKey(tester, 'unit-stories-u2');
    await check('unit stories sheet (locked)');
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await openStoriesTab(tester);
    await check('stories list');
    await tapKey(tester, 'story-tile-u1-pane');
    for (var i = 0; i < 3; i++) {
      await tapKey(tester, 'story-next');
    }
    await tapKey(tester, 'story-translate-1');
    await check('reader with a translation');
    await tapKey(tester, 'story-to-questions');
    await check('question');
    await tapOption(tester, 'mela');
    await check('question answered wrong');
    await tapKey(tester, 'story-question-next');
    await tapOption(tester, 'Thank you');
    await check('question answered right');
    await tapKey(tester, 'story-question-next');
    await check('result');
    await tapKey(tester, 'story-done');
    await check('stories list after reading');
    await tapKey(tester, 'story-tile-u2-dormire');
    await check('preview reader');
  }

  for (final entry in bwSizes.entries) {
    testWidgets('black & white ${entry.key}: stories screens are gray only and fit', (tester) async {
      await pumpStories(tester, size: entry.value, settings: {SettingKeys.display: 'bw'});
      await walk(tester, (what) async {
        await expectGrayscale(tester, what);
        expect(tester.takeException(), isNull, reason: what);
      });
    });
  }

  for (final size in const [Size(320, 568), Size(360, 640), Size(1280, 800)]) {
    testWidgets('color, dark, text 1.3 at ${size.width.toInt()}x${size.height.toInt()}: no overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpStories(tester, size: size, settings: {SettingKeys.themeMode: 'dark'});
      await walk(tester, (what) async => expect(tester.takeException(), isNull, reason: what));
    });
  }

  testWidgets('the Stories tab is reachable from a route', (tester) async {
    await pumpStories(tester, initialLocation: '/practice?tab=stories');
    expect(find.byKey(const ValueKey('stories-list')), findsOneWidget);
    // ProviderScope sanity: the overridden course is the one shown.
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('stories-list'))));
    expect((await container.read(courseDataProvider.future)).stories, hasLength(2));
  });
}
