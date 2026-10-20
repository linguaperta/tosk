/// Weekly and monthly challenges, and badges. See docs/progression.md.
///
/// Selection is a pure function of the period id (seeded PRNG), and progress
/// is a pure function of the replayed log, so every device computes the same
/// challenges, progress and badges.
library;

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'calendar.dart';
import 'nonstop.dart';
import 'prng.dart';
import 'replay.dart';
import 'xp.dart';

enum ChallengeMetric {
  /// Review events (every graded facet outcome).
  reviews,

  /// Correct review events.
  correctAnswers,

  /// Correct conjugation exercises (`conj_pick`, `conj_grid`).
  conjugations,

  /// Distinct local days with at least one review.
  practiceDays,

  /// Lessons (mode `lesson`) of at least 5 answers without a single mistake.
  perfectLessons,

  /// Items (words) reviewed for the first time ever.
  newWords,

  /// XP earned.
  xp,

  /// Verb tables (`#form:` facets) reaching stability ≥ 7 days for the first time.
  strongVerbTables,

  /// Verb tables reaching stability ≥ 21 days for the first time.
  masteredVerbTables,

  /// Best combo reached in a non-stop run (a maximum, not a sum).
  nonStopCombo,
}

@immutable
class ChallengeTemplate {
  const ChallengeTemplate({
    required this.id,
    required this.metric,
    required this.target,
    required this.title,
    required this.description,
  });

  /// Stable id, unique within its pool.
  final String id;
  final ChallengeMetric metric;
  final int target;

  /// English display strings (the UI may localize by [id]).
  final String title;
  final String description;
}

const List<ChallengeTemplate> weeklyChallengePool = [
  ChallengeTemplate(
      id: 'reviews150', metric: ChallengeMetric.reviews, target: 150,
      title: '150 reviews', description: 'Answer 150 exercises this week'),
  ChallengeTemplate(
      id: 'reviews300', metric: ChallengeMetric.reviews, target: 300,
      title: '300 reviews', description: 'Answer 300 exercises this week'),
  ChallengeTemplate(
      id: 'conj50', metric: ChallengeMetric.conjugations, target: 50,
      title: 'Conjugator', description: 'Get 50 conjugation exercises right'),
  ChallengeTemplate(
      id: 'days7', metric: ChallengeMetric.practiceDays, target: 7,
      title: 'Every single day', description: 'Practice on all 7 days of the week'),
  ChallengeTemplate(
      id: 'days5', metric: ChallengeMetric.practiceDays, target: 5,
      title: 'Five-day week', description: 'Practice on 5 days this week'),
  ChallengeTemplate(
      id: 'perfect3', metric: ChallengeMetric.perfectLessons, target: 3,
      title: 'Flawless ×3', description: 'Finish 3 lessons without a mistake'),
  ChallengeTemplate(
      id: 'new20', metric: ChallengeMetric.newWords, target: 20,
      title: 'Word collector', description: 'Learn 20 new words'),
  ChallengeTemplate(
      id: 'xp1500', metric: ChallengeMetric.xp, target: 1500,
      title: '1,500 XP', description: 'Earn 1,500 XP this week'),
  ChallengeTemplate(
      id: 'strong5', metric: ChallengeMetric.strongVerbTables, target: 5,
      title: 'Solid tables', description: 'Strengthen 5 verb tables to a week of memory'),
  ChallengeTemplate(
      id: 'combo25', metric: ChallengeMetric.nonStopCombo, target: 25,
      title: 'Combo 25', description: 'Reach a 25 combo in non-stop mode'),
];

const List<ChallengeTemplate> monthlyChallengePool = [
  ChallengeTemplate(
      id: 'reviews1000', metric: ChallengeMetric.reviews, target: 1000,
      title: '1,000 reviews', description: 'Answer 1,000 exercises this month'),
  ChallengeTemplate(
      id: 'conj250', metric: ChallengeMetric.conjugations, target: 250,
      title: 'Conjugation marathon', description: 'Get 250 conjugation exercises right'),
  ChallengeTemplate(
      id: 'days20', metric: ChallengeMetric.practiceDays, target: 20,
      title: '20 practice days', description: 'Practice on 20 days this month'),
  ChallengeTemplate(
      id: 'perfect10', metric: ChallengeMetric.perfectLessons, target: 10,
      title: 'Flawless ×10', description: 'Finish 10 lessons without a mistake'),
  ChallengeTemplate(
      id: 'new80', metric: ChallengeMetric.newWords, target: 80,
      title: 'Vocabulary builder', description: 'Learn 80 new words'),
  ChallengeTemplate(
      id: 'xp6000', metric: ChallengeMetric.xp, target: 6000,
      title: '6,000 XP', description: 'Earn 6,000 XP this month'),
  ChallengeTemplate(
      id: 'master10', metric: ChallengeMetric.masteredVerbTables, target: 10,
      title: 'Table master', description: 'Master 10 verb tables (3 weeks of memory)'),
  ChallengeTemplate(
      id: 'combo50', metric: ChallengeMetric.nonStopCombo, target: 50,
      title: 'Combo 50', description: 'Reach a 50 combo in non-stop mode'),
];

