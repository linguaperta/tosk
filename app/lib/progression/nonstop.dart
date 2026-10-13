/// Non-stop mode extras: combo multiplier, bonus rounds, run score, best run.
///
/// [NonStopRun] is an immutable state machine fed one *answer* (one graded
/// exercise) at a time. The UI feeds it live; [nonStopRuns] replays the same
/// machine from the review log, so the best-run record is derived from the log.
/// See docs/progression.md.
library;

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'replay.dart';

@immutable
class NonStopRules {
  const NonStopRules({
    this.pointsPerCorrect = 10,
    this.comboStep = 5,
    this.comboIncrement = 0.5,
    this.maxMultiplier = 3.0,
    this.bonusEvery = 25,
    this.bonusRoundLength = 10,
    this.bonusRoundDuration = const Duration(seconds: 60),
    this.bonusRoundMultiplier = 2,
    this.bonusCompletionPerCorrect = 10,
    this.bonusKind = 'conj_blitz',
    this.bonusPreferredTypes = const ['conj_pick'],
  });

  /// Points for a correct answer at ×1.
  final int pointsPerCorrect;

  /// The multiplier grows by [comboIncrement] every [comboStep] consecutive correct answers.
  final int comboStep;
  final double comboIncrement;
  final double maxMultiplier;

  /// A bonus round starts on every [bonusEvery]-th correct answer of the run.
  final int bonusEvery;

  /// A bonus round is [bonusRoundLength] answers within [bonusRoundDuration].
  final int bonusRoundLength;
  final Duration bonusRoundDuration;

  /// Extra multiplier on answers inside a bonus round (stacks with the combo).
  final int bonusRoundMultiplier;

  /// Completing a round in time adds this × correct answers in the round.
  final int bonusCompletionPerCorrect;

  final String bonusKind;

  /// Exercise type ids the engine should serve during a bonus round.
  final List<String> bonusPreferredTypes;

  /// Combo multiplier for a combo of [combo] consecutive correct answers
  /// (including the current one): 1.0 for 0–4, 1.5 for 5–9, … up to [maxMultiplier].
  double multiplierFor(int combo) {
    if (comboStep <= 0) return 1;
    final m = 1 + (combo ~/ comboStep) * comboIncrement;
    return m > maxMultiplier ? maxMultiplier : m;
  }
}

/// An active timed bonus round (e.g. a conjugation blitz).
@immutable
class BonusRound {
  const BonusRound({
    required this.kind,
    required this.preferredTypes,
    required this.startedAt,
    required this.deadline,
    required this.targetAnswers,
    required this.multiplier,
    this.answered = 0,
    this.correct = 0,
  });

  /// e.g. `'conj_blitz'`.
  final String kind;

  /// Exercise types the engine should serve while the round lasts.
  final List<String> preferredTypes;
  final DateTime startedAt;

  /// Answers after this instant no longer count for the round.
  final DateTime deadline;
  final int targetAnswers;
  final int multiplier;
  final int answered;
  final int correct;

  int get remainingAnswers => targetAnswers - answered;

  Duration remaining(DateTime now) {
    final d = deadline.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  bool isExpired(DateTime now) => now.isAfter(deadline);

  BonusRound _withAnswer(bool ok) => BonusRound(
        kind: kind,
        preferredTypes: preferredTypes,
        startedAt: startedAt,
        deadline: deadline,
        targetAnswers: targetAnswers,
        multiplier: multiplier,
        answered: answered + 1,
        correct: correct + (ok ? 1 : 0),
      );
}

/// Things that happened on the last transition, for UI feedback.
enum NonStopSignal {
  multiplierUp,
  comboBroken,
  bonusRoundStarted,
  bonusRoundCompleted,
  bonusRoundExpired,
}

/// One graded exercise in a non-stop run.
@immutable
class NonStopAnswer {
  const NonStopAnswer({required this.correct, required this.at, this.exerciseType});
  final bool correct;
  final DateTime at;
  final String? exerciseType;
}

/// Immutable non-stop run state. Start with `NonStopRun()` and call [answer].
@immutable
class NonStopRun {
  const NonStopRun({this.rules = const NonStopRules()})
      : answered = 0,
        correct = 0,
        combo = 0,
        bestCombo = 0,
        score = 0,
        bonusRoundsStarted = 0,
        bonusRoundsCompleted = 0,
        bonusRound = null,
        lastPoints = 0,
        lastSignals = const [],
        startedAt = null,
        lastAnswerAt = null;

  const NonStopRun._({
    required this.rules,
    required this.answered,
    required this.correct,
    required this.combo,
    required this.bestCombo,
    required this.score,
    required this.bonusRoundsStarted,
    required this.bonusRoundsCompleted,
    required this.bonusRound,
    required this.lastPoints,
    required this.lastSignals,
    required this.startedAt,
    required this.lastAnswerAt,
  });

