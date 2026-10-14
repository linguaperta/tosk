/// Stories: what has been read (from the review log) and which units' stories
/// are open. See docs/ARCHITECTURE.md, "Stories".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../map/skill_stats.dart';

/// What the log says about one story.
@immutable
class StoryRecord {
  const StoryRecord({required this.reads, required this.bestCorrect, required this.total, required this.lastRead});
  final int reads;
  final int bestCorrect;
  final int total;
  final DateTime lastRead;
}

/// Folds story read events (`kStoryReadType`) into one record per story id.
Map<String, StoryRecord> storyRecordsOf(Iterable<ReviewEvent> events) {
  final out = <String, StoryRecord>{};
  for (final e in events) {
    if (!e.isStory) continue;
    final id = storyIdOfFacet(e.facetId);
    if (id == null) continue;
    final score = storyScoreOf(e) ?? (correct: 0, total: 0);
    final old = out[id];
    out[id] = StoryRecord(
      reads: (old?.reads ?? 0) + 1,
      bestCorrect: old == null || score.correct > old.bestCorrect ? score.correct : old.bestCorrect,
      total: score.total > 0 ? score.total : (old?.total ?? 0),
      lastRead: old == null || e.at.isAfter(old.lastRead) ? e.at : old.lastRead,
    );
  }
  return out;
}

/// Units whose stories are open: every skill of the unit that trains facets
/// has been started (practiced or tested out), so the learner has met all of
/// the unit's words and grammar. A locked story can still be read as a preview.
Set<String> storyUnitsUnlocked(CourseData course, Map<String, SkillStats> stats) {
  final out = <String>{};
  for (final u in course.units) {
    final skills = [for (final s in course.skills) if (s.unitId == u.id && course.skillFacets(s.id).isNotEmpty) s];
    if (skills.isEmpty) continue;
    if (skills.every((s) => stats[s.id]?.practiced ?? false)) out.add(u.id);
  }
  return out;
}

/// Story records of the active course; refreshed after every session or read.
final storyRecordsProvider = FutureProvider<Map<String, StoryRecord>>((ref) async {
  ref.watch(progressRevisionProvider);
  final course = await ref.watch(courseDataProvider.future);
  if (course.stories.isEmpty) return const {};
  final store = ref.watch(progressStoreProvider);
  return storyRecordsOf(await store.log(courseId: course.meta.id));
});

/// Units of the active course whose stories are unlocked.
final storyUnitsUnlockedProvider = FutureProvider<Set<String>>((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  if (course.stories.isEmpty) return const {};
  final stats = await ref.watch(skillStatsProvider.future);
  return storyUnitsUnlocked(course, stats);
});
