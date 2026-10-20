/// Facade the UI calls. Pure Dart: no Flutter, no drift.
library;

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'calendar.dart';
import 'challenges.dart';
import 'nonstop.dart';
import 'replay.dart';
import 'session_summary.dart';
import 'stats.dart';
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

/// The header numbers. XP, level and the review counts are the **course's**
/// (progress is per language); the streak, freezes and the daily goal's
/// [accountTodayXp] / [accountTodayReviews] cover every course.
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
    int? accountTodayXp,
    int? accountTodayReviews,
  }) : accountTodayXp = accountTodayXp ?? todayXp,
       accountTodayReviews = accountTodayReviews ?? todayReviews;

  /// This course's total XP.
  final int totalXp;

  /// This course's level.
  final LevelInfo level;

  /// Account-wide: every course's practice days count.
  final StreakInfo streak;

  /// This course's reviews and XP today.
  final int todayReviews;
  final int todayXp;

  /// This course's reviews ever.
  final int totalReviews;
  final LocalDate today;

  /// Account-wide XP and reviews today (the daily goal).
  final int accountTodayXp;
  final int accountTodayReviews;

  int get currentStreak => streak.current;
  int get longestStreak => streak.longest;
  int get freezes => streak.freezes;
}

/// Everything progression shows, recomputed from the review log on demand.
///
/// Each query re-reads the full log from [store] (cheap: a few thousand rows)
/// and updates two incremental [LogReplay]s, one over the whole log and one
/// over [course]'s events (facet ids `{courseId}:...`); when the log only grew
/// at the end, only new events are replayed, otherwise (sync merge) the
/// replay is rebuilt. Results never depend on cached counters, so they always
/// equal a full replay.
///
/// Progress is per language: XP, level, challenges, badges (challenge and
/// level badges), skill tiers, the verb collection, non-stop records and
/// session summaries cover [course] only. Account-wide: the streak, freezes,
/// streak badges, the heatmap and the daily goal's XP per day ([xpByDay]).
/// A facet's replay depends only on its own events, so the course replay's
/// states and per-event XP equal the whole log's.
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
        _replay = LogReplay(scheduler: scheduler, xpRules: config.xp),
        _courseReplay = LogReplay(scheduler: scheduler, xpRules: config.xp);

  final ProgressStore store;
  final Scheduler scheduler;
  final CourseData course;
  final DateTime Function() clock;
  final LocalCalendar calendar;
  final ProgressionConfig config;

  /// Every course: streaks, freezes, the heatmap and the daily goal.
  final LogReplay _replay;

  /// [course]'s events only: everything else.
  final LogReplay _courseReplay;

  // Derived caches, valid for _allVersion / _courseVersion.
  int _allVersion = -1;
  int _courseVersion = -1;
  Map<LocalDate, int>? _dayCounts;
  Map<LocalDate, int>? _dayXp;
  Map<LocalDate, int>? _courseDayCounts;
  Map<LocalDate, int>? _courseDayXp;
  ChallengeFacts? _facts;
  List<NonStopRecord>? _runs;

  /// The course replay as of the last query (read-only use).
  LogReplay get replay => _courseReplay;

  /// The whole-log replay (every course) as of the last query.
  LogReplay get accountReplay => _replay;

  /// Whether [e] belongs to [course] (facet ids start with `{courseId}:`).
  bool inCourse(ReviewEvent e) => e.facetId.startsWith('${course.meta.id}:');

  /// Pulls the log from the store and updates both replays.
  Future<LogReplay> refresh() async {
    final log = await store.log();
    _replay.update(log);
    _courseReplay.update(log.where(inCourse));
    if (_allVersion != _replay.version) {
      _allVersion = _replay.version;
      _dayCounts = null;
      _dayXp = null;
    }
    if (_courseVersion != _courseReplay.version) {
      _courseVersion = _courseReplay.version;
      _courseDayCounts = null;
      _courseDayXp = null;
      _facts = null;
      _runs = null;
    }
    return _courseReplay;
  }

  /// Reviews per local date, every course (streaks, freezes, heatmap).
  Map<LocalDate, int> get _counts => _dayCounts ??= dayCountsOf(_replay.steps.map((s) => s.event), calendar);

  Map<LocalDate, int> get _courseCounts =>
      _courseDayCounts ??= dayCountsOf(_courseReplay.steps.map((s) => s.event), calendar);

  static Map<LocalDate, int> _xpPerDay(LogReplay r, LocalCalendar calendar) {
    final m = <LocalDate, int>{};
    for (final s in r.steps) {
      final d = calendar.dateOf(s.event.at);
      m[d] = (m[d] ?? 0) + s.xp;
    }
    return m;
  }

  /// XP per local date, every course (the daily goal).
  Map<LocalDate, int> get _xpByDay => _dayXp ??= _xpPerDay(_replay, calendar);

  Map<LocalDate, int> get _courseXpByDay => _courseDayXp ??= _xpPerDay(_courseReplay, calendar);

  ChallengeFacts get _challengeFacts =>
      _facts ??= ChallengeFacts.build(_courseReplay.steps, calendar, nonStopRules: config.nonStop);

  StreakInfo _streak(LocalDate today) => computeStreak(_counts, today: today, rules: config.streaks);

  /// The course's XP, level and counts; the account's streak, freezes and
  /// today's XP (daily goal).
  Future<ProgressProfile> profile([DateTime? now]) async {
    await refresh();
    final today = calendar.dateOf(now ?? clock());
    final total = _courseReplay.totalXp;
    return ProgressProfile(
      totalXp: total,
      level: config.levels.levelFor(total),
      streak: _streak(today),
      todayReviews: _courseCounts[today] ?? 0,
      todayXp: _courseXpByDay[today] ?? 0,
      totalReviews: _courseReplay.length,
      today: today,
      accountTodayXp: _xpByDay[today] ?? 0,
      accountTodayReviews: _counts[today] ?? 0,
    );
  }

  /// XP earned per local date (whole log, every course), for the daily goal.
  Future<Map<LocalDate, int>> xpByDay() async {
    await refresh();
    return Map.unmodifiable(_xpByDay);
  }

  /// Tier, strength and fading of every skill of [course], in course order.
  Future<Map<String, SkillProgress>> skillTiers([DateTime? now]) async {
    await refresh();
    return computeSkillProgress(
      course: course,
      states: _courseReplay.states,
      scheduler: scheduler,
      now: (now ?? clock()).toUtc(),
      rules: config.tiers,
    );
  }

  /// What [skillId] needs for its next tier now (see [nextTierNeeds]).
  Future<NextTierNeeds> nextTier(String skillId, [DateTime? now]) async {
    final at = (now ?? clock()).toUtc();
    final tiers = await skillTiers(at);
    return nextTierNeeds(
      tier: tiers[skillId]?.tier ?? SkillTier.available,
      facets: course.skillFacets(skillId),
      states: _courseReplay.states,
      scheduler: scheduler,
      now: at,
      rules: config.tiers,
    );
  }

  /// Heatmap for [from]..[to] (inclusive local dates), every course (it
  /// shows the account-wide streak). Defaults to the 26 weeks ending with the
  /// current week (Monday-aligned).
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

  /// This week's and month's challenges of [course] with progress, plus all badges.
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

  /// Every badge earned up to [now] (oldest first): [course]'s challenges and
  /// level milestones, and the account-wide streak milestones.
  Future<List<EarnedBadge>> badges([DateTime? now]) async {
    await refresh();
    return _badges(calendar.dateOf(now ?? clock()));
  }

  List<EarnedBadge> _badges(LocalDate today) {
    final all = [
      ..._challengeFacts.challengeBadges(today),
      ...streakBadges(_streak(today).milestonesReached),
      ...levelBadges(_courseReplay.steps, calendar, curve: config.levels),
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
      states: _courseReplay.states,
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
      replay: _courseReplay,
      scheduler: scheduler,
      course: course,
      curve: config.levels,
      tierRules: config.tiers,
    );
  }

  /// All non-stop runs of [course] in the log, oldest first.
  Future<List<NonStopRecord>> nonStopHistory() async {
    await refresh();
    return _runs ??= nonStopRuns(_courseReplay.steps.map((s) => s.event), rules: config.nonStop);
  }

  /// The best non-stop run (highest score), or null.
  Future<NonStopRecord?> bestNonStopRun() async {
    NonStopRecord? best;
    for (final r in await nonStopHistory()) {
      if (best == null || r.score > best.score) best = r;
    }
    return best;
  }

  /// [course]'s statistics at [now] (forecast, accuracy, time, words
  /// learned; see [computeCourseStats]), with labels in [lang].
  Future<CourseStats> stats({DateTime? now, String lang = 'en'}) async {
    await refresh();
    return computeCourseStats(
      course: course,
      steps: _courseReplay.steps,
      states: _courseReplay.states,
      calendar: calendar,
      now: (now ?? clock()).toUtc(),
      lang: lang,
    );
  }

  /// A fresh non-stop run state machine using this service's rules.
  NonStopRun newNonStopRun() => NonStopRun(rules: config.nonStop);
}
