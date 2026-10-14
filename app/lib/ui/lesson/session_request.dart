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

  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus});
}

class LessonRequest extends SessionRequest {
  const LessonRequest(this.skillId, {this.focus, this.skillTitle});
  final String skillId;

  /// Null = the user's default focus setting.
  final LessonFocus? focus;
  final String? skillTitle;

  @override
  String get title => skillTitle ?? 'Lesson';

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus}) =>
      factory.lesson(skillId, focus: focus ?? defaultFocus);
}

class FadingRequest extends SessionRequest {
  const FadingRequest({this.length = 12});
  final int length;

  @override
  String get title => "What's fading";

  @override
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus}) =>
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
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus}) =>
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
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus}) =>
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
  Future<PracticeSession> start(SessionFactory factory, {required LessonFocus defaultFocus}) => factory.nonStop();
}
