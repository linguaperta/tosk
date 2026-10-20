import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../theme/bw_skin.dart';
import 'answer_diff_view.dart';
import 'exercises/common.dart';

/// A secondary action in the [FeedbackBanner]'s actions row ("Why?",
/// "Explain answer with AI", "Report"). Takes the banner's colors; a null
/// [onPressed] shows it disabled (e.g. "Reported" after a flag was saved).
class FeedbackAction {
  const FeedbackAction({required this.key, required this.icon, required this.label, required this.onPressed});
  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
}

/// Instant feedback after Check: right/wrong, the expected answer, a row of
/// secondary actions, and Continue (full width, at the bottom: thumb zone).
/// Slides up from the bottom unless motion is reduced.
///
/// The actions row is the extension point for answer-panel features: the
/// player passes "Why?" (only when the explainer is available and the answer
/// was wrong) followed by [extraActions]. It wraps, so one to three compact
/// actions fit at 320 px.
class FeedbackBanner extends StatelessWidget {
  const FeedbackBanner({
    super.key,
    required this.result,
    required this.onContinue,
    this.onWhy,
    this.extraActions = const [],
    this.reduceMotion = false,
  });

  final Result result;
  final VoidCallback onContinue;

  /// Null hides the "Why?" button (explainer unavailable, or the answer was right).
  final VoidCallback? onWhy;

  /// More secondary actions after "Why?" (the player passes "Explain answer
  /// with AI" when AI is configured, and "Report").
  final List<FeedbackAction> extraActions;
  final bool reduceMotion;

  List<FeedbackAction> get actions => [
    if (onWhy != null)
      FeedbackAction(key: const ValueKey('why-button'), icon: Icons.help_outline, label: 'Why?', onPressed: onWhy!),
    ...extraActions,
  ];

  @override
  Widget build(BuildContext context) {
    final fb = FeedbackColors.of(context);
    final theme = Theme.of(context);
    final ok = result.correct;
    final bg = ok ? fb.correctContainer : fb.wrongContainer;
    final fg = ok ? fb.onCorrectContainer : fb.onWrongContainer;
    final accent = ok ? fb.correct : fb.wrong;

    // Black & white: a white panel set off by a thick top rule.
    final mono = fb.mono;
    final banner = Material(
      key: const ValueKey('feedback-banner'),
      color: bg,
      shape: mono ? const Border(top: BorderSide(color: kBwBlack, width: 3)) : null,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            // At most 60 % of the screen: with a long expected answer and
            // large text the details scroll, and Continue stays visible.
            constraints: BoxConstraints(maxWidth: 680, maxHeight: MediaQuery.sizeOf(context).height * 0.6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      key: const ValueKey('feedback-details'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(ok ? Icons.check_circle : Icons.cancel, color: accent, size: 28),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  ok ? 'Correct!' : 'Not quite',
                                  style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          if (ok && result.accentSlip) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Watch the accent: ${result.expected}',
                              key: const ValueKey('feedback-accent'),
                              style: theme.textTheme.titleMedium?.copyWith(color: fg),
                            ),
                          ],
                          // Partly right: exactly the places to fix, word by word.
                          if (!ok && result.diff != null && result.diff!.partial) ...[
                            const SizedBox(height: 6),
                            AnswerDiffView(diff: result.diff!, foreground: fg),
                          ] else if (!ok && result.expected.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('Correct answer:', style: theme.textTheme.labelLarge?.copyWith(color: fg)),
                            Text(
                              result.expected,
                              key: const ValueKey('feedback-expected'),
                              style: theme.textTheme.titleMedium?.copyWith(color: fg),
                            ),
                          ],
                          if (actions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              key: const ValueKey('feedback-actions'),
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final a in actions)
                                  OutlinedButton.icon(
                                    key: a.key,
                                    onPressed: a.onPressed,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: fg,
                                      side: BorderSide(
                                        color: mono ? fg : fg.withValues(alpha: 0.5),
                                        width: mono ? kBwBorder : 1,
                                      ),
                                      minimumSize: const Size(48, 48),
                                    ),
                                    icon: Icon(a.icon, size: 18),
                                    label: Text(a.label),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('continue-button'),
                    style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: bg),
                    onPressed: onContinue,
                    child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Continue')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (reduceMotion) return banner;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => FractionalTranslation(translation: Offset(0, v), child: child),
      child: banner,
    );
  }
}
