import 'dart:math' as math;

import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/events.dart';
import 'fakes/fake_scheduler.dart';
import 'fakes/random_log.dart';
import 'fakes/training.dart';

void main() {
  const sch = FakeScheduler();
  final cal = LocalCalendar.utc;

  ChallengeFacts factsOf(Iterable<ReviewEvent> events, {LocalCalendar? calendar}) =>
      ChallengeFacts.build((LogReplay(scheduler: sch)..update(events)).steps, calendar ?? cal);

  ChallengeTemplate tpl(ChallengeMetric m, int target) =>
      ChallengeTemplate(id: m.name, metric: m, target: target, title: m.name, description: '');

  // ISO week 2026-W41: Mon Oct 5 .. Sun Oct 11.
  final week = Period.weekOf(const LocalDate(2026, 10, 5));
  final month = Period.monthOf(const LocalDate(2026, 10, 5));

  group('selection', () {
    test('is deterministic per period and uses distinct metrics', () {
      for (var i = 0; i < 104; i++) {
        final p = Period.weekOf(const LocalDate(2026, 1, 5).addDays(7 * i));
        final a = selectChallenges(p), b = selectChallenges(p);
        expect(a.map((t) => t.id), b.map((t) => t.id));
        expect(a.length, 3);
        expect(a.map((t) => t.metric).toSet().length, 3);
        expect(weeklyChallengePool, containsAll(a));
      }
      final m = selectChallenges(month);
      expect(m.length, 2);
      expect(monthlyChallengePool, containsAll(m));
      expect(m.map((t) => t.metric).toSet().length, 2);
    });

    test('varies across periods and covers the pool', () {
      final seen = <String>{};
      final combos = <String>{};
      for (var i = 0; i < 52; i++) {
        final sel = selectChallenges(Period.weekOf(const LocalDate(2026, 1, 5).addDays(7 * i)));
        seen.addAll(sel.map((t) => t.id));
        combos.add(sel.map((t) => t.id).join(','));
      }
      expect(seen.length, weeklyChallengePool.length);
      expect(combos.length, greaterThan(20));
    });

    test('pinned selection for a known week (guards against accidental changes)', () {
      // If this fails, every user's challenges for past periods would change.
      final ids = selectChallenges(Period.weekOf(const LocalDate(2026, 10, 12))).map((t) => t.id).toList();
      expect(ids, ['reviews300', 'days5', 'new20']);
      expect(selectChallenges(Period.weekOf(const LocalDate(2026, 10, 18))).map((t) => t.id), ids);
      expect(selectChallenges(Period.monthOf(const LocalDate(2026, 10, 1))).map((t) => t.id), ['combo50', 'reviews1000']);
    });
  });

  group('progress', () {
    final t = utc(2026, 10, 5, 9);
    final f = EventFactory();

    test('reviews, correct answers and conjugations count within the period only', () {
      final evs = [
        ...f.many(['a#rec'], t.subtract(const Duration(days: 1)), 10), // Sunday before: previous week
        ...f.many(['a#rec'], t, 20),
        ...f.many(['v#form:presente'], t.add(const Duration(days: 1)), 12, type: 'conj_pick'),
        ...f.many(['v#form:presente'], t.add(const Duration(days: 2)), 5, type: 'conj_grid', correct: false),
        ...f.many(['a#rec'], utc(2026, 10, 12, 0, 0, 1), 7), // next week
      ];
      final facts = factsOf(evs);
      expect(facts.evaluate(tpl(ChallengeMetric.reviews, 30), week).progress, 37);
      expect(facts.evaluate(tpl(ChallengeMetric.correctAnswers, 30), week).progress, 32);
      final conj = facts.evaluate(tpl(ChallengeMetric.conjugations, 10), week);
      expect(conj.progress, 12);
      expect(conj.completed, isTrue);
      expect(conj.completedAt, evs[30 + 9].at); // the 10th correct conjugation
      expect(conj.fraction, 1.0);
      expect(conj.id, 'W2026-41:conjugations');
      final notYet = facts.evaluate(tpl(ChallengeMetric.reviews, 100), week);
      expect(notYet.completed, isFalse);
      expect(notYet.completedAt, isNull);
      expect(notYet.fraction, closeTo(0.37, 1e-9));
      // The month includes the Sunday before and the next week too.
      expect(facts.evaluate(tpl(ChallengeMetric.reviews, 1), month).progress, 54);
    });

    test('practice days follow the local calendar', () {
      // 22:30 UTC Sunday Oct 4 is Monday Oct 5 in UTC+2: inside the week there, not in UTC.
      final evs = [f.ev('a#rec', utc(2026, 10, 4, 22, 30)), f.ev('a#rec', utc(2026, 10, 6, 10))];
      expect(factsOf(evs).evaluate(tpl(ChallengeMetric.practiceDays, 7), week).progress, 1);
      final plus2 = LocalCalendar.fixed(const Duration(hours: 2));
      expect(factsOf(evs, calendar: plus2).evaluate(tpl(ChallengeMetric.practiceDays, 7), week).progress, 2);
    });

    test('perfect lessons need >= 5 answers, all correct, mode lesson', () {
      final evs = [
        ...f.many(['a#rec'], t, 6, session: 'L1', mode: 'lesson'), // perfect
        ...f.many(['a#rec'], t.add(const Duration(hours: 1)), 4, session: 'L2', mode: 'lesson'), // too short
        ...f.many(['a#rec'], t.add(const Duration(hours: 2)), 8, session: 'L3', mode: 'lab'), // not a lesson
        ...f.many(['a#rec'], t.add(const Duration(hours: 3)), 8, session: 'L4', mode: 'lesson'),
        f.ev('a#rec', t.add(const Duration(hours: 3, minutes: 5)), correct: false, session: 'L4', mode: 'lesson'),
        ...f.many(['a#rec'], t.add(const Duration(hours: 4)), 5, session: 'L5', mode: 'lesson'), // perfect
      ];
      final c = factsOf(evs).evaluate(tpl(ChallengeMetric.perfectLessons, 2), week);
      expect(c.progress, 2);
      expect(c.completedAt, evs.last.at);
    });

    test('new words count items first reviewed in the period, not facets', () {
      final evs = [
        f.ev('it:ciao#rec', t.subtract(const Duration(days: 3))), // previous week
        f.ev('it:ciao#prod', t), // same item: not new
        f.ev('it:grazie#rec', t),
        f.ev('it:grazie#prod', t.add(const Duration(minutes: 1))),
        f.ev('it:mangiare#form:presente', t.add(const Duration(minutes: 2))),
      ];
      expect(factsOf(evs).evaluate(tpl(ChallengeMetric.newWords, 5), week).progress, 2);
    });

    test('xp sums replay XP of the period', () {
      final evs = f.many(['a#rec', 'b#rec', 'c#rec'], t, 30);
      final r = LogReplay(scheduler: sch)..update(evs);
      expect(factsOf(evs).evaluate(tpl(ChallengeMetric.xp, 1), week).progress, r.totalXp);
    });

    test('verb tables count first crossings of the stability thresholds', () {
      final ff = EventFactory();
      final evs = trainFacet(ff, 'it:mangiare#form:presente', utc(2026, 9, 1), targetStability: 25);
      final crossing7 = evs.firstWhere((e) => stateAfter(evs.sublist(0, evs.indexOf(e) + 1)).stability >= 7);
      final crossing21 = evs.firstWhere((e) => stateAfter(evs.sublist(0, evs.indexOf(e) + 1)).stability >= 21);
      final facts = factsOf(evs);
      final p7 = Period.weekOf(cal.dateOf(crossing7.at));
      final p21 = Period.monthOf(cal.dateOf(crossing21.at));
      expect(facts.evaluate(tpl(ChallengeMetric.strongVerbTables, 1), p7).completedAt, crossing7.at);
      expect(facts.evaluate(tpl(ChallengeMetric.masteredVerbTables, 1), p21).completedAt, crossing21.at);
      // Non-form facets never count.
      final rec = trainFacet(ff, 'it:ciao#rec', utc(2026, 9, 1), targetStability: 25);
      final total = factsOf(rec);
      for (var p = Period.monthOf(const LocalDate(2026, 9, 1)); p.start.isBefore(const LocalDate(2027, 6, 1)); p = p.next) {
        expect(total.evaluate(tpl(ChallengeMetric.strongVerbTables, 1), p).progress, 0);
      }
    });

    test('non-stop combo is a maximum, not a sum', () {
      final evs = [
        ...f.many(['a#rec'], t, 12, session: 'n1', mode: 'nonstop'),
        f.ev('a#rec', t.add(const Duration(minutes: 5)), correct: false, session: 'n1', mode: 'nonstop'),
        ...f.many(['a#rec'], t.add(const Duration(minutes: 6)), 8, session: 'n1', mode: 'nonstop'),
      ];
      final c = factsOf(evs).evaluate(tpl(ChallengeMetric.nonStopCombo, 10), week);
      expect(c.progress, 12);
      expect(c.completedAt, evs[9].at);
    });
  });

  group('badges', () {
    test('derived from the log: identical for shuffled logs and stable over time', () {
      final log = randomLog(seed: 3, days: 90);
      final today = const LocalDate(2026, 11, 15);
      final a = factsOf(log).challengeBadges(today);
      final shuffled = List.of(log)..shuffle(math.Random(9));
      final b = factsOf(shuffled).challengeBadges(today);
      expect(a.map((x) => '${x.id}@${x.earnedAt}'), b.map((x) => '${x.id}@${x.earnedAt}'));
      expect(a, isNotEmpty);
      // Badges earned by a date never disappear when more events are added later.
      final cutoff = utc(2026, 9, 15);
      final early = factsOf(log.where((e) => e.at.isBefore(cutoff)))
          .challengeBadges(cal.dateOf(cutoff))
          .where((x) => x.period!.end.isBefore(cal.dateOf(cutoff)) || x.period!.end == cal.dateOf(cutoff));
      final ids = a.map((x) => x.id).toSet();
      for (final x in early) {
        expect(ids, contains(x.id));
      }
    });

    test('every badge corresponds to a completed selected challenge', () {
      final log = randomLog(seed: 4, days: 60);
      final facts = factsOf(log);
      for (final badge in facts.challengeBadges(const LocalDate(2026, 10, 13))) {
        final c = facts.challengesFor(badge.period!).firstWhere((c) => c.id == badge.id);
        expect(c.completed, isTrue);
        expect(badge.earnedAt, c.completedAt);
        expect(badge.kind, BadgeKind.challenge);
      }
    });

    test('level and streak milestone badges', () {
      final log = randomLog(seed: 5, days: 60);
      final r = LogReplay(scheduler: sch)..update(log);
      final lv = levelBadges(r.steps, cal);
      const curve = LevelCurve();
      final level = curve.levelFor(r.totalXp).level;
      expect(lv.length, [5, 10, 25, 50, 100].where((l) => l <= level).length);
      for (final b in lv) {
        final n = int.parse(b.id.split(':')[1]);
        final step = r.steps.firstWhere((s) => s.event.at == b.earnedAt);
        expect(step.cumulativeXp, greaterThanOrEqualTo(curve.threshold(n)));
        expect(step.cumulativeXp - step.xp, lessThan(curve.threshold(n)));
      }
      final sb = streakBadges({30: const LocalDate(2026, 2, 1), 7: const LocalDate(2026, 1, 7)});
      expect(sb.map((b) => b.id), ['streak:7', 'streak:30']);
    });

    test('empty log has no badges', () {
      expect(factsOf(const []).challengeBadges(const LocalDate(2026, 10, 13)), isEmpty);
      expect(factsOf(const []).firstDate, isNull);
    });
  });
}
