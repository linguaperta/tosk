// Grammar gating, the vocabulary cap and sentence variety on the real bundled
// packs (app/assets/courses/*.sqlite): simulated learners (fresh; started
// every skill of units 1..k) get only sentences they are ready for, and
// lessons still reach their planned length.
@TestOn('vm')
library;

import 'dart:io';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fakes.dart';
import 'gated_validity.dart';
import 'helpers.dart';
import 'real_packs.dart';

final _now = DateTime.utc(2026, 10, 14, 12);

FacetState _reviewed(String id) => FacetState(
      facetId: id,
      stability: 3,
      difficulty: 5,
      due: _now.add(const Duration(days: 3)),
      lastReview: _now.subtract(const Duration(days: 1)),
      reps: 2,
      lapses: 0,
      phase: CardPhase.review,
    );

List<String> _unitSkills(CourseData c, int unitIndex) =>
    [for (final s in c.skills) if (s.unitId == c.units[unitIndex].id) s.id];

Set<String> _skillsOfUnits(CourseData c, int k) => {for (var u = 0; u < k; u++) ..._unitSkills(c, u)};

/// A store where every skill in [started] has its first facet reviewed.
InMemoryProgressStore _storeFor(CourseData c, Set<String> started) {
  final store = InMemoryProgressStore();
  for (final s in started) {
    final f = c.skillFacets(s);
    if (f.isNotEmpty) store.seed(_reviewed(f.first.facetId));
  }
  return store;
}

EngineSessionFactory _factory(CourseData c, ProgressStore store, {int seed = 7}) => EngineSessionFactory(
      course: c,
      store: store,
      scheduler: const FakeScheduler(),
      options: SessionOptions(sourceLang: c.meta.translations.first, seed: seed, listening: true),
      clock: () => _now,
    );

/// Plays [session] to the end with correct answers (at most [max]
/// exercises), checking every exercise against what the learner knows:
/// [started] plus the skills answered so far, plus [current].
Future<List<Exercise>> _play(
  EngineSession session,
  CourseData c, {
  required Set<String> started,
  Iterable<String> current = const [],
  LessonFocus focus = LessonFocus.mixed,
  int max = 200,
  List<String>? failures,
}) async {
  final known = {...started};
  final out = <Exercise>[];
  for (var e = await session.next(); e != null && out.length < max; e = await session.next()) {
    out.add(e);
    final skill = c.skill(e.skillId ?? '');
    final k = Knowledge(c, started: known, current: current);
    final cap = SentenceGate.capFor(focus, skill);
    final facet = session.facetFor(e.facetId, e.skillId);
    for (final p in gatingProblems(e, c, k, cap, facet: facet)) {
      failures?.add('[${session.mode.name} ${e.skillId} ${e.type.id}] $p\n${formatExercise(e)}');
    }
    final r = await session.submit(e, correctAnswer(e), elapsed: const Duration(seconds: 4));
    for (final o in r.outcomes) {
      known.addAll(SentenceGate.startedSkills(c, [o.facetId]));   // the introducing skill only
    }
  }
  return out;
}

