import 'package:flutter/material.dart';

import '../../core/core.dart';
import 'exercises/common.dart';

/// Instant feedback after Check: right/wrong, the expected answer, "Why?" and Continue.
/// Slides up from the bottom unless motion is reduced.
class FeedbackBanner extends StatelessWidget {
  const FeedbackBanner({
    super.key,
    required this.result,
    required this.onContinue,
    this.onWhy,
    this.reduceMotion = false,
  });

  final Result result;
  final VoidCallback onContinue;

  /// Null hides the "Why?" button (explainer unavailable, or the answer was right).
  final VoidCallback? onWhy;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final fb = FeedbackColors.of(context);
    final theme = Theme.of(context);
    final ok = result.correct;
    final bg = ok ? fb.correctContainer : fb.wrongContainer;
    final fg = ok ? fb.onCorrectContainer : fb.onWrongContainer;
    final accent = ok ? fb.correct : fb.wrong;

    final banner = Material(
      key: const ValueKey('feedback-banner'),
      color: bg,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                      if (onWhy != null)
                        TextButton.icon(
                          key: const ValueKey('why-button'),
                          onPressed: onWhy,
                          style: TextButton.styleFrom(foregroundColor: fg),
                          icon: const Icon(Icons.help_outline),
                          label: const Text('Why?'),
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
                  if (!ok && result.expected.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Correct answer:', style: theme.textTheme.labelLarge?.copyWith(color: fg)),
                    Text(
                      result.expected,
                      key: const ValueKey('feedback-expected'),
                      style: theme.textTheme.titleMedium?.copyWith(color: fg),
                    ),
                  ],
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
