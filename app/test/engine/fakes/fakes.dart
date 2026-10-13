/// Deterministic test doubles for the engine (the real FSRS scheduler and
/// progress store live in lib/data and are written elsewhere).
library;

import 'dart:math';

import 'package:tosk/core/core.dart';

/// A simple, deterministic stand-in for FSRS: stability grows by a factor
/// per rating, Again shrinks it and counts a lapse; recall decays as
/// 0.9^(elapsed / stability).
class FakeScheduler implements Scheduler {
  const FakeScheduler();

  @override
  FacetState review(String facetId, FacetState? previous, Rating rating, DateTime now) {
    final s0 = previous?.stability;
    final double s = switch (rating) {
      Rating.again => s0 == null ? 0.2 : max(0.2, s0 * 0.3),
      Rating.hard => s0 == null ? 0.6 : s0 * 1.2,
      Rating.good => s0 == null ? 1.0 : s0 * 2.5,
      Rating.easy => s0 == null ? 4.0 : s0 * 4,
    };
    final due = rating == Rating.again
        ? now.add(const Duration(minutes: 10))
        : now.add(Duration(minutes: (s * 24 * 60).round()));
    return FacetState(
      facetId: facetId,
      stability: s,
      difficulty: 5,
      due: due,
      lastReview: now,
      reps: (previous?.reps ?? 0) + 1,
      lapses: (previous?.lapses ?? 0) + (rating == Rating.again && previous != null ? 1 : 0),
      phase: rating == Rating.again ? CardPhase.relearning : CardPhase.review,
    );
  }

  @override
  double retrievability(FacetState? state, DateTime now) {
    if (state == null || state.reps == 0) return 0;
    final days = now.difference(state.lastReview).inMinutes / (24 * 60);
    return pow(0.9, max(0, days) / state.stability).toDouble();
  }
}

/// In-memory [ProgressStore] backed by a [Scheduler].
class InMemoryProgressStore implements ProgressStore {
  InMemoryProgressStore({this.scheduler = const FakeScheduler()});

  final Scheduler scheduler;
  final List<ReviewEvent> events = [];
  final Map<String, FacetState> stateMap = {};
  final List<MistakeRecord> mistakeList = [];
  final Map<String, String> settings = {};

  /// Seeds a state directly (as if reviewed earlier).
  void seed(FacetState s) => stateMap[s.facetId] = s;

  @override
  Future<FacetState> record(ReviewEvent event) async {
    events.add(event);
    final s = scheduler.review(event.facetId, stateMap[event.facetId], event.rating, event.at);
    stateMap[event.facetId] = s;
    return s;
  }

  @override
  Future<FacetState?> state(String facetId) async => stateMap[facetId];

  @override
  Future<Map<String, FacetState>> states(Iterable<String> facetIds) async => {
        for (final id in facetIds)
          if (stateMap[id] != null) id: stateMap[id]!,
      };

  @override
  Future<List<FacetState>> allStates({String? courseId}) async => [
        for (final s in stateMap.values)
          if (courseId == null || s.facetId.startsWith('$courseId:')) s,
      ];

  @override
  Future<List<ReviewEvent>> log({DateTime? since, String? courseId, String? facetId}) async => [
        for (final e in events)
          if ((since == null || !e.at.isBefore(since)) &&
              (courseId == null || e.facetId.startsWith('$courseId:')) &&
              (facetId == null || e.facetId == facetId))
            e,
      ];

  @override
  Future<void> rebuildStates() async {
    stateMap.clear();
    for (final e in events) {
      stateMap[e.facetId] = scheduler.review(e.facetId, stateMap[e.facetId], e.rating, e.at);
    }
  }

  @override
  Future<List<MistakeRecord>> mistakes({String? courseId, int limit = 100}) async => [
        for (final m in mistakeList.reversed)
          if (courseId == null || m.facetId.startsWith('$courseId:')) m,
      ].take(limit).toList();

  @override
  Future<void> saveMistake(MistakeRecord mistake) async => mistakeList.add(mistake);

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      settings.remove(key);
    } else {
      settings[key] = value;
    }
  }
}

/// A facet state with the given stability, reviewed [ago] before [now].
FacetState stateWith(String facetId, {required double stability, required DateTime now, Duration ago = Duration.zero, bool due = false, int reps = 3}) =>
    FacetState(
      facetId: facetId,
      stability: stability,
      difficulty: 5,
      due: due ? now.subtract(const Duration(hours: 1)) : now.add(Duration(days: max(1, stability.round()))),
      lastReview: now.subtract(ago),
      reps: reps,
      lapses: 0,
      phase: CardPhase.review,
    );
