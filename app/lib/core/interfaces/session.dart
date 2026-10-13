/// Practice-session contract between the engine (implements) and the UI (drives).
library;

import '../models/exercise.dart';
import '../models/progress.dart';

enum SessionMode { lesson, lab, nonstop, review }

/// Lesson focus preset; weights per exercise type live in `assets/config/focus_presets.json`.
enum LessonFocus { mixed, vocab, grammar }

/// Answer-checking strictness for accents/diacritics.
enum AccentStrictness { strict, lenient }

/// Options that come from user settings.
class SessionOptions {
  const SessionOptions({
    required this.sourceLang,
    this.accents = AccentStrictness.lenient,
    this.preferredInput = InputMode.tap,
    this.seed,
  });
  final String sourceLang; // 'en' | 'nl'
  final AccentStrictness accents;
  final InputMode preferredInput; // tap now; keyboard/ink switch cloze & grid to free input
  final int? seed; // for deterministic tests
}

abstract interface class PracticeSession {
  String get id;
  SessionMode get mode;

  /// Planned number of exercises; null for endless (non-stop).
  int? get plannedLength;

  int get answered;
  int get correctCount;

  /// Next exercise, or null when the session is finished. Mistakes are re-queued later in the session.
  Future<Exercise?> next();

  /// Grades [answer], records every facet outcome in the progress store, stores a
  /// mistake record when wrong, and returns the result for instant feedback.
  Future<Result> submit(Exercise exercise, Answer answer, {required Duration elapsed});

  /// Ends the session early (non-stop "stop", or leaving a lesson).
  void stop();

  SessionSummary summary();
}

class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.mode,
    required this.answered,
    required this.correct,
    required this.startedAt,
    required this.endedAt,
    required this.facetsPracticed,
    required this.mistakes,
  });
  final String sessionId;
  final SessionMode mode;
  final int answered;
  final int correct;
  final DateTime startedAt;
  final DateTime endedAt;
  final Set<String> facetsPracticed;
  final List<String> mistakes; // facet ids answered wrong at least once

  double get accuracy => answered == 0 ? 0 : correct / answered;
}

/// Creates sessions for the active course.
abstract interface class SessionFactory {
  Future<PracticeSession> lesson(String skillId, {LessonFocus focus = LessonFocus.mixed, int length = 12});
  Future<PracticeSession> lab({
    required List<String> skillIds,
    required List<ExerciseType> types,
    required int length,
  });
  Future<PracticeSession> nonStop();

  /// "What's fading": due facets across all skills.
  Future<PracticeSession> fading({int length = 12});
}
