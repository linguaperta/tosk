import 'package:flutter/material.dart';

import '../../core/core.dart';
import 'setting_keys.dart';

/// How the app draws: the normal color theme, or pure black and white for
/// e-ink readers (Boox and similar), which also forces reduced motion.
enum DisplayMode { color, bw }

/// User settings as one immutable value. Persisted key by key in the [ProgressStore].
@immutable
class AppSettings {
  const AppSettings({
    this.courseId,
    this.sourceLang = 'en',
    this.defaultFocus = LessonFocus.mixed,
    this.accents = AccentStrictness.lenient,
    this.themeMode = ThemeMode.system,
    this.reduceMotion = false,
    this.display = DisplayMode.color,
    this.defaultLength = SessionLength.normal,
    this.leechLapses = 4,
    this.coursesAdded,
    this.soundEffects = true,
    this.autoCheckCourseUpdates = true,
  });

  /// Null until the user picks a course; the first available course is used then.
  final String? courseId;
  final String sourceLang;
  final LessonFocus defaultFocus;
  final AccentStrictness accents;
  final ThemeMode themeMode;
  final bool reduceMotion;

  /// Color, or black & white (e-ink).
  final DisplayMode display;

  /// Default lesson length (the lesson start sheet offers the others).
  final SessionLength defaultLength;

  /// Lapses from which a facet is a "tough word".
  final int leechLapses;

  /// The user's courses, in the order added; null until the course picker
  /// was first used (see [myCourseIds]).
  final List<String>? coursesAdded;
  /// Short sounds on answers, selections and the end of a lesson (on by
  /// default; independent of reduce motion).
  final bool soundEffects;

  /// Check for course updates once a day on start (on by default). Never downloads by itself.
  final bool autoCheckCourseUpdates;

  /// Black & white (e-ink) display.
  bool get bw => display == DisplayMode.bw;

  /// The courses shown in the app: [coursesAdded], or for an install from
  /// before the course picker the active course. Empty on a fresh install.
  List<String> get myCourseIds => coursesAdded ?? [?courseId];

  AppSettings copyWith({
    String? courseId,
    String? sourceLang,
    LessonFocus? defaultFocus,
    AccentStrictness? accents,
    ThemeMode? themeMode,
    bool? reduceMotion,
    DisplayMode? display,
    SessionLength? defaultLength,
    int? leechLapses,
    List<String>? coursesAdded,
    bool? soundEffects,
    bool? autoCheckCourseUpdates,
  }) => AppSettings(
    courseId: courseId ?? this.courseId,
    sourceLang: sourceLang ?? this.sourceLang,
    defaultFocus: defaultFocus ?? this.defaultFocus,
    accents: accents ?? this.accents,
    themeMode: themeMode ?? this.themeMode,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    display: display ?? this.display,
    defaultLength: defaultLength ?? this.defaultLength,
    leechLapses: leechLapses ?? this.leechLapses,
    coursesAdded: coursesAdded ?? this.coursesAdded,
    soundEffects: soundEffects ?? this.soundEffects,
    autoCheckCourseUpdates: autoCheckCourseUpdates ?? this.autoCheckCourseUpdates,
  );

  /// Reads every setting from [store], falling back to defaults for missing or unknown values.
  static Future<AppSettings> load(ProgressStore store) async {
    const d = AppSettings();
    final course = await store.getSetting(SettingKeys.course);
    final lang = await store.getSetting(SettingKeys.sourceLang);
    final focus = await store.getSetting(SettingKeys.defaultFocus);
    final accents = await store.getSetting(SettingKeys.accents);
    final theme = await store.getSetting(SettingKeys.themeMode);
    final motion = await store.getSetting(SettingKeys.reduceMotion);
    final display = await store.getSetting(SettingKeys.display);
    final length = await store.getSetting(SettingKeys.defaultLength);
    final leech = int.tryParse(await store.getSetting(SettingKeys.leechLapses) ?? '');
    final added = await store.getSetting(SettingKeys.coursesAdded);
    final sounds = await store.getSetting(SettingKeys.soundEffects);
    final autoCheck = await store.getSetting(SettingKeys.autoCheckCourseUpdates);
    return AppSettings(
      courseId: (course == null || course.isEmpty) ? null : course,
      sourceLang: (lang == null || lang.isEmpty) ? d.sourceLang : lang,
      defaultFocus: _byName(LessonFocus.values, focus) ?? d.defaultFocus,
      accents: _byName(AccentStrictness.values, accents) ?? d.accents,
      themeMode: _byName(ThemeMode.values, theme) ?? d.themeMode,
      reduceMotion: motion == 'true',
      display: _byName(DisplayMode.values, display) ?? d.display,
      defaultLength: _byName(SessionLength.values, length) ?? d.defaultLength,
      leechLapses: leech == null || leech < 1 ? d.leechLapses : leech,
      coursesAdded: added == null
          ? null
          : [
              for (final id in added.split(','))
                if (id.trim().isNotEmpty) id.trim(),
            ],
      soundEffects: sounds != 'false',
      autoCheckCourseUpdates: autoCheck != 'false',
    );
  }

