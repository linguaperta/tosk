import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../theme/bw_skin.dart';
import 'exercises/common.dart';

/// A partly right sentence answer, marked word by word (docs/ui.md,
/// "Partly right answers"): the learner's answer, the correct answer and a
/// legend of the marks used. Shown in the feedback panel when
/// [AnswerDiff.partial].
///
/// Never by colour alone: wrong and extra words are struck through, the
/// right words are bold and underlined, a right word in the wrong place is
/// boxed in both lines, and a box with `…` stands where words are missing.
/// Colour only adds to that (and is gone in black & white).
class AnswerDiffView extends StatelessWidget {
  const AnswerDiffView({super.key, required this.diff, required this.foreground});
  final AnswerDiff diff;

  /// The panel's text color.
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge?.copyWith(color: foreground);
    final n = diff.errors;
    return Column(
      key: const ValueKey('feedback-diff'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          n == 1 ? 'Almost: 1 word to fix' : 'Almost: $n words to fix',
          key: const ValueKey('feedback-diff-count'),
          style: theme.textTheme.titleSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text('Your answer:', style: label),
        AnswerDiffLine(key: const ValueKey('feedback-given'), tokens: diff.given, learner: true, foreground: foreground),
        const SizedBox(height: 4),
        Text('Correct answer:', style: label),
        AnswerDiffLine(
          key: const ValueKey('feedback-expected'),
          tokens: diff.expected,
          learner: false,
          foreground: foreground,
        ),
        const SizedBox(height: 4),
        _Legend(diff: diff, foreground: foreground),
      ],
    );
  }
}

/// One line of a diff: the learner's answer ([learner]) or the correct one.
class AnswerDiffLine extends StatelessWidget {
  const AnswerDiffLine({super.key, required this.tokens, required this.learner, required this.foreground});
  final List<DiffToken> tokens;
  final bool learner;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fb = FeedbackColors.of(context);
    final mono = fb.mono;
    final scheme = theme.colorScheme;
    final base = theme.textTheme.titleMedium?.copyWith(color: foreground) ?? TextStyle(color: foreground);
    final strike = base.copyWith(
      decoration: TextDecoration.lineThrough,
      decorationThickness: 2.5,
      decorationColor: mono ? kBwBlack : fb.wrong,
      color: mono ? kBwBlack : fb.wrong,
    );
    final fix = base.copyWith(
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationThickness: 2.5,
      decorationColor: mono ? kBwBlack : fb.onCorrectContainer,
      color: mono ? kBwBlack : fb.onCorrectContainer,
      backgroundColor: mono ? null : fb.correctContainer,
    );
    final boxColor = mono ? kBwBlack : scheme.tertiary;

    InlineSpan box(String text, {String? semantics}) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Semantics(
        label: semantics,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(color: boxColor, width: kBwBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(text, style: base),
        ),
      ),
    );

    final spans = <InlineSpan>[];
    for (final t in tokens) {
      if (t.pre.isNotEmpty) spans.add(TextSpan(text: t.pre));
      if (!t.isWord) {
        spans.add(TextSpan(text: t.text));
        continue;
      }
      switch (t.mark) {
        case DiffMark.same:
          spans.add(TextSpan(text: t.text));
        case DiffMark.moved:
          spans.add(box(t.text, semantics: '${t.text}, wrong place'));
        case DiffMark.missing when learner:
          spans.add(box('…', semantics: 'missing word'));
        case DiffMark.wrong || DiffMark.extra when learner:
          spans.add(TextSpan(text: t.text, style: strike, semanticsLabel: '${t.text}, wrong'));
        case DiffMark.wrong || DiffMark.missing || DiffMark.extra:
          spans.add(TextSpan(text: t.text, style: fix, semanticsLabel: '${t.text}, the right word'));
      }
    }
    return Text.rich(TextSpan(children: spans), style: base);
  }
}

/// The marks used in this diff, in words.
class _Legend extends StatelessWidget {
  const _Legend({required this.diff, required this.foreground});
  final AnswerDiff diff;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    bool has(List<DiffToken> line, Set<DiffMark> marks) => line.any((t) => t.isWord && marks.contains(t.mark));
    final parts = [
      if (has(diff.given, {DiffMark.wrong, DiffMark.extra})) 'struck through: wrong',
      if (has(diff.expected, {DiffMark.wrong, DiffMark.missing})) 'underlined: the right word',
      if (has(diff.given, {DiffMark.moved})) 'boxed: right word, wrong place',
      if (has(diff.given, {DiffMark.missing})) '… box: missing word',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    final text = parts.join(' · ');
    return Text(
      '${text[0].toUpperCase()}${text.substring(1)}',
      key: const ValueKey('feedback-diff-legend'),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: foreground),
    );
  }
}
