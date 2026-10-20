/// Course statistics for the Progress page: the review forecast, accuracy per
/// exercise type, per facet kind and per tense or inflection table, time
/// practiced, and words learned over time. Pure functions of the course replay (the review log)
/// and the facet states. See docs/progression.md, "Statistics".
library;

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'calendar.dart';
import 'replay.dart';

/// Days in the review forecast (today and the next 29). The UI shows the
/// first 7 on the Progress page and 14 or 30 on the stats page.
const int kForecastDays = 30;

/// Window of the accuracy breakdowns.
const int kAccuracyDays = 30;

/// Weeks in the "words learned" chart.
const int kLearnedWeeks = 12;

/// The longest response time counted as practice for one exercise (a longer
/// one is a learner who walked away). Story reads get [kMaxCountedReading].
const Duration kMaxCountedAnswer = Duration(minutes: 5);
const Duration kMaxCountedReading = Duration(minutes: 15);

/// Reviews coming due per local date.
@immutable
class ReviewForecast {
  const ReviewForecast({required this.days, required this.overdue});

  /// [kForecastDays] dates from today; today's count includes the overdue reviews.
  final List<(LocalDate, int)> days;

  /// Reviews already due before today (part of today's count).
  final int overdue;

  int get dueToday => days.isEmpty ? 0 : days.first.$2;
  int get total => days.fold(0, (a, d) => a + d.$2);

  /// The first [n] days (today first).
  List<(LocalDate, int)> window(int n) => days.take(n).toList();

  /// Reviews due within the first [n] days (overdue included).
  int totalIn(int n) => window(n).fold(0, (a, d) => a + d.$2);
}

/// Right answers out of all answers for one exercise type, tense or table.
@immutable
class AccuracyRow {
  const AccuracyRow({required this.key, required this.label, required this.correct, required this.total});

  /// An [ExerciseType] id, `kind:{FacetKind}`, `tense:{tense}`, `infl:{table}` or `article`.
  final String key;
  final String label;
  final int correct;
  final int total;

  double get accuracy => total == 0 ? 0 : correct / total;
}

/// Time spent answering (and reading stories).
@immutable
class PracticeTime {
  const PracticeTime({
    required this.today,
    required this.last7Days,
    required this.last30Days,
    required this.total,
    required this.byDay,
  });

  final Duration today;
  final Duration last7Days;
  final Duration last30Days;
  final Duration total;

  /// The last seven local dates (oldest first) with their time.
  final List<(LocalDate, Duration)> byDay;
}

@immutable
class CourseStats {
  const CourseStats({
    required this.forecast,
    required this.byType,
    this.byKind = const [],
    required this.byGrammar,
    required this.time,
    required this.learnedByWeek,
    required this.wordsLearned,
  });

  final ReviewForecast forecast;

  /// Accuracy per exercise type over the last [kAccuracyDays] days (types with answers only).
  final List<AccuracyRow> byType;

  /// Accuracy per facet kind (recognition, production, verb forms,
  /// inflections, articles), same window; kinds with answers only.
  final List<AccuracyRow> byKind;

  /// Accuracy per tense, inflection table and the article, same window.
  final List<AccuracyRow> byGrammar;
  final PracticeTime time;

  /// Words learned in total by the end of each of the last [kLearnedWeeks]
  /// weeks (`(week start, cumulative count)`, oldest first).
  final List<(LocalDate, int)> learnedByWeek;

  /// Words learned so far.
  final int wordsLearned;

  /// No answer in this course yet.
  bool get isEmpty => time.total == Duration.zero && wordsLearned == 0 && forecast.total == 0;
}

/// English labels of the exercise types (the UI is English).
String accuracyTypeLabel(ExerciseType t) => switch (t) {
  ExerciseType.flashcard => 'Flashcards',
  ExerciseType.multipleChoice => 'Multiple choice',
  ExerciseType.matchPairs => 'Match the pairs',
  ExerciseType.conjPick => 'Pick the ending',
  ExerciseType.conjGrid => 'Conjugation table',
  ExerciseType.sentenceBuilder => 'Build the sentence',
  ExerciseType.cloze => 'Fill the gap',
  ExerciseType.spotError => 'Spot the error',
  ExerciseType.transform => 'Change tense or person',
  ExerciseType.listenPick => 'Listen and pick',
};

