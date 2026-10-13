import 'package:flutter/material.dart';

import '../../../core/core.dart';
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
  });

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
        ],
      ),
      controls: TileAnswerArea(
        tiles: e.tiles,
        locked: widget.locked,
        correct: widget.result?.correct,
        keys: widget.keys,
        onChanged: (words) => widget.onChanged(words == null ? null : TilesAnswer(words)),
      ),
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
  });

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
          _SpeechBubble(text: e.source),
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
      controls: TileAnswerArea(
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
  const _SpeechBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}