/// Deterministic challenge selection for [period]: the pool is shuffled with a
/// PRNG seeded by the period id, then the first [count] templates with distinct
/// metrics are taken. Defaults: 3 weekly, 2 monthly.
List<ChallengeTemplate> selectChallenges(Period period, {List<ChallengeTemplate>? pool, int? count}) {
  final p = pool ?? (period.kind == PeriodKind.week ? weeklyChallengePool : monthlyChallengePool);
  final n = count ?? (period.kind == PeriodKind.week ? 3 : 2);
  // The seed predates the rename to tosk; changing it would reshuffle running challenges.
  // Split so a repo-wide rename never touches it.
  final rng = XorShift32.fromString('due' 'lingo/challenges/${period.id}');
  final out = <ChallengeTemplate>[];
  final metrics = <ChallengeMetric>{};
  for (final t in rng.shuffled(p)) {
    if (out.length >= n) break;
    if (metrics.add(t.metric)) out.add(t);
  }
  return out;
}

/// A challenge in a period with its progress.
@immutable
class Challenge {
  const Challenge({
    required this.template,
    required this.period,
    required this.progress,
    this.completedAt,
  });

  final ChallengeTemplate template;
  final Period period;

  /// Progress toward [ChallengeTemplate.target] (may exceed it).
  final int progress;

  /// The instant of the event that completed it.
  final DateTime? completedAt;

  String get id => '${period.id}:${template.id}';
  int get target => template.target;
  bool get completed => progress >= template.target;
  double get fraction => target <= 0 ? 1 : (progress / target).clamp(0.0, 1.0);
}

enum BadgeKind { challenge, streak, level }

/// A badge earned, derived from the log.
@immutable
class EarnedBadge {
  const EarnedBadge({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.earnedOn,
    this.earnedAt,
    this.period,
    this.metric,
  });

  /// e.g. `W2026-42:reviews150`, `streak:30`, `level:10`.
  final String id;
  final BadgeKind kind;
  final String title;
  final String description;

  /// Local date it was earned.
  final LocalDate earnedOn;
  final DateTime? earnedAt;
  final Period? period;
  final ChallengeMetric? metric;
}

/// Current challenges plus every badge earned so far.
@immutable
class ChallengeBoard {
  const ChallengeBoard({
    required this.week,
    required this.month,
    required this.weekly,
    required this.monthly,
    required this.badges,
  });

  final Period week;
  final Period month;
  final List<Challenge> weekly;
  final List<Challenge> monthly;

  /// All badges, oldest first.
  final List<EarnedBadge> badges;

  /// Days left in the week / month including [today].
  int daysLeftInWeek(LocalDate today) => today.daysUntil(week.end);
  int daysLeftInMonth(LocalDate today) => today.daysUntil(month.end);
}

@immutable
class _Contribution {
  const _Contribution(this.date, this.at, this.amount);
  final LocalDate date;
  final DateTime at;
  final int amount;
}

const Set<String> _conjTypes = {'conj_pick', 'conj_grid'};

/// Per-metric contributions extracted once from the replayed log, bucketed by period.
class ChallengeFacts {
  ChallengeFacts.build(
    List<ReplayStep> steps,
    this.calendar, {
    this.nonStopRules = const NonStopRules(),
    this.perfectLessonMinAnswers = 5,
    this.strongStabilityDays = 7,
    this.masteredStabilityDays = 21,
  }) {
    final seenItems = <String>{};
    final seenDays = <LocalDate>{};
    final strong = <String>{};
    final mastered = <String>{};
    final lessons = <String, List<ReplayStep>>{};
    final nonstop = <String, List<ReviewEvent>>{};
    final dates = <ReviewEvent, LocalDate>{};

    for (final s in steps) {
      final e = s.event;
      if (e.isCredit) continue; // test-out credits are not answers
      final d = calendar.dateOf(e.at);
      dates[e] = d;
      _firstDate ??= d;
      if (e.isStory) {
        // A story read is practice and earns XP, but it is no answer and no word.
        if (seenDays.add(d)) _add(ChallengeMetric.practiceDays, d, e.at, 1);
        if (s.xp > 0) _add(ChallengeMetric.xp, d, e.at, s.xp);
        continue;
      }
      _add(ChallengeMetric.reviews, d, e.at, 1);
      if (e.correct) {
        _add(ChallengeMetric.correctAnswers, d, e.at, 1);
        if (_conjTypes.contains(e.exerciseType)) _add(ChallengeMetric.conjugations, d, e.at, 1);
      }
      if (seenDays.add(d)) _add(ChallengeMetric.practiceDays, d, e.at, 1);
      if (s.xp > 0) _add(ChallengeMetric.xp, d, e.at, s.xp);
      if (seenItems.add(_itemIdOf(e.facetId))) _add(ChallengeMetric.newWords, d, e.at, 1);
      if (e.facetId.contains('#form:')) {
        if (s.after.stability >= strongStabilityDays && strong.add(e.facetId)) {
          _add(ChallengeMetric.strongVerbTables, d, e.at, 1);
        }
        if (s.after.stability >= masteredStabilityDays && mastered.add(e.facetId)) {
          _add(ChallengeMetric.masteredVerbTables, d, e.at, 1);
        }
      }
      final sid = e.sessionId;
      if (sid != null && e.mode == 'lesson') (lessons[sid] ??= []).add(s);
      if (sid != null && e.mode == kNonStopMode) (nonstop[sid] ??= []).add(e);
    }

    for (final l in lessons.values) {
      if (l.length >= perfectLessonMinAnswers && l.every((s) => s.event.correct)) {
        final last = l.last.event;
        _add(ChallengeMetric.perfectLessons, dates[last]!, last.at, 1);
      }
    }
    for (final evs in nonstop.values) {
      var run = NonStopRun(rules: nonStopRules);
      for (final a in answersFromEvents(evs)) {
        run = run.answer(correct: a.correct, at: a.at, exerciseType: a.exerciseType);
        if (run.combo > 0) _add(ChallengeMetric.nonStopCombo, calendar.dateOf(a.at), a.at, run.combo);
      }
    }
    for (final byPeriod in _buckets.values) {
      for (final l in byPeriod.values) {
        l.sort((a, b) => a.at.compareTo(b.at));
      }
    }
  }

