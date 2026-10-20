/// Settings of the v0.3 practice extras: typing ("challenge") mode, the daily
/// XP goal and the daily reminder. Kept apart from [AppSettings] (its own
/// value, notifier and keys), persisted the same way through the
/// `ProgressStore` settings table.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../providers.dart' show progressStoreProvider;

/// How production exercises take answers.
enum AnswerInputPref {
  /// Options and tiles (the default: typing is never required).
  tap,

  /// "Challenge mode": cloze, conjugation pick and grid, sentence builder and
  /// transform take typed answers. Recognition exercises stay tap.
  type,

  /// Handwriting (v0.5): the same production exercises take handwritten
  /// answers on a writing pad (ML Kit Digital Ink). Only offered where the
  /// recognizer runs (Android, iOS); elsewhere it falls back to tap.
  handwrite,
}

/// Keys (all strings in the settings table).
abstract final class LearnerSettingKeys {
  /// [AnswerInputPref] name: `tap` or `type`.
  static const answerInput = 'lesson.answer_input';

  /// Daily goal in XP (`0` = off). One of [kDailyGoalChoices].
  static const dailyGoalXp = 'goal.daily_xp';

  /// `true` when the daily reminder is on.
  static const reminderEnabled = 'reminder.enabled';

  /// Reminder time of day, `HH:MM` (24 h, local time).
  static const reminderTime = 'reminder.time';

  /// `false` turns listening exercises off (on by default where the device
  /// has a voice for the course language).
  static const listening = 'lesson.listening';

  /// ONYX e-readers: `true`/`false` for a full e-ink refresh after lessons;
  /// absent = on in black & white. Device-only (never imported).
  static const einkFullRefresh = 'eink.full_refresh';

  /// ONYX e-readers: `false` turns the Onyx pen SDK's low-latency drawing
  /// off (the writing pad then draws with Flutter). Device-only.
  static const onyxPen = 'eink.onyx_pen';

  static const all = [answerInput, dailyGoalXp, reminderEnabled, reminderTime, listening, einkFullRefresh, onyxPen];
}

/// Daily goal choices in XP; 0 is "Off". About half a lesson, one lesson and
/// two lessons for a learner with a few new words a day (docs/progression.md).
const List<int> kDailyGoalChoices = [0, 20, 50, 100];

const int kDefaultDailyGoalXp = 50;
const TimeOfDay kDefaultReminderTime = TimeOfDay(hour: 19, minute: 0);

@immutable
class LearnerSettings {
  const LearnerSettings({
    this.answerInput = AnswerInputPref.tap,
    this.dailyGoalXp = kDefaultDailyGoalXp,
    this.reminderEnabled = false,
    this.reminderTime = kDefaultReminderTime,
    this.listening = true,
    this.einkFullRefresh,
    this.onyxPen = true,
  });

  final AnswerInputPref answerInput;

  /// Listening exercises (when the device has a voice).
  final bool listening;

  /// Full e-ink refresh after lessons (ONYX); null = the default (on in
  /// black & white).
  final bool? einkFullRefresh;

  /// Onyx pen SDK drawing in the writing pad (ONYX).
  final bool onyxPen;

  /// XP per day; 0 = no goal (and no reminder).
  final int dailyGoalXp;
  final bool reminderEnabled;
  final TimeOfDay reminderTime;

  bool get typing => answerInput == AnswerInputPref.type;
  bool get handwriting => answerInput == AnswerInputPref.handwrite;
  bool get hasGoal => dailyGoalXp > 0;

  LearnerSettings copyWith({
    AnswerInputPref? answerInput,
    int? dailyGoalXp,
    bool? reminderEnabled,
    TimeOfDay? reminderTime,
    bool? listening,
    bool? einkFullRefresh,
    bool? onyxPen,
  }) => LearnerSettings(
    answerInput: answerInput ?? this.answerInput,
    dailyGoalXp: dailyGoalXp ?? this.dailyGoalXp,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderTime: reminderTime ?? this.reminderTime,
    listening: listening ?? this.listening,
    einkFullRefresh: einkFullRefresh ?? this.einkFullRefresh,
    onyxPen: onyxPen ?? this.onyxPen,
  );

