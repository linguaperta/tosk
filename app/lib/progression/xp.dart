/// XP per review event and the level curve. See docs/progression.md.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/core.dart';

/// How much XP one review event earns, given the facet's state just before it.
///
/// * wrong answer: [wrong] if the facet was new or due, otherwise 0
/// * correct, new facet (first review ever): [newFacet]
/// * correct, facet not yet due (re-practice): [notDue] (anti-farming)
/// * correct, due facet: [base]
///   + round([recallBonusMax] × (1 − R)) where R is the predicted recall at answer time
///     (rewards remembering something you were forgetting; grows with overdue-ness)
///   + round([difficultyBonusMax] × (D − 1) / 9) for FSRS difficulty D in 1..10
///   + [lapsedBonus] if the facet has lapsed before or is relearning
@immutable
class XpRules {
  const XpRules({
    this.base = 10,
    this.newFacet = 8,
    this.notDue = 2,
    this.wrong = 1,
    this.recallBonusMax = 8,
    this.difficultyBonusMax = 4,
    this.lapsedBonus = 3,
  });

  final int base;
  final int newFacet;
  final int notDue;
  final int wrong;
  final int recallBonusMax;
  final int difficultyBonusMax;
  final int lapsedBonus;

  /// The most XP a single event can earn.
  int get maxPerEvent => base + recallBonusMax + difficultyBonusMax + lapsedBonus;

  /// XP for [event] given the facet's [before] state (null = never reviewed).
  int xpFor(ReviewEvent event, FacetState? before, Scheduler scheduler) {
    final at = event.at;
    final due = before == null || before.isDue(at);
    if (!event.correct) return due ? wrong : 0;
    if (before == null) return newFacet;
    if (!due) return notDue;
    final r = scheduler.retrievability(before, at).clamp(0.0, 1.0);
    final d = before.difficulty.clamp(1.0, 10.0);
    var xp = base;
    xp += (recallBonusMax * (1 - r)).round();
    xp += (difficultyBonusMax * (d - 1) / 9).round();
    if (before.lapses > 0 || before.phase == CardPhase.relearning) xp += lapsedBonus;
    return xp;
  }
}

/// Position within the level curve.
@immutable
class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.xpIntoLevel,
    required this.xpForNext,
    required this.totalXp,
  });

  /// 1-based level.
  final int level;

  /// XP earned since reaching [level].
  final int xpIntoLevel;

  /// XP needed to go from [level] to the next one (the size of this level).
  final int xpForNext;

  final int totalXp;

  /// Fraction of the way to the next level (0..1).
  double get progress => xpForNext <= 0 ? 0 : (xpIntoLevel / xpForNext).clamp(0.0, 1.0);

  int get xpToNext => xpForNext - xpIntoLevel;

  @override
  bool operator ==(Object other) =>
      other is LevelInfo &&
      other.level == level &&
      other.xpIntoLevel == xpIntoLevel &&
      other.xpForNext == xpForNext &&
      other.totalXp == totalXp;

  @override
  int get hashCode => Object.hash(level, xpIntoLevel, xpForNext, totalXp);

  @override
  String toString() => 'LevelInfo(L$level, $xpIntoLevel/$xpForNext, total $totalXp)';
}

/// Cumulative XP to reach level n is `floor(a × (n − 1)^p)`; level 1 starts at 0.
///
/// Defaults (a = 100, p = 1.6): L2 = 100, L5 = 917, L10 = 3 373, L20 = 11 124, L50 = 50 6xx.
@immutable
class LevelCurve {
  const LevelCurve({this.a = 100, this.p = 1.6, this.maxLevel = 999});

  final double a;
  final double p;
  final int maxLevel;

  /// Cumulative XP needed to reach [level].
  int threshold(int level) => level <= 1 ? 0 : (a * math.pow(level - 1, p)).floor();

  LevelInfo levelFor(int totalXp) {
    final xp = math.max(0, totalXp);
    // Invert the curve, then correct for rounding.
    var level = 1 + math.pow(xp / a, 1 / p).floor();
    level = level.clamp(1, maxLevel);
    while (level > 1 && threshold(level) > xp) {
      level--;
    }
    while (level < maxLevel && threshold(level + 1) <= xp) {
      level++;
    }
    final lo = threshold(level);
    final hi = threshold(level + 1);
    return LevelInfo(level: level, xpIntoLevel: xp - lo, xpForNext: hi - lo, totalXp: xp);
  }
}
