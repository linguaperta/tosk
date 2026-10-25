/// Log replay shared by [ProgressRepo] and [InMemoryProgressStore]. Pure Dart.
///
/// Ordering rule (used everywhere): events are applied in `(at, id)` order,
/// `at` in UTC milliseconds, ties broken by the event id (ASCII UUIDs compare
/// the same in Dart and in SQLite's BINARY collation).
library;

import '../../core/core.dart';

/// Truncates to whole milliseconds in UTC (the precision stored in the DB).
DateTime toStoredTime(DateTime t) =>
    DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);

/// Returns [e] with `at` normalized by [toStoredTime].
ReviewEvent normalizeEvent(ReviewEvent e) {
  final at = toStoredTime(e.at);
  if (at == e.at) return e;
  return ReviewEvent(
    id: e.id,
    facetId: e.facetId,
    at: at,
    rating: e.rating,
    exerciseType: e.exerciseType,
    inputMode: e.inputMode,
    responseMs: e.responseMs,
    correct: e.correct,
    answer: e.answer,
    sessionId: e.sessionId,
    mode: e.mode,
  );
}

/// Compares two events by `(at, id)`.
int compareEventKeys(int atMsA, String idA, int atMsB, String idB) {
  final c = atMsA.compareTo(atMsB);
  return c != 0 ? c : idA.compareTo(idB);
}

int compareEvents(ReviewEvent a, ReviewEvent b) =>
    compareEventKeys(a.at.millisecondsSinceEpoch, a.id, b.at.millisecondsSinceEpoch, b.id);

/// Folds [events] of ONE facet (already in `(at, id)` order) into its state.
/// Answer overrides and reset undos are applied first ([replayable]); a
/// skill reset clears the state ([replayStep]).
FacetState? foldFacet(Scheduler scheduler, String facetId, Iterable<ReviewEvent> events) {
  FacetState? s;
  for (final e in replayable(events.toList())) {
    s = replayStep(scheduler, s, normalizeEvent(e));
  }
  return s;
}

/// Replays a whole log (any order) into states keyed by facet id (facets
/// whose last word was a skill reset have none). See [foldFacet].
Map<String, FacetState> replayLog(Scheduler scheduler, Iterable<ReviewEvent> events) {
  final sorted = events.toList()..sort(compareEvents);
  final out = <String, FacetState>{};
  for (final e in replayable(sorted)) {
    final s = replayStep(scheduler, out[e.facetId], normalizeEvent(e));
    if (s == null) {
      out.remove(e.facetId);
    } else {
      out[e.facetId] = s;
    }
  }
  return out;
}

/// Exclusive upper bound for ids starting with `'{courseId}:'` (`':'` + 1 = `';'`),
/// so a prefix filter becomes an index-friendly range: `id >= lo AND id < hi`.
(String lo, String hi) courseIdRange(String courseId) => ('$courseId:', '$courseId;');

bool facetInCourse(String facetId, String courseId) => facetId.startsWith('$courseId:');
