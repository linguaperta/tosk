import 'package:flutter/material.dart';

import '../../progression/progression.dart';
import '../theme/bw_skin.dart';
import 'progression_colors.dart';

/// GitHub-style practice heatmap: one column per week (Monday on top), months
/// labelled above, scrollable horizontally and opened at the most recent week.
class StreakHeatmap extends StatelessWidget {
  const StreakHeatmap({
    super.key,
    required this.data,
    this.reduceMotion = false,
    this.cellSize = 12,
    this.gap = 3,
    this.onDayTap,
    this.showLegend = true,
  });

  final HeatmapData data;
  final bool reduceMotion;
  final double cellSize;
  final double gap;
  final ValueChanged<LocalDate>? onDayTap;
  final bool showLegend;

  static const _weekdayLabels = ['Mon', '', 'Wed', '', 'Fri', '', ''];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 10);
    final start = data.from.startOfWeek;
    final weeks = (start.daysUntil(data.to) ~/ 7) + 1;
    final step = cellSize + gap;

    Widget cell(LocalDate d) {
      final inRange = !d.isBefore(data.from) && !d.isAfter(data.to);
      if (!inRange) return SizedBox(width: cellSize, height: cellSize);
      final count = data.countOn(d);
      final frozen = data.isFrozen(d) && count == 0;
      final color = frozen
          ? ProgressionColors.tint(ProgressionColors.freeze(cs), 0.55, cs)
          : ProgressionColors.heat(data.bucketOf(d), data.maxBucket, cs);
      final mono = isMonochrome(cs);
      final decoration = BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(cellSize / 5),
        border: d == data.today
            ? Border.all(color: cs.onSurface, width: mono ? 2 : 1.2)
            : (mono ? Border.all(color: kBwGray, width: 0.8) : null),
      );
      final label = '$d: $count review${count == 1 ? '' : 's'}${frozen ? ' (streak freeze)' : ''}';
      final dot = mono && !frozen ? HeatDot(bucket: data.bucketOf(d), maxBucket: data.maxBucket, size: cellSize) : null;
      final box = reduceMotion || mono
          ? Container(width: cellSize, height: cellSize, decoration: decoration, child: dot)
          : AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: cellSize,
              height: cellSize,
              decoration: decoration,
            );
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 400),
        child: Semantics(
          label: label,
          button: onDayTap != null,
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('heat-$d'),
            onTap: onDayTap == null ? null : () => onDayTap!(d),
            child: frozen
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      box,
                      Icon(Icons.ac_unit, size: cellSize * 0.75, color: mono ? kBwBlack : cs.surface),
                    ],
                  )
                : box,
          ),
        ),
      );
    }

    // Month label above the column holding the 1st of the month; the first
    // column gets its month's label unless another label follows within 2 columns.
    final labels = List<String?>.filled(weeks, null);
    for (var w = 0; w < weeks; w++) {
      final monday = start.addDays(7 * w);
      for (var i = 0; i < 7; i++) {
        final d = monday.addDays(i);
        if (d.day == 1 && !d.isBefore(data.from) && !d.isAfter(data.to)) labels[w] = kMonthShort[d.month - 1];
      }
    }
    if (weeks > 0 && labels[0] == null && !labels.skip(1).take(2).any((l) => l != null)) {
      final first = data.from.isAfter(start) ? data.from : start;
      labels[0] = kMonthShort[first.month - 1];
    }

    final columns = <Widget>[];
    final monthLabels = <Widget>[];
    for (var w = 0; w < weeks; w++) {
      final monday = start.addDays(7 * w);
      final month = labels[w];
      monthLabels.add(
        SizedBox(
          width: step,
          height: 14,
          child: month == null
              ? null
              : OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: step * 4,
                  child: Text(month, style: labelStyle, softWrap: false),
                ),
        ),
      );
      columns.add(
        Padding(
          padding: EdgeInsets.only(right: gap),
          child: Column(
            children: [
              for (var i = 0; i < 7; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == 6 ? 0 : gap),
                  child: cell(monday.addDays(i)),
                ),
            ],
          ),
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: monthLabels),
        Row(children: columns),
      ],
    );
    // Fits: left-aligned next to the weekday labels. Too wide: scroll, opened at the latest week.
    final grid = LayoutBuilder(
      builder: (context, constraints) => weeks * step <= constraints.maxWidth
          ? Align(alignment: Alignment.centerLeft, child: content)
          : SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: content),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14, right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 7; i++)
                    SizedBox(
                      height: i == 6 ? cellSize : step,
                      child: Text(_weekdayLabels[i], style: labelStyle),
                    ),
                ],
              ),
            ),
            Expanded(child: grid),
          ],
        ),
        if (showLegend) ...[
          const SizedBox(height: 6),
          // Wraps on narrow screens / large text instead of overflowing.
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Less', style: labelStyle),
                  const SizedBox(width: 4),
                  for (var b = 0; b <= data.maxBucket; b++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        width: cellSize,
                        height: cellSize,
                        decoration: BoxDecoration(
                          color: ProgressionColors.heat(b, data.maxBucket, cs),
                          borderRadius: BorderRadius.circular(cellSize / 5),
                          border: isMonochrome(cs) ? Border.all(color: kBwGray, width: 0.8) : null,
                        ),
                        child: isMonochrome(cs) ? HeatDot(bucket: b, maxBucket: data.maxBucket, size: cellSize) : null,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Text('More', style: labelStyle),
                ],
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.ac_unit, size: cellSize, color: ProgressionColors.freeze(cs)),
                  const SizedBox(width: 2),
                  Text('Freeze', style: labelStyle),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Black & white heatmap level: a black square growing with [bucket]
