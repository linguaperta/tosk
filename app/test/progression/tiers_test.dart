import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/events.dart';
import 'fakes/fake_course.dart';
import 'fakes/fake_scheduler.dart';
import 'fakes/training.dart';

void main() {
  const sch = FakeScheduler();
  final course = fakeCourse();
  final t0 = utc(2026, 9, 1, 8);

  Map<String, SkillProgress> progressAt(List<ReviewEvent> events, DateTime now) {
    final r = LogReplay(scheduler: sch)..update(events);
    return computeSkillProgress(course: course, states: r.states, scheduler: sch, now: now);
  }

  SkillTier tierAt(List<ReviewEvent> events, String skill, DateTime now) => progressAt(events, now)[skill]!.tier;

  group('next tier needs', () {
    NextTierNeeds needs(List<ReviewEvent> events, String skill, DateTime now) {
      final r = LogReplay(scheduler: sch)..update(events);
      final p = computeSkillProgress(course: course, states: r.states, scheduler: sch, now: now)[skill]!;
      return nextTierNeeds(
        tier: p.tier,
        facets: course.skillFacets(skill),
        states: r.states,
        scheduler: sch,
        now: now,
      );
    }

    test('counts items (not facets) still missing the next tier\'s rule', () {
      // Fresh: both greetings (4 facets, 2 items) to learn for bronze.
      expect(needs(const [], 'greetings', t0),
          const NextTierNeeds(tier: SkillTier.available, next: SkillTier.bronze, remaining: 2, total: 2));
      final f = EventFactory();
      // ciao fully graduated (both facets), grazie only reviewed once: 1 to go.
      final later = t0.add(const Duration(minutes: 15));
      final evs = [
        for (final id in greetingFacets) f.ev(id, t0),
        f.ev('it:ciao#rec', later),
        f.ev('it:ciao#prod', later),
      ];
      expect(needs(evs, 'greetings', later),
          const NextTierNeeds(tier: SkillTier.started, next: SkillTier.bronze, remaining: 1, total: 2));
    });

    test('bronze -> silver -> gold, then nothing left', () {
      final f = EventFactory();
      final bronzeEvs = [for (final id in greetingFacets) ...trainFacet(f, id, t0)];
      final at = bronzeEvs.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
      final b = needs(bronzeEvs, 'greetings', at);
      expect((b.tier, b.next, b.total), (SkillTier.bronze, SkillTier.silver, 2));
      expect(b.remaining, greaterThan(0));
      final goldEvs = [for (final id in greetingFacets) ...trainFacet(f, id, t0, targetStability: 30)];
      final end = goldEvs.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
      final g = needs(goldEvs, 'greetings', end);
      expect(g.tier, SkillTier.gold);
      expect(g.next, isNull);
      expect(g.remaining, 0);
    });
  });

  test('nothing reviewed: first skill available, dependents locked', () {
    final p = progressAt(const [], t0);
    expect(p['greetings']!.tier, SkillTier.available);
    expect(p['present-are']!.tier, SkillTier.locked);
    expect(p['past']!.tier, SkillTier.locked);
    // A prerequisite with no facets counts as satisfied.
    expect(p['empty']!.tier, SkillTier.available);
    expect(p['after-empty']!.tier, SkillTier.available);
    expect(p['greetings']!.strength, 0);
    expect(p['greetings']!.fading, 0);
    expect(p.keys.toList(), ['greetings', 'present-are', 'past', 'empty', 'after-empty']);
  });

  test('one review starts the skill and unlocks its dependents', () {
    final f = EventFactory();
    final evs = [f.ev('it:ciao#rec', t0)];
    final p = progressAt(evs, t0);
    expect(p['greetings']!.tier, SkillTier.started);
    expect(p['greetings']!.reviewedCount, 1);
    expect(p['present-are']!.tier, SkillTier.available);
    expect(p['past']!.tier, SkillTier.locked);
  });

  test('a started skill is never locked, even with unstarted prerequisites', () {
    final f = EventFactory();
    final p = progressAt([f.ev(pastFacets.first, t0)], t0);
    expect(p['past']!.tier, SkillTier.started);
    expect(p['present-are']!.tier, SkillTier.locked);
  });

  test('bronze needs every facet graduated out of initial learning', () {
    final f = EventFactory();
    // One Good per facet: all reviewed but still in learning (step 1).
    final once = [for (final id in greetingFacets) f.ev(id, t0)];
    expect(tierAt(once, 'greetings', t0.add(const Duration(minutes: 1))), SkillTier.started);
    // Graduate three of four.
    final later = t0.add(const Duration(minutes: 15));
    final three = [...once, for (final id in greetingFacets.take(3)) f.ev(id, later)];
    final p3 = progressAt(three, later)['greetings']!;
    expect(p3.tier, SkillTier.started);
    expect(p3.learnedCount, 3);
    expect(p3.nextTierProgress, 0.75);
    final all = [...three, f.ev(greetingFacets.last, later)];
    expect(tierAt(all, 'greetings', later), SkillTier.bronze);
    // A relearning facet still counts as learned (it graduated before).
    final lapse = [...all, f.ev(greetingFacets.first, later.add(const Duration(days: 1)), correct: false)];
    final p = progressAt(lapse, later.add(const Duration(days: 1, minutes: 1)));
    expect(p['greetings']!.tier, SkillTier.bronze);
  });

  test('silver and gold thresholds, then decay back down over time', () {
    final f = EventFactory();
    // Train every greeting facet to stability >= 21 days (gold-capable).
    final evs = [for (final id in greetingFacets) ...trainFacet(f, id, t0, targetStability: 21)];
    final lastAt = evs.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
    final states = (LogReplay(scheduler: sch)..update(evs)).states;
    final minS = states.values.map((s) => s.stability).reduce((a, b) => a < b ? a : b);
    expect(minS, greaterThanOrEqualTo(21));

    expect(tierAt(evs, 'greetings', lastAt), SkillTier.gold);
    // R = 0.9^(t/S): gold needs R >= 0.90 -> t <= S. Silver (R >= 0.85) holds until t = S*ln(.85)/ln(.9).
    final goldEnd = lastAt.add(FakeScheduler.days(minS));
    expect(tierAt(evs, 'greetings', goldEnd.subtract(const Duration(hours: 1))), SkillTier.gold);
    expect(tierAt(evs, 'greetings', goldEnd.add(const Duration(hours: 1))), SkillTier.silver);
    final silverEnd = lastAt.add(FakeScheduler.days(minS * 1.5425)); // ln(0.85)/ln(0.9) ≈ 1.5425
    expect(tierAt(evs, 'greetings', silverEnd.add(const Duration(days: 1))), SkillTier.bronze);
    // Much later: still bronze (learned never decays), but fading is high.
    final far = lastAt.add(const Duration(days: 2000));
    final p = progressAt(evs, far)['greetings']!;
    expect(p.tier, SkillTier.bronze);
    expect(p.fading, greaterThan(0.9));
    expect(p.dueCount, 4);
  });

  test('silver needs stability >= 7 even when recall is high', () {
    final f = EventFactory();
    final evs = [for (final id in greetingFacets) ...trainFacet(f, id, t0, targetStability: 1)];
    final lastAt = evs.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
    expect(tierAt(evs, 'greetings', lastAt), SkillTier.bronze); // R=1 but S=1 day
    final evs7 = [for (final id in greetingFacets) ...trainFacet(f, id, t0, targetStability: 7)];
    final last7 = evs7.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
    final p = progressAt(evs7, last7)['greetings']!;
    expect(p.tier, anyOf(SkillTier.silver, SkillTier.gold));
  });

  test('fading grows monotonically with time and strength falls', () {
    final f = EventFactory();
    final evs = [for (final id in greetingFacets) ...trainFacet(f, id, t0, targetStability: 7)];
    final lastAt = evs.last.at;
    var prevFade = -1.0, prevStrength = 2.0;
    for (var d = 0; d < 200; d += 10) {
      final p = progressAt(evs, lastAt.add(Duration(days: d)))['greetings']!;
      expect(p.fading, greaterThanOrEqualTo(prevFade));
      expect(p.strength, lessThanOrEqualTo(prevStrength));
      expect(p.fading, inInclusiveRange(0, 1));
      prevFade = p.fading;
      prevStrength = p.strength;
    }
  });

  test('strength counts unreviewed facets as zero; lastPracticed and daysSince', () {
    final f = EventFactory();
    final p = progressAt([f.ev('it:ciao#rec', t0)], t0)['greetings']!;
    expect(p.strength, closeTo(0.25, 1e-9)); // R=1 for one of four facets
    expect(p.lastPracticed, t0);
    expect(p.daysSincePracticed(t0.add(const Duration(days: 3, hours: 2))), 3);
    expect(p.minRetrievability, 1);
  });
}
