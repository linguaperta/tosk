/// Which settings cloud sync carries between devices (v0.7). Everything else
/// is device-only: the display (black & white on the Boox, colour on the
/// phone), reduced motion, reminders, the e-reader switches, pack download
/// bookkeeping, the AI provider and the engine's recent-sentence memory.
library;

import 'learner_settings.dart';
import 'setting_keys.dart';

const Set<String> kSyncedSettingKeys = {
  SettingKeys.course,
  SettingKeys.sourceLang,
  SettingKeys.defaultFocus,
  SettingKeys.accents,
  SettingKeys.themeMode,
  SettingKeys.soundEffects,
  SettingKeys.defaultLength,
  SettingKeys.leechLapses,
  SettingKeys.coursesAdded,
  SettingKeys.introSeen,
  SettingKeys.autoCheckCourseUpdates,
  LearnerSettingKeys.answerInput,
  LearnerSettingKeys.dailyGoalXp,
  LearnerSettingKeys.listening,
};

/// Comma-separated sets: when a device joins an account, they become the
/// union of both (no course or seen intro is lost); later changes are
/// last-writer-wins like the rest, so removing a course syncs too.
const Set<String> kUnionSettingKeys = {SettingKeys.coursesAdded, SettingKeys.introSeen};
