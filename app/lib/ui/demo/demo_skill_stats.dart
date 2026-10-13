import '../../core/core.dart';
import '../map/skill_stats.dart';
import 'demo_progress_store.dart';

/// Computes map stats from facet states with the demo forgetting curve.
///
/// TODO(integration): replace with the data layer's skill-strength query plus
/// progression's tier computation (bronze/silver/gold thresholds from the spec).
Future<Map<String, SkillStats>> computeDemoSkillStats(CourseData course, ProgressStore store, DateTime now) async {
  final result = <String, SkillStats>{};
  final allFacets = [for (final s in course.skills) ...course.skillFacets(s.id).map((f) => f.facetId)];
  final states = await store.states(allFacets);

  for (final skill in course.skills) {
    final facets = course.skillFacets(skill.id);
    var sum = 0.0;
    var practiced = 0;
    var minStability = double.infinity;
    DateTime? last;
    for (final f in facets) {
      final st = states[f.facetId];
      sum += demoRetrievability(st, now);
      if (st != null) {
        practiced++;
        if (st.stability < minStability) minStability = st.stability;
        if (last == null || st.lastReview.isAfter(last)) last = st.lastReview;
      }
    }
    final strength = facets.isEmpty ? 0.0 : sum / facets.length;
    MapTier tier;
    if (practiced == 0) {
      tier = MapTier.available;
    } else if (practiced < facets.length) {
      tier = MapTier.started;
    } else if (strength >= 0.9 && minStability >= 21) {
      tier = MapTier.gold;
    } else if (strength >= 0.85 && minStability >= 7) {
      tier = MapTier.silver;
    } else {
      tier = MapTier.bronze;
    }
    result[skill.id] = SkillStats(
      strength: strength,
      lastPracticed: last,
      tier: tier,
      practicedFacets: practiced,
      totalFacets: facets.length,
    );
  }

  // Locked: some prerequisite has never been practiced and this skill hasn't either.
  for (final skill in course.skills) {
    final s = result[skill.id]!;
    if (s.practiced) continue;
    final blocked = skill.requires.any((r) => result[r] != null && !result[r]!.practiced);
    if (blocked) {
      result[skill.id] = SkillStats(tier: MapTier.locked, totalFacets: s.totalFacets);
    }
  }
  return result;
}

/// Seeds a store with review history so the demo map shows strength, decay and tiers.
Future<void> seedDemoProgress(ProgressStore store, CourseData course, DateTime now) async {
  final plan = <String, (int daysAgo, int reps)>{
    'greetings': (1, 4),
    'food': (9, 2),
    'articles': (25, 1),
    'groeten': (2, 3),
  };
  var n = 0;
  for (final entry in plan.entries) {
    if (course.skill(entry.key) == null) continue;
    final (daysAgo, reps) = entry.value;
    for (final f in course.skillFacets(entry.key)) {
      for (var r = 0; r < reps; r++) {
        final at = now.subtract(Duration(days: daysAgo + (reps - r) * 3)).toUtc();
        await store.record(
          ReviewEvent(
            id: 'seed-${n++}',
            facetId: f.facetId,
            at: at,
            rating: Rating.good,
            exerciseType: ExerciseType.flashcard.id,
            inputMode: InputMode.self,
            responseMs: 2000,
            correct: true,
            mode: 'lesson',
          ),
        );
      }
    }
  }
}
