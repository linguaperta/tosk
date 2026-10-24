// v0.3 features: tap a word for its translation, the course picker,
// the reference (lookup and grammar library), navigation, session length,
// test out and placement, tough words.
import 'package:tosk/core/core.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/lesson/player_screen.dart';
import 'package:tosk/ui/lesson/session_request.dart';
import 'package:tosk/ui/map/map_screen.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/practice/practice_screen.dart';
import 'package:tosk/ui/reference/reference_screen.dart';
import 'package:tosk/ui/reference/word_screen.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byKey(appRootKey)));

String popoverHeadline(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('word-popover-headline'))).data!;

Future<void> closePopover(WidgetTester tester) async {
  await tester.tapAt(const Offset(2, 2));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('word-popover')), findsNothing);
}

/// History that gives [facetId] [lapses] lapses: graduated, then forgotten
/// and relearned again and again.
Future<void> seedLeech(TestProgressStore store, String facetId, {int lapses = 4}) async {
  var at = testNow.subtract(Duration(days: 4 * lapses + 10));
  var n = 0;
  Future<void> r(Rating rating) async {
    at = at.add(const Duration(days: 2));
    await store.record(
      ReviewEvent(
        id: 'leech-$facetId-${n++}',
        facetId: facetId,
        at: at,
        rating: rating,
        exerciseType: 'conj_pick',
        inputMode: InputMode.tap,
        responseMs: 3000,
        correct: rating != Rating.again,
        mode: 'lesson',
      ),
    );
  }

  await r(Rating.good);
  await r(Rating.good);
  for (var i = 0; i < lapses; i++) {
    await r(Rating.again);
    await r(Rating.good);
  }
  expect((await store.state(facetId))!.lapses, lapses);
}

