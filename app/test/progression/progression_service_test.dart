import 'dart:math' as math;

import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/events.dart';
import 'fakes/fake_course.dart';
import 'fakes/fake_scheduler.dart';
import 'fakes/fake_store.dart';
import 'fakes/random_log.dart';

void main() {
  const sch = FakeScheduler();
  final course = fakeCourse();
  final cal = LocalCalendar.fixed(const Duration(hours: 2));
  final now = utc(2026, 10, 13, 10);

  ProgressionService service(FakeProgressStore store) =>
      ProgressionService(store: store, scheduler: sch, course: course, clock: () => now, calendar: cal);

  test('empty log', () async {
    final s = service(FakeProgressStore(sch));
    final p = await s.profile();
    expect(p.totalXp, 0);
    expect(p.level.level, 1);
    expect(p.currentStreak, 0);
    expect(p.todayReviews, 0);
    expect((await s.skillTiers())['greetings']!.tier, SkillTier.available);
    expect((await s.heatmap()).counts, isEmpty);
    final board = await s.challenges();
    expect(board.weekly.length, 3);
    expect(board.monthly.length, 2);
    expect(board.badges, isEmpty);
    expect(await s.bestNonStopRun(), isNull);
    expect(await s.sessionSummary('x'), isNull);
    expect((await s.verbCollection()).totalTables, 4);
  });

  test('profile: XP, level, streak and today in the local calendar', () async {
    final f = EventFactory();
    final store = FakeProgressStore(sch, [
      // Oct 11 and 12 local (+2); 22:30 UTC Oct 12 is 00:30 Oct 13 local = today.
      ...f.many(greetingFacets, utc(2026, 10, 11, 9), 8, session: 'a', mode: 'lesson'),
      ...f.many(greetingFacets, utc(2026, 10, 12, 9), 8, session: 'b', mode: 'lesson'),
      ...f.many(presentFacets, utc(2026, 10, 12, 22, 30), 5, session: 'c', mode: 'lesson', type: 'conj_pick'),
    ]);
    final s = service(store);
    final p = await s.profile();
    final replay = LogReplay(scheduler: sch)..update(store.events);
    expect(p.totalXp, replay.totalXp);
    expect(p.level, const LevelCurve().levelFor(replay.totalXp));
    expect(p.currentStreak, 3);
    expect(p.streak.practicedToday, isTrue);
    expect(p.todayReviews, 5);
    expect(p.todayXp, replay.steps.skip(16).fold<int>(0, (a, x) => a + x.xp));
    expect(p.totalReviews, 21);
    expect(p.today, const LocalDate(2026, 10, 13));
  });

  test('every query equals a fresh service after new events and after a sync merge', () async {
    final log = randomLog(seed: 11, days: 75);
    final canon = canonicalOrder(log);
    final store = FakeProgressStore(sch, canon.take(canon.length ~/ 2));
    final s = service(store);
    await s.profile();
    // New events appended (normal use)...
    store.events.addAll(canon.skip(canon.length ~/ 2).take(100));
    await s.profile();
    // ...then a sync merge brings older events from another device, in random order.
    store.events
      ..clear()
      ..addAll(List.of(canon)..shuffle(math.Random(2)));

    final fresh = service(FakeProgressStore(sch, canon));
    expect((await s.profile()).totalXp, (await fresh.profile()).totalXp);
    expect((await s.profile()).streak.current, (await fresh.profile()).streak.current);
    expect((await s.profile()).streak.freezes, (await fresh.profile()).streak.freezes);
    final ta = await s.skillTiers(), tb = await fresh.skillTiers();
    expect({for (final e in ta.entries) e.key: e.value.tier}, {for (final e in tb.entries) e.key: e.value.tier});
    expect({for (final e in ta.entries) e.key: e.value.strength}, {for (final e in tb.entries) e.key: e.value.strength});
    expect((await s.heatmap()).counts, (await fresh.heatmap()).counts);
    final ca = await s.challenges(), cb = await fresh.challenges();
    expect(ca.weekly.map((c) => c.progress), cb.weekly.map((c) => c.progress));
    expect(ca.badges.map((b) => b.id), cb.badges.map((b) => b.id));
    expect((await s.bestNonStopRun())?.score, (await fresh.bestNonStopRun())?.score);
    final va = await s.verbCollection(), vb = await fresh.verbCollection();
    expect(va.counts, vb.counts);
    final sid = canon[500].sessionId!;
    expect((await s.sessionSummary(sid))!.xpEarned, (await fresh.sessionSummary(sid))!.xpEarned);
  });

  test('replay is incremental when the log only grows', () async {
    final log = canonicalOrder(randomLog(seed: 12, days: 20));
    final store = FakeProgressStore(sch, log.take(100));
    final s = service(store);
    await s.profile();
    final r = s.replay;
    store.events.addAll(log.skip(100));
    final v = r.version;
    await s.profile();
    expect(identical(s.replay, r), isTrue);
    expect(r.version, v + 1);
    expect(r.length, log.length);
  });

  test('heatmap default range, frozen days and explicit range', () async {
    final f = EventFactory();
    final store = FakeProgressStore(sch, [
      ...f.many(['it:ciao#rec'], utc(2026, 10, 9, 8), 60), // 60 reviews -> 1 freeze
      ...f.many(['it:ciao#rec'], utc(2026, 10, 11, 8), 3), // Oct 10 frozen
    ]);
    final s = service(store);
    final h = await s.heatmap();
    expect(h.to, const LocalDate(2026, 10, 13));
    expect(h.from, const LocalDate(2026, 10, 12).addDays(-7 * 25));
    expect(h.from.weekday, DateTime.monday);
    expect(h.counts, {const LocalDate(2026, 10, 9): 60, const LocalDate(2026, 10, 11): 3});
    expect(h.frozen, {const LocalDate(2026, 10, 10)});
    expect(h.bucketOf(const LocalDate(2026, 10, 9)), 4);
    final narrow = await s.heatmap(from: const LocalDate(2026, 10, 11), to: const LocalDate(2026, 10, 12));
    expect(narrow.counts.keys, [const LocalDate(2026, 10, 11)]);
  });

  test('session summary, best non-stop run and badges via the facade', () async {
    final f = EventFactory();
    final evs = [
      for (var i = 0; i < 30; i++)
        f.ev('it:ciao#rec', utc(2026, 10, 12, 18).add(Duration(seconds: 4 * i)),
            session: 'ns', mode: 'nonstop', type: 'conj_pick'),
      ...f.many(greetingFacets, utc(2026, 10, 12, 19), 8, session: 'les', mode: 'lesson'),
    ];
    final s = service(FakeProgressStore(sch, evs));
    final best = (await s.bestNonStopRun())!;
    expect(best.sessionId, 'ns');
    expect(best.answered, 30);
    expect(best.bestCombo, 30);
    expect((await s.nonStopHistory()).length, 1);
    final sum = (await s.sessionSummary('les'))!;
    expect(sum.reviews, 8);
    expect(sum.accuracy, 1);
    expect(s.newNonStopRun().score, 0);
    final badges = await s.badges();
    final board = await s.challenges();
    expect(board.badges.map((b) => b.id), badges.map((b) => b.id));
    for (var i = 1; i < badges.length; i++) {
      expect(badges[i].earnedOn.isBefore(badges[i - 1].earnedOn), isFalse);
    }
  });
}
