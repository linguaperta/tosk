// Placement on the real packs (app/assets/courses/*.sqlite, plus the packs
// of $TOSK_EXTRA_PACKS, or a French pack in tosk-data/dist when one is
// there): simulated learners place where they should, within the length cap.
//
// * perfect: every answer right -> past the last unit, every word confirmed;
// * beginner: every answer wrong -> unit 1, nothing credited;
// * mid: knows units 1..k -> placed into unit k+1 (within one unit);
// * noisy: 90 % right on what they know, 25 % on what they don't;
// * recognises but can't produce: right on recognition items, 30 % on
//   production -> must not land near the end;
// * knows the grammar, few words: the grammar is credited, most words stay new.
//
// Each run prints a line; `TOSK_PLACEMENT_REPORT=1` prints the table.
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

/// Packs to simulate: the bundled ones and `TOSK_EXTRA_PACKS`, else a French
/// pack in tosk-data/dist if present (next to this repo, or next to the main
/// checkout of a worktree).
Map<String, String> _packs() {
  final out = realPackPaths();
  if ((Platform.environment['TOSK_EXTRA_PACKS'] ?? '').trim().isEmpty) {
    for (final p in const [
      '../../tosk-data/dist/fr.sqlite',
      '../../../../../tosk-data/dist/fr.sqlite',
    ]) {
      if (File(p).existsSync()) {
        out.putIfAbsent('fr', () => p);
        break;
      }
    }
  }
  return out;
}

enum _Input { tap, typed }

/// The learner's answer: right or wrong, tapped or typed.
Answer _answer(Exercise e, bool right, _Input input) {
  if (input == _Input.typed) {
    if (e is ConjPickExercise && e.stem.isEmpty) return TextAnswer(right ? e.fullForm : 'xxx');
    if (e is ClozeExercise) return TextAnswer(right ? e.expected : 'xxx');
  }
  return right ? correctAnswer(e) : wrongAnswer(e);
}

class _Run {
  _Run(this.outcome, this.asked, this.course, this.probes, this.production);
  final AssessmentOutcome outcome;
  final int asked;
  final CourseData course;
  final Map<String, int> probes;

  /// Exercises that asked for production without context.
  final int production;

  List<Unit> get main => CourseTrees.of(course).mainUnits;

  int numberOf(String id) => main.indexWhere((u) => u.id == id) + 1;

  /// 1-based number of the placed unit; main.length + 1 past the end.
  int get placed {
    final id = outcome.placedUnit;
    return id == null ? main.length + 1 : numberOf(id);
  }

  String get words => '${outcome.wordsKnown}/${outcome.wordsTotal}';
  String get askedUnits => [for (final u in outcome.askedUnits) numberOf(u)].join(',');
}

/// A learner: whether they answer [e] (of 0-based main unit [unit]) right.
typedef _Learner = bool Function(Exercise e, int? unit);

final _report = <String>[];

void _log(String line) {
  _report.add(line);
  // ignore: avoid_print
  print(line);
}

/// Runs a placement on [course] and then the word check, where the learner
/// knows the words [knowsWord] says (null: every word they got right in the
/// test's terms, i.e. by [learner] on its unit).
Future<_Run> _place(
  CourseData course,
  _Learner learner, {
  int seed = 1,
  _Input input = _Input.tap,
  bool Function(String itemId, int? unit)? knowsWord,
}) async {
  final main = CourseTrees.of(course).mainUnits;
  final index = {for (var i = 0; i < main.length; i++) main[i].id: i};
  final ix = CourseIndex.of(course);
  int? unitOfFacet(String facetId) {
    final s = ix.introducingSkill(facetId);
    return s == null ? null : index[course.skill(s)?.unitId];
  }

  int? unitOfItem(String itemId) =>
      unitOfFacet('$itemId#prod') ?? unitOfFacet('$itemId#rec');
  final store = InMemoryProgressStore(scheduler: FsrsScheduler());
  var clock = _now;
  final factory = EngineSessionFactory(
    course: course,
    store: store,
    scheduler: FsrsScheduler(),
    options: SessionOptions(
      sourceLang: course.meta.translations.first,
      seed: seed,
      listening: true,
      preferredInput: input == _Input.typed ? InputMode.keyboard : InputMode.tap,
    ),
    clock: () => clock,
  );
  final s = await factory.placement();
  var asked = 0, production = 0;
  for (var i = 0; i < 200; i++) {
    final e = await s.next();
    if (e == null) break;
    asked++;
    if (isContextFreeProduction(e)) production++;
    await s.submit(e, _answer(e, learner(e, unitOfFacet(e.facetId)), input), elapsed: const Duration(seconds: 8));
    clock = clock.add(const Duration(seconds: 20));
  }
  final plan = s.wordCheck!;
  final run = WordCheckRun(plan);
  final knows = knowsWord ?? (id, unit) => learner(_probeWord, unit);
  for (var i = 0; i < 20000 && !run.isDone; i++) {
    if (run.step == WordCheckStep.offer) {
      run.markRest();
    } else {
      final w = run.word!;
      run.answer(knows(w.itemId, unitOfItem(w.itemId)));
    }
  }
  final o = await s.confirmWords(run.known);
  return _Run(o, asked, course, s.probes, production);
}