  /// Writes the settings that differ from [old] (all of them when [old] is null).
  Future<void> save(ProgressStore store, {AppSettings? old}) async {
    Future<void> put(String key, String? value, String? oldValue) async {
      if (old == null || value != oldValue) await store.setSetting(key, value);
    }

    await put(SettingKeys.course, courseId, old?.courseId);
    await put(SettingKeys.sourceLang, sourceLang, old?.sourceLang);
    await put(SettingKeys.defaultFocus, defaultFocus.name, old?.defaultFocus.name);
    await put(SettingKeys.accents, accents.name, old?.accents.name);
    await put(SettingKeys.themeMode, themeMode.name, old?.themeMode.name);
    await put(SettingKeys.reduceMotion, '$reduceMotion', old == null ? null : '${old.reduceMotion}');
    await put(SettingKeys.display, display.name, old?.display.name);
    await put(SettingKeys.defaultLength, defaultLength.name, old?.defaultLength.name);
    await put(SettingKeys.leechLapses, '$leechLapses', old == null ? null : '${old.leechLapses}');
    await put(SettingKeys.coursesAdded, coursesAdded?.join(','), old?.coursesAdded?.join(','));
    await put(SettingKeys.soundEffects, '$soundEffects', old == null ? null : '${old.soundEffects}');
    await put(
      SettingKeys.autoCheckCourseUpdates,
      '$autoCheckCourseUpdates',
      old == null ? null : '${old.autoCheckCourseUpdates}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.courseId == courseId &&
      other.sourceLang == sourceLang &&
      other.defaultFocus == defaultFocus &&
      other.accents == accents &&
      other.themeMode == themeMode &&
      other.reduceMotion == reduceMotion &&
      other.display == display &&
      other.defaultLength == defaultLength &&
      other.leechLapses == leechLapses &&
      other.coursesAdded?.join(',') == coursesAdded?.join(',') &&
      other.soundEffects == soundEffects &&
      other.autoCheckCourseUpdates == autoCheckCourseUpdates;

  @override
  int get hashCode => Object.hash(
    courseId,
    sourceLang,
    defaultFocus,
    accents,
    themeMode,
    reduceMotion,
    display,
    defaultLength,
    leechLapses,
    coursesAdded?.join(','),
    soundEffects,
    autoCheckCourseUpdates,
  );
}

/// "Quick (5)", "Normal (12)", "Long (20)".
String sessionLengthLabel(SessionLength l) => switch (l) {
  SessionLength.quick => 'Quick',
  SessionLength.normal => 'Normal',
  SessionLength.long => 'Long',
};

T? _byName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// Display names for source languages. Unknown codes are shown as-is.
const Map<String, String> kLanguageNames = {'en': 'English', 'nl': 'Nederlands'};

String languageName(String code) => kLanguageNames[code] ?? code;

/// Picks the source language to use: [wanted] if the course has translations for it,
/// otherwise the first language the course offers (or [wanted] if it offers none).
String effectiveSourceLang(String wanted, CourseMeta? meta) {
  if (meta == null || meta.translations.isEmpty || meta.translations.contains(wanted)) {
    return wanted;
  }
  return meta.translations.first;
}

String focusLabel(LessonFocus f) => switch (f) {
  LessonFocus.mixed => 'Mixed',
  LessonFocus.vocab => 'Vocabulary',
  LessonFocus.grammar => 'Grammar',
};

/// Short label for segmented controls (fits at 320 px).
String focusShortLabel(LessonFocus f) => switch (f) {
  LessonFocus.mixed => 'Mixed',
  LessonFocus.vocab => 'Vocab',
  LessonFocus.grammar => 'Grammar',
};

String exerciseTypeLabel(ExerciseType t) => switch (t) {
  ExerciseType.flashcard => 'Flashcard',
  ExerciseType.multipleChoice => 'Multiple choice',
  ExerciseType.matchPairs => 'Match pairs',
  ExerciseType.conjPick => 'Conjugation pick',
  ExerciseType.conjGrid => 'Conjugation grid',
  ExerciseType.sentenceBuilder => 'Sentence builder',
  ExerciseType.cloze => 'Cloze',
  ExerciseType.spotError => 'Spot the error',
  ExerciseType.transform => 'Transform',
};

IconData exerciseTypeIcon(ExerciseType t) => switch (t) {
  ExerciseType.flashcard => Icons.style_outlined,
  ExerciseType.multipleChoice => Icons.checklist,
  ExerciseType.matchPairs => Icons.compare_arrows,
  ExerciseType.conjPick => Icons.short_text,
  ExerciseType.conjGrid => Icons.grid_on,
  ExerciseType.sentenceBuilder => Icons.view_week_outlined,
  ExerciseType.cloze => Icons.space_bar,
  ExerciseType.spotError => Icons.search,
  ExerciseType.transform => Icons.transform,
};

/// Exercise types each lesson focus favors (mirrors the spec; the engine's
/// `focus_presets.json` holds the real weights).
const Map<LessonFocus, Set<ExerciseType>> kFocusTypes = {
  LessonFocus.mixed: {...ExerciseType.values},
  LessonFocus.vocab: {
    ExerciseType.flashcard,
    ExerciseType.matchPairs,
    ExerciseType.multipleChoice,
    ExerciseType.sentenceBuilder,
  },
  LessonFocus.grammar: {
    ExerciseType.conjPick,
    ExerciseType.conjGrid,
    ExerciseType.cloze,
    ExerciseType.transform,
    ExerciseType.spotError,
  },
};