/// (nothing at 0, the whole cell at the top bucket).
class HeatDot extends StatelessWidget {
  const HeatDot({super.key, required this.bucket, required this.maxBucket, required this.size});
  final int bucket;
  final int maxBucket;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (bucket <= 0 || maxBucket <= 0) return const SizedBox.shrink();
    final f = bucket >= maxBucket ? 1.0 : 0.3 + 0.55 * (bucket / maxBucket);
    return Center(
      child: Container(
        width: size * f,
        height: size * f,
        decoration: BoxDecoration(color: kBwBlack, borderRadius: BorderRadius.circular(size * f / 5)),
      ),
    );
  }
}

/// Flame with the current streak, plus held streak freezes.
class StreakCounter extends StatelessWidget {
  const StreakCounter({super.key, required this.streak, this.reduceMotion = false, this.showLongest = false});

  final StreakInfo streak;
  final bool reduceMotion;
  final bool showLongest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lit = streak.practicedToday;
    final mono = isMonochrome(cs);
    final flame = Icon(
      // Black & white: a filled flame when practiced today, an outline when not.
      lit || !mono ? Icons.local_fire_department : Icons.local_fire_department_outlined,
      key: ValueKey(lit),
      size: 28,
      color: lit ? ProgressionColors.flame(cs) : (mono ? kBwBlack : cs.outline),
    );
    return Semantics(
      label:
          '${streak.current} day streak, ${streak.freezes} streak freeze${streak.freezes == 1 ? '' : 's'}'
          '${lit ? '' : ', not practiced today'}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          reduceMotion
              ? flame
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: flame,
                ),
          const SizedBox(width: 4),
          Text('${streak.current}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          if (showLongest) ...[
            const SizedBox(width: 6),
            Text('best ${streak.longest}', style: theme.textTheme.labelSmall),
          ],
          const SizedBox(width: 10),
          for (var i = 0; i < streak.freezes; i++)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Icons.ac_unit, size: 18, color: ProgressionColors.freeze(cs)),
            ),
        ],
      ),
    );
  }
}
