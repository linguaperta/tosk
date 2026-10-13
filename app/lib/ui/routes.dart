import '../core/core.dart';

/// Route paths and builders, so screens never hand-assemble URLs.
abstract final class Routes {
  static const map = '/';
  static const lab = '/lab';
  static const nonstop = '/nonstop';
  static const settings = '/settings';
  static const debug = '/debug';

  /// Skill detail bottom sheet (grammar note, items, start with a focus).
  static String skill(String skillId) => '/skill/${Uri.encodeComponent(skillId)}';

  static String lesson(String skillId, {LessonFocus? focus}) => Uri(
    path: '/play/lesson/${Uri.encodeComponent(skillId)}',
    queryParameters: focus == null ? null : {'focus': focus.name},
  ).toString();

  static const fading = '/play/fading';
  static const nonstopPlay = '/play/nonstop';

  static String labPlay({required List<String> skills, required List<ExerciseType> types, required int length}) => Uri(
    path: '/play/lab',
    queryParameters: {'skills': skills.join(','), 'types': types.map((t) => t.id).join(','), 'length': '$length'},
  ).toString();
}
