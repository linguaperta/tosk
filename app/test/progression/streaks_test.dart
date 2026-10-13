import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/events.dart';

void main() {
  const d0 = LocalDate(2026, 10, 1);
  Map<LocalDate, int> days(Map<int, int> offsetsToCounts) =>
      {for (final e in offsetsToCounts.entries) d0.addDays(e.key): e.value};

  group('computeStreak (day counts)', () {
    test('empty log', () {
      final s = computeStreak({}, today: d0);
      expect(s.current, 0);
      expect(s.longest, 0);
      expect(s.freezes, 0);
      expect(s.practicedToday, isFalse);
      expect(s.atRisk, isFalse);
    });

    test('consecutive days build a streak; today not yet practiced keeps it alive', () {
      final c = days({0: 5, 1: 5, 2: 5});
      final today = computeStreak(c, today: d0.addDays(2));
      expect(today.current, 3);
      expect(today.practicedToday, isTrue);
      final tomorrow = computeStreak(c, today: d0.addDays(3));
      expect(tomorrow.current, 3);
      expect(tomorrow.practicedToday, isFalse);
      expect(tomorrow.atRisk, isTrue);
      final dayAfter = computeStreak(c, today: d0.addDays(4));
      expect(dayAfter.current, 0); // day 3 missed, no freezes
      expect(dayAfter.longest, 3);
    });

    test('a missed day without a freeze resets the streak', () {
      final s = computeStreak(days({0: 1, 1: 1, 3: 1, 4: 1}), today: d0.addDays(4));
      expect(s.current, 2);
      expect(s.longest, 2);
      expect(s.frozenDays, isEmpty);
    });

    test('freezes are earned per 50 reviews and consumed for missed days', () {
      // Day 0: 50 reviews -> 1 freeze. Day 1 missed (frozen). Day 2 practiced.
      final s = computeStreak(days({0: 50, 2: 3}), today: d0.addDays(2));
      expect(s.current, 2); // frozen days keep the run alive but don't add to it
      expect(s.frozenDays, {d0.addDays(1)});
      expect(s.freezes, 0);
      expect(s.reviewsTowardNextFreeze, 3);
    });

    test('freezes are capped and partial coverage still breaks the streak', () {
      // 200 reviews would be 4 freezes, capped at 2.
      final s1 = computeStreak(days({0: 200}), today: d0.addDays(1));
      expect(s1.freezes, 2);
      expect(s1.reviewsTowardNextFreeze, 0);
      // Three missed days: two frozen, the third breaks the run.
      final s2 = computeStreak(days({0: 200, 4: 1}), today: d0.addDays(4));
      expect(s2.frozenDays, {d0.addDays(1), d0.addDays(2)});
      expect(s2.freezes, 0);
      expect(s2.current, 1);
      expect(s2.longest, 1);
    });

    test('freezes cover the gap up to yesterday; today is never consumed', () {
      final c = days({0: 120}); // 2 freezes, 20 toward the next
      final s = computeStreak(c, today: d0.addDays(3)); // days 1, 2 missed
      expect(s.current, 1);
      expect(s.frozenDays, {d0.addDays(1), d0.addDays(2)});
      expect(s.freezes, 0);
      expect(s.atRisk, isTrue);
      expect(computeStreak(c, today: d0.addDays(4)).current, 0);
    });

    test('freezes are not spent when no streak is active', () {
      // Run breaks on day 2 and 3 (one freeze only), then a long idle period.
      final s = computeStreak(days({0: 50, 3: 50, 10: 1}), today: d0.addDays(10));
      // Day 1 frozen, day 2 breaks. Day 3 starts a new run and earns a freeze.
      // Days 4..9 missed: day 4 uses the freeze, day 5 breaks.
      expect(s.frozenDays, {d0.addDays(1), d0.addDays(4)});
      expect(s.current, 1);
      expect(s.freezes, 0);
    });

    test('freezes earned on a day are usable for the following gap only', () {
      // Day 0: 49 reviews (no freeze), day 1: 1 review -> freeze earned on day 1.
      final s = computeStreak(days({0: 49, 1: 1, 3: 1}), today: d0.addDays(3));
      expect(s.current, 3);
      expect(s.frozenDays, {d0.addDays(2)});
    });

    test('days after today are ignored', () {
      final s = computeStreak(days({0: 1, 1: 1, 5: 1}), today: d0.addDays(1));
      expect(s.current, 2);
      expect(s.lastPracticeDay, d0.addDays(1));
    });

    test('milestones record the day they were first reached', () {
      final c = {for (var i = 0; i < 40; i++) d0.addDays(i): 1};
      final s = computeStreak(c, today: d0.addDays(39));
      expect(s.current, 40);
      expect(s.milestonesReached, {7: d0.addDays(6), 30: d0.addDays(29)});
    });
  });

  group('local days from UTC instants', () {
    final f = EventFactory();
    ReviewEvent at(DateTime utcInstant) => f.ev('it:ciao#rec', utcInstant);

    // Builds the UTC instant of a local wall-clock time at [offset].
    DateTime local(int y, int m, int d, int h, int min, Duration offset) =>
        DateTime.utc(y, m, d, h, min).subtract(offset);

    test('midnight boundary on both sides, positive and negative offsets', () {
      for (final hours in [-11, -4, 0, 2, 5, 14]) {
        final off = Duration(hours: hours);
        final cal = LocalCalendar.fixed(off);
        final before = local(2026, 10, 1, 23, 59, off).add(const Duration(seconds: 59));
        final after = local(2026, 10, 2, 0, 0, off);
        expect(cal.dateOf(before), const LocalDate(2026, 10, 1), reason: 'offset $hours');
        expect(cal.dateOf(after), const LocalDate(2026, 10, 2), reason: 'offset $hours');
        final counts = dayCountsOf([at(before), at(after)], cal);
        expect(computeStreak(counts, today: const LocalDate(2026, 10, 2)).current, 2);
        // Two answers one minute apart before midnight are the same day.
        final same = dayCountsOf([at(before.subtract(const Duration(minutes: 1))), at(before)], cal);
        expect(computeStreak(same, today: const LocalDate(2026, 10, 1)).current, 1);
      }
    });

    test('the same instants give different streaks in different zones', () {
      // 22:30 UTC every day for 3 days, plus 01:30 UTC on day 4.
      final evs = [
        at(utc(2026, 10, 1, 22, 30)),
        at(utc(2026, 10, 2, 22, 30)),
        at(utc(2026, 10, 4, 1, 30)),
      ];
      // UTC: Oct 1, 2, 4 -> gap on Oct 3.
      expect(computeStreak(dayCountsOf(evs, LocalCalendar.utc), today: const LocalDate(2026, 10, 4)).current, 1);
      // UTC+2: Oct 2, 3, 4 -> 3 in a row.
      final plus2 = LocalCalendar.fixed(const Duration(hours: 2));
      expect(computeStreak(dayCountsOf(evs, plus2), today: const LocalDate(2026, 10, 4)).current, 3);
    });

    test('DST transitions (offset changes at an instant) keep local days correct', () {
      // Europe/Amsterdam-like: +1 in winter, +2 from 2026-03-29 01:00 UTC.
      final dstStart = utc(2026, 3, 29, 1);
      final cal = LocalCalendar((u) => u.isBefore(dstStart) ? const Duration(hours: 1) : const Duration(hours: 2));
      // 23:30 local on Mar 28 (+1) = 22:30 UTC; 23:30 local on Mar 29 (+2) = 21:30 UTC.
      final a = utc(2026, 3, 28, 22, 30), b = utc(2026, 3, 29, 21, 30), c = utc(2026, 3, 29, 22, 30);
      expect(cal.dateOf(a), const LocalDate(2026, 3, 28));
      expect(cal.dateOf(b), const LocalDate(2026, 3, 29));
      expect(cal.dateOf(c), const LocalDate(2026, 3, 30)); // 00:30 local
      // Just around the switch: 00:59 UTC = 01:59 local, 01:00 UTC = 03:00 local; both Mar 29.
      expect(cal.dateOf(utc(2026, 3, 29, 0, 59)), const LocalDate(2026, 3, 29));
      expect(cal.dateOf(dstStart), const LocalDate(2026, 3, 29));
      final s = computeStreak(dayCountsOf([at(a), at(b), at(c)], cal), today: const LocalDate(2026, 3, 30));
      expect(s.current, 3);
      // Autumn back: 2026-10-25 01:00 UTC from +2 to +1. 23:30 local on both sides.
      final dstEnd = utc(2026, 10, 25, 1);
      final cal2 = LocalCalendar((u) => u.isBefore(dstEnd) ? const Duration(hours: 2) : const Duration(hours: 1));
      final d1 = utc(2026, 10, 24, 21, 30), d2 = utc(2026, 10, 25, 22, 30);
      expect(cal2.dateOf(d1), const LocalDate(2026, 10, 24));
      expect(cal2.dateOf(d2), const LocalDate(2026, 10, 25));
      expect(computeStreak(dayCountsOf([at(d1), at(d2)], cal2), today: const LocalDate(2026, 10, 25)).current, 2);
    });

    test('travel west and east keeps a daily-evening practice streak', () {
      // Amsterdam (+2) until Oct 3 12:00 UTC, then New York (-4) until Oct 6 12:00 UTC, then Tokyo (+9).
      final toNy = utc(2026, 10, 3, 12), toTokyo = utc(2026, 10, 6, 12);
      final cal = LocalCalendar((u) => u.isBefore(toNy)
          ? const Duration(hours: 2)
          : u.isBefore(toTokyo)
              ? const Duration(hours: -4)
              : const Duration(hours: 9));
      // Practice at 21:00 local every day.
      final evs = [
        at(local(2026, 10, 1, 21, 0, const Duration(hours: 2))),
        at(local(2026, 10, 2, 21, 0, const Duration(hours: 2))),
        at(local(2026, 10, 3, 21, 0, const Duration(hours: -4))),
        at(local(2026, 10, 4, 21, 0, const Duration(hours: -4))),
        at(local(2026, 10, 5, 21, 0, const Duration(hours: -4))),
        // Flying to Tokyo skips most of Oct 6 local; practice on Oct 7 local.
        at(local(2026, 10, 7, 21, 0, const Duration(hours: 9))),
      ];
      final counts = dayCountsOf(evs, cal);
      expect(counts.keys.toSet(), {
        for (final d in [1, 2, 3, 4, 5, 7]) LocalDate(2026, 10, d),
      });
      // Oct 6 local is a real day for the traveller (they were awake for part of it in NY).
      final s = computeStreak(counts, today: const LocalDate(2026, 10, 7));
      expect(s.current, 1);
      // With a freeze earned earlier, the flight day is covered.
      final busy = [...evs, ...List.generate(50, (i) => at(local(2026, 10, 1, 20, i, const Duration(hours: 2))))];
      final s2 = computeStreak(dayCountsOf(busy, cal), today: const LocalDate(2026, 10, 7));
      expect(s2.current, 6);
      expect(s2.frozenDays, {const LocalDate(2026, 10, 6)});
    });

    test('flying west can put two sessions on one local day without double counting', () {
      final toNy = utc(2026, 10, 2, 6);
      final cal = LocalCalendar((u) => u.isBefore(toNy) ? const Duration(hours: 2) : const Duration(hours: -4));
      // 07:00 UTC Oct 2 = 09:00 Amsterdam (before flight) ... after: 03:00 UTC Oct 3 = 23:00 NY Oct 2.
      final evs = [at(utc(2026, 10, 1, 19)), at(utc(2026, 10, 2, 5)), at(utc(2026, 10, 3, 3))];
      final counts = dayCountsOf(evs, cal);
      expect(counts, {const LocalDate(2026, 10, 1): 1, const LocalDate(2026, 10, 2): 2});
      expect(computeStreak(counts, today: const LocalDate(2026, 10, 2)).current, 2);
    });
  });

  group('heatmap', () {
    test('bucket thresholds', () {
      expect(heatmapBucket(0), 0);
      expect(heatmapBucket(1), 1);
      expect(heatmapBucket(9), 1);
      expect(heatmapBucket(10), 2);
      expect(heatmapBucket(25), 3);
      expect(heatmapBucket(49), 3);
      expect(heatmapBucket(50), 4);
      expect(heatmapBucket(5000), 4);
    });

    test('fromCounts filters to the range and keeps frozen days in range', () {
      final counts = days({-1: 3, 0: 12, 3: 60, 10: 1});
      final h = HeatmapData.fromCounts(counts,
          from: d0, to: d0.addDays(6), frozen: {d0.addDays(1), d0.addDays(20)}, today: d0.addDays(6));
      expect(h.counts, {d0: 12, d0.addDays(3): 60});
      expect(h.frozen, {d0.addDays(1)});
      expect(h.bucketOf(d0), 2);
      expect(h.bucketOf(d0.addDays(3)), 4);
      expect(h.bucketOf(d0.addDays(2)), 0);
      expect(h.isFrozen(d0.addDays(1)), isTrue);
      expect(h.days.length, 7);
      expect(h.totalReviews, 72);
      expect(h.activeDays, 2);
    });
  });
}
