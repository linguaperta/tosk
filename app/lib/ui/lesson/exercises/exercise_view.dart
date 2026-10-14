import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/core.dart';
import '../../../providers.dart';
import '../../settings/learner_settings.dart' show typingModeProvider;
import '../typing.dart';
import 'cloze_view.dart';
import 'common.dart';
import 'conj_grid_view.dart';
import 'conj_pick_view.dart';
import 'flashcard_view.dart';
import 'match_pairs_view.dart';
import 'multiple_choice_view.dart';
import 'spot_error_view.dart';
import 'tile_builder_views.dart';

export 'common.dart' show ExerciseKeys;

/// Types that submit themselves (no Check button).
bool selfSubmitting(ExerciseType t) => t == ExerciseType.flashcard || t == ExerciseType.matchPairs;

/// Renders any [Exercise] with the widget for its type.
class ExerciseView extends ConsumerWidget {
  const ExerciseView({
    super.key,
    required this.exercise,
    required this.onChanged,
    this.onSubmit,
    this.onCheck,
    this.onSelect,
    this.result,
    this.keys,
  });

  final Exercise exercise;
  final ValueChanged<Answer?> onChanged;

  /// Called on every tap that selects an option, tile, token, cell or card
  /// (not on typing): the player's select tick and haptic.
  final VoidCallback? onSelect;
  final ValueChanged<Answer>? onSubmit;
  final VoidCallback? onCheck;
  final Result? result;
  final ExerciseKeys? keys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduce = ref.watch(reduceMotionProvider);
    // Typing ("challenge") mode: production types take typed answers.
    final typed = ref.watch(typingModeProvider);
    final tick = onSelect;
    // Draft changes from taps (choices, tiles, tokens, grid cells) tick;
    // typed text doesn't.
    final ValueChanged<Answer?> onChanged = tick == null
        ? this.onChanged
        : (a) {
            if (a is! TextAnswer && !typed) tick();
            this.onChanged(a);
          };
    return AccentLetters(letters: ref.watch(accentLettersProvider), child: _view(ref, reduce, typed, onChanged));
  }

  Widget _view(WidgetRef ref, bool reduce, bool typed, ValueChanged<Answer?> onChanged) {
    return switch (exercise) {
      FlashcardExercise e => FlashcardView(
        exercise: e,
        onChanged: onChanged,
        onSubmit: onSubmit,
        result: result,
        keys: keys,
        reduceMotion: reduce,
      ),
      MultipleChoiceExercise e => MultipleChoiceView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
      ),
      MatchPairsExercise e => MatchPairsView(
        exercise: e,
        onChanged: onChanged,
        onSubmit: onSubmit,
        onSelect: onSelect,
        result: result,
        keys: keys,
        reduceMotion: reduce,
      ),
      ConjPickExercise e => ConjPickView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
        onCheck: onCheck,
        typed: typed,
      ),
      ConjGridExercise e => ConjGridView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
        onCheck: onCheck,
        typed: typed,
      ),
      SentenceBuilderExercise e => SentenceBuilderView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
        onCheck: onCheck,
        typed: typed,
      ),
      ClozeExercise e => ClozeView(
        exercise: e,
        onChanged: onChanged,
        onCheck: onCheck,
        result: result,
        keys: keys,
        reduceMotion: reduce,
        inputBuilder: ref.watch(answerInputBuilderProvider),
        typed: typed,
      ),
      SpotErrorExercise e => SpotErrorView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
      ),
      TransformExercise e => TransformView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
        onCheck: onCheck,
        typed: typed,
      ),
    };
  }
}
