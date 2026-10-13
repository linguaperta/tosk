import 'package:tosk/core/core.dart';
import 'package:tosk/progression/xp.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/events.dart';
import 'fakes/fake_scheduler.dart';

void main() {
  const sch = FakeScheduler();
  const rules = XpRules();
  final f = EventFactory();
  const id = 'it:ciao#rec';
  final t0 = utc(2026, 10, 1, 9);

  FacetState reviewState({double s = 10, double d = 5, int lapses = 0, CardPhase phase = CardPhase.review}) =>
      FacetState(
        facetId: id,
        stability: s,
        difficulty: d,
        due: t0.add(FakeScheduler.days(s)),
        lastReview: t0,
        reps: 3,
        lapses: lapses,
        phase: phase,
      );

  group('XpRules', () {
    test('new facet: correct earns newFacet, wrong earns wrong', () {
      expect(rules.xpFor(f.ev(id, t0), null, sch), rules.newFacet);
      expect(rules.xpFor(f.ev(id, t0, correct: false), null, sch), rules.wrong);
    });

    test('not-due re-practice earns little (anti-farming), wrong earns nothing', () {
      final s = reviewState();
      final early = t0.add(const Duration(days: 2));
      expect(rules.xpFor(f.ev(id, early), s, sch), rules.notDue);
      expect(rules.xpFor(f.ev(id, early, correct: false), s, sch), 0);
    });

    test('due facet earns base plus a recall bonus that grows with overdue-ness', () {
      final s = reviewState(d: 1); // no difficulty bonus
      final onTime = rules.xpFor(f.ev(id, s.due), s, sch);
      final late = rules.xpFor(f.ev(id, s.due.add(const Duration(days: 60))), s, sch);
      // R at due = 0.9 -> round(8 * 0.1) = 1
      expect(onTime, rules.base + 1);
      expect(late, greaterThan(onTime));
      expect(late, lessThanOrEqualTo(rules.base + rules.recallBonusMax));
      expect(rules.xpFor(f.ev(id, s.due, correct: false), s, sch), rules.wrong);
    });

    test('difficulty and lapses add bonuses', () {
      final easy = reviewState(d: 1);
      final hard = reviewState(d: 10);
      final lapsed = reviewState(d: 1, lapses: 2);
      final relearning = reviewState(d: 1, phase: CardPhase.relearning);
      final base = rules.xpFor(f.ev(id, easy.due), easy, sch);
      expect(rules.xpFor(f.ev(id, hard.due), hard, sch), base + rules.difficultyBonusMax);
      expect(rules.xpFor(f.ev(id, lapsed.due), lapsed, sch), base + rules.lapsedBonus);
      expect(rules.xpFor(f.ev(id, relearning.due), relearning, sch), base + rules.lapsedBonus);
    });

    test('never exceeds maxPerEvent', () {
      final s = reviewState(d: 10, lapses: 5);
      final x = rules.xpFor(f.ev(id, t0.add(const Duration(days: 3650))), s, sch);
      expect(x, rules.maxPerEvent);
    });
  });

  group('LevelCurve', () {
    const curve = LevelCurve();

    test('thresholds increase and gaps widen', () {
      expect(curve.threshold(1), 0);
      expect(curve.threshold(2), 100);
      var prevGap = 0;
      for (var l = 1; l < 60; l++) {
        final gap = curve.threshold(l + 1) - curve.threshold(l);
        expect(gap, greaterThan(0));
        expect(gap, greaterThanOrEqualTo(prevGap));
        prevGap = gap;
      }
    });

    test('levelFor is consistent with thresholds at every boundary', () {
      expect(curve.levelFor(0), const LevelInfo(level: 1, xpIntoLevel: 0, xpForNext: 100, totalXp: 0));
      expect(curve.levelFor(-5).level, 1);
      expect(curve.levelFor(99).level, 1);
      expect(curve.levelFor(100).level, 2);
      for (var l = 2; l < 200; l++) {
        final t = curve.threshold(l);
        expect(curve.levelFor(t).level, l, reason: 'at threshold of $l');
        expect(curve.levelFor(t).xpIntoLevel, 0);
        expect(curve.levelFor(t - 1).level, l - 1);
      }
    });

    test('LevelInfo progress', () {
      final info = curve.levelFor(150);
      expect(info.level, 2);
      expect(info.xpIntoLevel, 50);
      expect(info.xpForNext, curve.threshold(3) - 100);
      expect(info.progress, closeTo(50 / info.xpForNext, 1e-9));
      expect(info.xpToNext, info.xpForNext - 50);
    });
  });
}
