// Placement on the real packs (app/assets/courses/*.sqlite, and a French pack
// from tosk-data/dist when one is there): simulated learners place where they
// should, within the length cap, on main trees of 15-20 units.
//
// * perfect: every answer right -> placed past the last unit, everything credited;
// * beginner: every answer wrong -> unit 1, nothing credited;
// * mid: knows units 1..k -> placed into unit k+1, units 1..k credited;
// * noisy learners (90 % right on what they know, 25 % on what they don't:
//   guessing) place within a unit of where they should, most of the time.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/course_builder.dart';
import 'helpers.dart';
import 'real_packs.dart';

final _now = DateTime.utc(2026, 10, 25, 12);

/// Extra packs to simulate besides the bundled ones: `TOSK_EXTRA_PACKS`
/// (comma-separated paths), else a French pack in tosk-data/dist if present
/// (the checkout next to this repo, or next to the main checkout of a worktree).
List<String> _extraPacks() {
  final env = Platform.environment['TOSK_EXTRA_PACKS'];
  if (env != null && env.trim().isNotEmpty) return [for (final p in env.split(',')) if (File(p.trim()).existsSync()) p.trim()];
  for (final p in const [
    '../../tosk-data/dist/fr.sqlite',
    '../../duelingo-data/dist/fr.sqlite',
    '../../../../../tosk-data/dist/fr.sqlite',
    '../../../../../duelingo-data/dist/fr.sqlite',
  ]) {
    if (File(p).existsSync()) return [p];
  }
  return const [];
}

class _Run {
  _Run(this.outcome, this.asked, this.course);
  final AssessmentOutcome outcome;
  final int asked;
  final CourseData course;

  List<Unit> get main => CourseTrees.of(course).mainUnits;

  /// 1-based number of the placed unit; main.length + 1 past the end.
  int get placed {
    final id = outcome.placedUnit;
    return id == null ? main.length + 1 : main.indexWhere((u) => u.id == id) + 1;
  }
}

const _letters = 'bcdfghlmnprstvz';

/// A synthetic main tree of [units] units (two vocabulary skills of six
/// words each), for the length cap on trees longer than the bundled ones
/// (French will have about 20 units).
InMemoryCourseData _longCourse(int units) {
  final b = CourseBuilder(CourseMeta(
    id: 'lx$units',
    version: '0.1.0',
    title: const {'en': 'Long'},
    target: 'lx',
    translations: const ['en'],
    persons: const [],
    tenses: const [],
    tenseLabels: const {},
    articles: const [],
    attribution: 'Synthetic test fixture.',
  ));
  String w(int u, int i) => '${_letters[u % 15]}a${_letters[(u ~/ 15) % 15]}o${_letters[i]}i';
  for (var u = 0; u < units; u++) {
    b.unit('u$u', u, 'Unit ${u + 1}', 'Unit ${u + 1}');
    for (var i = 0; i < 12; i++) {
      b.word(w(u, i), 'noun', en: ['thing ${u + 1}-${i + 1}'], freq: 100 + u * 12 + i);
    }
    b.vocabSkill('a$u', 0, 'A ${u + 1}', 'A', [for (var i = 0; i < 6; i++) w(u, i)], requires: [if (u > 0) 'b${u - 1}']);
    b.vocabSkill('b$u', 1, 'B ${u + 1}', 'B', [for (var i = 6; i < 12; i++) w(u, i)], requires: ['a$u']);
  }
  return b.build();
}

/// Runs a placement on [course] for a learner who answers right when [knows]
/// says so (the 0-based main unit of the exercise's skill).
Future<(AssessmentOutcome, int)> _place(CourseData course, bool Function(int? unit) knows, {int seed = 1}) async {
  final main = CourseTrees.of(course).mainUnits;
  final index = {for (var i = 0; i < main.length; i++) main[i].id: i};
  final unitOf = {for (final s in course.skills) s.id: index[s.unitId]};
  final store = InMemoryProgressStore(scheduler: FsrsScheduler());
  var clock = _now;
  final factory = EngineSessionFactory(
    course: course,
    store: store,
    scheduler: FsrsScheduler(),
    options: SessionOptions(sourceLang: course.meta.translations.first, seed: seed, listening: true),
    clock: () => clock,
  );
  final s = await factory.placement();
  var asked = 0;
  for (var i = 0; i < 200; i++) {
    final e = await s.next();
    if (e == null) break;
    asked++;
    await s.submit(e, knows(unitOf[e.skillId]) ? correctAnswer(e) : wrongAnswer(e), elapsed: const Duration(seconds: 8));
    clock = clock.add(const Duration(seconds: 20));
  }
  return (s.outcome!, asked);
}

