import '../../core/core.dart';

/// What kind of session the player should start. One player serves lessons,
/// the lab, non-stop and "what's fading".
sealed class SessionRequest {
  const SessionRequest();

  String get title;

  /// Endless sessions show a running count instead of a progress bar and end with Stop.
  bool get endless => false;

  /// Shown when the session has nothing to serve.
  String get emptyMessage => 'Nothing to practice here right now.';

  /// [defaultLength]: the user's default lesson length (exercises).
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12});
}

class LessonRequest extends SessionRequest {
  const LessonRequest(this.skillId, {this.focus, this.skillTitle, this.length});
  final String skillId;

  /// Null = the user's default focus setting.
  final LessonFocus? focus;
  final String? skillTitle;

  /// Exercises; null = the user's default session length.
  final int? length;

  @override
  String get title => skillTitle ?? 'Lesson';

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12}) =>
      factory.lesson(skillId, focus: focus ?? defaultFocus, length: length ?? defaultLength);
}

/// Test out of a skill: a short quiz; passing marks the skill as learned.
class TestOutRequest extends SessionRequest {
  const TestOutRequest(this.skillId);
  final String skillId;

  @override
  String get title => 'Test out';

  @override
  String get emptyMessage => 'This skill has nothing to test yet.';

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12}) =>
      factory.testOut(skillId);
}

/// "Find my level": units in order until one is failed.
class PlacementRequest extends SessionRequest {
  const PlacementRequest();

  @override
  String get title => 'Find my level';

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12}) =>
      factory.placement();
}

/// The "tough words" drill: facets with many lapses.
class ToughWordsRequest extends SessionRequest {
  const ToughWordsRequest({this.minLapses = 4, this.length = 12});
  final int minLapses;
  final int length;

  @override
  String get title => 'Tough words';

  @override
  String get emptyMessage => 'No tough words right now. Nice!';

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12}) =>
      factory.toughWords(length: length, minLapses: minLapses);
}

/// "Practice starred": the active course's bookmarks, loaded when the
/// session starts ([load]; `starredPracticeOf` in `ui/bookmarks/`).
class StarredRequest extends SessionRequest {
  const StarredRequest(this.load, {this.length = 12});
  final Future<StarredPractice> Function() load;
  final int length;

  @override
  String get title => 'Starred';

  @override
  String get emptyMessage => 'Nothing starred yet. Tap ☆ on a word, or "Star" after checking an exercise.';

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12}) async =>
      factory.starred(await load(), length: length);
}

/// "Practice my words": the learner's own words of the active course.
class MyWordsRequest extends SessionRequest {
  const MyWordsRequest({this.length});

  /// Exercises; null = the user's default session length.
  final int? length;

  @override
  String get title => 'My words';

  @override
  String get emptyMessage => 'No words of your own yet. Add some while reading (Practice → Read) or in My words.';

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12}) =>
      factory.myWords(length: length ?? defaultLength);
}

class FadingRequest extends SessionRequest {
  const FadingRequest({this.length = 12});
  final int length;

  @override
  String get title => "What's fading";

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12}) =>
      factory.fading(length: length);
}

class ReviewRequest extends SessionRequest {
  const ReviewRequest({this.length = 12});
  final int length;

  @override
  String get title => 'Mistake review';

  @override
  String get emptyMessage => 'No mistakes to review. Nice!';

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12}) =>
      factory.review(length: length);
}

class LabRequest extends SessionRequest {
  const LabRequest({required this.skillIds, required this.types, required this.length});
  final List<String> skillIds;
  final List<ExerciseType> types;
  final int length;

  @override
  String get title => 'Exercise lab';

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12}) =>
      factory.lab(skillIds: skillIds, types: types, length: length);

  /// Parses `/play/lab?skills=a,b&types=cloze,flashcard&length=12`.
  static LabRequest fromQuery(Map<String, String> q) {
    List<String> list(String? s) => (s == null || s.isEmpty) ? const [] : s.split(',');
    return LabRequest(
      skillIds: list(q['skills']),
      types: [for (final t in list(q['types'])) ?ExerciseType.tryParse(t)],
      length: (int.tryParse(q['length'] ?? '') ?? 12).clamp(1, 200),
    );
  }
}

class NonStopRequest extends SessionRequest {
  const NonStopRequest();

  @override
  String get title => 'Non-stop';

  @override
  bool get endless => true;

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus, int defaultLength = 12}) =>
      factory.nonStop();
}
