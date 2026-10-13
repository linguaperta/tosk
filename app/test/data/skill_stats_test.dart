import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/data/stats/skill_stats.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/course_fixture.dart';

void main() {
  final course = fixtureCourse();
  final scheduler = FsrsScheduler();
  final t0 = DateTime.utc(2026, 5, 1, 9);
  var n = 0;

  ReviewEvent ev(String facet, Rating r, DateTime at) => ReviewEvent(
        id: 'e${n++}'.padLeft(6, '0'),
        facetId: facet,
        at: at,
        rating: r,
        exerciseType: 'flashcard',
        inputMode: InputMode.self,
        responseMs: 1500,
        correct: r != Rating.again,
      );

  test('no progress: zero strength, counts from the course', () async {
    final service = SkillStatsService(InMemoryProgressStore(), scheduler);
    final all = await service.forCourse(course, now: t0);
    expect(all.keys, course.skills.map((s) => s.id));
    final g = all['greetings']!;
    expect(g.itemCount, 5);
    expect(g.facetCount, 10);
    expect(g.strength, 0);
    expect(g.lastPracticed, isNull);
    expect(g.learnedCount, 0);
    expect(g.started, isFalse);
    expect(all['present-are']!.facetCount, 4);
  });

  for (final kind in ['in-memory', 'drift']) {
    test('strength, learned and last practiced ($kind)', () async {
      final ProgressStore store;
      if (kind == 'drift') {
        final repo = ProgressRepo(ProgressDb(NativeDatabase.memory()));
        addTearDown(repo.close);
        store = repo;
      } else {
        store = InMemoryProgressStore();
      }
      // Learn ciao (both facets) with Easy -> review phase; grazie#rec only once (Again).
      await store.record(ev('it:ciao#rec', Rating.easy, t0));
      await store.record(ev('it:ciao#prod', Rating.easy, t0.add(const Duration(minutes: 1))));
      final lastAt = t0.add(const Duration(minutes: 2));
      await store.record(ev('it:grazie#rec', Rating.again, lastAt));
      // Another course's facet must not leak in.
      await store.record(ev('nl:huis#rec', Rating.easy, t0.add(const Duration(days: 1))));

      final service = SkillStatsService(store, scheduler);
      final now = t0.add(const Duration(days: 3));
      final g = await service.forSkill(course, 'greetings', now: now);
      final all = await service.forCourse(course, now: now);
      final gAll = all['greetings']!;

      final rCiaoRec = scheduler.retrievability(await store.state('it:ciao#rec'), now);
      final rCiaoProd = scheduler.retrievability(await store.state('it:ciao#prod'), now);
      final rGrazie = scheduler.retrievability(await store.state('it:grazie#rec'), now);
      final expected = (rCiaoRec + rCiaoProd + rGrazie) / 10;
      expect(g.strength, closeTo(expected, 1e-12));
      expect(gAll.strength, g.strength);
      expect(g.reviewedFacetCount, 3);
      expect(g.learnedFacetCount, 2); // grazie#rec is still learning
      expect(g.learnedCount, 1); // ciao
      expect(g.lastPracticed, lastAt);
      expect(g.minRecall, 0); // unreviewed facets
      expect(g.dueCount, 1); // grazie#rec (1 minute step) is due
      expect(all['food']!.strength, 0);
      expect(all['food']!.lastPracticed, isNull);
    });
  }
}
