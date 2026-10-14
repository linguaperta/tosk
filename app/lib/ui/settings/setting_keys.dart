/// Keys for user settings persisted through `ProgressStore.getSetting/setSetting`.
///
/// Values are stored as strings: enum values by their `name`, booleans as
/// `'true'`/`'false'`, language and course ids as-is.
abstract final class SettingKeys {
  /// Active course id, e.g. `'it'`.
  static const course = 'course.active';

  /// Source language for translations (`'en'` or `'nl'`); only languages in
  /// `CourseMeta.translations` are offered.
  static const sourceLang = 'ui.source_lang';

  /// Default [LessonFocus] name: `mixed`, `vocab` or `grammar`.
  static const defaultFocus = 'lesson.default_focus';

  /// [AccentStrictness] name: `strict` or `lenient`.
  static const accents = 'lesson.accent_strictness';

  /// `light`, `dark` or `system`.
  static const themeMode = 'ui.theme_mode';

  /// `'true'` disables animations, haptics and sounds (the future e-ink mode builds on it).
  static const reduceMotion = 'ui.reduce_motion';

  /// [DisplayMode] name: `color` or `bw` (black & white for e-ink; forces reduced motion).
  static const display = 'ui.display';

  /// [SessionLength] name of a lesson: `quick` (5), `normal` (12) or `long` (20).
  static const defaultLength = 'lesson.default_length';

  /// Lapses from which a facet is a "tough word" (an integer, default 4).
  static const leechLapses = 'lesson.leech_lapses';

  /// The user's courses ("my courses"), comma-separated ids in the order
  /// added. Absent until the course picker is first used (then an existing
  /// install counts `course.active` as added; a fresh one opens the picker).
  static const coursesAdded = 'courses.added';

  static const all = [
    course,
    sourceLang,
    defaultFocus,
    accents,
    themeMode,
    reduceMotion,
    display,
    defaultLength,
    leechLapses,
    coursesAdded,
  ];
}
