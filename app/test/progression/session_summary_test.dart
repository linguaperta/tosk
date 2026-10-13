import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/events.dart';
import 'fakes/fake_course.dart';
import 'fakes/fake_scheduler.dart';

void main() {
  const sch = FakeScheduler();
  final course = fakeCourse();
  final t0 = utc(2026, 10, 1, 9);

  test('summarizes XP, accuracy, improved facets and tier changes', () {
    final f = EventFactory();
    // Earlier session: first exposure to all greeting facets.
    final earlier = [
      for (final id in greetingFacets) f.ev(id, t0, session: 'A', mode: 'lesson'),
    ];
    // Session B: graduates every greeting facet (-> bronze), one mistake on a new facet.
    final b0 = t0.add(const Duration(minutes: 30));
    final session = [
      for (var i = 0; i < greetingFacets.length; i++)
        f.ev(greetingFacets[i], b0.add(Duration(seconds: i * 10)), session: 'B', mode: 'lesson'),
      f.ev(presentFacets.first, b0.add(const Duration(minutes: 1)), correct: false, session: 'B', mode: 'lesson'),
      f.ev(presentFacets.first, b0.add(const Duration(minutes: 2)), session: 'B', mode: 'lesson'),
    ];
    // Interleaved event from another session (e.g. another device) must not count.
    final other = f.ev(pastFacets.first, b0.add(const Duration(seconds: 15)), session: 'C', mode: 'lab');
    final replay = LogReplay(scheduler: sch)..update([...earlier, ...session, other]);

    final s = summarizeSession(sessionId: 'B', replay: replay, scheduler: sch, course: course)!;
    expect(s.mode, 'lesson');
    expect(s.reviews, 6);
    expect(s.correct, 5);
    expect(s.accuracy, closeTo(5 / 6, 1e-9));
    expect(s.startedAt, b0);
    expect(s.endedAt, b0.add(const Duration(minutes: 2)));
    final sessionXp = replay.steps.where((x) => x.event.sessionId == 'B').fold<int>(0, (a, x) => a + x.xp);
    expect(s.xpEarned, sessionXp);
    expect(s.levelBefore.totalXp, replay.steps.where((x) => x.event.sessionId == 'A').fold<int>(0, (a, x) => a + x.xp));

    expect(s.facetChanges.map((c) => c.facetId), [...greetingFacets, presentFacets.first]);
    final first = s.facetChanges.first;
    expect(first.before, isNotNull);
    expect(first.after.phase, CardPhase.review);
    expect(first.recallAfter, closeTo(1, 1e-3)); // evaluated at session end
    final present = s.facetChanges.last;
    expect(present.isNew, isTrue);
    expect(present.reviews, 2);
    expect(present.mistakes, 1);
    expect(present.recallBefore, 0);
    expect(s.newFacets.map((c) => c.facetId), [presentFacets.first]);
    expect(s.improvedItemIds, containsAll(['it:ciao', 'it:grazie', 'it:mangiare']));

    final changes = {for (final c in s.tierChanges) c.skillId: c};
    expect(changes['greetings']!.from, SkillTier.started);
    expect(changes['greetings']!.to, SkillTier.bronze);
    expect(changes['greetings']!.isUp, isTrue);
    expect(changes['present-are']!.from, SkillTier.available);
    expect(changes['present-are']!.to, SkillTier.started);
    // B unlocks 'past'; session C's interleaved review of it is not B's effect (else: started).
    expect(changes['past']!.from, SkillTier.locked);
    expect(changes['past']!.to, SkillTier.available);
    // 'after-empty' trains only it:ciao#rec, which graduated.
    expect(changes['after-empty']!.to, SkillTier.bronze);
    expect(changes.length, 4);
  });

  test('level-up is reported', () {
    final f = EventFactory();
    // ~ 13 new-facet events at 8 XP cross level 2 at 100 XP.
    final evs = [
      for (var i = 0; i < 20; i++) f.ev('it:w$i#rec', t0.add(Duration(seconds: i)), session: 'S', mode: 'lesson'),
    ];
    final replay = LogReplay(scheduler: sch)..update(evs);
    final s = summarizeSession(sessionId: 'S', replay: replay, scheduler: sch)!;
    expect(s.xpEarned, 160);
    expect(s.levelBefore.level, 1);
    expect(s.levelAfter.level, 2);
    expect(s.leveledUp, isTrue);
    expect(s.levelsGained, 1);
    expect(s.tierChanges, isEmpty); // no course given
  });

  test('unknown session gives null', () {
    final replay = LogReplay(scheduler: sch);
    expect(summarizeSession(sessionId: 'nope', replay: replay, scheduler: sch), isNull);
  });
}
