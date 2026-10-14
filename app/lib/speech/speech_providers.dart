/// Riverpod wiring of text-to-speech (v0.5).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/test_env.dart';
import '../providers.dart' show courseDataProvider;
import '../ui/settings/learner_settings.dart';
import 'speaker.dart';

/// The speaker: `flutter_tts`, or silent under `flutter test` (tests
/// override it with a fake).
final speakerProvider = Provider<Speaker>((ref) {
  final Speaker s = runningInFlutterTest ? const NullSpeaker() : TtsSpeaker();
  ref.onDispose(() => s.stop());
  return s;
});

/// Whether the device has a voice for the active course's target language
/// (false while unknown, and for Sarnami, which has no voice).
final courseVoiceProvider = FutureProvider<bool>((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  final speaker = ref.watch(speakerProvider);
  try {
    return await speaker.canSpeak(course.meta.target).timeout(const Duration(seconds: 5));
  } catch (_) {
    return false;
  }
});

/// Pronounce buttons are shown (a voice for the course language).
final canPronounceProvider = Provider<bool>((ref) => ref.watch(courseVoiceProvider).value ?? false);

/// Listening exercises may be generated: a voice, and not switched off in
/// Settings ("Listening exercises").
final listeningProvider = Provider<bool>(
  (ref) =>
      ref.watch(canPronounceProvider) &&
      ref.watch(learnerSettingsProvider.select((s) => s.value?.listening ?? true)),
);
