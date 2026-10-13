import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../map/skill_sheet.dart' show itemLabel;
import '../slots/progression_slots.dart';

/// Human-readable label for a facet id: "il pane · produce", "mangiare · presente".
String facetLabel(String facetId, CourseData? course, String lang) {
  FacetId f;
  try {
    f = FacetId.parse(facetId);
  } on FormatException {
    return facetId;
  }
  final item = course?.item(f.itemId);
  final name = item == null ? f.itemId.substring(f.itemId.indexOf(':') + 1) : itemLabel(item);
  final what = switch (f.kind) {
    FacetKind.rec => 'meaning',
    FacetKind.prod => 'produce',
    FacetKind.form => course?.meta.tenseLabel(f.tense!, lang) ?? f.tense!,
    FacetKind.article => 'article',
  };
  return '$name · $what';
}

/// End-of-session screen: answered, accuracy, time, mistakes.
class SessionSummaryView extends ConsumerWidget {
  const SessionSummaryView({
    super.key,
    required this.summary,
    required this.onDone,
    this.endless = false,
    this.onAgain,
  });

  final SessionSummary summary;
  final VoidCallback onDone;
  final VoidCallback? onAgain;
  final bool endless;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final pct = (summary.accuracy * 100).round();
    final dur = summary.endedAt.difference(summary.startedAt);
    final time = dur.inMinutes > 0 ? '${dur.inMinutes}m ${dur.inSeconds % 60}s' : '${dur.inSeconds}s';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          key: const ValueKey('session-summary'),
          padding: const EdgeInsets.all(20),
          children: [
            Icon(
              summary.answered == 0
                  ? Icons.flag_outlined
                  : (pct >= 80 ? Icons.emoji_events : Icons.check_circle_outline),
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              endless ? 'Run finished' : 'Session complete',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Stat(label: 'Answered', value: '${summary.answered}', key: const ValueKey('stat-answered')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Stat(label: 'Accuracy', value: '$pct%', key: const ValueKey('stat-accuracy')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Stat(label: 'Time', value: time),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SummaryProgressSlot(summary: summary),
            if (summary.mistakes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('To review', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final m in summary.mistakes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.replay, color: theme.colorScheme.error),
                  title: Text(facetLabel(m, course, lang)),
                ),
            ] else if (summary.answered > 0) ...[
              const SizedBox(height: 8),
              Text('No mistakes. Well done!', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('summary-done'),
              onPressed: onDone,
              child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Done')),
            ),
            if (onAgain != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onAgain,
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Practice again')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
