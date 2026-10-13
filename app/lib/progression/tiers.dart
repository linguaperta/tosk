/// Skill mastery tiers and the map's "fading" signal. See docs/progression.md.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/core.dart';

/// A skill's tier on the map, lowest first.
enum SkillTier {
  /// A prerequisite skill has not been started yet.
  locked,

  /// Unlocked, but no facet of the skill has been reviewed.
  available,

  /// At least one facet reviewed.
  started,

  /// Every facet learned (reviewed and graduated out of the initial learning phase).
  bronze,

  /// Bronze, and every facet has R ≥ 0.85 now and stability ≥ 7 days.
  silver,

  /// Bronze, and every facet has R ≥ 0.90 now and stability ≥ 21 days.
  gold;

  bool get isMedal => index >= SkillTier.bronze.index;
  bool operator >(SkillTier o) => index > o.index;
  bool operator <(SkillTier o) => index < o.index;
}

@immutable
class TierRules {
  const TierRules({
    this.silverRecall = 0.85,
    this.silverStabilityDays = 7,
    this.goldRecall = 0.90,
    this.goldStabilityDays = 21,
    this.fadeTarget = 0.90,
    this.fadeFloor = 0.50,
  });

  final double silverRecall;
  final double silverStabilityDays;
  final double goldRecall;
  final double goldStabilityDays;

  /// Per-facet fade is 0 at R ≥ [fadeTarget] and 1 at R ≤ [fadeFloor], linear between.
  final double fadeTarget;
  final double fadeFloor;

  /// Learned = reviewed at least once and out of the initial learning phase
  /// (FSRS phase review or relearning; relearning means it graduated before).
  bool isLearned(FacetState? s) => s != null && s.reps > 0 && s.phase != CardPhase.learning;

  bool meetsSilver(FacetState? s, double r) =>
      isLearned(s) && r >= silverRecall && s!.stability >= silverStabilityDays;

  bool meetsGold(FacetState? s, double r) =>
      isLearned(s) && r >= goldRecall && s!.stability >= goldStabilityDays;

  double fadeOf(double r) {
    if (fadeTarget <= fadeFloor) return r < fadeTarget ? 1 : 0;
    return ((fadeTarget - r) / (fadeTarget - fadeFloor)).clamp(0.0, 1.0);
  }
}

/// A skill's progress at a given instant.
@immutable
class SkillProgress {
  const SkillProgress({
    required this.skillId,
    required this.tier,
    required this.facetCount,
    required this.reviewedCount,
    required this.learnedCount,
    required this.silverCount,
    required this.goldCount,
    required this.dueCount,
    required this.strength,
    required this.fading,
    required this.minRetrievability,
    this.lastPracticed,
  });

  final String skillId;
  final SkillTier tier;
  final int facetCount;

  /// Facets reviewed at least once.
  final int reviewedCount;

  /// Facets learned (see [TierRules.isLearned]).
  final int learnedCount;

  /// Facets meeting the silver / gold criteria right now.
  final int silverCount;
  final int goldCount;

  /// Reviewed facets that are due now.
  final int dueCount;

  /// Mean predicted recall across all facets (never-reviewed facets count as 0).
  final double strength;

  /// 0 = fresh … 1 = badly faded: mean per-facet fade over *reviewed* facets.
  /// 0 for a skill that was never started (new, not faded). Use it to desaturate the map.
  final double fading;

  /// Lowest predicted recall among reviewed facets (1 when none reviewed).
  final double minRetrievability;

  /// Most recent review of any facet in the skill.
  final DateTime? lastPracticed;

  /// Fraction of facets that satisfy the next tier's requirement (for a progress ring).
  double get nextTierProgress {
    if (facetCount == 0) return 0;
    return switch (tier) {
      SkillTier.locked || SkillTier.available || SkillTier.started => learnedCount / facetCount,
      SkillTier.bronze => silverCount / facetCount,
      SkillTier.silver => goldCount / facetCount,
      SkillTier.gold => 1,
    };
  }

