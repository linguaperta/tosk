/// Statistics of the active course (v0.4): the review forecast on the
/// Progress page, and the stats page (`/progress/stats`) with time practiced,
/// words learned over time and accuracy per exercise type and per tense or
/// inflection table. Everything comes from `courseStatsProvider` (log-derived,
/// `progression/stats.dart`). Charts are a small custom paint that reads in
/// black & white: solid black bars, every value also written as a number.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../progression/progression.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../theme/bw_skin.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _day(LocalDate d, LocalDate today) => d == today ? 'Today' : _weekdays[(d.weekday - 1) % 7];

/// `1 h 05 min`, `12 min`, `0 min`.
String formatDuration(Duration d) {
  final minutes = (d.inSeconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')} min';
}

/// A small bar chart: one bar per value, the value above it and the label
/// below. Black bars in black & white; the values are always written out.
class StatBarChart extends StatelessWidget {
  const StatBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.valueLabels,
    this.height = 96,
    this.semanticsLabel,
  });

  final List<double> values;
  final List<String> labels;

  /// Shown above the bars (defaults to the values as integers).
  final List<String>? valueLabels;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = isMonochrome(theme.colorScheme);
    final small = theme.textTheme.labelSmall;
    final tops = valueLabels ?? [for (final v in values) v.round().toString()];
    Widget row(List<String> texts, TextStyle? style) => Row(
      children: [
        for (final t in texts)
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Text(t, style: style, maxLines: 1),
                ),
              ),
            ),
          ),
      ],
    );
    return Semantics(
      label: semanticsLabel ??
          [for (var i = 0; i < values.length; i++) '${labels[i]}: ${tops[i]}'].join(', '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            row(tops, small?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            SizedBox(
              height: height,
              child: CustomPaint(
                painter: BarChartPainter(
                  values: values,
                  bar: mono ? kBwBlack : theme.colorScheme.primary,
                  axis: mono ? kBwBlack : theme.colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(height: 4),
            row(labels, small),
          ],
        ),
      ),
    );
  }
}

/// Bars from a baseline, scaled to the largest value; a zero value is just
/// the baseline.
class BarChartPainter extends CustomPainter {
  BarChartPainter({required this.values, required this.bar, required this.axis});
  final List<double> values;
  final Color bar;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<double>(0, math.max);
    final slot = size.width / values.length;
    final w = math.min(slot * 0.6, 40.0);
    final fill = Paint()..color = bar;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0 || maxV <= 0) continue;
      final h = math.max(2.0, (size.height - 2) * values[i] / maxV);
      final x = slot * i + (slot - w) / 2;
      canvas.drawRect(Rect.fromLTWH(x, size.height - 2 - h, w, h), fill);
    }
    canvas.drawRect(Rect.fromLTWH(0, size.height - 2, size.width, 2), Paint()..color = axis);
  }

  @override
  bool shouldRepaint(BarChartPainter old) => old.values != values || old.bar != bar || old.axis != axis;
}

/// The forecast chart: reviews due today (overdue included) and the next six days.
class ForecastChart extends StatelessWidget {
  const ForecastChart({super.key, required this.forecast});
  final ReviewForecast forecast;

  @override
  Widget build(BuildContext context) {
    final today = forecast.days.first.$1;
    return StatBarChart(
      key: const ValueKey('stats-forecast-chart'),
      values: [for (final d in forecast.days) d.$2.toDouble()],
      labels: [for (final d in forecast.days) _day(d.$1, today)],
      semanticsLabel:
          'Reviews due: ${[for (final d in forecast.days) '${_day(d.$1, today)} ${d.$2}'].join(', ')}',
    );
  }
}

