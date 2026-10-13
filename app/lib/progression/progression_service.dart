/// Facade the UI calls. Pure Dart: no Flutter, no drift.
library;

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'calendar.dart';
import 'challenges.dart';
import 'nonstop.dart';
import 'replay.dart';
import 'session_summary.dart';
import 'streaks.dart';
import 'tiers.dart';
import 'verb_collection.dart';
import 'xp.dart';

/// All tunable rules in one place.
@immutable
class ProgressionConfig {
  const ProgressionConfig({
    this.xp = const XpRules(),
    this.levels = const LevelCurve(),
    this.tiers = const TierRules(),
    this.streaks = const StreakRules(),
    this.nonStop = const NonStopRules(),
  });

  final XpRules xp;
  final LevelCurve levels;
  final TierRules tiers;
  final StreakRules streaks;
  final NonStopRules nonStop;
}

/// The header numbers: XP, level, streak, today's reviews.
@immutable
class ProgressProfile {
  const ProgressProfile({
    required this.totalXp,
    required this.level,
    required this.streak,
    required this.todayReviews,
    required this.todayXp,
    required this.totalReviews,
    required this.today,
  });

  final int totalXp;
  final LevelInfo level;
  final StreakInfo streak;
  final int todayReviews;
  final int todayXp;
  final int totalReviews;
  final LocalDate today;

  int get currentStreak => streak.current;
  int get longestStreak => streak.longest;
  int get freezes => streak.freezes;
}

/// Everything progression shows, recomputed from the review log on demand.
///
/// Each query re-reads the full log from [store] (cheap: a few thousand rows)
/// and updates an incremental [LogReplay]; when the log only grew at the end,
/// only new events are replayed, otherwise (sync merge) the replay is rebuilt.
/// Results never depend on cached counters, so they always equal a full replay.
///
/// XP, level, streak, heatmap, challenges and badges cover the whole log (all
/// courses); skill tiers and the verb collection cover [course].
class ProgressionService {
  ProgressionService({
    required this.store,
    required this.scheduler,
    required this.course,
    DateTime Function()? clock,
    LocalCalendar? calendar,
    this.config = const ProgressionConfig(),
  })  : clock = clock ?? DateTime.now,
        calendar = calendar ?? LocalCalendar.system(),
        _replay = LogReplay(scheduler: scheduler, xpRules: config.xp);

  final ProgressStore store;
  final Scheduler scheduler;
  final CourseData course;
  final DateTime Function() clock;
  final LocalCalendar calendar;
  final ProgressionConfig config;

  final LogReplay _replay;

  // Derived caches, valid for _cacheVersion.
  int _cacheVersion = -1;
  Map<LocalDate, int>? _dayCounts;
  Map<LocalDate, int>? _dayXp;
  ChallengeFacts? _facts;
  List<NonStopRecord>? _runs;

  /// The replay as of the last query (read-only use).
  LogReplay get replay => _replay;

  /// Pulls the log from the store and updates the replay.
  Future<LogReplay> refresh() async {
    _replay.update(await store.log());
    if (_cacheVersion != _replay.version) {
      _cacheVersion = _replay.version;
      _dayCounts = null;
      _dayXp = null;
      _facts = null;
      _runs = null;
    }
    return _replay;
  }

  Map<LocalDate, int> get _counts =>
      _dayCounts ??= dayCountsOf(_replay.steps.map((s) => s.event), calendar);

  Map<LocalDate, int> get _xpByDay {
    final cached = _dayXp;
    if (cached != null) return cached;
    final m = <LocalDate, int>{};
    for (final s in _replay.steps) {
      final d = calendar.dateOf(s.event.at);
      m[d] = (m[d] ?? 0) + s.xp;
    }
    return _dayXp = m;
  }

  ChallengeFacts get _challengeFacts =>
      _facts ??= ChallengeFacts.build(_replay.steps, calendar, nonStopRules: config.nonStop);

  StreakInfo _streak(LocalDate today) => computeStreak(_counts, today: today, rules: config.streaks);

