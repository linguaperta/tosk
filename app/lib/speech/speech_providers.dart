/// Riverpod wiring of text-to-speech (v0.5).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/test_env.dart';
import '../core/core.dart' show ProgressStore;
import '../providers.dart' show courseDataProvider;
import '../ui/settings/learner_settings.dart';
import '../ui/settings/setting_keys.dart';
import 'speaker.dart';

/// The speaker: `flutter_tts`, or silent under `flutter test` (tests
/// override it with a fake). When speaking reveals that a voice isn't
/// installed after all, the course's voice status is checked again.
final Provider<Speaker> speakerProvider = Provider<Speaker>((ref) {
  final Speaker s = runningInFlutterTest
      ? const NullSpeaker()
      : TtsSpeaker(
          onVoiceProblem: (_, _) {
            try {
              ref.invalidate(courseVoiceStatusProvider);
            } catch (_) {} // the speaker was replaced meanwhile
          },
        );
  ref.onDispose(() => s.stop());
  return s;
});

/// Whether the active course's target language can be spoken here.
final FutureProvider<VoiceStatus> courseVoiceStatusProvider = FutureProvider<VoiceStatus>((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  final speaker = ref.watch(speakerProvider);
  try {
    return await speaker.voiceStatus(course.meta.target).timeout(const Duration(seconds: 5));
  } catch (_) {
    return VoiceStatus.unavailable;
  }
});

/// Whether the device has a voice for the active course's target language
/// (false while unknown, and for Sarnami, which has no voice).
final courseVoiceProvider = FutureProvider<bool>(
  (ref) async => await ref.watch(courseVoiceStatusProvider.future) == VoiceStatus.ready,
);

/// Pronounce buttons are shown (a voice for the course language).
final canPronounceProvider = Provider<bool>((ref) => ref.watch(courseVoiceProvider).value ?? false);

/// The voice for the course language was found missing (not installed) on
/// this device: running sessions skip their listening exercises.
final voiceNotInstalledProvider = Provider<bool>(
  (ref) => ref.watch(courseVoiceStatusProvider).value == VoiceStatus.notInstalled,
);

/// English names of languages a TTS engine may offer (the voice notice).
const Map<String, String> kVoiceLanguageNames = {
  'it': 'Italian',
  'nl': 'Dutch',
  'es': 'Spanish',
  'pt': 'Portuguese',
  'fr': 'French',
  'de': 'German',
  'en': 'English',
  'sv': 'Swedish',
  'da': 'Danish',
  'nb': 'Norwegian',
  'no': 'Norwegian',
  'eo': 'Esperanto',
};

/// A hint that the learner can install a voice for [languageCode].
@immutable
class VoiceNotice {
  const VoiceNotice(this.languageCode, this.status);
  final String languageCode;
  final VoiceStatus status;

  String get languageName => kVoiceLanguageNames[languageCode] ?? languageCode;

  /// "a Dutch voice", "an Italian voice".
  String get aVoice => '${'aeiouAEIOU'.contains(languageName[0]) ? 'an' : 'a'} $languageName voice';

  /// The one-time snack bar (short: it must fit small phones at large text).
  String get message => 'No sound? Install $aVoice in Android text-to-speech settings.';

  @override
  bool operator ==(Object other) =>
      other is VoiceNotice && other.languageCode == languageCode && other.status == status;

  @override
  int get hashCode => Object.hash(languageCode, status);
}

/// The notice for [status] of [languageCode] on [platform], or null: only on
/// Android (where the learner can install voices), when the engine lists the
/// language without its data, or has no voice for a major language (a
/// two-letter code; Sarnami `hns` has no voice anywhere, so no nagging).
VoiceNotice? voiceNoticeFor(String languageCode, VoiceStatus status, {required bool android}) {
  if (!android) return null;
  return switch (status) {
    VoiceStatus.notInstalled => VoiceNotice(languageCode, status),
    VoiceStatus.missing when languageCode.length == 2 => VoiceNotice(languageCode, status),
    _ => null,
  };
}

/// Whether this is Android (overridable in tests).
final isAndroidProvider = Provider<bool>((ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android);

/// The voice notice for the active course (Settings → Challenge shows it;
/// the app shows it once per language as a snack bar).
final voiceNoticeProvider = Provider<VoiceNotice?>((ref) {
  final course = ref.watch(courseDataProvider).value;
  final status = ref.watch(courseVoiceStatusProvider).value;
  if (course == null || status == null) return null;
  return voiceNoticeFor(course.meta.target, status, android: ref.watch(isAndroidProvider));
});

/// Languages whose voice notice was shown (device-only, comma-separated in
/// [SettingKeys.voiceNoticeShown]).
Set<String> parseShownNotices(String? raw) => {
  for (final s in (raw ?? '').split(','))
    if (s.trim().isNotEmpty) s.trim(),
};

/// Marks [languageCode]'s notice as shown; true when it hadn't been (show it
/// now), false when it was shown before.
Future<bool> claimVoiceNotice(ProgressStore store, String languageCode) async {
  final shown = parseShownNotices(await store.getSetting(SettingKeys.voiceNoticeShown));
  if (shown.contains(languageCode)) return false;
  await store.setSetting(SettingKeys.voiceNoticeShown, ({...shown, languageCode}.toList()..sort()).join(','));
  return true;
}

/// "Can't listen right now": listening exercises are skipped until this time
/// (in memory; an app restart ends the snooze).
class ListenSnooze extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  static const duration = Duration(hours: 1);

  void snooze([Duration d = duration]) => state = DateTime.now().add(d);

  bool get active => state != null && DateTime.now().isBefore(state!);
}

final listenSnoozeProvider = NotifierProvider<ListenSnooze, DateTime?>(ListenSnooze.new);

/// Listening exercises may be generated: a voice, not switched off in
/// Settings ("Listening exercises"), and not snoozed ("Can't listen now").
final listeningProvider = Provider<bool>((ref) {
  final until = ref.watch(listenSnoozeProvider);
  final snoozed = until != null && DateTime.now().isBefore(until);
  return !snoozed &&
      ref.watch(canPronounceProvider) &&
      ref.watch(learnerSettingsProvider.select((s) => s.value?.listening ?? true));
});
