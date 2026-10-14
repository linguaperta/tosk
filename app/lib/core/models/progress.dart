/// Progress domain model: review events (the source of truth) and derived facet state.
library;

import 'package:meta/meta.dart';

/// FSRS rating. Wire values are 1..4.
enum Rating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Rating(this.value);
  final int value;
  static Rating fromValue(int v) => Rating.values.firstWhere((r) => r.value == v);
}

/// How the answer was entered. `ink` is reserved for handwriting (Phase 8).
enum InputMode { tap, keyboard, ink, self }

/// Exercise type ids, stable strings stored in the log and in course packs.
enum ExerciseType {
  flashcard('flashcard'),
  multipleChoice('multiple_choice'),
  matchPairs('match_pairs'),
  conjPick('conj_pick'),
  conjGrid('conj_grid'),
  sentenceBuilder('sentence_builder'),
  cloze('cloze'),
  spotError('spot_error'),
  transform('transform');

  const ExerciseType(this.id);
  final String id;

  static ExerciseType? tryParse(String id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }

  static ExerciseType parse(String id) =>
      tryParse(id) ?? (throw FormatException('Unknown exercise type: $id'));
}

/// [ReviewEvent.exerciseType] of a *test-out credit*: when a test-out quiz or a
/// placement test is passed, every facet of the skills it covers that is not
/// yet learned gets one event with this type, rating [Rating.easy], `correct`,
/// `responseMs` 0 and the session's id and mode (`testOut` / `placement`).
/// Easy graduates a new facet straight into review, so the skill reaches
/// bronze and what follows unlocks; being ordinary log events, credits sync
/// like any answer. Progression gives them no XP and doesn't count them as
/// reviews (see docs/progression.md).
const String kTestOutCreditType = 'test_out';

/// One graded answer. Append-only; never edited. Facet ids embed the course id.
@immutable
class ReviewEvent {
  const ReviewEvent({
    required this.id,
    required this.facetId,
    required this.at,
    required this.rating,
    required this.exerciseType,
    required this.inputMode,
    required this.responseMs,
    required this.correct,
    this.answer,
    this.sessionId,
    this.mode,
  });

  final String id; // UUID v4
  final String facetId;
  final DateTime at; // UTC
  final Rating rating;
  final String exerciseType; // ExerciseType.id
  final InputMode inputMode;
  final int responseMs;
  final bool correct;
  final String? answer; // the answer given (for mistake review)
  final String? sessionId;
  final String? mode; // 'lesson' | 'lab' | 'nonstop' | 'review' | 'testOut' | 'placement'

  /// A test-out credit rather than an answer (see [kTestOutCreditType]).
  bool get isCredit => exerciseType == kTestOutCreditType;
}

/// FSRS learning phase.
enum CardPhase { learning, review, relearning }

/// Scheduler state for one facet, derived from the review log.
@immutable
class FacetState {
  const FacetState({
    required this.facetId,
    required this.stability,
    required this.difficulty,
    required this.due,
    required this.lastReview,
    required this.reps,
    required this.lapses,
    this.phase = CardPhase.learning,
    this.step,
  });

  final String facetId;
  final double stability; // days
  final double difficulty; // 1..10
  final DateTime due; // UTC
  final DateTime lastReview; // UTC
  final int reps;
  final int lapses;
  final CardPhase phase;
  final int? step; // learning/relearning step index, null in review

  bool isDue(DateTime now) => !due.isAfter(now);

  FacetState copyWith({
    double? stability,
    double? difficulty,
    DateTime? due,
    DateTime? lastReview,
    int? reps,
    int? lapses,
    CardPhase? phase,
    int? step,
    bool clearStep = false,
  }) =>
      FacetState(
        facetId: facetId,
        stability: stability ?? this.stability,
        difficulty: difficulty ?? this.difficulty,
        due: due ?? this.due,
        lastReview: lastReview ?? this.lastReview,
        reps: reps ?? this.reps,
        lapses: lapses ?? this.lapses,
        phase: phase ?? this.phase,
        step: clearStep ? null : (step ?? this.step),
      );

  @override
  bool operator ==(Object other) =>
      other is FacetState &&
      other.facetId == facetId &&
      other.stability == stability &&
      other.difficulty == difficulty &&
      other.due == due &&
      other.lastReview == lastReview &&
      other.reps == reps &&
      other.lapses == lapses &&
      other.phase == phase &&
      other.step == step;

  @override
  int get hashCode =>
      Object.hash(facetId, stability, difficulty, due, lastReview, reps, lapses, phase, step);

  @override
  String toString() =>
      'FacetState($facetId, S=$stability, D=$difficulty, due=$due, reps=$reps, lapses=$lapses, $phase, step=$step)';
}
