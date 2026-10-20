// Course statistics (v0.4): the review forecast, accuracy per exercise type,
// facet kind and tense, practice time and words learned, all derived from
// the review log.
import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/events.dart';
import 'fakes/fake_course.dart';
import 'fakes/fake_scheduler.dart';
import 'fakes/fake_store.dart';

void main() {
  const sch = FakeScheduler();
  final course = fakeCourse();
  final cal = LocalCalendar.fixed(const Duration(hours: 2));
  final now = utc(2026, 10, 13, 10); // 12:00 local on Oct 13
  final today = cal.dateOf(now);

  FacetState st(String facet, DateTime due, {int reps = 1}) => FacetState(
    facetId: facet,
    stability: 3,
    difficulty: 5,
    due: due,
    lastReview: now.subtract(const Duration(days: 1)),
    reps: reps,
    lapses: 0,
    phase: CardPhase.review,
  );

  CourseStats statsOf(Map<String, FacetState> states, [List<ReplayStep> steps = const []]) =>
      computeCourseStats(course: course, steps: steps, states: states, calendar: cal, now: now, lang: 'en');

  group('forecast', () {
    test('per local day for 30 days; overdue counts today; unreviewed and foreign facets are ignored', () {
      final s = statsOf({
        'it:ciao#rec': st('it:ciao#rec', now.subtract(const Duration(days: 2))), // overdue
        'it:ciao#prod': st('it:ciao#prod', utc(2026, 10, 13, 21, 30)), // 23:30 local: today
        'it:grazie#rec': st('it:grazie#rec', utc(2026, 10, 13, 22, 30)), // 00:30 local Oct 14: tomorrow
        'it:grazie#prod': st('it:grazie#prod', now.add(const Duration(days: 13))),
        'it:mangiare#form:presente': st('it:mangiare#form:presente', now.add(const Duration(days: 20))),
        'it:parlare#form:presente': st('it:parlare#form:presente', now.add(const Duration(days: 45))), // beyond
        'it:mangiare#form:passato_prossimo': st(
          'it:mangiare#form:passato_prossimo',
          now.add(const Duration(days: 1)),
          reps: 0,
        ),
        'xx:other#rec': st('xx:other#rec', now), // not in the course
      });
      final f = s.forecast;
      expect(f.days, hasLength(kForecastDays));
      expect(f.days.first.$1, today);
      expect(f.days.last.$1, today.addDays(29));
      expect(f.overdue, 1);
      expect(f.dueToday, 2);
      expect(f.days[1].$2, 1);
      expect(f.days[13].$2, 1);
      expect(f.days[20].$2, 1);
      expect(f.totalIn(7), 3);
      expect(f.totalIn(14), 4);
      expect(f.totalIn(30), 5);
      expect(f.total, 5);
      expect(f.window(14), hasLength(14));
    });

    test('from the log: equals the replayed facet states', () async {
      final f = EventFactory();
      final store = FakeProgressStore(sch, [
        ...f.many(greetingFacets, utc(2026, 10, 10, 9), 8, session: 'a', mode: 'lesson'),
        ...f.many(presentFacets, utc(2026, 10, 12, 9), 4, session: 'b', mode: 'lesson', type: 'conj_pick'),
      ]);
      final svc = ProgressionService(store: store, scheduler: sch, course: course, clock: () => now, calendar: cal);
      final s = await svc.stats();
      final states = await store.allStates();
      final due = states.where((x) => x.reps > 0 && cal.dateOf(x.due).daysUntil(today.addDays(29)) >= 0).length;
      expect(s.forecast.total, due);
      expect(s.isEmpty, isFalse);
    });
  });

  group('accuracy, time and words learned', () {
    late CourseStats s;
    setUp(() async {
      final f = EventFactory();
      final events = <ReviewEvent>[
        // Multiple choice on recognition: 3 right, 1 wrong.
        f.ev('it:ciao#rec', utc(2026, 10, 12, 9), type: 'multiple_choice', session: 'a'),
        f.ev('it:grazie#rec', utc(2026, 10, 12, 9, 1), type: 'multiple_choice', session: 'a'),
        f.ev('it:ciao#rec', utc(2026, 10, 12, 9, 2), type: 'multiple_choice', session: 'a', correct: false),
        f.ev('it:grazie#rec', utc(2026, 10, 12, 9, 3), type: 'multiple_choice', session: 'a'),
        // Cloze on production: 1 wrong, then overridden ("I was right").
        f.ev('it:ciao#prod', utc(2026, 10, 12, 9, 4), type: 'cloze', session: 'a', correct: false, id: 'wrong1'),
        // Conjugation: two facets graded by one exercise (same at and session).
        f.ev('it:mangiare#form:presente', utc(2026, 10, 12, 9, 5), type: 'conj_grid', session: 'a'),
        f.ev('it:parlare#form:presente', utc(2026, 10, 12, 9, 5), type: 'conj_grid', session: 'a', correct: false),
        // Past tense: right.
        f.ev('it:mangiare#form:passato_prossimo', utc(2026, 10, 12, 9, 6), type: 'conj_pick', session: 'a'),
        // Older than 30 days: no accuracy, but time and learning count.
        f.ev('it:grazie#prod', utc(2026, 9, 1, 9), type: 'cloze', session: 'old', correct: false),
        // A test-out credit: no answer.
        f.ev('it:parlare#form:passato_prossimo', utc(2026, 10, 11, 9), type: kTestOutCreditType, session: 't'),
      ];
      events.add(
        ReviewEvent(
          id: 'ovr',
          facetId: 'it:ciao#prod',
          at: utc(2026, 10, 12, 9, 4, 30),
          rating: Rating.good,
          exerciseType: kOverrideType,
          inputMode: InputMode.self,
          responseMs: 0,
          correct: true,
          answer: 'wrong1',
          sessionId: 'a',
        ),
      );
      final store = FakeProgressStore(sch, events);
      final svc = ProgressionService(store: store, scheduler: sch, course: course, clock: () => now, calendar: cal);
      s = await svc.stats();
    });

    AccuracyRow row(List<AccuracyRow> rows, String key) => rows.firstWhere((r) => r.key == key);

    test('per exercise type (each graded facet counts once)', () {
      expect(s.byType.map((r) => r.key), ['multiple_choice', 'conj_pick', 'conj_grid', 'cloze']);
      expect(row(s.byType, 'multiple_choice'), isA<AccuracyRow>().having((r) => r.correct, 'right', 3).having((r) => r.total, 'n', 4));
      expect(row(s.byType, 'cloze').correct, 1, reason: 'the override made it right');
      expect(row(s.byType, 'cloze').total, 1, reason: 'the September answer is outside the window');
      expect(row(s.byType, 'conj_grid').total, 2);
      expect(row(s.byType, 'conj_grid').accuracy, 0.5);
      expect(row(s.byType, 'multiple_choice').label, 'Multiple choice');
    });

    test('per facet kind and per tense', () {
      expect(s.byKind.map((r) => r.key), ['kind:rec', 'kind:prod', 'kind:form']);
      expect(row(s.byKind, 'kind:rec').total, 4);
      expect(row(s.byKind, 'kind:form').correct, 2);
      expect(row(s.byKind, 'kind:form').total, 3);
      expect(row(s.byKind, 'kind:prod').label, startsWith('Production'));
      expect(s.byGrammar.map((r) => r.key), ['tense:presente', 'tense:passato_prossimo']);
      expect(row(s.byGrammar, 'tense:presente').accuracy, 0.5);
      expect(row(s.byGrammar, 'tense:passato_prossimo').total, 1, reason: 'the credit is no answer');
    });

    test('time: one exercise grading two facets counts once; capped; by local day', () {
      // 7 exercises on Oct 12 (the grid once; no credit, no override) at 1.5 s, plus September's.
      expect(s.time.total, const Duration(milliseconds: 1500 * 8));
      expect(s.time.today, Duration.zero);
      expect(s.time.last7Days, const Duration(milliseconds: 1500 * 7));
      expect(s.time.byDay, hasLength(7));
      expect(s.time.byDay.last.$1, today);
      expect(s.time.byDay[5].$2, const Duration(milliseconds: 1500 * 7));
    });

    test('words learned by week, cumulative', () {
      expect(s.learnedByWeek, hasLength(kLearnedWeeks));
      expect(s.learnedByWeek.last.$2, s.wordsLearned);
      for (var i = 1; i < s.learnedByWeek.length; i++) {
        expect(s.learnedByWeek[i].$2, greaterThanOrEqualTo(s.learnedByWeek[i - 1].$2));
      }
      expect(s.wordsLearned, greaterThan(0));
    });
  });

  test('an empty log has empty stats', () async {
    final svc = ProgressionService(
      store: FakeProgressStore(sch),
      scheduler: sch,
      course: course,
      clock: () => now,
      calendar: cal,
    );
    final s = await svc.stats();
    expect(s.isEmpty, isTrue);
    expect(s.byType, isEmpty);
    expect(s.byKind, isEmpty);
    expect(s.forecast.days, hasLength(kForecastDays));
  });
}
