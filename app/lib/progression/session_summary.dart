/// End-of-session progression summary: XP, level-up, improved words, tier changes.
library;

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'replay.dart';
import 'tiers.dart';
import 'xp.dart';

/// How one facet changed over the session.
@immutable
class FacetChange {
  const FacetChange({
    required this.facetId,
    required this.before,
    required this.after,
    required this.recallBefore,
    required this.recallAfter,
    required this.reviews,
    required this.mistakes,
  });

  final String facetId;

  /// State before the session (null = new facet).
  final FacetState? before;
  final FacetState after;

  /// Predicted recall at session start (0 for a new facet) and at session end.
  final double recallBefore;
  final double recallAfter;

  /// Events for this facet in the session, and how many were wrong.
  final int reviews;
  final int mistakes;

  String get itemId {
    final i = facetId.lastIndexOf('#');
    return i <= 0 ? facetId : facetId.substring(0, i);
  }

  bool get isNew => before == null;

  /// New, its stability grew, or it graduated into the review phase.
  bool get improved {
    final b = before;
    if (b == null) return true;
    if (after.stability > b.stability) return true;
    return b.phase != CardPhase.review && after.phase == CardPhase.review;
  }
}

@immutable
class TierChange {
  const TierChange({required this.skillId, required this.from, required this.to});
  final String skillId;
  final SkillTier from;
  final SkillTier to;
  bool get isUp => to > from;
}

/// Progression results of one session, derived from the log.
@immutable
class SessionProgressSummary {
  const SessionProgressSummary({
    required this.sessionId,
    required this.mode,
    required this.startedAt,
    required this.endedAt,
    required this.reviews,
    required this.correct,
    required this.xpEarned,
    required this.levelBefore,
    required this.levelAfter,
    required this.facetChanges,
    required this.tierChanges,
  });

  final String sessionId;
  final String? mode;
  final DateTime startedAt;
  final DateTime endedAt;

  /// Review events in the session (one per graded facet outcome) and how many were correct.
  final int reviews;
  final int correct;
  final int xpEarned;

  /// Level from all XP before the first and after the last event of the session.
  final LevelInfo levelBefore;
  final LevelInfo levelAfter;

  /// One entry per facet practiced, in first-practiced order.
  final List<FacetChange> facetChanges;

  /// Skills of the course whose tier differs, evaluated at [endedAt] with the
  /// states before vs. after the session's own events (isolates the session's
  /// effect from decay and from interleaved events of other sessions).
  final List<TierChange> tierChanges;

  double get accuracy => reviews == 0 ? 0 : correct / reviews;
  bool get leveledUp => levelAfter.level > levelBefore.level;
  int get levelsGained => levelAfter.level - levelBefore.level;

  List<FacetChange> get improvedFacets => [for (final c in facetChanges) if (c.improved) c];
  List<FacetChange> get newFacets => [for (final c in facetChanges) if (c.isNew) c];

  /// Item ids with at least one improved facet, in first-practiced order.
  List<String> get improvedItemIds {
    final seen = <String>{};
    return [for (final c in improvedFacets) if (seen.add(c.itemId)) c.itemId];
  }
}

/// Summarizes [sessionId] from a replay, or null if it has no events.
SessionProgressSummary? summarizeSession({
  required String sessionId,
  required LogReplay replay,
  required Scheduler scheduler,
  CourseData? course,
  LevelCurve curve = const LevelCurve(),
  TierRules tierRules = const TierRules(),
}) {
  final steps = replay.steps;
  final idx = <int>[
    for (var i = 0; i < steps.length; i++)
      if (steps[i].event.sessionId == sessionId) i,
  ];
  if (idx.isEmpty) return null;
  final first = idx.first, last = idx.last;
  final startedAt = steps[first].event.at;
  final endedAt = steps[last].event.at;

  final statesBefore = replay.statesAfterSteps(first);
  // Before-states overlaid with this session's own results only, so events of
  // other sessions interleaved in time (another device) don't leak in.
  final statesAfter = Map.of(statesBefore);
  for (final i in idx) {
    statesAfter[steps[i].event.facetId] = steps[i].after;
  }

  var xp = 0, correct = 0;
  final order = <String>[];
  final reviews = <String, int>{};
  final mistakes = <String, int>{};
  for (final i in idx) {
    final s = steps[i];
    final f = s.event.facetId;
    xp += s.xp;
    if (s.event.correct) {
      correct++;
    } else {
      mistakes[f] = (mistakes[f] ?? 0) + 1;
    }
    if (!reviews.containsKey(f)) order.add(f);
    reviews[f] = (reviews[f] ?? 0) + 1;
  }

  final xpBefore = first == 0 ? 0 : steps[first - 1].cumulativeXp;
  final changes = [
    for (final f in order)
      FacetChange(
        facetId: f,
        before: statesBefore[f],
        after: statesAfter[f]!,
        recallBefore: scheduler.retrievability(statesBefore[f], startedAt),
        recallAfter: scheduler.retrievability(statesAfter[f], endedAt),
        reviews: reviews[f]!,
        mistakes: mistakes[f] ?? 0,
      ),
  ];

  final tierChanges = <TierChange>[];
  if (course != null) {
    final tb = computeSkillProgress(
        course: course, states: statesBefore, scheduler: scheduler, now: endedAt, rules: tierRules);
    final ta = computeSkillProgress(
        course: course, states: statesAfter, scheduler: scheduler, now: endedAt, rules: tierRules);
    for (final skill in course.skills) {
      final a = tb[skill.id]!.tier, b = ta[skill.id]!.tier;
      if (a != b) tierChanges.add(TierChange(skillId: skill.id, from: a, to: b));
    }
  }

  return SessionProgressSummary(
    sessionId: sessionId,
    mode: steps[first].event.mode,
    startedAt: startedAt,
    endedAt: endedAt,
    reviews: idx.length,
    correct: correct,
    xpEarned: xp,
    levelBefore: curve.levelFor(xpBefore),
    levelAfter: curve.levelFor(steps[last].cumulativeXp),
    facetChanges: List.unmodifiable(changes),
    tierChanges: List.unmodifiable(tierChanges),
  );
}