  /// Total XP, level, streak, freezes and today's count.
  Future<ProgressProfile> profile([DateTime? now]) async {
    await refresh();
    final today = calendar.dateOf(now ?? clock());
    final total = _replay.totalXp;
    return ProgressProfile(
      totalXp: total,
      level: config.levels.levelFor(total),
      streak: _streak(today),
      todayReviews: _counts[today] ?? 0,
      todayXp: _xpByDay[today] ?? 0,
      totalReviews: _replay.length,
      today: today,
    );
  }

  /// Tier, strength and fading of every skill of [course], in course order.
  Future<Map<String, SkillProgress>> skillTiers([DateTime? now]) async {
    await refresh();
    return computeSkillProgress(
      course: course,
      states: _replay.states,
      scheduler: scheduler,
      now: (now ?? clock()).toUtc(),
      rules: config.tiers,
    );
  }

  /// Heatmap for [from]..[to] (inclusive local dates). Defaults to the 26 weeks
  /// ending with the current week (Monday-aligned).
  Future<HeatmapData> heatmap({LocalDate? from, LocalDate? to, DateTime? now}) async {
    await refresh();
    final today = calendar.dateOf(now ?? clock());
    final end = to ?? today;
    final start = from ?? today.startOfWeek.addDays(-7 * 25);
    return HeatmapData.fromCounts(
      _counts,
      from: start,
      to: end,
      frozen: _streak(today).frozenDays,
      today: today,
    );
  }

  /// This week's and month's challenges with progress, plus all badges.
  Future<ChallengeBoard> challenges([DateTime? now]) async {
    await refresh();
    final today = calendar.dateOf(now ?? clock());
    final week = Period.weekOf(today), month = Period.monthOf(today);
    return ChallengeBoard(
      week: week,
      month: month,
      weekly: _challengeFacts.challengesFor(week),
      monthly: _challengeFacts.challengesFor(month),
      badges: _badges(today),
    );
  }

  /// Every badge earned up to [now]: challenges, streak and level milestones (oldest first).
  Future<List<EarnedBadge>> badges([DateTime? now]) async {
    await refresh();
    return _badges(calendar.dateOf(now ?? clock()));
  }

  List<EarnedBadge> _badges(LocalDate today) {
    final all = [
      ..._challengeFacts.challengeBadges(today),
      ...streakBadges(_streak(today).milestonesReached),
      ...levelBadges(_replay.steps, calendar, curve: config.levels),
    ];
    all.sort((a, b) {
      final c = a.earnedOn.compareTo(b.earnedOn);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return all;
  }

  /// Verb tables of [course] with their mastery now.
  Future<VerbCollection> verbCollection([DateTime? now]) async {
    await refresh();
    return computeVerbCollection(
      course: course,
      states: _replay.states,
      scheduler: scheduler,
      now: (now ?? clock()).toUtc(),
      rules: config.tiers,
    );
  }

  /// Summary of [sessionId], or null if the log has no events for it.
  Future<SessionProgressSummary?> sessionSummary(String sessionId) async {
    await refresh();
    return summarizeSession(
      sessionId: sessionId,
      replay: _replay,
      scheduler: scheduler,
      course: course,
      curve: config.levels,
      tierRules: config.tiers,
    );
  }

  /// All non-stop runs in the log, oldest first.
  Future<List<NonStopRecord>> nonStopHistory() async {
    await refresh();
    return _runs ??= nonStopRuns(_replay.steps.map((s) => s.event), rules: config.nonStop);
  }

  /// The best non-stop run (highest score), or null.
  Future<NonStopRecord?> bestNonStopRun() async {
    NonStopRecord? best;
    for (final r in await nonStopHistory()) {
      if (best == null || r.score > best.score) best = r;
    }
    return best;
  }

  /// A fresh non-stop run state machine using this service's rules.
  NonStopRun newNonStopRun() => NonStopRun(rules: config.nonStop);
}
