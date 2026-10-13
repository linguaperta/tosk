import 'package:flutter/material.dart';

import '../../../core/core.dart';
import 'common.dart';

/// See the front, reveal the back, grade yourself (Again / Hard / Good / Easy).
class FlashcardView extends ExerciseWidget<FlashcardExercise> {
  const FlashcardView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.onSubmit,
    super.result,
    super.keys,
    super.reduceMotion,
  });

  @override
  State<FlashcardView> createState() => _FlashcardViewState();
}

class _FlashcardViewState extends State<FlashcardView> with ExerciseKeysMixin<FlashcardView> {
  bool _revealed = false;

  void _reveal() => setState(() => _revealed = true);

  void _grade(Rating r) {
    if (widget.locked) return;
    widget.onSubmit?.call(SelfGradeAnswer(r));
  }

  @override
  void onPrimary() {
    if (!_revealed) _reveal();
  }

  @override
  void onDigit(int n) {
    if (_revealed && n >= 1 && n <= 4) _grade(Rating.fromValue(n));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final theme = Theme.of(context);
    final revealed = _revealed || widget.locked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InstructionText(e.instruction),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Column(
              children: [
                Text(e.front, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                if (e.hint != null) ...[
                  const SizedBox(height: 6),
                  Text(e.hint!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
                AnimatedSize(
                  duration: widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                  child: revealed
                      ? Column(
                          children: [
                            const Divider(height: 32),
                            Text(
                              e.back,
                              key: const ValueKey('flashcard-back'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary),
                            ),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (!revealed)
          FilledButton.tonal(
            key: const ValueKey('flashcard-reveal'),
            onPressed: _reveal,
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Show answer')),
          )
        else
          Row(
            children: [
              for (final r in Rating.values) ...[
                if (r != Rating.again) const SizedBox(width: 8),
                Expanded(
                  child: _GradeButton(rating: r, onPressed: widget.locked ? null : () => _grade(r)),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({required this.rating, this.onPressed});
  final Rating rating;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fb = FeedbackColors.of(context);
    final (String label, Color color) = switch (rating) {
      Rating.again => ('Again', fb.wrong),
      Rating.hard => ('Hard', scheme.tertiary),
      Rating.good => ('Good', fb.correct),
      Rating.easy => ('Easy', scheme.primary),
    };
    return OutlinedButton(
      key: ValueKey('grade-${rating.name}'),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      ),
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
    );
  }
}
