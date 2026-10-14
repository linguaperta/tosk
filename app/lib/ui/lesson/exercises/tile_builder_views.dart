import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../../common/word_popover.dart';
import '../../ink/ink_pad.dart';
import '../../theme/bw_skin.dart';
import '../typing.dart';
import 'common.dart';

/// Answer line plus word bank: tap a tile to append it, tap a placed tile to remove it.
class TileAnswerArea extends StatefulWidget {
  const TileAnswerArea({
    super.key,
    required this.tiles,
    required this.onChanged,
    this.locked = false,
    this.correct,
    this.keys,
  });

  final List<String> tiles;
  final ValueChanged<List<String>?> onChanged;
  final bool locked;

  /// Null before checking; colors the answer line after.
  final bool? correct;
  final ExerciseKeys? keys;

  @override
  State<TileAnswerArea> createState() => _TileAnswerAreaState();
}

class _TileAnswerAreaState extends State<TileAnswerArea> {
  final List<int> _placed = [];

  @override
  void initState() {
    super.initState();
    widget.keys?.addListener(_onKey);
  }

  @override
  void didUpdateWidget(TileAnswerArea old) {
    super.didUpdateWidget(old);
    if (old.keys != widget.keys) {
      old.keys?.removeListener(_onKey);
      widget.keys?.addListener(_onKey);
    }
  }

  @override
  void dispose() {
    widget.keys?.removeListener(_onKey);
    super.dispose();
  }

  void _onKey() {
    final d = widget.keys?.last?.digit;
    if (d != null && d >= 1 && d <= widget.tiles.length) _place(d - 1);
  }

  void _place(int t) {
    if (widget.locked || _placed.contains(t)) return;
    setState(() => _placed.add(t));
    _report();
  }

  void _remove(int t) {
    if (widget.locked) return;
    setState(() => _placed.remove(t));
    _report();
  }

  void _report() => widget.onChanged(_placed.isEmpty ? null : [for (final t in _placed) widget.tiles[t]]);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fb = FeedbackColors.of(context);
    final lineColor = widget.correct == null ? scheme.outlineVariant : (widget.correct! ? fb.correct : fb.wrong);
    final placedState = widget.correct == null
        ? OptionState.idle
        : (widget.correct! ? OptionState.correct : OptionState.wrong);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('answer-line'),
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: lineColor, width: 2)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _placed)
                WordTile(
                  key: ValueKey('placed-$t'),
                  label: widget.tiles[t],
                  state: placedState,
                  onTap: widget.locked ? null : () => _remove(t),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 10,
          children: [
            for (var t = 0; t < widget.tiles.length; t++)
              WordTile(
                key: ValueKey('tile-$t'),
                label: widget.tiles[t],
                hidden: _placed.contains(t),
                onTap: widget.locked ? null : () => _place(t),
              ),
          ],
        ),
      ],
    );
  }
}

/// Build the translation from word tiles.
class SentenceBuilderView extends ExerciseWidget<SentenceBuilderExercise> {
  const SentenceBuilderView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.result,
    super.keys,
    super.reduceMotion,
    super.onCheck,
    this.typed = false,
    this.ink = false,
  });

  /// Typing mode: type the sentence instead of building it from tiles.
  final bool typed;

  /// Handwriting: write the sentence on the pad (in parts: "Next word").
  final bool ink;

  @override
  State<SentenceBuilderView> createState() => _SentenceBuilderViewState();
}

class _SentenceBuilderViewState extends State<SentenceBuilderView> {
  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    return ExerciseLayout(
      prompt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InstructionText(e.instruction),
          _SpeechBubble(text: e.prompt),
          // After checking: the answer sentence, with tappable words.
          if (widget.locked && e.answerTokens != null) ...[
            const SizedBox(height: 10),
            Row(
              key: const ValueKey('answer-sentence'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 8),
                  child: Icon(Icons.translate, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                Expanded(
                  child: TappableSentence(tokens: e.answerTokens!, style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
          ],
        ],
      ),
      controls: widget.ink
          ? InkSentenceArea(
              locked: widget.locked,
              correct: widget.result?.correct,
              onChanged: widget.onChanged,
            )
          : widget.typed
          ? TypedSentenceArea(
              locked: widget.locked,
              correct: widget.result?.correct,
              hintText: 'Type the translation',
              onChanged: widget.onChanged,
              onSubmitted: widget.onCheck,
            )
          : TileAnswerArea(
              tiles: e.tiles,
              locked: widget.locked,
              correct: widget.result?.correct,
              keys: widget.keys,
              onChanged: (words) => widget.onChanged(words == null ? null : TilesAnswer(words)),
            ),
    );
  }
}

/// Typing mode for the sentence builder and transform: the whole sentence as
/// text (with the accent bar), no tiles.
class TypedSentenceArea extends StatelessWidget {
  const TypedSentenceArea({
    super.key,
    required this.locked,
    required this.onChanged,
    this.correct,
    this.hintText,
    this.onSubmitted,
  });

