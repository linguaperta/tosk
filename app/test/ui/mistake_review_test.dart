import 'package:tosk/core/core.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/lesson/feedback_banner.dart';
import 'package:tosk/ui/lesson/player_screen.dart';
import 'package:tosk/ui/map/map_screen.dart';
import 'package:tosk/ui/mistakes/mistakes_screen.dart';
import 'package:tosk/ui/map/skill_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _FakeExplainer implements Explainer {
  ExplainContext? last;
  @override
  bool get isAvailable => true;
  @override
  Stream<String> explain(ExplainContext context) {
    last = context;
    return Stream.value('Because noi takes -iamo.');
  }
}

/// A one-exercise conj_pick lab answered wrong, then right on the re-ask: one open mistake.
Future<TestProgressStore> makeMistake(WidgetTester tester, {List<Override> overrides = const []}) async {
  final store = await pumpApp(
    tester,
    initialLocation: '/play/lab?skills=present-are&types=conj_pick&length=1',
    overrides: overrides,
  );
  await answerCurrent(tester, wrong: true);
  await playToSummary(tester);
  await tapKey(tester, 'summary-done');
  expect(find.byType(MapScreen), findsOneWidget);
  return store;
}

void main() {
  testWidgets('map: "Review mistakes (N)" appears after a mistake, starts the review, and goes once resolved', (
    tester,
  ) async {
    final store = await makeMistake(tester);
    expect((await store.mistakes()).length, 1);
    // Right on the re-ask in the same session: still open.
    expect(find.text('Review mistakes (1)'), findsOneWidget);

    await tapKey(tester, 'mistakes-button');
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(currentExercise(tester).type, ExerciseType.conjPick);
    await playToSummary(tester);
    expect(find.text('Session complete'), findsOneWidget);
    await tapKey(tester, 'summary-done');
    expect(find.byType(MapScreen), findsOneWidget);
    // Answered right in a later session: resolved.
    expect(find.byKey(const ValueKey('mistakes-button')), findsNothing);
    expect(find.byKey(const ValueKey('fading-button')), findsOneWidget);
  });

  testWidgets('progress page → mistakes list: prompt, answers, note excerpt, review button; "Why?" hidden', (
    tester,
  ) async {
    await makeMistake(tester);
    await goTab(tester, 'Progress');
    await scrollToFind(tester, find.text('Review mistakes (1)'));
    expect(find.text('Review mistakes (1)'), findsOneWidget);
    await tapKey(tester, 'open-mistakes');
    expect(find.byType(MistakesScreen), findsOneWidget);
    final card = find.byKey(const ValueKey('mistake-it:mangiare#form:presente'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('You answered')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('mangiamo')), findsWidgets);
    expect(find.descendant(of: card, matching: find.textContaining('-are')), findsWidgets); // note excerpt
    expect(find.descendant(of: card, matching: find.byIcon(Icons.help_outline)), findsNothing);
    expect(find.text('Review 1 mistake'), findsOneWidget);

    // The grammar note link opens the skill sheet.
    await tapKey(tester, 'mistake-note-it:mangiare#form:presente');
    expect(find.byType(SkillSheet), findsOneWidget);
    await tester.tapAt(const Offset(200, 20)); // dismiss the sheet
    await tester.pumpAndSettle();

    await tapKey(tester, 'mistakes-review');
    expect(find.byType(PlayerScreen), findsOneWidget);
    await playToSummary(tester);
    await tapKey(tester, 'summary-done');
    // Back on the (now empty) list.
    expect(find.byKey(const ValueKey('mistakes-empty')), findsOneWidget);
  });

  testWidgets('"Why?" on a mistake when an explainer is available', (tester) async {
    final explainer = _FakeExplainer();
    await makeMistake(tester, overrides: [explainerProvider.overrideWithValue(explainer)]);
    await goTab(tester, 'Progress');
    await tapKey(tester, 'open-mistakes');
    await tapKey(tester, 'mistake-why-it:mangiare#form:presente');
    expect(find.text('Because noi takes -iamo.'), findsOneWidget);
    expect(explainer.last!.expected, 'mangiamo');
    expect(explainer.last!.exerciseType, ExerciseType.conjPick);
    expect(explainer.last!.note, contains('-are'));
  });

  testWidgets('empty states: no map button, empty list', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('mistakes-button')), findsNothing);
    await goTab(tester, 'Progress');
    await scrollToFind(tester, find.text('No mistakes to review'));
    expect(find.text('No mistakes to review'), findsOneWidget);
    await tapKey(tester, 'open-mistakes');
    expect(find.byKey(const ValueKey('mistakes-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('mistakes-review')), findsNothing);
  });

  testWidgets('empty state: review session with nothing open', (tester) async {
    await pumpApp(tester, initialLocation: '/play/review');
    expect(find.text('No mistakes to review. Nice!'), findsOneWidget);
  });

  testWidgets('feedback panel: extra actions sit in the actions row above Continue', (tester) async {
    var flagged = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: FeedbackBanner(
            result: const Result(correct: false, expected: 'mangiamo', given: 'mangiate', outcomes: []),
            onContinue: () {},
            onWhy: () {},
            reduceMotion: true,
            extraActions: [
              FeedbackAction(
                key: const ValueKey('flag-button'),
                icon: Icons.flag_outlined,
                label: 'Flag',
                onPressed: () => flagged++,
              ),
            ],
          ),
        ),
      ),
    );
    final row = find.byKey(const ValueKey('feedback-actions'));
    expect(find.descendant(of: row, matching: find.byKey(const ValueKey('why-button'))), findsOneWidget);
    expect(find.descendant(of: row, matching: find.byKey(const ValueKey('flag-button'))), findsOneWidget);
    expect(
      tester.getBottomLeft(row).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(const ValueKey('continue-button'))).dy),
    );
    await tester.tap(find.byKey(const ValueKey('flag-button')));
    expect(flagged, 1);
  });
}
