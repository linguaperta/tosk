// A pack update may drop items (item ids are permanent, never reused). Their
// facets stay in the review log and facet states; they must simply stop being
// scheduled: every session builder, the skill stats, mistakes and progression
// work as if they weren't there.
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/data/stats/skill_stats.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/course_fixture.dart';
import 'helpers.dart';

void main() {
  final now = DateTime.utc(2026, 10, 14, 12);
  const gone = ['it:scomparso#rec', 'it:scomparso#prod', 'it:sparito#form:presente'];

  test('facets of removed items are ignored by sessions, stats, mistakes and progression', () async {
    final course = fixtureCourseRepo();
    final scheduler = FsrsScheduler();
    final store = InMemoryProgressStore(scheduler: scheduler);
    final real = course.skillFacets(course.skills.first.id).first.facetId;
    var n = 0;
    for (final facet in [...gone, real]) {
      for (final days in [9, 5, 1]) {
        final at = now.subtract(Duration(days: days));
        await store.record(
          ReviewEvent(
            id: 'e${n++}',
            facetId: facet,
            at: at,
            rating: days == 1 ? Rating.again : Rating.good,
            exerciseType: 'flashcard',
            inputMode: InputMode.self,
            responseMs: 900,
            correct: days != 1,
          ),
        );
        if (days == 1) {
          await store.saveMistake(
            MistakeRecord(
              id: 'e${n - 1}',
              facetId: facet,
              at: at,
              exerciseType: 'flashcard',
              prompt: 'x',
              expected: 'y',
              given: 'z',
            ),
          );
        }
      }
    }
    expect((await store.allStates(courseId: 'it')).length, gone.length + 1);

    final stats = await SkillStatsService(store, scheduler).forCourse(course, now: now);
    expect(stats.keys.toSet(), course.skills.map((s) => s.id).toSet());

    final factory = EngineSessionFactory(
      course: course,
      store: store,
      scheduler: scheduler,
      options: const SessionOptions(sourceLang: 'en', seed: 3),
      clock: () => now,
    );
    Future<List<Exercise>> drain(PracticeSession s) async {
      final out = <Exercise>[];
      for (var i = 0; i < 40; i++) {
        final e = await s.next();
        if (e == null) break;
        out.add(e);
        await s.submit(e, correctAnswer(e), elapsed: const Duration(seconds: 3));
      }
      return out;
    }

    final sessions = <String, PracticeSession>{
      'lesson': await factory.lesson(course.skills.first.id),
      'non-stop': await factory.nonStop(),
      'fading': await factory.fading(),
      'mistakes': await factory.review(),
      'tough words': await factory.toughWords(minLapses: 1),
    };
    for (final MapEntry(key: name, value: s) in sessions.entries) {
      final served = await drain(s);
      for (final e in served) {
        expect(gone, isNot(contains(e.facetId)), reason: '$name served a removed facet');
      }
    }
    final mistakes = await openMistakes(store: store, course: course, scheduler: scheduler, now: now);
    expect(mistakes.map((m) => m.record.facetId), isNot(contains(anyOf(gone))));

    final progression = ProgressionService(store: store, scheduler: scheduler, course: course, clock: () => now);
    await progression.profile(now);
    await progression.skillTiers(now);
    await progression.verbCollection(now);
  });
}