  /// Whole days since [lastPracticed] at [now], or null if never practiced.
  int? daysSincePracticed(DateTime now) =>
      lastPracticed == null ? null : now.difference(lastPracticed!).inDays;

  @override
  String toString() =>
      'SkillProgress($skillId, $tier, learned $learnedCount/$facetCount, strength ${strength.toStringAsFixed(2)}, fading ${fading.toStringAsFixed(2)})';
}

/// Progress of one skill, ignoring prerequisites (tier is at least [SkillTier.available]).
SkillProgress skillProgressOf({
  required String skillId,
  required List<String> facetIds,
  required Map<String, FacetState> states,
  required Scheduler scheduler,
  required DateTime now,
  TierRules rules = const TierRules(),
}) {
  var reviewed = 0, learned = 0, silver = 0, gold = 0, due = 0;
  var rSum = 0.0, fadeSum = 0.0, minR = 1.0;
  DateTime? last;
  for (final f in facetIds) {
    final s = states[f];
    if (s == null) continue;
    reviewed++;
    final r = scheduler.retrievability(s, now).clamp(0.0, 1.0);
    rSum += r;
    fadeSum += rules.fadeOf(r);
    minR = math.min(minR, r);
    if (rules.isLearned(s)) learned++;
    if (rules.meetsSilver(s, r)) silver++;
    if (rules.meetsGold(s, r)) gold++;
    if (s.isDue(now)) due++;
    if (last == null || s.lastReview.isAfter(last)) last = s.lastReview;
  }
  final n = facetIds.length;
  SkillTier tier;
  if (reviewed == 0) {
    tier = SkillTier.available;
  } else if (n > 0 && gold == n) {
    tier = SkillTier.gold;
  } else if (n > 0 && silver == n) {
    tier = SkillTier.silver;
  } else if (n > 0 && learned == n) {
    tier = SkillTier.bronze;
  } else {
    tier = SkillTier.started;
  }
  return SkillProgress(
    skillId: skillId,
    tier: tier,
    facetCount: n,
    reviewedCount: reviewed,
    learnedCount: learned,
    silverCount: silver,
    goldCount: gold,
    dueCount: due,
    strength: n == 0 ? 0 : rSum / n,
    fading: reviewed == 0 ? 0 : fadeSum / reviewed,
    minRetrievability: minR,
    lastPracticed: last,
  );
}

/// Progress and tier of every skill in [course], keyed by skill id (course order).
///
/// A skill is [SkillTier.locked] when it has not been started and some
/// prerequisite has not been started (prerequisites without facets, or unknown
/// ids, count as satisfied). A started skill is never shown as locked, e.g.
/// when practiced through the exercise lab.
Map<String, SkillProgress> computeSkillProgress({
  required CourseData course,
  required Map<String, FacetState> states,
  required Scheduler scheduler,
  required DateTime now,
  TierRules rules = const TierRules(),
}) {
  final out = <String, SkillProgress>{};
  for (final skill in course.skills) {
    out[skill.id] = skillProgressOf(
      skillId: skill.id,
      facetIds: [for (final f in course.skillFacets(skill.id)) f.facetId],
      states: states,
      scheduler: scheduler,
      now: now,
      rules: rules,
    );
  }
  bool satisfied(String prereq) {
    final p = out[prereq];
    return p == null || p.facetCount == 0 || p.reviewedCount > 0;
  }

  for (final skill in course.skills) {
    final p = out[skill.id]!;
    if (p.tier == SkillTier.available && !skill.requires.every(satisfied)) {
      out[skill.id] = SkillProgress(
        skillId: p.skillId,
        tier: SkillTier.locked,
        facetCount: p.facetCount,
        reviewedCount: p.reviewedCount,
        learnedCount: p.learnedCount,
        silverCount: p.silverCount,
        goldCount: p.goldCount,
        dueCount: p.dueCount,
        strength: p.strength,
        fading: p.fading,
        minRetrievability: p.minRetrievability,
        lastPracticed: p.lastPracticed,
      );
    }
  }
  return out;
}
