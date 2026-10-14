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
  transform('transform'),

  /// Listen and pick (v0.5): on-device text-to-speech reads a sentence or a
  /// word; pick what you heard. Only generated when the course language has a
  /// voice ([SessionOptions.listening]).
  listenPick('listen_pick');

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

/// [ReviewEvent.exerciseType] of an *answer override* ("I was right"): the
/// learner says an answer graded wrong was right. The override is its own
/// event (the log stays append-only), on the same facet as the event it
/// corrects, later in time, with `correct` true, the corrected [Rating]
/// (Good), `responseMs` 0, input `self`, and the overridden event's id in
/// [ReviewEvent.answer].
///
/// **Replay convention** ([applyOverrides]): before folding a facet's events,
/// an override replaces the overridden event's rating and verdict in place
/// (at the original time) and is itself skipped. So the facet's state is
/// exactly what it would have been had the answer been graded right, every
/// replay (incremental, `rebuildStates()`, progression) gives the same
/// result, and an override never earns XP or counts as a review. An override
/// whose target is not in the log yet (sync order) has no effect until the
/// target arrives; of several overrides of one event the last in `(at, id)`
/// order wins. See docs/engine.md.
const String kOverrideType = 'override';

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

  /// An answer override rather than an answer (see [kOverrideType]).
  bool get isOverride => exerciseType == kOverrideType;

  /// A story read rather than an answer (see `kStoryReadType` in story.dart).
  bool get isStory => exerciseType == 'story';

  /// For an override, the id of the event it corrects.
  String? get overriddenId => isOverride ? answer : null;

  ReviewEvent copyWith({DateTime? at, Rating? rating, bool? correct}) => ReviewEvent(
        id: id,
        facetId: facetId,
        at: at ?? this.at,
        rating: rating ?? this.rating,
        exerciseType: exerciseType,
        inputMode: inputMode,
        responseMs: responseMs,
        correct: correct ?? this.correct,
        answer: answer,
        sessionId: sessionId,
        mode: mode,
      );
}

/// Applies answer overrides ([kOverrideType]) to [events], which must already
/// be in canonical `(at, id)` order: every overridden event gets the
/// override's rating and `correct`, and the override events themselves are
/// dropped. Returns [events] itself when it holds no override. Pure and
/// order-preserving, so every replay of the log agrees.
List<ReviewEvent> applyOverrides(List<ReviewEvent> events) {
  Map<String, ReviewEvent>? overrides;
  for (final e in events) {
    final target = e.overriddenId;
    if (target != null) (overrides ??= {})[target] = e; // later ones win
  }
  if (overrides == null) return events;
  return [
    for (final e in events)
      if (!e.isOverride)
        if (overrides[e.id] case final o?) e.copyWith(rating: o.rating, correct: o.correct) else e,
  ];
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