  final NonStopRules rules;
  final int answered;
  final int correct;

  /// Consecutive correct answers (0 after a mistake).
  final int combo;
  final int bestCombo;
  final int score;
  final int bonusRoundsStarted;
  final int bonusRoundsCompleted;

  /// The active bonus round, if any.
  final BonusRound? bonusRound;

  /// Points earned by the last answer (including a bonus-round completion bonus).
  final int lastPoints;
  final List<NonStopSignal> lastSignals;
  final DateTime? startedAt;
  final DateTime? lastAnswerAt;

  /// Current combo multiplier.
  double get multiplier => rules.multiplierFor(combo);

  /// Correct answers until the next bonus round starts.
  int get correctUntilBonus {
    if (rules.bonusEvery <= 0) return -1;
    final r = correct % rules.bonusEvery;
    return rules.bonusEvery - r;
  }

  /// Exercise types the engine should prefer now (empty = no preference).
  List<String> get preferredTypes => bonusRound?.preferredTypes ?? const [];

  double get accuracy => answered == 0 ? 0 : correct / answered;

  NonStopRun _copy({
    int? answered,
    int? correct,
    int? combo,
    int? bestCombo,
    int? score,
    int? bonusRoundsStarted,
    int? bonusRoundsCompleted,
    BonusRound? bonusRound,
    bool clearRound = false,
    int? lastPoints,
    List<NonStopSignal>? lastSignals,
    DateTime? startedAt,
    DateTime? lastAnswerAt,
  }) =>
      NonStopRun._(
        rules: rules,
        answered: answered ?? this.answered,
        correct: correct ?? this.correct,
        combo: combo ?? this.combo,
        bestCombo: bestCombo ?? this.bestCombo,
        score: score ?? this.score,
        bonusRoundsStarted: bonusRoundsStarted ?? this.bonusRoundsStarted,
        bonusRoundsCompleted: bonusRoundsCompleted ?? this.bonusRoundsCompleted,
        bonusRound: clearRound ? null : (bonusRound ?? this.bonusRound),
        lastPoints: lastPoints ?? this.lastPoints,
        lastSignals: lastSignals ?? this.lastSignals,
        startedAt: startedAt ?? this.startedAt,
        lastAnswerAt: lastAnswerAt ?? this.lastAnswerAt,
      );

  /// Applies one graded exercise answered at [at].
  ///
  /// Order of rules: an expired bonus round ends first (the answer then scores
  /// normally); the combo updates; points = round(pointsPerCorrect × combo
  /// multiplier × round multiplier) for a correct answer, 0 otherwise; the
  /// round counts the answer and, at its target, completes with a bonus; finally
  /// a new round starts if this was the [NonStopRules.bonusEvery]-th correct answer.
  NonStopRun answer({required bool correct, required DateTime at, String? exerciseType}) {
    final signals = <NonStopSignal>[];
    var round = bonusRound;
    if (round != null && round.isExpired(at)) {
      signals.add(NonStopSignal.bonusRoundExpired);
      round = null;
    }
    final newCombo = correct ? combo + 1 : 0;
    if (!correct && combo > 0) signals.add(NonStopSignal.comboBroken);
    final mult = rules.multiplierFor(newCombo);
    if (mult > rules.multiplierFor(combo)) signals.add(NonStopSignal.multiplierUp);
    var points = correct ? (rules.pointsPerCorrect * mult * (round?.multiplier ?? 1)).round() : 0;
    final newCorrect = this.correct + (correct ? 1 : 0);
    var started = bonusRoundsStarted, completed = bonusRoundsCompleted;
    var justCompleted = false;
    if (round != null) {
      round = round._withAnswer(correct);
      if (round.answered >= round.targetAnswers) {
        points += rules.bonusCompletionPerCorrect * round.correct;
        completed++;
        signals.add(NonStopSignal.bonusRoundCompleted);
        round = null;
        justCompleted = true;
      }
    }
    if (round == null &&
        !justCompleted &&
        correct &&
        rules.bonusEvery > 0 &&
        rules.bonusRoundLength > 0 &&
        newCorrect % rules.bonusEvery == 0) {
      round = BonusRound(
        kind: rules.bonusKind,
        preferredTypes: rules.bonusPreferredTypes,
        startedAt: at,
        deadline: at.add(rules.bonusRoundDuration),
        targetAnswers: rules.bonusRoundLength,
        multiplier: rules.bonusRoundMultiplier,
      );
      started++;
      signals.add(NonStopSignal.bonusRoundStarted);
    }
    return _copy(
      answered: answered + 1,
      correct: newCorrect,
      combo: newCombo,
      bestCombo: newCombo > bestCombo ? newCombo : bestCombo,
      score: score + points,
      bonusRoundsStarted: started,
      bonusRoundsCompleted: completed,
      bonusRound: round,
      clearRound: round == null,
      lastPoints: points,
      lastSignals: List.unmodifiable(signals),
      startedAt: startedAt ?? at,
      lastAnswerAt: at,
    );
  }