void main() {
  for (final id in bundledPackIds()) {
    final path = 'assets/courses/$id.sqlite';
    group('real pack $id gating', () {
      late CourseData course;
      setUpAll(() => course = loadCourseFile(path));

      test('the pack carries gating data', () {
        expect(SentenceGate.supports(course), isTrue);
        expect(course.meta.timeAdverbs, isNotEmpty);
      });

      test('generated exercises respect gating for learners at every unit', () {
        final report = GatedReport();
        final units = course.units.length;
        // A brand-new learner in each unit-1 skill.
        runGatedValidity(course, report, scenario: 'fresh', started: const {}, skills: _unitSkills(course, 0));
        for (var k = 1; k < units; k++) {
          final started = _skillsOfUnits(course, k);
          // A lesson in each skill of the next unit.
          runGatedValidity(course, report, scenario: 'u1-$k lesson', started: started, skills: _unitSkills(course, k));
          // Non-stop / review over the started skills of the last started unit.
          runGatedValidity(course, report,
              scenario: 'u1-$k review', started: started, skills: _unitSkills(course, k - 1), asCurrent: false, perPair: 3);
        }
        expect(report.failures.take(8).join('\n\n'), isEmpty, reason: '${report.failures.length} failures');
        // Not vacuous: sentence exercises are generated for later units, and every
        // sentence-based template shows up somewhere.
        for (var k = 2; k < units; k++) {
          expect(report.sentenceExercises['u1-$k lesson'] ?? 0, greaterThan(40), reason: 'units 1-$k');
        }
        for (final label in ['cloze', 'spot_error', 'transform', 'sentence_builder', 'multiple_choice/sentence']) {
          expect(report.generated[label] ?? 0, greaterThan(20), reason: label);
        }
      });

      test('a brand-new learner gets a full lesson in every unit-1 skill', () async {
        final failures = <String>[];
        for (final skill in _unitSkills(course, 0)) {
          for (final focus in [LessonFocus.mixed, LessonFocus.grammar]) {
            final session = await _factory(course, InMemoryProgressStore()).lesson(skill, focus: focus);
            final played = await _play(session, course, started: const {}, current: [skill], focus: focus, failures: failures);
            expect(played.length, session.plannedLength, reason: '$skill $focus');
            expect(played.length, greaterThanOrEqualTo(12), reason: '$skill $focus');
          }
        }
        expect(failures.take(5).join('\n\n'), isEmpty, reason: '${failures.length} failures');
      });

      test('a learner who started units 1-3 gets full, gated unit-3 lessons and non-stop', () async {
        final started = _skillsOfUnits(course, 3);
        final failures = <String>[];
        var sentences = 0;
        for (final skill in _unitSkills(course, 2)) {
          for (final focus in [LessonFocus.mixed, LessonFocus.grammar]) {
            final store = _storeFor(course, started);
            final session = await _factory(course, store).lesson(skill, focus: focus);
            final played = await _play(session, course, started: started, current: [skill], focus: focus, failures: failures);
            expect(played.length, greaterThanOrEqualTo(12), reason: '$skill $focus');
            sentences += played.where(isSentenceExercise).length;
          }
        }
        expect(sentences, greaterThan(10));
        final nonStop = await _factory(course, _storeFor(course, started)).nonStop();
        final played = await _play(nonStop, course, started: started, max: 60, failures: failures);
        nonStop.stop();
        expect(played.length, 60);
        expect(failures.take(5).join('\n\n'), isEmpty, reason: '${failures.length} failures');
      });

      test('variety: no sentence twice in a lesson, the next lesson prefers new ones, types alternate', () async {
        final started = _skillsOfUnits(course, 3);
        final store = _storeFor(course, started);
        var sameTypeInARow = 0;
        var exercises = 0;
        for (final skill in _unitSkills(course, 2)) {
          final shown = <List<String>>[];
          for (var round = 0; round < 2; round++) {
            final session = await _factory(course, store, seed: round).lesson(skill);
            final played = await _play(session, course, started: started, current: [skill]);
            final ids = [
              for (final e in played)
                if (shownSentences(e, course).$1 case final s?) s.id,
            ];
            expect(ids.toSet().length, ids.length, reason: '$skill round $round: $ids');
            shown.add(ids);
            for (var i = 1; i < played.length; i++) {
              if (played[i].type == played[i - 1].type) sameTypeInARow++;
            }
            exercises += played.length;
          }
          final again = shown[1].toSet().intersection(shown[0].toSet());
          expect(again, isEmpty, reason: '$skill: sentences of the first lesson came back: $again');
        }
        // The previous type is only repeated when nothing else can serve the facet.
        expect(sameTypeInARow / exercises, lessThan(0.15), reason: '$sameTypeInARow of $exercises');
        final stored = SentenceHistory.decode(store.settings[SentenceHistory.settingKey(course.meta.id)]);
        expect(stored, isNotEmpty);
        expect(stored.length, lessThanOrEqualTo(SentenceHistory.defaultCapacity));
      });
    }, skip: File(path).existsSync() ? false : 'pack $path not built');
  }
}