  static Future<LearnerSettings> load(ProgressStore store) async {
    const d = LearnerSettings();
    final input = await store.getSetting(LearnerSettingKeys.answerInput);
    final goal = int.tryParse(await store.getSetting(LearnerSettingKeys.dailyGoalXp) ?? '');
    final enabled = await store.getSetting(LearnerSettingKeys.reminderEnabled);
    final time = parseTimeOfDay(await store.getSetting(LearnerSettingKeys.reminderTime));
    final listening = await store.getSetting(LearnerSettingKeys.listening);
    final refresh = await store.getSetting(LearnerSettingKeys.einkFullRefresh);
    final pen = await store.getSetting(LearnerSettingKeys.onyxPen);
    return LearnerSettings(
      answerInput: AnswerInputPref.values.asNameMap()[input] ?? d.answerInput,
      dailyGoalXp: goal == null || goal < 0 ? d.dailyGoalXp : goal,
      reminderEnabled: enabled == 'true',
      reminderTime: time ?? d.reminderTime,
      listening: listening != 'false',
      einkFullRefresh: refresh == null ? null : refresh == 'true',
      onyxPen: pen != 'false',
    );
  }

  /// Writes the values that differ from [old] (all when [old] is null).
  Future<void> save(ProgressStore store, {LearnerSettings? old}) async {
    Future<void> put(String key, String value, String? oldValue) async {
      if (old == null || value != oldValue) await store.setSetting(key, value);
    }

    await put(LearnerSettingKeys.answerInput, answerInput.name, old?.answerInput.name);
    await put(LearnerSettingKeys.dailyGoalXp, '$dailyGoalXp', old == null ? null : '${old.dailyGoalXp}');
    await put(LearnerSettingKeys.reminderEnabled, '$reminderEnabled', old == null ? null : '${old.reminderEnabled}');
    await put(
      LearnerSettingKeys.reminderTime,
      formatTimeOfDay(reminderTime),
      old == null ? null : formatTimeOfDay(old.reminderTime),
    );
    await put(LearnerSettingKeys.listening, '$listening', old == null ? null : '${old.listening}');
    if (einkFullRefresh != null) {
      await put(LearnerSettingKeys.einkFullRefresh, '$einkFullRefresh', old?.einkFullRefresh?.toString());
    }
    await put(LearnerSettingKeys.onyxPen, '$onyxPen', old == null ? null : '${old.onyxPen}');
  }

  @override
  bool operator ==(Object other) =>
      other is LearnerSettings &&
      other.answerInput == answerInput &&
      other.dailyGoalXp == dailyGoalXp &&
      other.reminderEnabled == reminderEnabled &&
      other.reminderTime == reminderTime &&
      other.listening == listening &&
      other.einkFullRefresh == einkFullRefresh &&
      other.onyxPen == onyxPen;

  @override
  int get hashCode =>
      Object.hash(answerInput, dailyGoalXp, reminderEnabled, reminderTime, listening, einkFullRefresh, onyxPen);
}

/// `HH:MM`, 24 h.
String formatTimeOfDay(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? parseTimeOfDay(String? s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s?.trim() ?? '');
  if (m == null) return null;
  final h = int.parse(m[1]!), min = int.parse(m[2]!);
  if (h > 23 || min > 59) return null;
  return TimeOfDay(hour: h, minute: min);
}

final learnerSettingsProvider = AsyncNotifierProvider<LearnerSettingsController, LearnerSettings>(
  LearnerSettingsController.new,
);

class LearnerSettingsController extends AsyncNotifier<LearnerSettings> {
  @override
  Future<LearnerSettings> build() => LearnerSettings.load(ref.watch(progressStoreProvider));

  Future<void> change(LearnerSettings Function(LearnerSettings s) edit) async {
    final old = state.value ?? await future;
    final next = edit(old);
    if (next == old) return;
    state = AsyncData(next);
    await next.save(ref.read(progressStoreProvider), old: old);
  }
}

/// Typing ("challenge") mode is on.
final typingModeProvider = Provider<bool>(
  (ref) => ref.watch(learnerSettingsProvider.select((s) => s.value?.typing ?? false)),
);

/// Handwriting is the chosen answer input (whether it can run here is
/// `inkModeProvider`, in `ui/ink/ink_providers.dart`).
final handwritingPrefProvider = Provider<bool>(
  (ref) => ref.watch(learnerSettingsProvider.select((s) => s.value?.handwriting ?? false)),
);

/// The daily XP goal (0 = off).
final dailyGoalXpProvider = Provider<int>(
  (ref) => ref.watch(learnerSettingsProvider.select((s) => s.value?.dailyGoalXp ?? kDefaultDailyGoalXp)),
);

String dailyGoalLabel(int xp) => xp == 0 ? 'Off' : '$xp XP';
