import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/core.dart';
import '../../../providers.dart';
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
    this.result,
    this.keys,
  });

  final Exercise exercise;
  final ValueChanged<Answer?> onChanged;
  final ValueChanged<Answer>? onSubmit;
  final VoidCallback? onCheck;
  final Result? result;
  final ExerciseKeys? keys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduce = ref.watch(reduceMotionProvider);
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
      ),
      ConjGridExercise e => ConjGridView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
      ),
      SentenceBuilderExercise e => SentenceBuilderView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
      ),
      ClozeExercise e => ClozeView(
        exercise: e,
        onChanged: onChanged,
        onCheck: onCheck,
        result: result,
        keys: keys,
        reduceMotion: reduce,
        inputBuilder: ref.watch(answerInputBuilderProvider),
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
      ),
    };
  }
}
