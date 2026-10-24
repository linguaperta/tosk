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

  /// `'true'` disables animations and haptics (black & white mode forces it).
  static const reduceMotion = 'ui.reduce_motion';

  /// [DisplayMode] name: `color` or `bw` (black & white for e-ink; forces reduced motion).
  static const display = 'ui.display';

  /// `'false'` mutes sound effects (on by default; separate from reduce motion).
  static const soundEffects = 'ui.sound_effects';

  /// [SessionLength] name of a lesson: `quick` (5), `normal` (12) or `long` (20).
  static const defaultLength = 'lesson.default_length';

  /// Lapses from which a facet is a "tough word" (an integer, default 4).
  static const leechLapses = 'lesson.leech_lapses';

  /// The user's courses ("my courses"), comma-separated ids in the order
  /// added. Absent until the course picker is first used (then an existing
  /// install counts `course.active` as added; a fresh one opens the picker).
  static const coursesAdded = 'courses.added';

  /// Exercise types whose first-time intro was seen: comma-separated type ids
  /// (account-wide, not per course).
  static const introSeen = 'intro.seen';

  /// `'false'` turns off the daily check for course updates (on by default).
  /// Downloads always need a tap.
  static const autoCheckCourseUpdates = 'packs.auto_check';

  /// Device-only (not in [all], never imported from a backup): the release
  /// index URL override (debug screen; empty = the default), the last fetched
  /// index (JSON) and when it was fetched (UTC ISO 8601).
  static const packIndexUrl = 'packs.index_url';
  static const packIndexCache = 'packs.index_cache';
  static const packLastCheck = 'packs.last_check';

  /// Device-only (not in [all]): languages whose "install a voice" notice
  /// was shown, comma-separated (voices are per device).
  static const voiceNoticeShown = 'speech.voice_notice';

  /// Device-only (not in [all], not synced): `'true'` once the first-run
  /// welcome (who Tosk is, how it works, sign-in, Claude key) was left. A
  /// fresh install shows it before the course picker; Settings → About →
  /// "Show welcome again" opens it on demand.
  static const welcomeDone = 'welcome.done';

  /// Device-only: `'true'` while the hidden developer options (the debug
  /// screen) show in Settings → About. Tapping the version seven times turns
  /// them on; their own switch turns them off.
  static const developerOptions = 'dev.options';

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
    soundEffects,
    introSeen,
    autoCheckCourseUpdates,
  ];
}
