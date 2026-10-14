// Generation speed on the real bundled packs (app/assets/courses/*.sqlite).
// Thresholds are generous (CI machines vary); the printed numbers are the
// interesting part. Targets on a desktop: a single exercise typically < 5 ms,
// a 12-exercise lesson < 100 ms once the course index is warm.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fakes.dart';
import 'helpers.dart';
import 'real_packs.dart';

final _now = DateTime.utc(2026, 10, 13, 12);

FacetState _state(String id, double stability) => FacetState(
      facetId: id,
      stability: stability,
      difficulty: 5,
      due: _now.subtract(const Duration(hours: 1)),
      lastReview: _now.subtract(Duration(days: stability.round())),
      reps: 4,
      lapses: 0,
      phase: CardPhase.review,
    );

double _pct(List<int> us, double p) {
  final s = List.of(us)..sort();
  return s[min(s.length - 1, (s.length * p).floor())] / 1000;
}

void main() {
  for (final id in bundledPackIds()) {
    final path = 'assets/courses/$id.sqlite';
    group('real pack $id performance', () {
      late CourseData course;
      late int warmupMs;
      setUpAll(() {
        course = loadCourseFile(path);
        final sw = Stopwatch()..start();
        // What the first exercise of a session pays once per course.
        final ix = CourseIndex.of(course);
        ix.dropsPronoun(course.meta.persons.first);
        ix.contiguousTense(course.meta.tenses.first);
        warmupMs = sw.elapsedMilliseconds;
      });

      test('course index warm-up', () {
        // ignore: avoid_print
        print('[$id] index warm-up ${warmupMs}ms');
        expect(warmupMs, lessThan(3000));
      });

      test('single exercise generation', () {
        final selector = ExerciseSelector();
        final times = <int>[];
        for (final skill in course.skills) {
          final facets = course.skillFacets(skill.id);
          for (var i = 0; i < 40; i++) {
            final f = facets[i % facets.length];
            final ctx = GenContext(
              course: course,
              options: SessionOptions(sourceLang: course.meta.translations.first),
              random: Random(i),
              states: {if (i.isOdd) f.facetId: _state(f.facetId, i % 4 == 1 ? 3 : 30)},
              skill: skill,
              now: _now,
            );
            final sw = Stopwatch()..start();
            selector.generate(f, ctx);
            times.add(sw.elapsedMicroseconds);
          }
        }
        final median = _pct(times, 0.5);
        final p95 = _pct(times, 0.95);
        // ignore: avoid_print
        print('[$id] exercise generation: median ${median.toStringAsFixed(2)}ms, '
            'p95 ${p95.toStringAsFixed(2)}ms, max ${_pct(times, 1).toStringAsFixed(2)}ms (n=${times.length})');
        expect(median, lessThan(10));
        expect(p95, lessThan(50));
      });

      test('12-exercise lessons', () async {
        final times = <int>[];
        for (final skill in course.skills) {
          for (final stable in [false, true]) {
            final store = InMemoryProgressStore();
            if (stable) {
              for (final f in course.skillFacets(skill.id)) {
                store.stateMap[f.facetId] = _state(f.facetId, 30);
              }
            }
            final factory = EngineSessionFactory(
              course: course,
              store: store,
              scheduler: const FakeScheduler(),
              options: SessionOptions(sourceLang: course.meta.translations.first, seed: 7),
              clock: () => _now,
            );
            final sw = Stopwatch()..start();
            final session = await factory.lesson(skill.id);
            var n = 0;
            for (var e = await session.next(); e != null; e = await session.next()) {
              await session.submit(e, correctAnswer(e), elapsed: const Duration(seconds: 5));
              n++;
            }
            times.add(sw.elapsedMicroseconds);
            expect(n, greaterThanOrEqualTo(10), reason: '${skill.id} served $n exercises');
          }
        }
        final median = _pct(times, 0.5);
        final worst = _pct(times, 1);
        // ignore: avoid_print
        print('[$id] lesson (12 exercises, generate + grade + record): median ${median.toStringAsFixed(1)}ms, '
            'max ${worst.toStringAsFixed(1)}ms (n=${times.length})');
        expect(median, lessThan(250));
        expect(worst, lessThan(1000));
      });
    }, skip: File(path).existsSync() ? false : 'pack $path not built');
  }
}