  final bool locked;
  final bool? correct;
  final String? hintText;
  final ValueChanged<Answer?> onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final fb = FeedbackColors.of(context);
    final mark = correct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TypedAnswerField(
          enabled: !locked,
          autofocus: true,
          multiline: true,
          hintText: hintText,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            // Black & white: a wrong answer is struck through after checking.
            decoration: mark == false && fb.mono ? TextDecoration.lineThrough : null,
          ),
          onChanged: (text) => onChanged(text.trim().isEmpty ? null : TextAnswer(text, inputMode: InputMode.keyboard)),
          onSubmitted: onSubmitted,
        ),
        if (mark != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              key: const ValueKey('typed-verdict'),
              children: [
                Icon(mark ? Icons.check : Icons.close, size: 18, color: mark ? fb.correct : fb.wrong),
                const SizedBox(width: 6),
                Text(mark ? 'Right' : 'Not quite', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
      ],
    );
  }
}

/// Handwriting for the sentence builder and transform: the whole sentence
/// on the pad, word by word or in a few parts ("Next word" commits a part),
/// reported as an ink `TextAnswer` with combined candidates.
class InkSentenceArea extends StatelessWidget {
  const InkSentenceArea({super.key, required this.locked, required this.onChanged, this.correct});

  final bool locked;
  final bool? correct;
  final ValueChanged<Answer?> onChanged;

  /// Sentences are written in parts; more combinations of the parts' readings count.
  static const int topK = 5;

  @override
  Widget build(BuildContext context) {
    final fb = FeedbackColors.of(context);
    final mark = correct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkPad(
          key: const ValueKey('sentence-ink'),
          enabled: !locked,
          segmented: true,
          hintText: 'Write a word or a few',
          onChanged: (r) => onChanged(r?.toAnswer(topK: topK)),
        ),
        if (mark != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              key: const ValueKey('typed-verdict'),
              children: [
                Icon(mark ? Icons.check : Icons.close, size: 18, color: mark ? fb.correct : fb.wrong),
                const SizedBox(width: 6),
                Text(mark ? 'Right' : 'Not quite', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
      ],
    );
  }
}

/// Rebuild a sentence in another tense or person from tiles.
class TransformView extends ExerciseWidget<TransformExercise> {
  const TransformView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.result,
    super.keys,
    super.reduceMotion,
    super.onCheck,
    this.typed = false,
    this.ink = false,
  });

  /// Typing mode: type the sentence instead of building it from tiles.
  final bool typed;

  /// Handwriting: write the sentence on the pad (in parts: "Next word").
  final bool ink;

  @override
  State<TransformView> createState() => _TransformViewState();
}

class _TransformViewState extends State<TransformView> {
  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final scheme = Theme.of(context).colorScheme;
    return ExerciseLayout(
      prompt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InstructionText(e.instruction),
          _SpeechBubble(
            text: e.source,
            tokens: e.sourceTokens,
            enabled: hideItemUntilAnswered(e, answered: widget.locked),
          ),
          if (e.translation != null) ...[
            const SizedBox(height: 6),
            SubtleText(
              e.translation!,
              key: const ValueKey('transform-translation'),
              italic: true,
              icon: Icons.translate,
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              key: const ValueKey('transform-target'),
              avatar: Icon(Icons.swap_horiz, size: 18, color: scheme.onTertiaryContainer),
              backgroundColor: scheme.tertiaryContainer,
              label: Text(e.targetDescription, style: TextStyle(color: scheme.onTertiaryContainer)),
            ),
          ),
        ],
      ),
      controls: widget.ink
          ? InkSentenceArea(
              locked: widget.locked,
              correct: widget.result?.correct,
              onChanged: widget.onChanged,
            )
          : widget.typed
          ? TypedSentenceArea(
              locked: widget.locked,
              correct: widget.result?.correct,
              hintText: 'Type the new sentence',
              onChanged: widget.onChanged,
              onSubmitted: widget.onCheck,
            )
          : TileAnswerArea(
              tiles: e.tiles,
              locked: widget.locked,
              correct: widget.result?.correct,
              keys: widget.keys,
              onChanged: (words) => widget.onChanged(words == null ? null : TilesAnswer(words)),
            ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text, this.tokens, this.enabled});
  final String text;

  /// Target-language tokens of [text]: words become tappable for their gloss.
  final List<TokenRef>? tokens;
  final bool Function(int, TokenRef)? enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: isMonochrome(scheme) ? Border.all(color: kBwBlack, width: kBwBorder) : null,
      ),
      child: tokens != null && renderTokenRefs(tokens!) == text
          ? TappableSentence(
              key: const ValueKey('source-sentence'),
              tokens: tokens!,
              enabled: enabled,
              style: Theme.of(context).textTheme.titleLarge,
            )
          : Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}
