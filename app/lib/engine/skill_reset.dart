/// "Reset this skill": the learner says the app over-estimated a skill
/// (placement, test out or plain luck), so its words and grammar are treated
/// as new again. Written as [kResetType] events in the review log (one per
/// facet that has a state), so every replay (`rebuildStates()`, sync merges,
/// progression) reproduces it; the Undo writes [kResetUndoType] events that
/// cancel them. The answer history stays: XP, streaks and stats don't change.
/// See docs/engine.md, "Skill reset".
library;

import 'package:uuid/uuid.dart';

import '../core/interfaces/course_data.dart';
import '../core/interfaces/progress_store.dart';
import '../core/models/progress.dart';

/// Session mode stored on reset and undo events.
const String kResetMode = 'reset';

/// What resetting [skillIds] touches: every facet the skills train (shared
/// facets included: a word is one word in every skill), in course order, with
/// the first of [skillIds] that trains it.
List<(String facetId, String skillId)> resetFacets(CourseData course, Iterable<String> skillIds) {
  final seen = <String>{};
  return [
    for (final s in skillIds)
      for (final f in course.skillFacets(s))
        if (seen.add(f.facetId)) (f.facetId, s),
  ];
}

/// The facets of [skillIds] that the learner has studied (a state exists):
/// what a reset would actually change.
Future<List<(String facetId, String skillId)>> resettableFacets(
  ProgressStore store,
  CourseData course,
  Iterable<String> skillIds,
) async {
  final all = resetFacets(course, skillIds);
  final states = await store.states(all.map((f) => f.$1));
  return [for (final f in all) if (states.containsKey(f.$1)) f];
}

/// Resets [skillIds]: one [kResetType] event per studied facet, all at [now]
/// with one batch id as the session id. Returns the events written (empty
/// when nothing was studied), which [undoReset] takes.
Future<List<ReviewEvent>> resetSkills(
  ProgressStore store,
  CourseData course,
  Iterable<String> skillIds, {
  required DateTime now,
}) async {
  final batch = const Uuid().v4();
  final at = now.toUtc();
  final events = [
    for (final (facetId, skillId) in await resettableFacets(store, course, skillIds))
      ReviewEvent(
        id: const Uuid().v4(),
        facetId: facetId,
        at: at,
        rating: Rating.again,
        exerciseType: kResetType,
        inputMode: InputMode.self,
        responseMs: 0,
        correct: false,
        answer: skillId,
        sessionId: batch,
        mode: kResetMode,
      ),
  ];
  for (final e in events) {
    await store.record(e);
  }
  return events;
}

/// Undoes a reset: one [kResetUndoType] event per reset event, on its facet,
/// at [now] (not before the reset), carrying the reset's id. Replays then skip
/// both, so the facets are as they were.
Future<List<ReviewEvent>> undoReset(ProgressStore store, List<ReviewEvent> resets, {required DateTime now}) async {
  final events = [
    for (final r in resets)
      if (r.isReset)
        ReviewEvent(
          id: const Uuid().v4(),
          facetId: r.facetId,
          at: now.toUtc().isAfter(r.at) ? now.toUtc() : r.at.add(const Duration(milliseconds: 1)),
          rating: Rating.again,
          exerciseType: kResetUndoType,
          inputMode: InputMode.self,
          responseMs: 0,
          correct: false,
          answer: r.id,
          sessionId: r.sessionId,
          mode: kResetMode,
        ),
  ];
  for (final e in events) {
    await store.record(e);
  }
  return events;
}