void main() {
  group('placement on long synthetic trees', () {
    for (final n in const [20, 24, 30]) {
      test('$n units: perfect, beginner and mid learners within the cap', () async {
        final course = _longCourse(n);
        final (perfect, a1) = await _place(course, (_) => true);
        final (beginner, a2) = await _place(course, (_) => false);
        final k = (n * 3) ~/ 4;
        final (mid, a3) = await _place(course, (u) => u != null && u < k);
        // ignore: avoid_print
        print('$n units: perfect ${perfect.passedUnits.length} credited in $a1 exercises; '
            'beginner placed ${beginner.placedUnit} in $a2; knows 1-$k placed ${mid.placedUnit} in $a3');
        expect(perfect.placedUnit, isNull);
        expect(perfect.passedUnits.length, n);
        expect(beginner.placedUnit, 'u0');
        expect(mid.placedUnit, 'u$k');
        for (final a in [a1, a2, a3]) {
          expect(a, lessThanOrEqualTo(kPlacementMaxExercises));
        }
      });
    }
  });

  final packs = [
    for (final id in bundledPackIds()) 'assets/courses/$id.sqlite',
    ..._extraPacks(),
  ];
  if (packs.isEmpty) {
    test('no packs', () {}, skip: 'no course packs found');
    return;
  }

  for (final path in packs) {
    final name = path.split('/').last.replaceAll('.sqlite', '');
    group('placement on $name', () {
      late CourseData course;
      late List<Unit> main;
      late Map<String, int> unitOfSkill; // skill id -> 0-based main unit index

      setUpAll(() {
        course = loadCourseFile(path);
        main = CourseTrees.of(course).mainUnits;
        final index = {for (var i = 0; i < main.length; i++) main[i].id: i};
        unitOfSkill = {
          for (final s in course.skills)
            if (index[s.unitId] != null) s.id: index[s.unitId]!,
        };
      });

      /// Runs a placement for a learner who answers right when [knows] says so.
      Future<_Run> run(bool Function(Exercise e, int? unit) knows, {int seed = 1}) async {
        final store = InMemoryProgressStore(scheduler: FsrsScheduler());
        var clock = _now;
        final factory = EngineSessionFactory(
          course: course,
          store: store,
          scheduler: FsrsScheduler(),
          options: SessionOptions(sourceLang: course.meta.translations.first, seed: seed, listening: true),
          clock: () => clock,
        );
        final s = await factory.placement();
        var asked = 0;
        for (var i = 0; i < 200; i++) {
          final e = await s.next();
          if (e == null) break;
          asked++;
          final unit = unitOfSkill[e.skillId];
          await s.submit(e, knows(e, unit) ? correctAnswer(e) : wrongAnswer(e), elapsed: const Duration(seconds: 8));
          clock = clock.add(const Duration(seconds: 20));
        }
        return _Run(s.outcome!, asked, course);
      }

      test('a perfect learner places past the last unit within the cap', () async {
        final r = await run((_, _) => true);
        // ignore: avoid_print
        print('$name: ${main.length} main units; perfect learner: ${r.asked} exercises, '
            'placed ${r.placed}, credited ${r.outcome.passedUnits.length} units '
            '(${r.outcome.inferredUnits.length} by a jump)');
        expect(r.asked, lessThanOrEqualTo(kPlacementMaxExercises));
        expect(r.outcome.placedUnit, isNull);
        expect(r.outcome.passedUnits.length, main.where((u) => course.skills.any((s) => s.unitId == u.id && course.skillFacets(s.id).isNotEmpty)).length);
        expect(r.outcome.failedUnit, isNull);
      });

      test('a beginner places into unit 1 with nothing credited', () async {
        final r = await run((_, _) => false);
        // ignore: avoid_print
        print('$name: beginner: ${r.asked} exercises, placed ${r.placed}');
        expect(r.placed, 1);
        expect(r.outcome.creditedSkills, isEmpty);
        expect(r.asked, lessThanOrEqualTo(8));
      });

      test('a mid learner places mid', () async {
        for (final k in {main.length ~/ 3, main.length ~/ 2, (main.length * 2) ~/ 3}) {
          final r = await run((_, unit) => unit != null && unit < k);
          // ignore: avoid_print
          print('$name: knows units 1-$k: ${r.asked} exercises, placed ${r.placed}, '
              'credited ${r.outcome.passedUnits.length}');
          expect(r.placed, k + 1, reason: 'knows 1..$k');
          expect(r.outcome.passedUnits, [for (final u in main.take(k)) u.id]);
          expect(r.asked, lessThanOrEqualTo(kPlacementMaxExercises));
        }
      });

      // A unit the test asks (unit 2: no jump has started yet). A unit a jump
      // skipped is credited with the unit after it (units build on each other).
      test('a gap: one unknown unit between known ones stays open', () async {
        const gap = 1; // unit 2
        final r = await run((_, unit) => unit != gap);
        // ignore: avoid_print
        print('$name: knows everything but unit 2: ${r.asked} exercises, placed ${r.placed}, '
            'gaps ${r.outcome.gapUnits}');
        expect(r.outcome.gapUnits, [main[gap].id]);
        expect(r.outcome.passedUnits, isNot(contains(main[gap].id)));
        expect(r.outcome.passedUnits.length, greaterThan(gap + 2));
        expect(r.asked, lessThanOrEqualTo(kPlacementMaxExercises));
      });

      test('noisy learners place close to their level', () async {
        final k = main.length ~/ 2;
        final strong = <int>[], mid = <int>[], asked = <int>[];
        for (var seed = 1; seed <= 12; seed++) {
          final rnd = Random(seed);
          final rs = await run((_, _) => rnd.nextDouble() < 0.9, seed: seed);
          strong.add(rs.placed);
          asked.add(rs.asked);
          final rm = await run((_, unit) => rnd.nextDouble() < (unit != null && unit < k ? 0.9 : 0.25), seed: seed);
          mid.add(rm.placed);
          asked.add(rm.asked);
        }
        // ignore: avoid_print
        print('$name: 90 % learner placed $strong; knows 1-$k at 90 % (25 % beyond) placed $mid; '
            'longest test ${asked.reduce(max)} exercises');
        expect(asked.every((n) => n <= kPlacementMaxExercises), isTrue);
        // Most strong runs reach the last third of the tree.
        expect(strong.where((p) => p > main.length * 2 ~/ 3).length, greaterThanOrEqualTo(8));
        // Mid runs land within one unit of k+1 most of the time.
        expect(mid.where((p) => (p - (k + 1)).abs() <= 1).length, greaterThanOrEqualTo(8));
      });
    });
  }
}
