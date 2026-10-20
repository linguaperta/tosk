/// Statistics of the active course (v0.4): the review forecast on the
/// Progress page, and the stats page (`/progress/stats`) with the forecast
/// for 14 or 30 days, time practiced, words learned over time, and accuracy
/// per exercise type, per facet kind and per tense or inflection table.
/// Everything comes from `courseStatsProvider` (derived from the review log,
/// `progression/stats.dart`). Charts are a small custom paint that reads in
/// black & white: solid black bars on a black baseline, values written as
/// numbers, nothing told by color alone.
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
import '../theme/tosk_palette.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _day(LocalDate d, LocalDate today) => d == today ? 'Today' : _weekdays[(d.weekday - 1) % 7];

String _date(LocalDate d) => '${d.day}/${d.month}';

/// `1 h 05 min`, `12 min`, `0 min`.
String formatDuration(Duration d) {
  final minutes = (d.inSeconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')} min';
}

String _reviews(int n) => '$n ${n == 1 ? 'review' : 'reviews'}';

/// A small bar chart: one bar per value, the value above it (when
/// [valueLabels] isn't empty) and the label below. Black bars in black &
/// white. [labels] may hold empty strings to label only some bars; with no
/// values above the bars the largest value is written at the top left.
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

  /// Shown above the bars (defaults to the values as integers; empty: none).
  final List<String>? valueLabels;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = isMonochrome(theme.colorScheme);
    final small = theme.textTheme.labelSmall;
    final tops = valueLabels ?? [for (final v in values) v.round().toString()];
    final maxV = values.fold<double>(0, math.max);
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
    // Sparse labels (every n-th bar) start at their bar and may be wider
    // than it: they take the space of the empty labels after them.
    final sparse = labels.where((l) => l.isNotEmpty).length < labels.length;
    Widget labelRow() {
      if (!sparse) return row(labels, small);
      return LayoutBuilder(
        builder: (context, c) {
          final slot = c.maxWidth / math.max(1, labels.length);
          return SizedBox(
            height: (small?.fontSize ?? 11) * 1.6 * MediaQuery.textScalerOf(context).scale(1),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < labels.length; i++)
                  if (labels[i].isNotEmpty)
                    Positioned(
                      left: math.max(0, slot * i),
                      top: 0,
                      child: Text(labels[i], style: small, maxLines: 1),
                    ),
              ],
            ),
          );
        },
      );
    }

    return Semantics(
      label:
          semanticsLabel ?? [for (var i = 0; i < values.length; i++) '${labels[i]}: ${values[i].round()}'].join(', '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tops.isNotEmpty)
              row(tops, small?.copyWith(fontWeight: FontWeight.w700))
            else
              Text('max ${maxV.round()}', style: small?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            SizedBox(
              height: height,
              child: CustomPaint(
                painter: BarChartPainter(
                  values: values,
                  bar: mono ? kBwBlack : theme.colorScheme.primary,
                  axis: mono ? kBwBlack : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            labelRow(),
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
    if (values.isEmpty || size.width <= 0 || size.height <= 2) return;
    final maxV = values.fold<double>(0, math.max);
    final slot = size.width / values.length;
    final w = math.max(1.0, math.min(slot * 0.6, 40.0));
    final fill = Paint()..color = bar;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (!v.isFinite || v <= 0 || maxV <= 0) continue;
      final h = math.max(2.0, (size.height - 2) * v / maxV);
      final x = slot * i + (slot - w) / 2;
      canvas.drawRect(Rect.fromLTWH(x, size.height - 2 - h, w, h), fill);
    }
    canvas.drawRect(Rect.fromLTWH(0, size.height - 2, size.width, 2), Paint()..color = axis);
  }

  @override
  bool shouldRepaint(BarChartPainter old) => !_same(old.values, values) || old.bar != bar || old.axis != axis;

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The forecast chart: reviews due on each of the first [days] days (today
/// includes the overdue ones). Up to 14 days every bar has its count and day;
/// longer windows label every 7th day with its date and write the busiest
/// day's count at the top.
class ForecastChart extends StatelessWidget {
  const ForecastChart({super.key, required this.forecast, this.days = 7});
  final ReviewForecast forecast;
  final int days;

  @override
  Widget build(BuildContext context) {
    final window = forecast.window(days);
    if (window.isEmpty) return const SizedBox.shrink();
    final today = window.first.$1;
    final dense = window.length > 14;
    return StatBarChart(
      key: ValueKey('stats-forecast-chart-$days'),
      values: [for (final d in window) d.$2.toDouble()],
      valueLabels: dense ? const [] : null,
      labels: [
        for (var i = 0; i < window.length; i++)
          if (dense)
            i % 7 == 0 && i + 5 < window.length ? (i == 0 ? 'Today' : _date(window[i].$1)) : ''
          else if (window.length > 7)
            i == 0 ? 'Today' : _weekdays[(window[i].$1.weekday - 1) % 7].substring(0, 2)
          else
            _day(window[i].$1, today),
      ],
      semanticsLabel:
          'Reviews due in the next $days days: ${[for (final d in window) '${_day(d.$1, today)} ${_date(d.$1)}: ${d.$2}'].join(', ')}',
    );
  }
}

/// On the Progress page: reviews due today and this week, the 7-day
/// forecast, today's practice time, and "All stats".
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
              f.dueToday == 0 ? 'Nothing due today' : '${_reviews(f.dueToday)} due today',
              key: const ValueKey('stats-due-today'),
              style: theme.textTheme.titleSmall,
            ),
            Text(
              '${f.totalIn(7)} in the next 7 days · ${formatDuration(stats.time.today)} practiced today',
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
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  /// The forecast window: 14 or 30 days.
  int _days = 14;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.progress)),
        title: const Text('Stats'),
      ),
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
                Text(title, style: theme.textTheme.serifSection),
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
          final f = s.forecast;
          final weeks = [
            for (var w = 0; w * 7 < _days; w++)
              (f.days[w * 7].$1, f.days.skip(w * 7).take(math.min(7, _days - w * 7)).fold(0, (a, d) => a + d.$2)),
          ];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                key: const ValueKey('stats-list'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  section('Reviews coming up', key: const ValueKey('stats-forecast'), [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<int>(
                        key: const ValueKey('stats-forecast-days'),
                        segments: const [
                          ButtonSegment(value: 14, label: Text('14 days')),
                          ButtonSegment(value: 30, label: Text('30 days')),
                        ],
                        selected: {_days},
                        onSelectionChanged: (v) => setState(() => _days = v.first),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${f.dueToday} due today'
                      '${f.overdue > 0 ? ' (${f.overdue} overdue)' : ''} · '
                      '${f.totalIn(_days)} in the next $_days days',
                      key: const ValueKey('stats-forecast-total'),
                    ),
                    const SizedBox(height: 10),
                    ForecastChart(forecast: f, days: _days),
                    const SizedBox(height: 8),
                    Text(
                      'By week: ${[for (final (start, n) in weeks) '${_date(start)}: $n'].join(' · ')}',
                      key: const ValueKey('stats-forecast-weeks'),
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      'Each word or form you have practiced comes back on the day it is due.',
                      style: theme.textTheme.bodySmall,
                    ),
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
                      labels: [for (var i = 0; i < learned.length; i++) i.isEven ? _date(learned[i].$1) : ''],
                      semanticsLabel:
                          'Words learned by week: ${[for (final w in learned) 'week of ${_date(w.$1)}: ${w.$2}'].join(', ')}',
                    ),
                    Text('In total, by week', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  ]),
                  section('Accuracy by exercise · last $kAccuracyDays days', key: const ValueKey('stats-by-type'), [
                    if (s.byType.isEmpty) const Text('No answers in the last 30 days.'),
                    for (final r in s.byType) AccuracyRowView(row: r),
                  ]),
                  section('Accuracy by skill kind · last $kAccuracyDays days', key: const ValueKey('stats-by-kind'), [
                    if (s.byKind.isEmpty) const Text('No answers in the last 30 days.'),
                    for (final r in s.byKind) AccuracyRowView(row: r),
                  ]),
                  section(
                    'Accuracy by tense and form · last $kAccuracyDays days',
                    key: const ValueKey('stats-by-grammar'),
                    [
                      if (s.byGrammar.isEmpty)
                        const Text('No conjugation, inflection or article answers in the last 30 days.'),
                      for (final r in s.byGrammar) AccuracyRowView(row: r),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "Fill the gap · 84% · 52 answers" with a bar (the percentage is written
/// out, so the bar never carries meaning alone).
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
      child: Semantics(
        label: '${row.label}: $pct percent right, ${row.total} answers',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                children: [
                  Text(row.label, style: theme.textTheme.bodyMedium),
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
        ),
      ),
    );
  }
}
