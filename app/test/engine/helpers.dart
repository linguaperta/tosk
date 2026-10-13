import 'package:tosk/core/core.dart';

/// The answer a perfect learner gives.
Answer correctAnswer(Exercise e) => switch (e) {
      FlashcardExercise() => const SelfGradeAnswer(Rating.good),
      MultipleChoiceExercise() => ChoiceAnswer(e.correctIndex),
      MatchPairsExercise() => MatchAnswer(Map.of(e.solution)),
      ConjPickExercise() => ChoiceAnswer(e.correctIndex),
      ConjGridExercise() => GridAnswer([for (final c in e.cells) c.prefilled ? '' : c.expected]),
      SentenceBuilderExercise() => TilesAnswer(e.answers.first),
      ClozeExercise() => e.options != null ? ChoiceAnswer(e.correctIndex!) : TextAnswer(e.expected),
      SpotErrorExercise() => TokenAnswer(e.errorIndex),
      TransformExercise() => TilesAnswer(e.answers.first),
    };

/// A wrong answer for every facet of [e].
Answer wrongAnswer(Exercise e) => switch (e) {
      FlashcardExercise() => const SelfGradeAnswer(Rating.again),
      MultipleChoiceExercise() => ChoiceAnswer((e.correctIndex + 1) % e.options.length),
      MatchPairsExercise() => MatchAnswer(
          {for (var i = 0; i < e.left.length; i++) i: e.solution[(i + 1) % e.left.length]!},
          missed: {for (var i = 0; i < e.left.length; i++) i},
        ),
      ConjPickExercise() => ChoiceAnswer((e.correctIndex + 1) % e.endings.length),
      ConjGridExercise() => GridAnswer([for (final _ in e.cells) 'xxx']),
      SentenceBuilderExercise() => const TilesAnswer(['xxx']),
      ClozeExercise() => e.options != null ? ChoiceAnswer((e.correctIndex! + 1) % e.options!.length) : const TextAnswer('xxx'),
      SpotErrorExercise() => TokenAnswer(e.tokenIsWord.indexWhere((w) => w) == e.errorIndex
          ? e.tokenIsWord.lastIndexWhere((w) => w)
          : e.tokenIsWord.indexWhere((w) => w)),
      TransformExercise() => const TilesAnswer(['xxx']),
    };
