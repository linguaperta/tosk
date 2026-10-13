import 'dart:math' as math;

import '../../core/core.dart';

/// In-memory [ProgressStore] with a toy scheduler, for the demo and widget tests.
/// The real one is the data layer's drift-backed `ProgressRepo` with FSRS.
class InMemoryProgressStore implements ProgressStore {
  InMemoryProgressStore({Map<String, String>? settings}) : _settings = {...?settings};

  final List<ReviewEvent> _log = [];
  final Map<String, FacetState> _states = {};
  final List<MistakeRecord> _mistakes = [];
  final Map<String, String> _settings;

  /// Settings as stored (read-only view, for tests).
  Map<String, String> get settings => Map.unmodifiable(_settings);

  @override
  Future<FacetState> record(ReviewEvent event) async {
    _log.add(event);
    final s = demoReview(event.facetId, _states[event.facetId], event.rating, event.at);
    _states[event.facetId] = s;
    return s;
  }

  @override
  Future<FacetState?> state(String facetId) async => _states[facetId];

  @override
  Future<Map<String, FacetState>> states(Iterable<String> facetIds) async => {
    for (final id in facetIds)
      if (_states[id] != null) id: _states[id]!,
  };

  @override
  Future<List<FacetState>> allStates({String? courseId}) async => [
    for (final s in _states.values)
      if (courseId == null || s.facetId.startsWith('$courseId:')) s,
  ];

  @override
  Future<List<ReviewEvent>> log({DateTime? since, String? courseId, String? facetId}) async => [
    for (final e in _log)
      if ((since == null || !e.at.isBefore(since)) &&
          (courseId == null || e.facetId.startsWith('$courseId:')) &&
          (facetId == null || e.facetId == facetId))
        e,
  ];

  @override
  Future<void> rebuildStates() async {
    _states.clear();
    final sorted = List.of(_log)..sort((a, b) => a.at.compareTo(b.at));
    for (final e in sorted) {
      _states[e.facetId] = demoReview(e.facetId, _states[e.facetId], e.rating, e.at);
    }
  }

  @override
  Future<List<MistakeRecord>> mistakes({String? courseId, int limit = 100}) async {
    final list = [
      for (final m in _mistakes.reversed)
        if (courseId == null || m.facetId.startsWith('$courseId:')) m,
    ];
    return list.take(limit).toList();
  }

  @override
  Future<void> saveMistake(MistakeRecord mistake) async => _mistakes.add(mistake);

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      _settings.remove(key);
    } else {
      _settings[key] = value;
    }
  }
}

/// Toy scheduling: stability multiplies on success, collapses on failure.
FacetState demoReview(String facetId, FacetState? prev, Rating rating, DateTime now) {
  if (prev == null) {
    final s = switch (rating) {
      Rating.again => 0.3,
      Rating.hard => 1.0,
      Rating.good => 2.5,
      Rating.easy => 6.0,
    };
    return FacetState(
      facetId: facetId,
      stability: s,
      difficulty: 5,
      due: now.add(Duration(minutes: (s * 1440).round())),
      lastReview: now,
      reps: 1,
      lapses: rating == Rating.again ? 1 : 0,
      phase: rating == Rating.again ? CardPhase.learning : CardPhase.review,
    );
  }
  final factor = switch (rating) {
    Rating.again => 0.3,
    Rating.hard => 1.2,
    Rating.good => 2.5,
    Rating.easy => 3.5,
  };
  final s = math.max(0.2, prev.stability * factor);
  return prev.copyWith(
    stability: s,
    due: now.add(Duration(minutes: (s * 1440).round())),
    lastReview: now,
    reps: prev.reps + 1,
    lapses: prev.lapses + (rating == Rating.again ? 1 : 0),
    phase: rating == Rating.again ? CardPhase.relearning : CardPhase.review,
  );
}

/// FSRS-shaped forgetting curve (power law), good enough for the demo map.
double demoRetrievability(FacetState? s, DateTime now) {
  if (s == null) return 0;
  final days = math.max(0, now.difference(s.lastReview).inMinutes) / 1440.0;
  return math.pow(1 + 19 / 81 * days / s.stability, -0.5).toDouble();
}
