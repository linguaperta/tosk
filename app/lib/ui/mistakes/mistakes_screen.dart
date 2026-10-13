import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../engine/engine.dart' show OpenMistake;
import '../../providers.dart';
import '../common/async_view.dart';
import '../common/markdown.dart';
import '../lesson/exercises/common.dart' show FeedbackColors;
import '../lesson/session_summary_view.dart' show facetLabel;
import '../lesson/why_sheet.dart';
import '../routes.dart';
import '../settings/app_settings.dart' show exerciseTypeLabel;

/// Open mistakes of the active course (route `/mistakes`): what was asked,
/// the given and the expected answer, an excerpt of the skill's grammar note,
/// and a "Why?" slot (hidden while the explainer is unavailable). The
/// "Review mistakes" button at the bottom starts a mistake-review session.
class MistakesScreen extends ConsumerWidget {
  const MistakesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mistakes = ref.watch(openMistakesProvider);
    final n = mistakes.value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        // Also reachable as a deep link (no back stack): back then goes to the map.
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.map)),
        title: const Text('Mistakes'),
      ),
      body: AsyncView(
        value: mistakes,
        onRetry: () => ref.invalidate(openMistakesProvider),
        builder: (list) => list.isEmpty ? const _Empty() : _MistakeList(mistakes: list),
      ),
      bottomNavigationBar: n == 0
          ? null
          : SafeArea(
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('mistakes-review'),
                        onPressed: () => context.push(Routes.review),
                        icon: const Icon(Icons.replay),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(n > 12 ? 'Review 12 of $n mistakes' : 'Review ${_count(n)}'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

String _count(int n) => n == 1 ? '1 mistake' : '$n mistakes';

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const ValueKey('mistakes-empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Nothing to review', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Wrong answers show up here until you get them right in a later session.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MistakeList extends ConsumerWidget {
  const _MistakeList({required this.mistakes});
  final List<OpenMistake> mistakes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final now = ref.watch(clockProvider)();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.separated(
          key: const ValueKey('mistakes-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: mistakes.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Text(
                '${_count(mistakes.length)} to review. Each one leaves this list once you answer it '
                'correctly in a later session.',
                style: Theme.of(context).textTheme.bodyMedium,
              );
            }
            return MistakeCard(mistake: mistakes[i - 1], course: course, lang: lang, now: now);
          },
        ),
      ),
    );
  }
}

/// One open mistake.
class MistakeCard extends ConsumerWidget {
  const MistakeCard({super.key, required this.mistake, required this.course, required this.lang, required this.now});
  final OpenMistake mistake;
  final CourseData? course;
  final String lang;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fb = FeedbackColors.of(context);
    final m = mistake.record;
    final skillId = mistake.facet.skillId;
    final skill = course?.skill(skillId);
    final note = noteExcerpt(course?.note(skillId, lang) ?? m.note);
    final type = mistake.missedType;
    final explainer = ref.watch(explainerAvailableProvider);
    final meta = [
      if (skill != null) pickLang(skill.title, lang),
      if (type != null) exerciseTypeLabel(type),
      _ago(m.at, now),
      if (mistake.count > 1) '${mistake.count}×',
    ].join(' · ');

    Widget answerLine(String label, String value, Color color, {bool strike = false}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value.isEmpty ? '—' : value,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                decoration: strike ? TextDecoration.lineThrough : null,
                decorationColor: color,
              ),
            ),
          ],
        ),
      ),
    );

    return Card(
      key: ValueKey('mistake-${m.facetId}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(facetLabel(m.facetId, course, lang), style: theme.textTheme.titleMedium),
            Text(meta, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(m.prompt, maxLines: 4, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            answerLine('You answered', m.given, fb.wrong, strike: true),
            answerLine('Correct', m.expected, fb.correct),
            if (note != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.menu_book_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(child: Text(note, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ],
            if (skill != null || explainer || m.explanation != null)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  if (m.explanation != null)
                    TextButton.icon(
                      key: ValueKey('mistake-explanation-${m.facetId}'),
                      onPressed: () => showWhySheet(context, Stream.value(m.explanation!)),
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('Explanation'),
                    )
                  else if (explainer)
                    TextButton.icon(
                      key: ValueKey('mistake-why-${m.facetId}'),
                      onPressed: () => showWhySheet(context, ref.read(explainerProvider).explain(_context(m))),
                      icon: const Icon(Icons.help_outline),
                      label: const Text('Why?'),
                    ),
                  if (skill != null && note != null)
                    TextButton.icon(
                      key: ValueKey('mistake-note-${m.facetId}'),
                      onPressed: () => context.push(Routes.skill(skillId)),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Grammar note'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  MistakeContext _context(MistakeRecord m) => MistakeContext(
    courseId: course?.meta.id ?? '',
    facetId: m.facetId,
    exerciseType: mistake.missedType ?? ExerciseType.flashcard,
    prompt: m.prompt,
    expected: m.expected,
    given: m.given,
    sourceLang: lang,
    targetLang: course?.meta.target ?? '',
    skillId: mistake.facet.skillId,
    note: course?.note(mistake.facet.skillId, lang) ?? m.note,
    at: m.at,
  );
}

String _ago(DateTime at, DateTime now) {
  final d = now.toUtc().difference(at.toUtc());
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}
