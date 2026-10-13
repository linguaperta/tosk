/// Skill statistics for the map and debug screen. Pure Dart.
///
/// One store query per call: [SkillStatsService.forSkill] fetches the states of
/// that skill's facets, [SkillStatsService.forCourse] fetches all of the
/// course's states once and computes every skill in Dart (facets shared
/// between skills are evaluated once).
library;

import 'package:meta/meta.dart';

import '../../core/core.dart';

@immutable
class SkillStats {
  const SkillStats({
    required this.skillId,
    required this.itemCount,
    required this.facetCount,
    required this.reviewedFacetCount,
    required this.learnedFacetCount,
    required this.learnedCount,
    required this.dueCount,
    required this.strength,
    required this.minRecall,
    required this.minStability,
    this.lastPracticed,
  });

  final String skillId;
  final int itemCount;
  final int facetCount;

  /// Facets with at least one review.
  final int reviewedFacetCount;

  /// Facets that left the initial learning phase (review or relearning).
  final int learnedFacetCount;

  /// Items whose facets in this skill are all learned (the bronze criterion).
  final int learnedCount;

  /// Reviewed facets due at the evaluation time.
  final int dueCount;

  /// Mean predicted recall across the skill's facets, 0..1 (unreviewed facets count as 0).
  final double strength;

  /// Lowest predicted recall / stability (days) over all facets (0 if any is unreviewed).
  final double minRecall;
  final double minStability;

  /// Most recent review of any of the skill's facets.
  final DateTime? lastPracticed;

  bool get started => reviewedFacetCount > 0;
  bool get allLearned => itemCount > 0 && learnedCount == itemCount;

  @override
  String toString() => 'SkillStats($skillId: items=$itemCount facets=$facetCount '
      'learned=$learnedCount strength=${strength.toStringAsFixed(3)} last=$lastPracticed)';
}

bool isLearnedState(FacetState? s) => s != null && s.phase != CardPhase.learning;

/// Computes stats for [skillId] from already-fetched [states] (facet id -> state).
SkillStats computeSkillStats(
  CourseData course,
  String skillId,
  Map<String, FacetState> states,
  Scheduler scheduler,
  DateTime now, {
  Map<String, double>? recallCache,
}) {
  final facets = course.skillFacets(skillId);
  final items = course.skillItems(skillId);
  var sum = 0.0;
  var reviewed = 0;
  var learned = 0;
  var due = 0;
  var minRecall = facets.isEmpty ? 0.0 : 1.0;
  var minStability = facets.isEmpty ? 0.0 : double.infinity;
  DateTime? last;
  final itemAllLearned = <String, bool>{};
  for (final f in facets) {
    final s = states[f.facetId];
    final r = s == null
        ? 0.0
        : (recallCache == null
            ? scheduler.retrievability(s, now)
            : recallCache.putIfAbsent(f.facetId, () => scheduler.retrievability(s, now)));
    sum += r;
    if (r < minRecall) minRecall = r;
    final stab = s?.stability ?? 0.0;
    if (stab < minStability) minStability = stab;
    final isLearned = isLearnedState(s);
    itemAllLearned[f.itemId] = (itemAllLearned[f.itemId] ?? true) && isLearned;
    if (s == null) continue;
    reviewed++;
    if (isLearned) learned++;
    if (s.isDue(now)) due++;
    if (last == null || s.lastReview.isAfter(last)) last = s.lastReview;
  }
  return SkillStats(
    skillId: skillId,
    itemCount: items.length,
    facetCount: facets.length,
    reviewedFacetCount: reviewed,
    learnedFacetCount: learned,
    learnedCount: itemAllLearned.values.where((v) => v).length,
    dueCount: due,
    strength: facets.isEmpty ? 0 : sum / facets.length,
    minRecall: minRecall,
    minStability: minStability,
    lastPracticed: last,
  );
}

/// Stats for every skill of [course] from one map of states.
Map<String, SkillStats> computeCourseSkillStats(
  CourseData course,
  Map<String, FacetState> states,
  Scheduler scheduler,
  DateTime now,
) {
  final cache = <String, double>{};
  return {
    for (final s in course.skills)
      s.id: computeSkillStats(course, s.id, states, scheduler, now, recallCache: cache),
  };
}

class SkillStatsService {
  SkillStatsService(this.store, this.scheduler);

  final ProgressStore store;
  final Scheduler scheduler;

  /// Stats for one skill (one query for its facets' states).
  Future<SkillStats> forSkill(CourseData course, String skillId, {DateTime? now}) async {
    final ids = [for (final f in course.skillFacets(skillId)) f.facetId];
    final states = await store.states(ids);
    return computeSkillStats(course, skillId, states, scheduler, now ?? DateTime.now().toUtc());
  }

  /// Stats for every skill of the course (one query for all of the course's states).
  Future<Map<String, SkillStats>> forCourse(CourseData course, {DateTime? now}) async {
    final all = await store.allStates(courseId: course.meta.id);
    final states = {for (final s in all) s.facetId: s};
    return computeCourseSkillStats(course, states, scheduler, now ?? DateTime.now().toUtc());
  }
}
