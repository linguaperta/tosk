import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/events.dart';

void main() {
  const rules = NonStopRules();
  final t0 = utc(2026, 10, 1, 18);

  NonStopRun play(List<bool> answers, {Duration gap = const Duration(seconds: 3), NonStopRun? from}) {
    var run = from ?? const NonStopRun();
    var at = run.lastAnswerAt ?? t0;
    for (final ok in answers) {
      at = at.add(gap);
      run = run.answer(correct: ok, at: at, exerciseType: 'conj_pick');
    }
    return run;
  }

  group('combo multiplier', () {
    test('steps every 5 correct answers and caps at 3x', () {
      expect(rules.multiplierFor(0), 1.0);
      expect(rules.multiplierFor(4), 1.0);
      expect(rules.multiplierFor(5), 1.5);
      expect(rules.multiplierFor(10), 2.0);
      expect(rules.multiplierFor(20), 3.0);
      expect(rules.multiplierFor(500), 3.0);
    });

    test('points use the multiplier including the current answer; a mistake resets', () {
      var run = play(List.filled(4, true));
      expect(run.score, 40);
      expect(run.multiplier, 1.0);
      run = play([true], from: run);
      expect(run.combo, 5);
      expect(run.lastPoints, 15);
      expect(run.lastSignals, contains(NonStopSignal.multiplierUp));
      run = play([false], from: run);
      expect(run.combo, 0);
      expect(run.lastPoints, 0);
      expect(run.lastSignals, contains(NonStopSignal.comboBroken));
      expect(run.bestCombo, 5);
      expect(run.multiplier, 1.0);
      expect(run.answered, 6);
      expect(run.correct, 5);
    });

    test('a first wrong answer does not signal a broken combo', () {
      final run = play([false]);
      expect(run.lastSignals, isEmpty);
      expect(run.score, 0);
    });
  });

  group('bonus round', () {
    test('starts on the 25th correct answer and asks for conjugation exercises', () {
      var run = play(List.filled(24, true));
      expect(run.bonusRound, isNull);
      expect(run.correctUntilBonus, 1);
      expect(run.preferredTypes, isEmpty);
      run = play([true], from: run);
      final round = run.bonusRound!;
      expect(run.lastSignals, contains(NonStopSignal.bonusRoundStarted));
      expect(round.kind, 'conj_blitz');
      expect(run.preferredTypes, ['conj_pick']);
      expect(round.targetAnswers, 10);
      expect(round.deadline, run.lastAnswerAt!.add(const Duration(seconds: 60)));
      expect(round.remaining(run.lastAnswerAt!), const Duration(seconds: 60));
      expect(run.bonusRoundsStarted, 1);
    });

    test('completing in time doubles points and adds a completion bonus', () {
      var run = play(List.filled(25, true));
      final before = run.score;
      // 10 answers, 9 correct, 3 seconds apart: well within 60 s.
      run = play([...List.filled(5, true), false, ...List.filled(4, true)], from: run);
      expect(run.bonusRound, isNull);
      expect(run.bonusRoundsCompleted, 1);
      expect(run.lastSignals, contains(NonStopSignal.bonusRoundCompleted));
      // combos 26..30 -> x3.0 (>=20), each x2 in round: 5 * 60 = 300
      // then a miss, then combos 1..4 at x1 x2: 4 * 20 = 80; completion: 9 * 10 = 90
      expect(run.score - before, 300 + 80 + 90);
    });

    test('expires at the deadline: later answers score normally, no completion bonus', () {
      var run = play(List.filled(25, true));
      final deadline = run.bonusRound!.deadline;
      run = play(List.filled(3, true), from: run); // 3 in-round answers
      expect(run.bonusRound!.answered, 3);
      // Next answer just after the deadline.
      final s0 = run.score;
      run = run.answer(correct: true, at: deadline.add(const Duration(milliseconds: 1)));
      expect(run.bonusRound, isNull);
      expect(run.lastSignals, contains(NonStopSignal.bonusRoundExpired));
      expect(run.score - s0, 30); // combo 29 -> x3, no round multiplier
      expect(run.bonusRoundsCompleted, 0);
    });

    test('an answer exactly at the deadline still counts for the round', () {
      var run = play(List.filled(25, true));
      final deadline = run.bonusRound!.deadline;
      run = run.answer(correct: true, at: deadline);
      expect(run.bonusRound!.answered, 1);
    });

    test('tick ends an expired round without changing the score', () {
      var run = play(List.filled(25, true));
      final score = run.score;
      final deadline = run.bonusRound!.deadline;
      expect(identical(run.tick(deadline), run), isTrue);
      final ticked = run.tick(deadline.add(const Duration(seconds: 1)));
      expect(ticked.bonusRound, isNull);
      expect(ticked.score, score);
      expect(ticked.lastSignals, [NonStopSignal.bonusRoundExpired]);
      // Ticking or not, the next answer scores the same.
      final next = deadline.add(const Duration(seconds: 5));
      expect(ticked.answer(correct: true, at: next).score, run.answer(correct: true, at: next).score);
    });

    test('the next round starts at the 50th correct answer', () {
      var run = play(List.filled(49, true));
      expect(run.bonusRoundsStarted, 1);
      run = play([true], from: run);
      expect(run.bonusRoundsStarted, 2);
      expect(run.bonusRound, isNotNull);
    });
  });

  group('from the log', () {
    final f = EventFactory();

    test('events of one exercise (same instant and type) form one answer', () {
      final evs = [
        f.ev('a#rec', t0, type: 'match_pairs', session: 's', mode: 'nonstop'),
        f.ev('b#rec', t0, type: 'match_pairs', session: 's', mode: 'nonstop', correct: false),
        f.ev('c#rec', t0, type: 'match_pairs', session: 's', mode: 'nonstop'),
        f.ev('d#rec', t0.add(const Duration(seconds: 5)), session: 's', mode: 'nonstop'),
      ];
      final answers = answersFromEvents(evs.reversed);
      expect(answers.length, 2);
      expect(answers[0].correct, isFalse);
      expect(answers[0].exerciseType, 'match_pairs');
      expect(answers[1].correct, isTrue);
    });

    test('replaying a session from the log gives the live score; best run is the max', () {
      // Live run of 60 answers with a few mistakes; log mirrors it.
      final pattern = [for (var i = 0; i < 60; i++) i % 17 != 16];
      var live = const NonStopRun();
      final evs = <ReviewEvent>[];
      var at = t0;
      for (final ok in pattern) {
        at = at.add(const Duration(seconds: 4));
        live = live.answer(correct: ok, at: at, exerciseType: 'conj_pick');
        evs.add(f.ev('x#form:presente', at, correct: ok, type: 'conj_pick', session: 'run1', mode: 'nonstop'));
      }
      // A weaker run and a lesson that must be ignored.
      final weak = f.many(['y#rec'], t0.add(const Duration(days: 1)), 10, session: 'run2', mode: 'nonstop');
      final lesson = f.many(['y#rec'], t0.add(const Duration(days: 2)), 200, session: 'l1', mode: 'lesson');
      final all = [...lesson, ...weak, ...evs]..shuffle();
      final runs = nonStopRuns(all);
      expect(runs.map((r) => r.sessionId), ['run1', 'run2']);
      final best = bestNonStopRun(all)!;
      expect(best.sessionId, 'run1');
      expect(best.score, live.score);
      expect(best.bestCombo, live.bestCombo);
      expect(best.answered, 60);
      expect(best.correct, live.correct);
      expect(best.bonusRoundsCompleted, live.bonusRoundsCompleted);
      expect(best.duration, const Duration(seconds: 59 * 4));
      expect(NonStopRun.replay(answersFromEvents(evs)).score, live.score);
    });

    test('no non-stop events gives no best run', () {
      expect(bestNonStopRun([f.ev('a#rec', t0, session: 's', mode: 'lesson')]), isNull);
      expect(bestNonStopRun([f.ev('a#rec', t0, mode: 'nonstop')]), isNull); // no session id
    });

    test('applyResult uses the exercise type and correctness', () {
      const ex = ConjPickExercise(
        id: 'x', facetId: 'it:mangiare#form:presente', lemma: 'mangiare', gloss: 'to eat',
        tense: 'presente', tenseLabel: 'Present', person: 'noi', personLabel: 'noi', stem: 'mang',
        endings: ['iamo', 'iate'], correctIndex: 0, fullForm: 'mangiamo');
      const res = Result(correct: true, expected: 'mangiamo', given: 'mangiamo', outcomes: []);
      final run = const NonStopRun().applyResult(ex, res, at: t0);
      expect(run.correct, 1);
      expect(run.score, 10);
    });
  });
}