  /// Convenience for the engine/UI: applies a graded [result] of [exercise].
  NonStopRun applyResult(Exercise exercise, Result result, {required DateTime at}) =>
      answer(correct: result.correct, at: at, exerciseType: exercise.type.id);

  /// Ends an expired bonus round (for the HUD countdown). Score is unaffected,
  /// so ticking or not gives the same score as a replay from the log.
  NonStopRun tick(DateTime now) {
    final round = bonusRound;
    if (round == null || !round.isExpired(now)) return this;
    return _copy(
      clearRound: true,
      lastPoints: 0,
      lastSignals: const [NonStopSignal.bonusRoundExpired],
    );
  }

  /// Replays [answers] from a fresh run.
  static NonStopRun replay(Iterable<NonStopAnswer> answers, {NonStopRules rules = const NonStopRules()}) {
    var run = NonStopRun(rules: rules);
    for (final a in answers) {
      run = run.answer(correct: a.correct, at: a.at, exerciseType: a.exerciseType);
    }
    return run;
  }
}

/// Groups one session's events (canonical order) into answers: consecutive
/// events with the same instant and exercise type are one exercise (e.g. the
/// five pairs of a match-pairs exercise), correct only if all are correct.
///
/// Contract for the engine: record all facet outcomes of one exercise with the
/// same `at`.
List<NonStopAnswer> answersFromEvents(Iterable<ReviewEvent> sessionEvents) {
  final evs = canonicalOrder(sessionEvents);
  final out = <NonStopAnswer>[];
  for (var i = 0; i < evs.length;) {
    final e = evs[i];
    var ok = e.correct;
    var j = i + 1;
    while (j < evs.length && evs[j].at == e.at && evs[j].exerciseType == e.exerciseType) {
      ok = ok && evs[j].correct;
      j++;
    }
    out.add(NonStopAnswer(correct: ok, at: e.at, exerciseType: e.exerciseType));
    i = j;
  }
  return out;
}

/// The outcome of one finished (or ongoing) non-stop run, derived from the log.
@immutable
class NonStopRecord {
  const NonStopRecord({
    required this.sessionId,
    required this.score,
    required this.answered,
    required this.correct,
    required this.bestCombo,
    required this.bonusRoundsCompleted,
    required this.startedAt,
    required this.endedAt,
  });

  final String sessionId;
  final int score;
  final int answered;
  final int correct;
  final int bestCombo;
  final int bonusRoundsCompleted;
  final DateTime startedAt;
  final DateTime endedAt;

  Duration get duration => endedAt.difference(startedAt);
  double get accuracy => answered == 0 ? 0 : correct / answered;
}

const String kNonStopMode = 'nonstop';

/// Every non-stop run in [events] (events with mode `'nonstop'`, grouped by
/// session id), in order of start time.
List<NonStopRecord> nonStopRuns(Iterable<ReviewEvent> events, {NonStopRules rules = const NonStopRules()}) {
  final bySession = <String, List<ReviewEvent>>{};
  for (final e in events) {
    final sid = e.sessionId;
    if (e.mode != kNonStopMode || sid == null) continue;
    (bySession[sid] ??= []).add(e);
  }
  final out = <NonStopRecord>[];
  for (final entry in bySession.entries) {
    final answers = answersFromEvents(entry.value);
    if (answers.isEmpty) continue;
    final run = NonStopRun.replay(answers, rules: rules);
    out.add(NonStopRecord(
      sessionId: entry.key,
      score: run.score,
      answered: run.answered,
      correct: run.correct,
      bestCombo: run.bestCombo,
      bonusRoundsCompleted: run.bonusRoundsCompleted,
      startedAt: answers.first.at,
      endedAt: answers.last.at,
    ));
  }
  out.sort((a, b) {
    final c = a.startedAt.compareTo(b.startedAt);
    return c != 0 ? c : a.sessionId.compareTo(b.sessionId);
  });
  return out;
}

/// The highest-scoring non-stop run (ties: the earlier run), or null.
NonStopRecord? bestNonStopRun(Iterable<ReviewEvent> events, {NonStopRules rules = const NonStopRules()}) {
  NonStopRecord? best;
  for (final r in nonStopRuns(events, rules: rules)) {
    if (best == null || r.score > best.score) best = r;
  }
  return best;
}