/// On the Progress page: reviews due today and this week, the forecast chart,
/// today's practice time, and "All stats".
class StatsSummaryCard extends ConsumerWidget {
  const StatsSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(courseStatsProvider).value;
    final theme = Theme.of(context);
    if (stats == null) return const SizedBox.shrink();
    final f = stats.forecast;
    return Card(
      key: const ValueKey('stats-summary'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              f.dueToday == 0 ? 'Nothing due today' : '${f.dueToday} ${f.dueToday == 1 ? 'review' : 'reviews'} due today',
              key: const ValueKey('stats-due-today'),
              style: theme.textTheme.titleSmall,
            ),
            Text(
              '${f.total} in the next 7 days · ${formatDuration(stats.time.today)} practiced today',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ForecastChart(forecast: f),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('open-stats'),
                onPressed: () => context.go(Routes.stats),
                icon: const Icon(Icons.insights_outlined),
                label: const Text('All stats'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `/progress/stats`: every statistic of the active course.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: AsyncView(
        value: ref.watch(courseStatsProvider),
        onRetry: () => ref.invalidate(courseStatsProvider),
        builder: (s) {
          Widget section(String title, List<Widget> children, {required Key key}) => Padding(
            key: key,
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                  ),
                ),
              ],
            ),
          );
          final today = s.forecast.days.first.$1;
          final learned = s.learnedByWeek;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                key: const ValueKey('stats-list'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  section('Reviews coming up', key: const ValueKey('stats-forecast'), [
                    Text(
                      '${s.forecast.dueToday} due today'
                      '${s.forecast.overdue > 0 ? ' (${s.forecast.overdue} overdue)' : ''} · '
                      '${s.forecast.total} in the next 7 days',
                    ),
                    const SizedBox(height: 10),
                    ForecastChart(forecast: s.forecast),
                  ]),
                  section('Time practiced', key: const ValueKey('stats-time'), [
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Text('Today: ${formatDuration(s.time.today)}'),
                        Text('7 days: ${formatDuration(s.time.last7Days)}'),
                        Text('30 days: ${formatDuration(s.time.last30Days)}'),
                        Text('In total: ${formatDuration(s.time.total)}'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    StatBarChart(
                      key: const ValueKey('stats-time-chart'),
                      values: [for (final d in s.time.byDay) d.$2.inSeconds / 60],
                      valueLabels: [for (final d in s.time.byDay) '${(d.$2.inSeconds / 60).round()}'],
                      labels: [for (final d in s.time.byDay) _day(d.$1, today)],
                      semanticsLabel:
                          'Minutes practiced: ${[for (final d in s.time.byDay) '${_day(d.$1, today)} ${formatDuration(d.$2)}'].join(', ')}',
                    ),
                    Text('Minutes per day', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  ]),
                  section('Words learned', key: const ValueKey('stats-learned'), [
                    Text('${s.wordsLearned} ${s.wordsLearned == 1 ? 'word' : 'words'} learned'),
                    const SizedBox(height: 10),
                    StatBarChart(
                      key: const ValueKey('stats-learned-chart'),
                      values: [for (final w in learned) w.$2.toDouble()],
                      labels: [for (final w in learned) '${w.$1.day}/${w.$1.month}'],
                      semanticsLabel:
                          'Words learned by week: ${[for (final w in learned) 'week of ${w.$1.day}/${w.$1.month}: ${w.$2}'].join(', ')}',
                    ),
                    Text('In total, by week', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  ]),
                  section('Accuracy by exercise · last $kAccuracyDays days', key: const ValueKey('stats-by-type'), [
                    if (s.byType.isEmpty) const Text('No answers in the last 30 days.'),
                    for (final r in s.byType) AccuracyRowView(row: r),
                  ]),
                  section('Accuracy by tense and form · last $kAccuracyDays days', key: const ValueKey('stats-by-grammar'), [
                    if (s.byGrammar.isEmpty) const Text('No conjugation, inflection or article answers in the last 30 days.'),
                    for (final r in s.byGrammar) AccuracyRowView(row: r),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "Fill the gap · 84% · 52 answers" with a bar.
class AccuracyRowView extends StatelessWidget {
  const AccuracyRowView({super.key, required this.row});
  final AccuracyRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (row.accuracy * 100).round();
    return Padding(
      key: ValueKey('accuracy-${row.key}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(row.label, style: theme.textTheme.bodyMedium)),
              const SizedBox(width: 8),
              Text(
                '$pct% · ${row.total} ${row.total == 1 ? 'answer' : 'answers'}',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: row.accuracy, minHeight: 8),
          ),
        ],
      ),
    );
  }
}