void main() {
  group('tap a word for its translation', () {
    testWidgets('cloze: other words before checking, the asked verb and the gap after; open in reference', (
      tester,
    ) async {
      await pumpApp(
        tester,
        initialLocation: Routes.labPlay(skills: ['passato'], types: [ExerciseType.cloze], length: 1),
      );
      expect(currentExercise(tester).id, 'it-cl-ho');
      // "Ieri" is tappable; "mangiato" (the asked verb) is not, before checking.
      expect(find.byKey(const ValueKey('word-2')), findsNothing);
      await tapKey(tester, 'word-0');
      expect(find.byKey(const ValueKey('word-popover')), findsOneWidget);
      expect(popoverHeadline(tester), 'ieri');
      expect(find.text('yesterday'), findsOneWidget);
      await closePopover(tester);
      // Nothing was answered by looking.
      expect(find.byKey(const ValueKey('feedback-banner')), findsNothing);

      await answerCurrentNoContinue(tester);
      await tapKey(tester, 'word-2');
      expect(popoverHeadline(tester), 'mangiato → mangiare · io · present perfect');
      await closePopover(tester);
      await tapKey(tester, 'cloze-gap');
      expect(popoverHeadline(tester), 'ho → mangiare · io · present perfect');
      await tapKey(tester, 'word-popover-reference');
      expect(find.byType(WordScreen), findsOneWidget);
      expect(find.text('mangiare'), findsWidgets);
      expect(find.byKey(const ValueKey('verb-tense-presente')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('feedback-banner')), findsOneWidget);
    });

    testWidgets('spot the error: a tap answers before checking, translates after', (tester) async {
      await pumpApp(
        tester,
        initialLocation: Routes.labPlay(skills: ['articles'], types: [ExerciseType.spotError], length: 1),
      );
      await tapKey(tester, 'token-1');
      expect(find.byKey(const ValueKey('word-popover')), findsNothing);
      await answerCurrentNoContinue(tester);
      await tapKey(tester, 'token-1');
      expect(popoverHeadline(tester), 'il pane');
      expect(find.text('bread'), findsOneWidget);
      await closePopover(tester);
      // The wrong word: the correct one's translation (unaligned here: none).
      await tapKey(tester, 'token-2');
      expect(popoverHeadline(tester), 'è → essere · lui/lei · present');
    });

    testWidgets('sentence multiple choice: the prompt, without the asked word before checking', (tester) async {
      await pumpApp(
        tester,
        initialLocation: Routes.labPlay(skills: ['family'], types: [ExerciseType.multipleChoice], length: 1),
      );
      expect(find.byKey(const ValueKey('mc-prompt-sentence')), findsOneWidget);
      expect(find.byKey(const ValueKey('word-1')), findsNothing); // padre: the asked word
      await tapKey(tester, 'word-2');
      expect(popoverHeadline(tester), 'parla → parlare · lui/lei · present');
      await closePopover(tester);
      await answerCurrentNoContinue(tester);
      await tapKey(tester, 'word-1');
      expect(popoverHeadline(tester), 'il padre');
    });

    testWidgets('sentence builder: the answer sentence after checking', (tester) async {
      await pumpApp(
        tester,
        initialLocation: Routes.labPlay(skills: ['present-ere'], types: [ExerciseType.sentenceBuilder], length: 1),
      );
      expect(find.byKey(const ValueKey('answer-sentence')), findsNothing);
      await answerCurrentNoContinue(tester);
      expect(find.byKey(const ValueKey('answer-sentence')), findsOneWidget);
      await tapKey(tester, 'word-0');
      expect(popoverHeadline(tester), 'Leggo → leggere · io · present');
    });
  });

  group('course picker', () {
    testWidgets('first run opens the picker; preview; add a course, start from scratch', (tester) async {
      final store = await pumpApp(tester, store: TestProgressStore(fresh: true));
      expect(find.byKey(const ValueKey('course-picker')), findsOneWidget);
      expect(find.text('Choose your course'), findsOneWidget);
      expect(find.byKey(const ValueKey('course-card-it')), findsOneWidget);
      expect(find.byKey(const ValueKey('course-card-nl')), findsOneWidget);
      await tapKey(tester, 'course-preview-it');
      expect(find.byKey(const ValueKey('course-counts-it')), findsOneWidget);
      expect(find.textContaining('words ·'), findsOneWidget);
      expect(find.byKey(const ValueKey('course-samples-it')), findsOneWidget);
      expect(find.text('Mangiamo alle otto.'), findsOneWidget); // sample sentence
      expect(find.text('A small sample course.'), findsOneWidget);
      expect(find.textContaining('Learn Italian (it)'), findsOneWidget);
      await tapKey(tester, 'course-preview-it'); // hide
      expect(find.byKey(const ValueKey('unverified-badge')), findsWidgets); // demo nl is unverified
      await tapKey(tester, 'course-add-nl');
      // No progress in that course yet: where to start?
      expect(find.byKey(const ValueKey('placement-find')), findsOneWidget);
      await tapKey(tester, 'placement-scratch');
      expect(store.settings[SettingKeys.coursesAdded], 'nl');
      expect(store.settings[SettingKeys.course], 'nl');
      await tapKey(tester, 'course-picker-done');
      expect(find.byKey(const ValueKey('course-picker')), findsNothing);
      expect(find.byKey(const ValueKey('skill-node-groeten')), findsOneWidget);
      // Settings lists only my courses (+ manage).
      await goTab(tester, 'Settings');
      expect(find.byKey(const ValueKey('course-it')), findsNothing);
      expect(find.byKey(const ValueKey('course-nl')), findsOneWidget);
      expect(find.byKey(const ValueKey('manage-courses-tile')), findsOneWidget);
    });

    testWidgets('closing the first-run picker without choosing adds the course shown', (tester) async {
      final store = await pumpApp(tester, store: TestProgressStore(fresh: true));
      await tapKey(tester, 'course-picker-done');
      expect(store.settings[SettingKeys.coursesAdded], 'it');
      expect(find.byKey(const ValueKey('course-picker')), findsNothing);
    });

    testWidgets('remove a course from the switcher menu; the last one cannot be removed; progress stays', (
      tester,
    ) async {
      final store = await pumpApp(tester, store: TestProgressStore(settings: {SettingKeys.course: 'nl'}));
      await store.record(
        ReviewEvent(
          id: 'nl-1',
          facetId: 'nl:hallo#rec',
          at: testNow,
          rating: Rating.good,
          exerciseType: 'flashcard',
          inputMode: InputMode.self,
          responseMs: 1000,
          correct: true,
        ),
      );
      await goTab(tester, 'Settings');
      await tapKey(tester, 'manage-courses-tile');
      expect(find.byKey(const ValueKey('course-picker')), findsOneWidget);
      await tapKey(tester, 'course-remove-nl');
      expect(store.settings[SettingKeys.coursesAdded], 'it');
      expect(store.settings[SettingKeys.course], 'it'); // the removed one was active
      final lastRemove = tester.widget<IconButton>(find.byKey(const ValueKey('course-remove-it')));
      expect(lastRemove.onPressed, isNull);
      // Adding it back: it has progress, so no placement question.
      await tapKey(tester, 'course-add-nl');
      expect(find.byKey(const ValueKey('placement-find')), findsNothing);
      expect(store.settings[SettingKeys.coursesAdded], 'it,nl');
      expect((await store.log(courseId: 'nl')).length, 1);
    });

    testWidgets('find my level: placement runs and marks the passed units', (tester) async {
      await pumpApp(tester, store: TestProgressStore(fresh: true));
      await tapKey(tester, 'course-add-it');
      await tapKey(tester, 'placement-find');
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(tester.widget<PlayerScreen>(find.byType(PlayerScreen)).request, isA<PlacementRequest>());
      await playToSummary(tester);
      expect(find.byKey(const ValueKey('placement-result')), findsOneWidget);
      expect(find.byKey(const ValueKey('placement-learned')), findsOneWidget);
      await tapKey(tester, 'summary-done');
      final stats = await containerOf(tester).read(skillStatsProvider.future);
      expect(stats['greetings']!.tier.index, greaterThanOrEqualTo(MapTier.bronze.index));
    });
  });

  group('navigation', () {
    testWidgets('five tabs: Map, Practice (non-stop, lab), Reference (lookup, grammar), Progress, Settings', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(320, 568));
      for (final label in ['Map', 'Practice', 'Reference', 'Progress', 'Settings']) {
        expect(
          find.descendant(of: find.byKey(const ValueKey('bottom-nav')), matching: find.text(label)),
          findsOneWidget,
        );
      }
      await goTab(tester, 'Practice');
      expect(find.byType(PracticeScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('nonstop-start')), findsOneWidget);
      await goTab(tester, 'Lab');
      expect(find.byKey(const ValueKey('lab-start')), findsOneWidget);
      await goTab(tester, 'Reference');
      expect(find.byType(ReferenceScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('old /lab and /nonstop links open the Practice tab', (tester) async {
      await pumpApp(tester, initialLocation: '/lab');
      expect(find.byKey(const ValueKey('lab-start')), findsOneWidget);
    });
  });

  group('reference', () {
    testWidgets('lookup: by an inflected form, by a translation, verbs only; word page with full tables', (
      tester,
    ) async {
      await pumpApp(tester, initialLocation: Routes.reference);
      expect(find.byKey(const ValueKey('lookup-list')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('lookup-field')), 'Mangiamo');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lookup-hit-it:mangiare')), findsOneWidget);
      expect(find.textContaining('form: Mangiamo'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('lookup-field')), 'bread');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lookup-hit-it:pane')), findsOneWidget);
      expect(find.text('il pane'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('lookup-field')), '');
      await tapKey(tester, 'lookup-verbs');
      expect(find.byKey(const ValueKey('lookup-hit-it:pane')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('lookup-field')), 'parl');
      await tester.pumpAndSettle();
      await tapKey(tester, 'lookup-hit-it:parlare');
      expect(find.byType(WordScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('verb-tense-presente')), findsOneWidget);
      expect(find.byKey(const ValueKey('verb-tense-passato_prossimo')), findsOneWidget);
      final noi = tester.widget<Text>(find.byKey(const ValueKey('verb-form-presente-noi')));
      expect(noi.textSpan!.toPlainText(), 'parliamo');
      expect(find.text('Taught in'), findsOneWidget);
    });

    testWidgets('lookup: a query from a popover link, nothing found', (tester) async {
      await pumpApp(tester, initialLocation: Routes.lookup('xyzzy'));
      expect(find.byKey(const ValueKey('lookup-empty')), findsOneWidget);
    });

    testWidgets('grammar library: notes by unit, practice this skill', (tester) async {
      await pumpApp(tester, initialLocation: Routes.grammar);
      expect(find.byKey(const ValueKey('grammar-list')), findsOneWidget);
      expect(find.text('Present tense'), findsOneWidget); // unit heading
      await tapKey(tester, 'grammar-note-present-are');
      expect(find.text('Present tense of -are verbs'), findsOneWidget);
      await tapKey(tester, 'grammar-practice-present-are');
      expect(find.byType(PlayerScreen), findsOneWidget);
      final request = tester.widget<PlayerScreen>(find.byType(PlayerScreen)).request as LessonRequest;
      expect(request.skillId, 'present-are');
      expect(request.focus, LessonFocus.grammar);
    });

    testWidgets('the verb collection links to the reference', (tester) async {
      await pumpApp(tester, initialLocation: Routes.verbs);
      await tapIt(tester, find.text('mangiare').first);
      expect(find.byType(WordScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapKey(tester, 'verbs-lookup');
      expect(find.byType(ReferenceScreen), findsOneWidget);
    });
  });

  group('session length', () {
    testWidgets('the lesson sheet offers quick / normal / long', (tester) async {
      await pumpApp(tester, size: const Size(400, 900), initialLocation: Routes.skill('present-are'));
      await tapKey(tester, 'length-quick');
      await tapKey(tester, 'start-lesson');
      final s = tester.state(find.byType(PlayerScreen));
      expect((s.widget as PlayerScreen).request, isA<LessonRequest>());
      expect(((s.widget as PlayerScreen).request as LessonRequest).length, 5);
      expect(await playToSummary(tester), 5);
    });

    testWidgets('the default length is a setting', (tester) async {
      final store = await pumpApp(tester, initialLocation: Routes.settings);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('setting-length-Long')),
        300,
        scrollable: find
            .descendant(of: find.byKey(const ValueKey('settings-list')), matching: find.byType(Scrollable))
            .first,
      );
      await tapKey(tester, 'setting-length-Long');
      expect(store.settings[SettingKeys.defaultLength], 'long');
      await tapKey(tester, 'setting-leech-3');
      expect(store.settings[SettingKeys.leechLapses], '3');
      await goTab(tester, 'Map');
      await startLessonFromMap(tester, 'greetings');
      expect(await playToSummary(tester, cap: 80), 20);
    });
  });

  group('test out', () {
    testWidgets('passing marks the skill as learned (bronze) and says so', (tester) async {
      await pumpApp(tester, size: const Size(400, 900), initialLocation: Routes.skill('present-are'));
      await tapKey(tester, 'test-out');
      expect(tester.widget<PlayerScreen>(find.byType(PlayerScreen)).request, isA<TestOutRequest>());
      await playToSummary(tester);
      expect(find.text('Tested out!'), findsOneWidget);
      await tapKey(tester, 'summary-done');
      expect(find.byType(MapScreen), findsOneWidget);
      final stats = await containerOf(tester).read(skillStatsProvider.future);
      expect(stats['present-are']!.tier.index, greaterThanOrEqualTo(MapTier.bronze.index));
    });

    testWidgets('failing says "Not yet" and marks nothing', (tester) async {
      await pumpApp(tester, initialLocation: Routes.testOut('present-are'));
      while (find.byKey(const ValueKey('session-summary')).evaluate().isEmpty) {
        await answerCurrent(tester, wrong: true);
      }
      expect(find.text('Not yet'), findsOneWidget);
      final stats = await containerOf(tester).read(skillStatsProvider.future);
      expect(stats['present-are']!.tier, isNot(MapTier.bronze));
    });

    testWidgets('a learned skill offers no test out', (tester) async {
      final store = await pumpApp(tester, initialLocation: Routes.testOut('present-are'));
      await playToSummary(tester);
      await tapKey(tester, 'summary-done');
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, store: store, size: const Size(400, 900), initialLocation: Routes.skill('present-are'));
      expect(find.byKey(const ValueKey('start-lesson')), findsOneWidget);
      expect(find.byKey(const ValueKey('test-out')), findsNothing);
    });
  });

  group('tough words', () {
    testWidgets('progress and mistakes show "Tough words (N)"; the drill plays them', (tester) async {
      final store = TestProgressStore();
      await seedLeech(store, 'it:mangiare#form:presente');
      await pumpApp(tester, store: store, size: const Size(400, 1400), initialLocation: Routes.progress);
      expect(find.byKey(const ValueKey('open-tough')), findsOneWidget);
      expect(find.text('Tough words (1)'), findsOneWidget);
      expect(find.textContaining('mangiare'), findsWidgets);
      await tapKey(tester, 'open-tough');
      expect(tester.widget<PlayerScreen>(find.byType(PlayerScreen)).request, isA<ToughWordsRequest>());
      expect(currentExercise(tester).facetId, 'it:mangiare#form:presente');
      await playToSummary(tester);
      await tapKey(tester, 'summary-done');
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, store: store, initialLocation: Routes.mistakes);
      expect(find.byKey(const ValueKey('mistakes-tough')), findsOneWidget);
    });

    testWidgets('below the threshold: no entry; the threshold is a setting', (tester) async {
      final store = TestProgressStore(settings: {SettingKeys.leechLapses: '5'});
      await seedLeech(store, 'it:mangiare#form:presente');
      await pumpApp(tester, store: store, size: const Size(400, 1400), initialLocation: Routes.progress);
      expect(find.byKey(const ValueKey('open-tough')), findsNothing);
    });
  });
}
