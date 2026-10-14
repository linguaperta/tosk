import '../core/core.dart';

/// Route paths and builders, so screens never hand-assemble URLs.
abstract final class Routes {
  static const map = '/';

  /// Practice tab: non-stop and the exercise lab.
  static const practice = '/practice';

  /// The lab inside the practice tab (`/lab` redirects here).
  static const lab = '/practice?tab=lab';

  /// Non-stop inside the practice tab (`/nonstop` redirects here).
  static const nonstop = '/practice?tab=nonstop';

  /// Reference tab: word and conjugation lookup, grammar library.
  static const reference = '/reference';

  /// The grammar library inside the reference tab.
  static const grammar = '/reference?tab=grammar';

  /// Lookup with a prefilled search.
  static String lookup(String query) => Uri(path: reference, queryParameters: {'q': query}).toString();

  static const settings = '/settings';
  static const progress = '/progress';
  static const verbs = '/progress/verbs';
  static const debug = '/debug';

  /// Settings → Feedback & flags: flagged exercises and their export.
  static const flags = '/flags';

  /// Open mistakes of the active course, with "Review mistakes".
  static const mistakes = '/mistakes';

  /// Skill detail bottom sheet (grammar note, items, start with a focus).
  /// The skill sheet; [section] `note` or `words` opens that section.
  static String skill(String skillId, {String? section}) => Uri(
    path: '/skill/${Uri.encodeComponent(skillId)}',
    queryParameters: section == null ? null : {'section': section},
  ).toString();

  /// A word's reference page (glosses, article, skills, examples; full
  /// conjugation table for verbs). Opens over anything, the player included.
  static String word(String itemId) => '/word/${Uri.encodeComponent(itemId)}';

  static String lesson(String skillId, {LessonFocus? focus, int? length}) {
    final q = {'focus': ?focus?.name, if (length != null) 'length': '$length'};
    return Uri(path: '/play/lesson/${Uri.encodeComponent(skillId)}', queryParameters: q.isEmpty ? null : q).toString();
  }

  static const fading = '/play/fading';
  static const review = '/play/review';
  static const nonstopPlay = '/play/nonstop';

  /// Tough words drill (leeches).
  static const tough = '/play/tough';

  /// "Find my level" for the active course.
  static const placement = '/play/placement';

  /// Test out of a skill.
  static String testOut(String skillId) => '/play/testout/${Uri.encodeComponent(skillId)}';

  static String labPlay({required List<String> skills, required List<ExerciseType> types, required int length}) => Uri(
    path: '/play/lab',
    queryParameters: {'skills': skills.join(','), 'types': types.map((t) => t.id).join(','), 'length': '$length'},
  ).toString();
}
