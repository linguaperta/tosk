/// Maps graded results to FSRS ratings (docs/ARCHITECTURE.md "FSRS ratings").
library;

import '../../core/interfaces/session.dart' show AccentStrictness;
import '../../core/models/progress.dart';

/// Wrong -> Again; right -> Good; right and faster than the type's
/// fast-answer threshold -> Easy. Flashcards are self-graded and never pass
/// through here. An answer accepted only thanks to accent folding is capped
/// at Good.
class RatingPolicy {
  const RatingPolicy({this.fastMs = defaultFastMs});

  /// Fast-answer thresholds in milliseconds per exercise type.
  static const Map<ExerciseType, int> defaultFastMs = {
    ExerciseType.flashcard: 0, // self-graded
    ExerciseType.multipleChoice: 3500,
    ExerciseType.matchPairs: 12000,
    ExerciseType.conjPick: 3000,
    ExerciseType.conjGrid: 20000,
    ExerciseType.sentenceBuilder: 10000,
    ExerciseType.cloze: 5000,
    ExerciseType.spotError: 6000,
    ExerciseType.transform: 12000,
  };

  final Map<ExerciseType, int> fastMs;

  Rating rate(ExerciseType type, {required bool correct, required Duration elapsed, bool accentSlip = false}) {
    if (!correct) return Rating.again;
    if (accentSlip) return Rating.good;
    final fast = fastMs[type] ?? 0;
    if (fast > 0 && elapsed.inMilliseconds < fast) return Rating.easy;
    return Rating.good;
  }
}

/// Options for grading one answer.
class GradeOptions {
  const GradeOptions({this.accents = AccentStrictness.lenient, this.rating = const RatingPolicy()});
  final AccentStrictness accents;
  final RatingPolicy rating;
}
