import 'dart:math' as math;

import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/events.dart';
import 'fakes/fake_course.dart';
import 'fakes/fake_scheduler.dart';
import 'fakes/random_log.dart';

void main() {
  const sch = FakeScheduler();
  final course = fakeCourse();

  LogReplay full(Iterable<ReviewEvent> events) => LogReplay(scheduler: sch)..update(events);

  void expectSameReplay(LogReplay a, LogReplay b) {
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a.steps[i].event.id, b.steps[i].event.id);
      expect(a.steps[i].xp, b.steps[i].xp);
      expect(a.steps[i].before, b.steps[i].before);
      expect(a.steps[i].after, b.steps[i].after);
      expect(a.steps[i].cumulativeXp, b.steps[i].cumulativeXp);
    }
    expect(a.states, b.states);
    expect(a.totalXp, b.totalXp);
  }

  Map<String, SkillTier> tiers(LogReplay r, DateTime now) => {
        for (final e in computeSkillProgress(course: course, states: r.states, scheduler: sch, now: now).entries)
          e.key: e.value.tier,
      };

  final log = randomLog(seed: 7);
  final now = utc(2026, 10, 13, 12);

  test('random log is non-trivial', () {
    final r = full(log);
    expect(r.length, greaterThan(500));
    expect(r.totalXp, greaterThan(1000));
    expect(r.steps.where((s) => s.xp == 0), isNotEmpty);
  });

  test('event-by-event incremental replay equals full replay', () {
    final inc = LogReplay(scheduler: sch);
    for (final e in canonicalOrder(log)) {
      expect(inc.add(e), ReplayUpdate.appended);
    }
    expectSameReplay(inc, full(log));
    expect(tiers(inc, now), tiers(full(log), now));
  });

  test('growing-prefix updates equal full replay', () {
    final canon = canonicalOrder(log);
    final inc = LogReplay(scheduler: sch);
    for (var n = 0; n <= canon.length; n += 37) {
      inc.update(canon.take(n));
    }
    expect(inc.update(canon), anyOf(ReplayUpdate.appended, ReplayUpdate.unchanged));
    expectSameReplay(inc, full(log));
  });

  test('shuffled insertion order gives identical XP, states and tiers', () {
    final reference = full(log);
    for (var seed = 0; seed < 5; seed++) {
      final shuffled = List.of(log)..shuffle(math.Random(seed));
      final r = full(shuffled);
      expectSameReplay(r, reference);
      expect(tiers(r, now), tiers(reference, now));
    }
  });

  test('events arriving out of order (sync merge) trigger a rebuild with the same result', () {
    final canon = canonicalOrder(log);
    final odd = [for (var i = 0; i < canon.length; i += 2) canon[i]];
    final r = LogReplay(scheduler: sch)..update(odd);
    expect(r.update(canon), ReplayUpdate.rebuilt);
    expectSameReplay(r, full(log));
    // Adding an old event one at a time also rebuilds.
    final r2 = LogReplay(scheduler: sch)..update(canon.skip(1));
    expect(r2.add(canon.first), ReplayUpdate.rebuilt);
    expectSameReplay(r2, full(log));
  });

  test('duplicates are ignored and unchanged logs report unchanged', () {
    final r = full([...log, ...log.take(50)]);
    expectSameReplay(r, full(log));
    final v = r.version;
    expect(r.update(log), ReplayUpdate.unchanged);
    expect(r.version, v);
    expect(r.add(log.first), ReplayUpdate.unchanged);
  });

  test('identical timestamps are ordered by id', () {
    final f = EventFactory();
    final t = utc(2026, 10, 1, 9);
    final a = f.ev('it:ciao#rec', t, id: 'b');
    final b = f.ev('it:ciao#rec', t, id: 'a', correct: false);
    final r1 = full([a, b]), r2 = full([b, a]);
    expect(r1.steps.map((s) => s.event.id), ['a', 'b']);
    expectSameReplay(r1, r2);
  });

  test('replay states match a store-style fold through the scheduler', () {
    final m = <String, FacetState>{};
    for (final e in canonicalOrder(log)) {
      m[e.facetId] = sch.review(e.facetId, m[e.facetId], e.rating, e.at);
    }
    expect(full(log).states, m);
  });

  test('statesAfterSteps and firstStepAtOrAfter', () {
    final r = full(log);
    expect(r.statesAfterSteps(r.length), r.states);
    expect(r.statesAfterSteps(0), isEmpty);
    final mid = r.steps[100].event.at;
    final i = r.firstStepAtOrAfter(mid);
    expect(r.steps[i].event.at, mid);
    expect(i == 0 || r.steps[i - 1].event.at.isBefore(mid), isTrue);
    expect(r.firstStepAtOrAfter(utc(2030, 1, 1)), r.length);
  });
}
