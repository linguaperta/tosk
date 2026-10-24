import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../engine/debug/exercise_printer.dart' show exercisePrompt;
import '../../feedback/exercise_snapshot.dart';
import '../../feedback/flags_export.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../settings/app_settings.dart' show exerciseTypeLabel;
import '../common/error_text.dart';

/// How the export is saved (file_picker's save flow; tests override it).
final flagsSaverProvider = Provider<SaveBytes>((ref) => saveWithFilePicker);

/// Settings → Feedback & flags (route `/flags`): every flagged exercise on
/// this device, and "Export flags" as JSON Lines for the developer.
class FlagsScreen extends ConsumerWidget {
  const FlagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(flagsProvider);
    final n = flags.value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.settings)),
        title: const Text('Feedback & flags'),
      ),
      body: AsyncView(
        value: flags,
        onRetry: () => ref.invalidate(flagsProvider),
        builder: (list) => list.isEmpty ? const _Empty() : _FlagList(flags: list),
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
                        key: const ValueKey('flags-export'),
                        onPressed: () => unawaited(_export(context, ref, flags.value!)),
                        icon: const Icon(Icons.ios_share),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(n == 1 ? 'Export 1 flag' : 'Export $n flags'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref, List<FlagRecord> flags) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final uri = await exportFlags(flags, now: ref.read(clockProvider)(), save: ref.read(flagsSaverProvider));
      if (uri == null) return; // cancelled
      messenger?.showSnackBar(
        SnackBar(content: Text('Exported ${flags.length} flag${flags.length == 1 ? '' : 's'}')),
      );
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(tryAgainMessage("The flags couldn't be exported.", e))));
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const ValueKey('flags-empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.outlined_flag, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('No flags yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'After checking an answer, tap "Report" to flag an exercise that looks wrong. '
              'Flags stay on this device until you export them here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FlagList extends StatelessWidget {
  const _FlagList({required this.flags});
  final List<FlagRecord> flags;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.separated(
          key: const ValueKey('flags-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: flags.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => i == 0
              ? Text(
                  'Export writes a JSON Lines file (one flag per line, with the full exercise) that you can '
                  'send to the developer.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : FlagCard(flag: flags[i - 1]),
        ),
      ),
    );
  }
}

/// One flag: what was asked, the answers, the reasons, the AI's verdict.
class FlagCard extends ConsumerWidget {
  const FlagCard({super.key, required this.flag});
  final FlagRecord flag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final f = flag;
    final type = ExerciseType.tryParse(f.exerciseType);
    String prompt;
    try {
      prompt = exercisePrompt(exerciseFromJson(f.exercise));
    } catch (_) {
      prompt = f.facetId;
    }
    final local = f.createdAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
    final meta = [f.courseId, if (type != null) exerciseTypeLabel(type), date].join(' · ');
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      key: ValueKey('flag-${f.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(meta, style: muted),
                  const SizedBox(height: 4),
                  Text(prompt, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    'You answered: ${f.given.isEmpty ? '—' : f.given} (${f.correct ? 'accepted' : 'marked wrong'})',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text('Expected: ${f.expected}', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    f.reasons.map((r) => r.label).join(' · '),
                    style: theme.textTheme.labelLarge,
                  ),
                  if (f.comment.isNotEmpty) Text('“${f.comment}”', style: theme.textTheme.bodyMedium),
                  if (f.aiVerdict != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome_outlined, size: 16),
                          const SizedBox(width: 6),
                          Expanded(child: Text(f.aiVerdict!.label, style: theme.textTheme.labelLarge)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('flag-delete-${f.id}'),
              tooltip: 'Delete flag',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => unawaited(_delete(context, ref)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this flag?'),
        content: const Text('It is removed from this device and won\'t be exported.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          FilledButton(
            key: const ValueKey('flag-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(feedbackStoreProvider).deleteFlag(flag.id);
    ref.read(flagsRevisionProvider.notifier).bump();
  }
}
