/// Practice-session contract between the engine (implements) and the UI (drives).
library;

import '../models/exercise.dart';
import '../models/progress.dart';

enum SessionMode {
  lesson,
  lab,
  nonstop,
  review,

  /// A short quiz over one skill; passing credits the skill (see [AssessmentSession]).
  testOut,

  /// "Find my level": units in order until one is failed.
  placement,

  /// "Practice starred" (v0.4): the learner's bookmarks ([SessionFactory.starred]).
  starred,

  /// "My words": the learner's own words ([SessionFactory.myWords]).
  myWords,
}

/// Lesson lengths offered on the lesson start sheet.
enum SessionLength {
  quick(5),
  normal(12),
  long(20);

  const SessionLength(this.exercises);
  final int exercises;
}

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
    this.listening = false,
    this.seed,
  });
  final String sourceLang; // 'en' | 'nl'
  final AccentStrictness accents;
  final InputMode preferredInput; // tap; keyboard/ink switch cloze to free input
  /// Text-to-speech has a voice for the course's target language on this
  /// device: `listen_pick` exercises may be generated (never otherwise).
  final bool listening;
  final int? seed; // for deterministic tests
}

abstract interface class PracticeSession {
  String get id;
  SessionMode get mode;

  /// Planned number of exercises; null for endless (non-stop).
  int? get plannedLength;

  int get answered;
  int get correctCount;

  /// Next exercise, or null when the session is finished. Mistakes come back later in the session (retries).
  Future<Exercise?> next();

  /// Grades [answer], records every facet outcome in the progress store, stores a
  /// mistake record when wrong, and returns the result for instant feedback.
  Future<Result> submit(Exercise exercise, Answer answer, {required Duration elapsed});

  /// Ends the session early (non-stop "stop", or leaving a lesson).
  void stop();

  SessionSummary summary();
}

/// A session whose wrong verdicts the learner may override ("I was right").
/// Engine sessions implement it; the player offers the action only then.
abstract interface class OverridableSession {
  /// Whether the answer to [exerciseId] was graded wrong and not overridden yet.
  bool canOverride(String exerciseId);

  /// Counts the wrong answer to [exerciseId] as right: one override event
  /// (`kOverrideType`, rating Good) per wrong facet outcome the answer
  /// recorded, so replay rates those facets Good instead of Again; the
  /// session counts the answer as correct and drops its re-asks and its
  /// mistake. Returns the events written (none for an answer that recorded
  /// nothing, such as a wrong re-ask; the session still counts it right).
  Future<List<ReviewEvent>> overrideAnswer(String exerciseId);
}

/// A session that brings wrong answers back until they are right (engine
/// sessions; docs/engine.md, "Retries"). The player shows how many are
/// waiting and marks an exercise that is a retry.
abstract interface class RetryingSession {
  /// Mistakes waiting to come back (already counted in `plannedLength`).
  int get pendingRetries;

  /// Whether the exercise [exerciseId] is a mistake asked again.
  bool isRetry(String exerciseId);
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

  /// Mistake review (mode [SessionMode.review]): the facets of recent,
  /// still-open mistakes, preferring the exercise type that was missed.
  /// Empty (`plannedLength == 0`) when nothing is open. See docs/engine.md.
  Future<PracticeSession> review({int length = 12});

  /// Test out of a skill: about [length] production-leaning exercises over
  /// its facets, no re-asks. Passing (score >= [passMark]) credits every
  /// facet of the skill (see `kTestOutCreditType`).
  Future<AssessmentSession> testOut(String skillId, {int length = 10, double passMark = 0.8});

  /// Placement ("Find my level"): a few exercises per skill, unit by unit in
  /// course order, stopping after the first unit scoring below [passMark];
  /// every skill of the units passed before it is credited.
  Future<AssessmentSession> placement({int perSkill = 2, double passMark = 0.8});

  /// "Tough words": facets with at least [minLapses] lapses, each as a small
  /// recognition -> production ladder. Empty when there are none.
  Future<PracticeSession> toughWords({int length = 12, int minLapses = 4});

  /// "Practice starred" (mode [SessionMode.starred]): the learner's
  /// bookmarks. Starred exercises are served again as they were (when the
  /// course still trains their facets; otherwise a fresh exercise on the same
  /// facet), starred words through their facets (weakest first), starred
  /// sentences through the facets of their words, preferring the sentence
  /// itself. Empty (`plannedLength == 0`) when nothing is starred. See
  /// docs/engine.md, "Starred practice".
  Future<PracticeSession> starred(StarredPractice starred, {int length = 12});

  /// "My words" (mode [SessionMode.myWords]): the learner's own words of the
  /// course (`core/models/user_word.dart`): due facets first, then new words,
  /// then the weakest. Empty (`plannedLength == 0`) without words.
  Future<PracticeSession> myWords({int length = 12});
}

/// What "Practice starred" practices: bookmarked words, sentences and
/// exercises of one course (the UI decodes the stored exercise snapshots).
class StarredPractice {
  const StarredPractice({this.itemIds = const [], this.sentenceIds = const [], this.exercises = const []});

  /// Starred words (item ids), most recently starred first.
  final List<String> itemIds;

  /// Starred sentences (sentence ids), most recently starred first.
  final List<String> sentenceIds;

  /// Starred exercises as they were shown, most recently starred first. Their
  /// ids must be unique (the UI uses `starred:{bookmark id}`).
  final List<Exercise> exercises;

  bool get isEmpty => itemIds.isEmpty && sentenceIds.isEmpty && exercises.isEmpty;
}

/// The result of a test-out or placement session, available once the session
/// has ended (its last `next()` returned null).
class AssessmentOutcome {
  const AssessmentOutcome({
    required this.passed,
    required this.correct,
    required this.total,
    required this.passMark,
    this.creditedSkills = const [],
    this.passedUnits = const [],
    this.failedUnit,
  });

  /// Test-out: the score reached [passMark]. Placement: at least one unit passed.
  final bool passed;
  final int correct;
  final int total;
  final double passMark;

  /// Skills whose facets were credited, in course order.
  final List<String> creditedSkills;

  /// Placement: units passed, in course order.
  final List<String> passedUnits;

  /// Placement: the unit where it stopped (null when every unit passed).
  final String? failedUnit;

  double get score => total == 0 ? 0 : correct / total;
}

/// A test-out or placement session.
abstract interface class AssessmentSession implements PracticeSession {
  /// Null while the session runs; set when it ended normally (not when stopped).
  AssessmentOutcome? get outcome;
}
