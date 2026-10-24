/// Progress access used by the engine and progression layers. Implemented by
/// `data/progress/progress_repo.dart` (drift) and by in-memory fakes in tests.
library;

import '../models/progress.dart';

/// FSRS scheduling math. Pure and deterministic (no randomness, no fuzz), so
/// rebuilding states from the log reproduces stored states exactly.
abstract interface class Scheduler {
  /// The state after reviewing [previous] (null = a new facet) with [rating] at [now].
  FacetState review(String facetId, FacetState? previous, Rating rating, DateTime now);

  /// Predicted probability of recall at [now] (0..1). A new or never-reviewed facet gives 0.
  double retrievability(FacetState? state, DateTime now);
}

/// Folds one replayable event (see `replayable` in models/progress.dart) into
/// the facet's state: a skill reset ([kResetType]) clears it (null: never
/// reviewed), anything else is a [Scheduler.review].
FacetState? replayStep(Scheduler scheduler, FacetState? previous, ReviewEvent e) =>
    e.isReset ? null : scheduler.review(e.facetId, previous, e.rating, e.at);

abstract interface class ProgressStore {
  /// Appends [event] to the review log and updates that facet's state. Returns
  /// the new state: null when the facet has none afterwards (a skill reset,
  /// [kResetType]; answers always give one).
  Future<FacetState?> record(ReviewEvent event);

  Future<FacetState?> state(String facetId);

  /// States for the given facets. Facets never reviewed are absent from the map.
  Future<Map<String, FacetState>> states(Iterable<String> facetIds);

  /// All facet states (optionally only facets whose id starts with `'{courseId}:'`).
  Future<List<FacetState>> allStates({String? courseId});

  /// Review events in chronological order, optionally filtered.
  Future<List<ReviewEvent>> log({DateTime? since, String? courseId, String? facetId});

  /// Recomputes every facet state from the review log (the log is the single source of truth).
  Future<void> rebuildStates();

  /// Wrong answers kept for mistake review (most recent first).
  Future<List<MistakeRecord>> mistakes({String? courseId, int limit = 100});
  Future<void> saveMistake(MistakeRecord mistake);

  /// Key/value settings.
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String? value);
}

/// A stored wrong answer, which feeds mistake review and later AI explanations.
class MistakeRecord {
  const MistakeRecord({
    required this.id,
    required this.facetId,
    required this.at,
    required this.exerciseType,
    required this.prompt,
    required this.expected,
    required this.given,
    this.skillId,
    this.note,
    this.explanation,
  });

  final String id; // same as the ReviewEvent id
  final String facetId;
  final DateTime at;
  final String exerciseType;
  final String prompt; // human-readable exercise prompt
  final String expected;
  final String given;
  final String? skillId;
  final String? note; // grammar note markdown at the time
  final String? explanation; // cached Explainer output (later)
}
