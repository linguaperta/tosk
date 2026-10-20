import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/core.dart';
import '../../../providers.dart';
import '../../../speech/speech_providers.dart';
import '../../ink/ink_providers.dart';
import '../../settings/learner_settings.dart' show typingModeProvider;
import '../typing.dart';
import 'cloze_view.dart';
import 'common.dart';
import 'conj_grid_view.dart';
import 'conj_pick_view.dart';
import 'flashcard_view.dart';
import 'listen_pick_view.dart';
import 'match_pairs_view.dart';
import 'multiple_choice_view.dart';
import 'spot_error_view.dart';
import 'tile_builder_views.dart';

export 'common.dart' show ExerciseKeys;

/// How production exercises take answers (Settings → Answer input).
enum AnswerMode { tap, type, ink }

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
    // Typing ("challenge") mode and handwriting: production types take
    // typed or handwritten answers.
    final mode = ref.watch(inkModeProvider)
        ? AnswerMode.ink
        : ref.watch(typingModeProvider)
        ? AnswerMode.type
        : AnswerMode.tap;
    final tick = onSelect;
    // Draft changes from taps (choices, tiles, tokens, grid cells) tick;
    // typed and handwritten text doesn't.
    final ValueChanged<Answer?> onChanged = tick == null
        ? this.onChanged
        : (a) {
            if (a is! TextAnswer && mode == AnswerMode.tap) tick();
            this.onChanged(a);
          };
    return AccentLetters(letters: ref.watch(accentLettersProvider), child: _view(ref, reduce, mode, onChanged));
  }

  Widget _view(WidgetRef ref, bool reduce, AnswerMode mode, ValueChanged<Answer?> onChanged) {
    final typed = mode == AnswerMode.type;
    final ink = mode == AnswerMode.ink;
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
        ink: ink,
      ),
      ConjGridExercise e => ConjGridView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
        onCheck: onCheck,
        typed: typed,
        ink: ink,
      ),
      SentenceBuilderExercise e => SentenceBuilderView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
        onCheck: onCheck,
        typed: typed,
        ink: ink,
      ),
      ClozeExercise e => ClozeView(
        exercise: e,
        onChanged: onChanged,
        onCheck: onCheck,
        result: result,
        keys: keys,
        reduceMotion: reduce,
        inputBuilder: ref.watch(answerInputBuilderProvider),
        typed: typed || ink,
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
        ink: ink,
      ),
      ListenPickExercise e => ListenPickView(
        exercise: e,
        onChanged: onChanged,
        result: result,
        keys: keys,
        reduceMotion: reduce,
        speaker: ref.watch(speakerProvider),
      ),
    };
  }
}
