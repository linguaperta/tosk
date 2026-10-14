/// Practice-day streaks with freezes, and heatmap data. See docs/progression.md.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'calendar.dart';

@immutable
class StreakRules {
  const StreakRules({
    this.reviewsPerFreeze = 50,
    this.maxFreezes = 2,
    this.milestones = const [7, 30, 100, 365],
  });

  /// Every this many reviews earns one streak freeze (while below [maxFreezes]).
  final int reviewsPerFreeze;

  /// Freezes held at most; reviews done at the cap earn nothing.
  final int maxFreezes;

  /// Streak lengths that earn a milestone badge.
  final List<int> milestones;
}

/// Streak state on a given local day.
@immutable
class StreakInfo {
  const StreakInfo({
    required this.today,
    required this.current,
    required this.longest,
    required this.freezes,
    required this.practicedToday,
    required this.reviewsTowardNextFreeze,
    required this.frozenDays,
    required this.milestonesReached,
    this.lastPracticeDay,
  });

  static StreakInfo empty(LocalDate today) => StreakInfo(
        today: today,
        current: 0,
        longest: 0,
        freezes: 0,
        practicedToday: false,
        reviewsTowardNextFreeze: 0,
        frozenDays: const {},
        milestonesReached: const {},
      );

  final LocalDate today;

  /// Practice days in the current run. Frozen days keep the run alive but don't add to it.
  /// If today has no practice yet, this is the run through yesterday (still alive until today ends).
  final int current;
  final int longest;

  /// Freezes held now.
  final int freezes;
  final bool practicedToday;

  /// Reviews counted toward the next freeze (0 ..< reviewsPerFreeze).
  final int reviewsTowardNextFreeze;

  /// Missed days covered by a freeze.
  final Set<LocalDate> frozenDays;

  /// Milestone length → the practice day it was first reached.
  final Map<int, LocalDate> milestonesReached;

  final LocalDate? lastPracticeDay;

  /// The streak breaks at the end of today unless the user practices (and no freeze covers it).
  bool get atRisk => current > 0 && !practicedToday && freezes == 0;
}

/// Computes the streak from per-day review counts.
///
/// Days are processed in order, as they happened:
/// * a practice day (count > 0) extends the run by one, then its reviews
///   accumulate toward freezes (one per [StreakRules.reviewsPerFreeze], up to
///   [StreakRules.maxFreezes] held);
/// * a missed day while a run is active consumes one freeze if available
///   (the day becomes frozen), otherwise the run resets to 0;
/// * today is never treated as missed; days after [today] are ignored.
StreakInfo computeStreak(
  Map<LocalDate, int> dayCounts, {
  required LocalDate today,
  StreakRules rules = const StreakRules(),
}) {
  final days = [
    for (final e in dayCounts.entries)
      if (e.value > 0 && !e.key.isAfter(today)) e.key,
  ]..sort();
  if (days.isEmpty) return StreakInfo.empty(today);

  var streak = 0, longest = 0, freezes = 0, progress = 0;
  final frozen = <LocalDate>{};
  final milestones = <int, LocalDate>{};

  void missDay(LocalDate d) {
    if (streak == 0) return;
    if (freezes > 0) {
      freezes--;
      frozen.add(d);
    } else {
      streak = 0;
    }
  }

  void missRange(LocalDate fromIncl, LocalDate toExcl) {
    for (var d = fromIncl; d.isBefore(toExcl); d = d.addDays(1)) {
      if (streak == 0) return; // nothing left to protect
      missDay(d);
    }
  }

  LocalDate? prev;
  for (final d in days) {
    if (prev != null) missRange(prev.addDays(1), d);
    streak++;
    longest = math.max(longest, streak);
    for (final m in rules.milestones) {
      if (streak >= m) milestones.putIfAbsent(m, () => d);
    }
    progress += dayCounts[d]!;
    if (rules.reviewsPerFreeze > 0) {
      while (progress >= rules.reviewsPerFreeze) {
        progress -= rules.reviewsPerFreeze;
        if (freezes < rules.maxFreezes) freezes++;
      }
    }
    prev = d;
  }
  // Days after the last practice day, up to and excluding today.
  missRange(prev!.addDays(1), today);

  return StreakInfo(
    today: today,
    current: streak,
    longest: longest,
    freezes: freezes,
    practicedToday: prev == today,
    reviewsTowardNextFreeze: progress,
    frozenDays: UnmodifiableSetView(frozen),
    milestonesReached: UnmodifiableMapView(milestones),
    lastPracticeDay: prev,
  );
}

/// Review counts per local date (test-out credits are not reviews).
Map<LocalDate, int> dayCountsOf(Iterable<ReviewEvent> events, LocalCalendar calendar) {
  final m = <LocalDate, int>{};
  for (final e in events) {
    if (e.isCredit) continue;
    final d = calendar.dateOf(e.at);
    m[d] = (m[d] ?? 0) + 1;
  }
  return m;
}

/// Intensity bucket 0..4 for a day's review count (0 = none).
int heatmapBucket(int count, {List<int> thresholds = const [1, 10, 25, 50]}) {
  var b = 0;
  for (final t in thresholds) {
    if (count >= t) b++;
  }
  return b;
}

/// GitHub-style heatmap data for an inclusive range of local dates.
@immutable
class HeatmapData {
  const HeatmapData({
    required this.from,
    required this.to,
    required this.counts,
    this.frozen = const {},
    this.today,
    this.thresholds = const [1, 10, 25, 50],
  });

  /// First and last day shown (inclusive).
  final LocalDate from;
  final LocalDate to;

  /// Review count per day (days without reviews are absent).
  final Map<LocalDate, int> counts;

  /// Days covered by a streak freeze.
  final Set<LocalDate> frozen;
  final LocalDate? today;
  final List<int> thresholds;

  int countOn(LocalDate d) => counts[d] ?? 0;

  /// 0..[maxBucket].
  int bucketOf(LocalDate d) => heatmapBucket(countOn(d), thresholds: thresholds);

  int get maxBucket => thresholds.length;

  bool isFrozen(LocalDate d) => frozen.contains(d);

  int get totalReviews => counts.values.fold(0, (a, b) => a + b);

  int get activeDays => counts.values.where((c) => c > 0).length;

  /// Days in range, in order.
  Iterable<LocalDate> get days sync* {
    for (var d = from; !d.isAfter(to); d = d.addDays(1)) {
      yield d;
    }
  }

  /// Builds heatmap data for [from]..[to] from full day counts.
  factory HeatmapData.fromCounts(
    Map<LocalDate, int> allCounts, {
    required LocalDate from,
    required LocalDate to,
    Set<LocalDate> frozen = const {},
    LocalDate? today,
  }) {
    bool inRange(LocalDate d) => !d.isBefore(from) && !d.isAfter(to);
    return HeatmapData(
      from: from,
      to: to,
      counts: {
        for (final e in allCounts.entries)
          if (inRange(e.key) && e.value > 0) e.key: e.value,
      },
      frozen: {for (final d in frozen) if (inRange(d)) d},
      today: today,
    );
  }
}
