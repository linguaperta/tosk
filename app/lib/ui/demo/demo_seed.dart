import '../../core/core.dart';

/// Seeds [store] with review history for the demo courses, so the demo map
/// shows strength, decay and tiers. Event ids are fixed (`seed-N`), so seeding
/// a persistent store twice records nothing new.
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
            id: '${course.meta.id}-seed-${n++}',
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