/// English labels of the facet kinds (what an answer trained).
String facetKindLabel(FacetKind k) => switch (k) {
  FacetKind.rec => 'Recognition (meaning)',
  FacetKind.prod => 'Production (recall the word)',
  FacetKind.form => 'Verb forms',
  FacetKind.infl => 'Inflections',
  FacetKind.article => 'Articles',
};

/// Statistics of [course] at [now] from its replay [steps] (canonical order,
/// overrides applied) and the facet [states].
///
/// * **Forecast:** the course's reviewed facets by the local date they are
///   due; overdue ones count today.
/// * **Accuracy:** answers in the last [kAccuracyDays] days. Test-out
///   credits, story reads and overrides are no answers (an overridden answer
///   counts as right). Per exercise type (one count per graded facet, so a
///   conjugation grid counts every cell), per facet kind, and per grammar:
///   `#form` facets by tense, `#infl` facets by table, `#article` facets.
/// * **Time:** one exercise records every facet it grades with the same `at`
///   and session, so its response time is counted once (the largest), capped
///   at [kMaxCountedAnswer] ([kMaxCountedReading] for a story).
/// * **Words learned:** an item counts from the first time one of its facets
///   left FSRS's learning phase (the tiers' "learned"; a test-out credit counts).
CourseStats computeCourseStats({
  required CourseData course,
  required Iterable<ReplayStep> steps,
  required Map<String, FacetState> states,
  required LocalCalendar calendar,
  required DateTime now,
  required String lang,
}) {
  final today = calendar.dateOf(now);
  final trained = <String, SkillFacet>{
    for (final s in course.skills)
      for (final f in course.skillFacets(s.id)) f.facetId: f,
  };

  // Forecast.
  final counts = List.filled(kForecastDays, 0);
  var overdue = 0;
  for (final st in states.values) {
    if (!trained.containsKey(st.facetId) || st.reps == 0) continue;
    final d = calendar.dateOf(st.due);
    final offset = today.daysUntil(d);
    if (offset <= 0) {
      counts[0]++;
      if (offset < 0) overdue++;
    } else if (offset < kForecastDays) {
      counts[offset]++;
    }
  }
  final forecast = ReviewForecast(
    days: [for (var i = 0; i < kForecastDays; i++) (today.addDays(i), counts[i])],
    overdue: overdue,
  );

  // Accuracy, time and learning, in one pass.
  final since = now.toUtc().subtract(const Duration(days: kAccuracyDays));
  final byType = <ExerciseType, (int, int)>{};
  final byKind = <FacetKind, (int, int)>{};
  final byGrammar = <String, (int, int)>{};
  final exerciseTime = <(String, int), Duration>{};
  final exerciseDay = <(String, int), LocalDate>{};
  final learnedAt = <String, LocalDate>{};
  (int, int) add((int, int)? old, bool ok) => ((old?.$1 ?? 0) + (ok ? 1 : 0), (old?.$2 ?? 0) + 1);

  for (final step in steps) {
    final e = step.event;
    final facet = trained[e.facetId];
    // Time: once per exercise.
    if (!e.isCredit && !e.isOverride) {
      final key = (e.sessionId ?? e.id, e.at.millisecondsSinceEpoch);
      final cap = e.isStory ? kMaxCountedReading : kMaxCountedAnswer;
      var t = Duration(milliseconds: e.responseMs < 0 ? 0 : e.responseMs);
      if (t > cap) t = cap;
      final old = exerciseTime[key];
      if (old == null || t > old) exerciseTime[key] = t;
      exerciseDay[key] = calendar.dateOf(e.at);
    }
    if (facet == null) continue;
    // Words learned: first graduation of any of the item's facets.
    final graduated = step.after.reps > 0 && step.after.phase != CardPhase.learning;
    final wasLearning = step.before == null || step.before!.phase == CardPhase.learning;
    if (graduated && wasLearning) learnedAt.putIfAbsent(facet.itemId, () => calendar.dateOf(e.at));
    // Accuracy: real answers in the window.
    if (e.isCredit || e.isStory || e.isOverride || e.at.isBefore(since)) continue;
    final type = ExerciseType.tryParse(e.exerciseType);
    if (type != null) byType[type] = add(byType[type], e.correct);
    byKind[facet.kind] = add(byKind[facet.kind], e.correct);
    final g = switch (facet.kind) {
      FacetKind.form when facet.tense != null => 'tense:${facet.tense}',
      FacetKind.infl when facet.tense != null => 'infl:${facet.tense}',
      FacetKind.article => 'article',
      _ => null,
    };
    if (g != null) byGrammar[g] = add(byGrammar[g], e.correct);
  }

  // Time windows.
  var tToday = Duration.zero, t7 = Duration.zero, t30 = Duration.zero, total = Duration.zero;
  final perDay = <LocalDate, Duration>{};
  for (final entry in exerciseTime.entries) {
    final d = exerciseDay[entry.key]!;
    final t = entry.value;
    total += t;
    final ago = d.daysUntil(today);
    if (ago == 0) tToday += t;
    if (ago >= 0 && ago < 7) {
      t7 += t;
      perDay[d] = (perDay[d] ?? Duration.zero) + t;
    }
    if (ago >= 0 && ago < 30) t30 += t;
  }

  // Rows in a stable order: types as declared; tenses in course order, then tables, then the article.
  final meta = course.meta;
  final typeRows = [
    for (final t in ExerciseType.values)
      if (byType[t] case (final ok, final n)) AccuracyRow(key: t.id, label: accuracyTypeLabel(t), correct: ok, total: n),
  ];
  final kindRows = [
    for (final k in FacetKind.values)
      if (byKind[k] case (final ok, final n))
        AccuracyRow(key: 'kind:${k.name}', label: facetKindLabel(k), correct: ok, total: n),
  ];
  final grammarKeys = byGrammar.keys.toList()
    ..sort((a, b) {
      int rank(String k) {
        if (k.startsWith('tense:')) {
          final i = meta.tenses.indexOf(k.substring(6));
          return i < 0 ? 999 : i;
        }
        if (k.startsWith('infl:')) {
          final i = meta.inflectionTables.keys.toList().indexOf(k.substring(5));
          return 1000 + (i < 0 ? 999 : i);
        }
        return 3000;
      }

      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : a.compareTo(b);
    });
  String grammarLabel(String k) {
    if (k.startsWith('tense:')) {
      final tense = k.substring(6);
      return meta.tenseLabel(tense, lang);
    }
    if (k.startsWith('infl:')) {
      final table = meta.inflectionTables[k.substring(5)];
      return table == null ? k.substring(5).replaceAll('_', ' ') : table.titleIn(lang);
    }
    return 'Articles';
  }

  final grammarRows = [
    for (final k in grammarKeys)
      AccuracyRow(key: k, label: grammarLabel(k), correct: byGrammar[k]!.$1, total: byGrammar[k]!.$2),
  ];

  // Words learned per week (cumulative).
  final firstWeek = today.startOfWeek.addDays(-7 * (kLearnedWeeks - 1));
  final learnedDates = learnedAt.values.toList()..sort();
  final weeks = <(LocalDate, int)>[];
  var k = 0;
  for (var w = 0; w < kLearnedWeeks; w++) {
    final start = firstWeek.addDays(7 * w);
    final end = start.addDays(7);
    while (k < learnedDates.length && learnedDates[k].isBefore(end)) {
      k++;
    }
    weeks.add((start, k));
  }

  return CourseStats(
    forecast: forecast,
    byType: typeRows,
    byKind: kindRows,
    byGrammar: grammarRows,
    time: PracticeTime(
      today: tToday,
      last7Days: t7,
      last30Days: t30,
      total: total,
      byDay: [for (var i = 6; i >= 0; i--) (today.addDays(-i), perDay[today.addDays(-i)] ?? Duration.zero)],
    ),
    learnedByWeek: weeks,
    wordsLearned: learnedAt.length,
  );
}