  final LocalCalendar calendar;
  final NonStopRules nonStopRules;
  final int perfectLessonMinAnswers;
  final double strongStabilityDays;
  final double masteredStabilityDays;

  LocalDate? _firstDate;

  /// Local date of the first event, or null for an empty log.
  LocalDate? get firstDate => _firstDate;

  // metric -> period id -> contributions
  final Map<ChallengeMetric, Map<String, List<_Contribution>>> _buckets = {};

  static String _itemIdOf(String facetId) {
    final i = facetId.lastIndexOf('#');
    return i <= 0 ? facetId : facetId.substring(0, i);
  }

  void _add(ChallengeMetric m, LocalDate d, DateTime at, int amount) {
    final c = _Contribution(d, at, amount);
    final b = _buckets[m] ??= {};
    (b[Period.weekOf(d).id] ??= []).add(c);
    (b[Period.monthOf(d).id] ??= []).add(c);
  }

  /// Progress of [template] in [period].
  Challenge evaluate(ChallengeTemplate template, Period period) {
    final list = _buckets[template.metric]?[period.id] ?? const <_Contribution>[];
    final isMax = template.metric == ChallengeMetric.nonStopCombo;
    var progress = 0;
    DateTime? completedAt;
    for (final c in list) {
      progress = isMax ? (c.amount > progress ? c.amount : progress) : progress + c.amount;
      if (completedAt == null && progress >= template.target) completedAt = c.at;
    }
    return Challenge(template: template, period: period, progress: progress, completedAt: completedAt);
  }

  List<Challenge> challengesFor(Period period) =>
      [for (final t in selectChallenges(period)) evaluate(t, period)];

  /// Badges for every completed challenge from the first event's period up to [today]'s.
  List<EarnedBadge> challengeBadges(LocalDate today) {
    final first = firstDate;
    if (first == null) return const [];
    final out = <EarnedBadge>[];
    for (final kind in PeriodKind.values) {
      for (var p = Period.of(kind, first); !p.start.isAfter(today); p = p.next) {
        for (final c in challengesFor(p)) {
          if (!c.completed) continue;
          out.add(EarnedBadge(
            id: c.id,
            kind: BadgeKind.challenge,
            title: c.template.title,
            description: c.template.description,
            earnedOn: calendar.dateOf(c.completedAt!),
            earnedAt: c.completedAt,
            period: p,
            metric: c.template.metric,
          ));
        }
      }
    }
    return out;
  }
}

/// Level milestone badges ([levels]) from the replayed log.
List<EarnedBadge> levelBadges(
  List<ReplayStep> steps,
  LocalCalendar calendar, {
  LevelCurve curve = const LevelCurve(),
  List<int> levels = const [5, 10, 25, 50, 100],
}) {
  final out = <EarnedBadge>[];
  var i = 0;
  for (final lvl in levels) {
    final need = curve.threshold(lvl);
    while (i < steps.length && steps[i].cumulativeXp < need) {
      i++;
    }
    if (i >= steps.length) break;
    final at = steps[i].event.at;
    out.add(EarnedBadge(
      id: 'level:$lvl',
      kind: BadgeKind.level,
      title: 'Level $lvl',
      description: 'Reached level $lvl',
      earnedOn: calendar.dateOf(at),
      earnedAt: at,
    ));
  }
  return out;
}

/// Streak milestone badges from [milestonesReached] (length → day reached).
List<EarnedBadge> streakBadges(Map<int, LocalDate> milestonesReached) => [
      for (final e in (milestonesReached.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
        EarnedBadge(
          id: 'streak:${e.key}',
          kind: BadgeKind.streak,
          title: '${e.key}-day streak',
          description: 'Practiced ${e.key} days in a row',
          earnedOn: e.value,
        ),
    ];