/// Stands for a word of the word check when a learner decides by unit.
const _probeWord = ClozeExercise(id: 'w', facetId: 'w#prod', before: '', after: '', expected: '', accepted: []);

const _letters = 'bcdfghlmnprstvz';

/// A synthetic main tree of [units] units (two vocabulary skills of six
/// words each), for trees longer than the bundled ones.
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

void main() {
  tearDownAll(() {
    if (Platform.environment['TOSK_PLACEMENT_REPORT'] == '1') {
      // ignore: avoid_print
      print('\n=== placement report ===\n${_report.join('\n')}');
    }
  });

  group('placement on long synthetic trees (no grammar: the search runs over every unit)', () {
    for (final n in const [20, 30]) {
      test('$n units: perfect, beginner and mid learners within the cap', () async {
        final course = _longCourse(n);
        final perfect = await _place(course, (_, _) => true);
        final beginner = await _place(course, (_, _) => false);
        final k = (n * 3) ~/ 4;
        final mid = await _place(course, (_, u) => u != null && u < k);
        _log('synthetic $n: perfect placed ${perfect.placed} in ${perfect.asked}; beginner ${beginner.placed} in '
            '${beginner.asked}; knows 1-$k placed ${mid.placed} in ${mid.asked}');
        expect(perfect.outcome.placedUnit, isNull);
        expect(perfect.outcome.passedUnits.length, n);
        expect(beginner.outcome.placedUnit, 'u0');
        expect(mid.outcome.placedUnit, 'u$k');
        for (final r in [perfect, beginner, mid]) {
          expect(r.asked, lessThanOrEqualTo(kPlacementMaxExercises));
        }
      });
    }
  });

  final packs = _packs();
  if (packs.isEmpty) {
    test('no packs', () {}, skip: 'no course packs found');
    return;
  }

  for (final MapEntry(key: name, value: path) in packs.entries) {
    group('placement on $name', () {
      late CourseData course;
      late List<Unit> main;
      late Set<int> grammarUnits; // 0-based main units with grammar facets
      late int units; // main units with something to learn

      setUpAll(() {
        course = loadCourseFile(path);
        main = CourseTrees.of(course).mainUnits;
        grammarUnits = {
          for (var i = 0; i < main.length; i++)
            if (course.skills.any((s) =>
                s.unitId == main[i].id && course.skillFacets(s.id).any((f) => isPlacementGrammarFacet(course, f))))
              i,
        };
        units = main.where((u) => course.skills.any((s) => s.unitId == u.id && course.skillFacets(s.id).isNotEmpty)).length;
      });

      bool grammarItem(Exercise e) {
        for (final s in course.skillsForFacet(e.facetId)) {
          for (final f in course.skillFacets(s)) {
            if (f.facetId == e.facetId) return isPlacementGrammarFacet(course, f);
          }
        }
        return false;
      }

      test('a perfect learner places past the last unit within the cap, every word confirmed', () async {
        for (final input in _Input.values) {
          final r = await _place(course, (_, _) => true, input: input);
          _log('$name ${input.name}: ${main.length} units; perfect: ${r.asked} items (${r.production} production), '
              'asked units ${r.askedUnits}, placed ${r.placed}, words ${r.words}');
          expect(r.asked, lessThanOrEqualTo(kPlacementMaxExercises));
          expect(r.outcome.placedUnit, isNull);
          expect(r.outcome.passedUnits.length, units);
          expect(r.outcome.wordsKnown, r.outcome.wordsTotal);
          expect(r.production / r.asked, greaterThan(0.6), reason: 'production without context');
        }
      });

      test('a beginner places into unit 1 with nothing credited', () async {
        final r = await _place(course, (_, _) => false);
        _log('$name: beginner: ${r.asked} items, asked units ${r.askedUnits}, placed ${r.placed}');
        expect(r.placed, 1);
        expect(r.outcome.creditedSkills, isEmpty);
        expect(r.outcome.wordsTotal, 0);
        expect(r.asked, lessThanOrEqualTo(14));
      });

      test('a mid learner places within one unit of where they are', () async {
        for (final k in {main.length ~/ 3, main.length ~/ 2, (main.length * 2) ~/ 3}) {
          final r = await _place(course, (_, unit) => unit != null && unit < k);
          _log('$name: knows units 1-$k: ${r.asked} items, asked units ${r.askedUnits}, placed ${r.placed}, '
              'words ${r.words}');
          expect((r.placed - (k + 1)).abs(), lessThanOrEqualTo(1), reason: 'knows 1..$k');
          expect(r.outcome.passedUnits.length, lessThanOrEqualTo(k + 1));
          expect(r.asked, lessThanOrEqualTo(kPlacementMaxExercises));
        }
      });

      test('noisy learners place close to their level', () async {
        final k = main.length ~/ 2;
        final strong = <int>[], mid = <int>[], asked = <int>[];
        for (var seed = 1; seed <= 12; seed++) {
          final rnd = Random(seed);
          final rs = await _place(course, (_, _) => rnd.nextDouble() < 0.9, seed: seed);
          strong.add(rs.placed);
          asked.add(rs.asked);
          final rm = await _place(course, (_, unit) => rnd.nextDouble() < (unit != null && unit < k ? 0.9 : 0.25), seed: seed);
          mid.add(rm.placed);
          asked.add(rm.asked);
        }
        _log('$name: 90 % learner placed ${strong..sort()}; knows 1-$k at 90 % (25 % beyond) placed ${mid..sort()}; '
            'longest test ${asked.reduce(max)} items');
        expect(asked.every((n) => n <= kPlacementMaxExercises), isTrue);
        // Most strong runs reach the last third of the tree.
        expect(strong.where((p) => p > main.length * 2 ~/ 3).length, greaterThanOrEqualTo(8));
        // Mid runs land within one unit of k+1 most of the time, and never far above it.
        expect(mid.where((p) => (p - (k + 1)).abs() <= 1).length, greaterThanOrEqualTo(8));
        expect(mid.every((p) => p <= k + 2), isTrue);
      });

      test('a learner who recognises everything but can\'t produce does not land near the end', () async {
        final placed = <String>[];
        for (final input in _Input.values) {
          for (var seed = 1; seed <= 6; seed++) {
            final rnd = Random(seed * 7);
            final r = await _place(
              course,
              (e, _) => isContextFreeProduction(e) ? rnd.nextDouble() < 0.3 : true,
              seed: seed,
              input: input,
            );
            placed.add('${input.name}:${r.placed}');
            expect(r.placed, lessThanOrEqualTo(max(2, main.length ~/ 3)), reason: '${input.name} seed $seed');
          }
        }
        _log('$name: recognises but can\'t produce (30 % on production): placed $placed of ${main.length + 1}');
      });

      test('a learner who knows the grammar but few words: grammar credited, most words stay new', () async {
        final rnd = Random(5);
        final r = await _place(
          course,
          (e, _) => grammarItem(e) || rnd.nextDouble() < 0.2,
          knowsWord: (_, _) => rnd.nextDouble() < 0.2,
        );
        final credited = {for (final u in r.outcome.passedUnits) main.indexWhere((m) => m.id == u)};
        _log('$name: knows the grammar, 20 % of words: ${r.asked} items, placed ${r.placed}, '
            'grammar of ${credited.intersection(grammarUnits).length}/${grammarUnits.length} grammar units credited, '
            'words ${r.words}');
        expect(credited.containsAll(grammarUnits), isTrue);
        expect(r.outcome.wordsKnown, lessThan(r.outcome.wordsTotal * 0.4));
      });
    });
  }
}
