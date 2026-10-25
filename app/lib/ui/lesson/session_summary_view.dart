import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tosk_palette.dart';
import '../brand/tosk.dart';
import '../../core/core.dart';
import '../../providers.dart';
import '../map/skill_sheet.dart' show itemLabel;
import '../my_words/my_words_providers.dart' show userWordsProvider;
import '../slots/progression_slots.dart';

/// Human-readable label for a facet id: "il pane · produce", "mangiare · presente".
/// [names] labels items the course doesn't have (the learner's own words).
String facetLabel(String facetId, CourseData? course, String lang, {Map<String, String> names = const {}}) {
  FacetId f;
  try {
    f = FacetId.parse(facetId);
  } on FormatException {
    return facetId;
  }
  final item = course?.item(f.itemId);
  final name = item == null ? (names[f.itemId] ?? f.itemId.substring(f.itemId.indexOf(':') + 1)) : itemLabel(item);
  final what = switch (f.kind) {
    FacetKind.rec => 'meaning',
    FacetKind.prod => 'produce',
    FacetKind.form => course?.meta.tenseLabel(f.tense!, lang) ?? f.tense!,
    FacetKind.article => 'article',
    FacetKind.infl => course?.meta.inflectionTables[f.table!]?.titleIn(lang) ?? f.table!,
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
    this.header,
  });

  /// Shown under the title (the verdict of a test out or placement).
  final Widget? header;

  final SessionSummary summary;
  final VoidCallback onDone;
  final VoidCallback? onAgain;
  final bool endless;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final course = ref.watch(courseDataProvider).value;
    final ownWords = {
      if (course != null)
        for (final w in ref.watch(userWordsProvider).value?.all ?? const <UserWord>[]) w.itemId(course.meta.id): w.word,
    };
    final lang = ref.watch(sourceLangProvider);
    final pct = (summary.accuracy * 100).round();
    final dur = summary.endedAt.difference(summary.startedAt);
    final time = dur.inMinutes > 0 ? '${dur.inMinutes}m ${dur.inSeconds % 60}s' : '${dur.inSeconds}s';

    // Scrolling content (built eagerly: it is short) with Done pinned below.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          key: const ValueKey('session-summary'),
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tosk celebrates a finished session (and keeps reading
                    // when nothing was answered).
                    ToskImage(pose: summary.answered == 0 ? ToskPose.thinking : ToskPose.celebrating, height: 112),
                    const SizedBox(height: 8),
                    Text(
                      endless ? 'Run finished' : 'Session complete',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.serifHeadline,
                    ),
                    const SizedBox(height: 20),
                    ?header,
                    Row(
                      children: [
                        Expanded(
                          child: _Stat(
                            label: 'Answered',
                            value: '${summary.answered}',
                            key: const ValueKey('stat-answered'),
                          ),
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
                    if (summary.mistakes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('To review', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      for (final m in summary.mistakes)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.replay, color: theme.colorScheme.error),
                          title: Text(facetLabel(m, course, lang, names: ownWords)),
                        ),
                    ] else if (summary.answered > 0) ...[
                      const SizedBox(height: 16),
                      Text('No mistakes. Well done!', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                    ],
                    const SizedBox(height: 16),
                    SummaryProgressSlot(summary: summary),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      key: const ValueKey('summary-done'),
                      onPressed: onDone,
                      child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Done')),
                    ),
                    if (onAgain != null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: onAgain,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Practice again'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
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
