import 'package:tosk/core/core.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/lesson/feedback_banner.dart';
import 'package:tosk/ui/lesson/player_screen.dart';
import 'package:tosk/ui/map/map_screen.dart';
import 'package:tosk/ui/map/skill_node.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _FakeExplainer implements Explainer {
  ExplainContext? last;
  @override
  bool get isAvailable => true;
  @override
  Stream<String> explain(ExplainContext context) {
    last = context;
    return Stream.fromIterable(['Because ', 'noi takes -iamo.']);
  }
}

SkillStats statsOf(WidgetTester tester, String id) => tester
    .widget<SkillNode>(find.ancestor(of: find.byKey(ValueKey('skill-node-$id')), matching: find.byType(SkillNode)))
    .stats;

void main() {
  testWidgets('full lesson: start from the map, answer everything, see the summary, back to the map', (tester) async {
    final store = await pumpApp(tester);
    expect(statsOf(tester, 'greetings').practiced, isFalse);
    await tapKey(tester, 'skill-node-greetings');
    expect(find.byType(PlayerScreen), findsOneWidget);

    final n = await playToSummary(tester);
    expect(n, 12);
    expect(find.text('Session complete'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('stat-answered')), matching: find.text('12')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('stat-accuracy')), matching: find.text('100%')),
      findsOneWidget,
    );
    expect(find.text('No mistakes. Well done!'), findsOneWidget);
    expect(await store.log(), isNotEmpty);

    await tapKey(tester, 'summary-done');
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);
    // Stats were refreshed after the session.
    expect(statsOf(tester, 'greetings').practiced, isTrue);
    expect(statsOf(tester, 'greetings').strength, greaterThan(0));
  });

  testWidgets('wrong answer: feedback shows the expected answer, the mistake comes back and is listed', (tester) async {
    await pumpApp(tester);
    await tapKey(tester, 'skill-node-greetings');
    // 1st exercise is a flashcard; answer it, then get the multiple choice wrong.
    await answerCurrent(tester);
    expect(currentExercise(tester).type, ExerciseType.multipleChoice);
    final mc = currentExercise(tester) as MultipleChoiceExercise;
    await tapKey(tester, 'option-${(mc.correctIndex + 1) % mc.options.length}');
    await tapKey(tester, 'check-button');
    expect(find.text('Not quite'), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-expected')), findsOneWidget);
    expect(find.text(mc.options[mc.correctIndex]), findsWidgets);
    expect(find.byKey(const ValueKey('ai-explain-button')), findsNothing); // AI not configured
    expect(find.byKey(const ValueKey('flag-button')), findsOneWidget);
    await tapKey(tester, 'continue-button');

    final n = await playToSummary(tester);
    expect(n, 11); // 10 left + the re-queued mistake
    expect(find.text('To review'), findsOneWidget);
    expect(find.text('grazie · meaning'), findsOneWidget);
  });

  testWidgets('progress bar advances', (tester) async {
    await pumpApp(tester);
    await tapKey(tester, 'skill-node-greetings');
    double value() => tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('lesson-progress'))).value!;
    expect(value(), 0);
    await answerCurrent(tester);
    await answerCurrent(tester);
    expect(value(), closeTo(2 / 12, 1e-9));
  });

  testWidgets('exit asks for confirmation', (tester) async {
    await pumpApp(tester);
    await tapKey(tester, 'skill-node-greetings');
    await answerCurrent(tester);
    await tapKey(tester, 'player-close');
    expect(find.text('Quit this session?'), findsOneWidget);
    await tapKey(tester, 'exit-cancel');
    expect(find.byType(PlayerScreen), findsOneWidget);

    // System back also asks.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Quit this session?'), findsOneWidget);
    await tapKey(tester, 'exit-confirm');
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(MapScreen), findsOneWidget);
    expect(statsOf(tester, 'greetings').practiced, isTrue); // answers so far were saved
  });

  testWidgets('desktop shortcuts: Enter reveals/checks/continues, digits pick options', (tester) async {
    await pumpApp(tester, size: const Size(1280, 800));
    await tapKey(tester, 'skill-node-greetings');
    expect(currentExercise(tester).type, ExerciseType.flashcard);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flashcard-back')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // Good
    await tester.pumpAndSettle();

    final mc = currentExercise(tester) as MultipleChoiceExercise;
    await tester.sendKeyEvent(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + mc.correctIndex));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Correct!'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(currentExercise(tester).type, ExerciseType.matchPairs);

    // Esc asks to leave.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Quit this session?'), findsOneWidget);
  });

  testWidgets('typing in the cloze field does not trigger digit shortcuts; Enter checks', (tester) async {
    await pumpApp(tester, initialLocation: '/play/lab?skills=present-are&types=cloze&length=1');
    final cloze = currentExercise(tester) as ClozeExercise;
    expect(cloze.options, isNull);
    await tester.tap(find.byKey(const ValueKey('answer-input')));
    await tester.enterText(find.byKey(const ValueKey('answer-input')), cloze.expected);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Correct!'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus moved back to the player
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('session-summary')), findsOneWidget);
    await tapKey(tester, 'summary-done'); // no back stack: goes to the map
    expect(find.byType(MapScreen), findsOneWidget);
  });

  testWidgets('"Explain answer with AI" shows when an explainer is available and streams its answer', (
    tester,
  ) async {
    final explainer = _FakeExplainer();
    await pumpApp(
      tester,
      initialLocation: '/play/lab?skills=present-are&types=conj_pick&length=1',
      overrides: [explainerProvider.overrideWithValue(explainer)],
    );
    await answerWrongWithoutContinuing(tester);
    expect(find.byKey(const ValueKey('why-button')), findsNothing, reason: 'replaced by the AI button');
    await tapKey(tester, 'ai-explain-button');
    expect(find.text('Because noi takes -iamo.'), findsOneWidget);
    expect(explainer.last!.note, contains('-are'));
    expect(explainer.last!.expected, 'mangiamo');
    expect(explainer.last!.correct, isFalse);
  });

  testWidgets('reduce motion: feedback banner is not animated, fx disabled', (tester) async {
    await pumpApp(
      tester,
      store: TestProgressStore(settings: {SettingKeys.reduceMotion: 'true'}),
      initialLocation: '/play/lab?skills=present-are&types=conj_pick&length=1',
    );
    await answerWrongWithoutContinuing(tester);
    final banner = find.byType(FeedbackBanner);
    expect(tester.widget<FeedbackBanner>(banner).reduceMotion, isTrue);
    expect(find.descendant(of: banner, matching: find.byType(TweenAnimationBuilder<double>)), findsNothing);
  });

  testWidgets('empty selection shows a friendly empty state', (tester) async {
    await pumpApp(tester, initialLocation: '/play/lab?skills=greetings&types=conj_grid&length=5');
    expect(find.text('Nothing to practice here right now.'), findsOneWidget);
  });

  testWidgets('a failing session factory shows an error with retry', (tester) async {
    await pumpApp(
      tester,
      initialLocation: '/play/fading',
      engine: true, // no fake factory: this test overrides the factory itself
      overrides: [sessionFactoryProvider.overrideWith((ref) => Future<SessionFactory>.error(StateError('boom')))],
    );
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

Future<void> answerWrongWithoutContinuing(WidgetTester tester) async {
  final ex = currentExercise(tester) as ConjPickExercise;
  await tapKey(tester, 'ending-${(ex.correctIndex + 1) % ex.endings.length}');
  await tapKey(tester, 'check-button');
  expect(find.text('Not quite'), findsOneWidget);
}
