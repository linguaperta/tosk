import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../ai/ai_errors.dart';
import '../../ai/prompts.dart' show ParsedVerdict;
import '../../app_version.dart';
import '../../core/core.dart';
import '../../feedback/exercise_snapshot.dart';
import '../../feedback/reports.dart';
import '../../providers.dart';
import '../../sync/sync_providers.dart';
import '../common/markdown.dart';
import '../common/error_text.dart';

/// Everything a flag records about the checked exercise.
class FlagDraft {
  const FlagDraft({
    required this.exercise,
    required this.result,
    required this.context,
    this.packVersion,
  });

  final Exercise exercise;
  final Result result;

  /// The answer's context (course, languages, note), also sent to the AI.
  final ExplainContext context;
  final String? packVersion;
}

/// Opens the flag sheet; resolves to true when a flag was saved.
Future<bool?> showFlagSheet(BuildContext context, FlagDraft draft) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => FlagSheet(draft: draft),
);

/// "Report a problem" (like Duolingo's flag): reason chips, a comment, Submit
/// (saved on the device, exported from Settings → Feedback & flags, and sent
/// to the developer when signed in: `queueReport`) and,
/// when AI is configured, "Confer with AI" for a second opinion that is shown
/// and stored with the flag.
class FlagSheet extends ConsumerStatefulWidget {
  const FlagSheet({super.key, required this.draft});
  final FlagDraft draft;

  @override
  ConsumerState<FlagSheet> createState() => _FlagSheetState();
}

class _FlagSheetState extends ConsumerState<FlagSheet> {
  final Set<FlagReason> _reasons = {};
  final _comment = TextEditingController();
  ParsedVerdict? _verdict;
  Object? _conferError;
  bool _conferring = false;
  bool _saving = false;

  bool get _hasInput => _reasons.isNotEmpty || _comment.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _comment.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  List<FlagReason> get _orderedReasons => [
    for (final r in FlagReason.values)
      if (_reasons.contains(r)) r,
  ];

  Future<void> _confer() async {
    final reviewer = ref.read(flagReviewerProvider);
    if (reviewer == null || _conferring) return;
    setState(() {
      _conferring = true;
      _conferError = null;
    });
    try {
      final v = await reviewer.review(
        context: widget.draft.context.copyWith(explainLang: ref.read(explainLangProvider)),
        reasons: _orderedReasons,
        comment: _comment.text,
        snapshot: exerciseToJson(widget.draft.exercise),
      );
      if (mounted) setState(() => _verdict = v);
    } catch (e) {
      if (mounted) setState(() => _conferError = e);
    } finally {
      if (mounted) setState(() => _conferring = false);
    }
  }

  Future<void> _submit() async {
    if (_saving || !_hasInput) return;
    setState(() => _saving = true);
    final d = widget.draft;
    final ctx = d.context;
    final flag = FlagRecord(
      id: const Uuid().v4(),
      createdAt: ref.read(clockProvider)().toUtc(),
      courseId: ctx.courseId,
      skillId: ctx.skillId ?? d.exercise.skillId,
      facetId: d.exercise.facetId,
      exerciseType: d.exercise.type.id,
      exercise: exerciseToJson(d.exercise),
      given: d.result.given,
      expected: d.result.expected,
      correct: d.result.correct,
      reasons: _orderedReasons,
      comment: _comment.text.trim(),
      aiVerdict: _verdict?.verdict,
      aiReasoning: _verdict?.reasoning,
      appVersion: kAppVersion,
      packVersion: d.packVersion,
      sourceLang: ctx.sourceLang,
    );
    try {
      await ref.read(feedbackStoreProvider).saveFlag(flag);
      ref.read(flagsRevisionProvider.notifier).bump();
      // Signed in: also to the developer (queued; offline it waits).
      await queueReport(ref, flagReport(flag));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tryAgainMessage("The flag couldn't be saved.", e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canConfer = ref.watch(flagReviewerProvider) != null;
    final sends = ref.watch(canSendReportsProvider);
    final canSignIn = ref.watch(canSignInProvider);
    final verdict = _verdict;
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: SingleChildScrollView(
            key: const ValueKey('flag-sheet'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.flag_outlined, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Report a problem', style: theme.textTheme.titleLarge)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text("What's wrong with this exercise?", style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final r in FlagReason.values)
                          FilterChip(
                            key: ValueKey('flag-reason-${r.id}'),
                            label: Text(r.label),
                            selected: _reasons.contains(r),
                            onSelected: (on) => setState(() => on ? _reasons.add(r) : _reasons.remove(r)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('flag-comment'),
                      controller: _comment,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Comment (optional)',
                        hintText: 'e.g. "mangiate" should also be accepted',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_conferring) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(key: ValueKey('flag-conferring')),
                      const SizedBox(height: 4),
                      Text('Asking the AI…', style: theme.textTheme.bodySmall),
                    ],
                    if (_conferError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _conferError is AiException
                            ? (_conferError! as AiException).userMessage
                            : 'The AI request failed.',
                        key: const ValueKey('flag-confer-error'),
                      ),
                    ],
                    if (verdict != null) ...[const SizedBox(height: 8), _VerdictCard(verdict: verdict)],
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (verdict != null)
                          TextButton(
                            key: const ValueKey('flag-discard'),
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Discard'),
                          ),
                        if (canConfer && verdict == null)
                          OutlinedButton.icon(
                            key: const ValueKey('flag-confer'),
                            onPressed: _hasInput && !_conferring ? _confer : null,
                            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                            label: const Text('Confer with AI'),
                          ),
                        FilledButton.icon(
                          key: const ValueKey('flag-submit'),
                          onPressed: _hasInput && !_saving && !_conferring ? _submit : null,
                          icon: const Icon(Icons.send_outlined, size: 18),
                          label: const Text('Submit'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sends
                          ? 'Submitted flags are sent to the developer and kept on this device.'
                          : canSignIn
                          ? 'Sign in to send flags to the developer automatically (Settings → Account & sync). '
                                'Until then they stay on this device; export them from Settings → Feedback & flags.'
                          : 'Flags stay on this device. Export them from Settings → Feedback & flags.',
                      key: const ValueKey('flag-destination'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The AI's verdict: an icon and a label (never color alone) plus its reasoning.
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.verdict});
  final ParsedVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = verdict.verdict;
    final (icon, label) = switch (v) {
      FlagVerdict.exerciseWrong => (Icons.report_outlined, 'AI: the exercise is wrong'),
      FlagVerdict.ambiguous => (Icons.help_outline, 'AI: the exercise is ambiguous'),
      FlagVerdict.exerciseCorrect => (Icons.check_circle_outline, 'AI: the exercise is correct'),
      null => (Icons.info_outline, 'AI: no clear verdict'),
    };
    return Container(
      key: ValueKey('flag-verdict-${v?.id ?? 'none'}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (verdict.reasoning.isNotEmpty) ...[const SizedBox(height: 6), MarkdownView(verdict.reasoning)],
          const SizedBox(height: 6),
          Text(
            'You can still submit the flag (the verdict is saved with it) or discard it.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
