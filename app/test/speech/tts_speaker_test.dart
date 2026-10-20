// TtsSpeaker over a recording FlutterTts: the set-up order (speech on the
// media stream before anything else), the voice choice (installed voices
// only), "not installed" found while speaking, uncached failures; the voice
// notice rules; the sound effects' audio context.
import 'package:audioplayers/audioplayers.dart';
import 'package:tosk/audio/sound_service.dart';
import 'package:tosk/speech/speaker.dart';
import 'package:tosk/speech/speech_providers.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../ui/helpers.dart' show TestProgressStore;

Map<String, String> _voice(String name, String locale, {bool network = false, bool notInstalled = false}) => {
  'name': name,
  'locale': locale,
  'quality': 'normal',
  'latency': 'normal',
  'network_required': network ? '1' : '0',
  'features': notInstalled ? 'networkTimeoutMs\tnotInstalled' : 'networkTimeoutMs',
};

/// Records every engine call in order; answers like the Android plugin.
class RecordingTts extends FlutterTts {
  RecordingTts({this.voices = const [], this.languages = const [], this.available = true});

  List<Map<String, String>> voices;
  List<String> languages;
  bool available;
  Object? voicesError;
  Object? languagesError;
  int speakResult = 1;
  final List<String> calls = [];

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async =>
      calls.add('awaitSpeakCompletion($awaitCompletion)');

  @override
  Future<dynamic> setAudioAttributes({required int usage, required int contentType}) async =>
      calls.add('setAudioAttributes($usage, $contentType)');

  @override
  Future<dynamic> setSharedInstance(bool sharedSession) async => calls.add('setSharedInstance($sharedSession)');

  @override
  Future<dynamic> setIosAudioCategory(
    IosTextToSpeechAudioCategory category,
    List<IosTextToSpeechAudioCategoryOptions> options, [
    IosTextToSpeechAudioMode mode = IosTextToSpeechAudioMode.defaultMode,
  ]) async => calls.add('setIosAudioCategory(${category.name}, ${options.map((o) => o.name).join(',')})');

  @override
  Future<dynamic> get getVoices async {
    calls.add('getVoices');
    if (voicesError != null) throw voicesError!;
    return voices;
  }

  @override
  Future<dynamic> get getLanguages async {
    calls.add('getLanguages');
    if (languagesError != null) throw languagesError!;
    return languages;
  }

  @override
  Future<dynamic> isLanguageAvailable(String language) async {
    calls.add('isLanguageAvailable($language)');
    return available;
  }

  @override
  Future<SpeechRateValidRange> get getSpeechRateValidRange async =>
      SpeechRateValidRange(0, 0.5, 1.5, TextToSpeechPlatform.android);

  @override
  Future<dynamic> stop() async => calls.add('stop');

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    calls.add('setVoice(${voice['name']})');
    return 1;
  }

  @override
  Future<dynamic> setLanguage(String language) async {
    calls.add('setLanguage($language)');
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async => calls.add('setSpeechRate($rate)');

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    calls.add('speak($text)');
    return speakResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('voice choice', () {
    test('voice maps parse features and the network flag', () {
      final v = TtsVoice.fromMap(_voice('it-it-x-kda-network', 'it-IT', network: true, notInstalled: true))!;
      expect(v.network, isTrue);
      expect(v.notInstalled, isTrue);
      expect(TtsVoice.fromMap({'name': '', 'locale': 'it-IT'}), isNull);
      expect(TtsVoice.fromMap('nope'), isNull);
    });

    test('installed voices only; on-device before network; the preferred region', () {
      TtsVoice v(String n, String l, {bool net = false, bool missing = false}) =>
          TtsVoice(name: n, locale: l, network: net, notInstalled: missing);
      final pick = pickVoice('it', [
        v('it-ch-local', 'it-CH'),
        v('it-it-network', 'it-IT', net: true),
        v('it-it-local', 'it-IT'),
        v('en-gb-local', 'en-GB'),
      ]);
      expect(pick.status, VoiceStatus.ready);
      expect(pick.voice!.name, 'it-it-local');
      // Only a network voice installed: use it.
      expect(pickVoice('it', [v('a', 'it-IT', net: true)]).voice!.name, 'a');
      // Listed, but no data on the device.
      final none = pickVoice('nl', [v('nl-nl-x-a', 'nl-NL', missing: true), v('en', 'en-US')]);
      expect(none.status, VoiceStatus.notInstalled);
      expect(none.voice, isNull);
      // Installed in another region only.
      expect(pickVoice('nl', [v('x', 'nl-NL', missing: true), v('y', 'nl-BE')]).voice!.name, 'y');
      // No voice for the language at all (Sarnami).
      expect(pickVoice('hns', [v('hi', 'hi-IN')]).status, VoiceStatus.missing);
    });
  });

  group('TtsSpeaker on Android', () {
    test('set-up first: wait for completion and speech on the media stream, then the voices', () async {
      final tts = RecordingTts(voices: [_voice('it-it-x-itb-local', 'it-IT')]);
      final s = TtsSpeaker(tts: tts, platform: TtsPlatform.android);
      expect(await s.voiceStatus('it'), VoiceStatus.ready);
      expect(tts.calls, [
        'awaitSpeakCompletion(true)',
        'setAudioAttributes($kAndroidUsageMedia, $kAndroidContentTypeSpeech)',
        'getVoices',
      ]);
      expect(kAndroidUsageMedia, 1, reason: 'AudioAttributes.USAGE_MEDIA');
      expect(kAndroidContentTypeSpeech, 1, reason: 'AudioAttributes.CONTENT_TYPE_SPEECH');
    });

    test('speaking before any check still sets up first, then picks the installed voice', () async {
      final tts = RecordingTts(
        voices: [_voice('it-it-x-kda-network', 'it-IT', notInstalled: true), _voice('it-it-x-itb-local', 'it-IT')],
      );
      final s = TtsSpeaker(tts: tts, platform: TtsPlatform.android);
      await s.speak('Ciao', 'it');
      expect(tts.calls, [
        'awaitSpeakCompletion(true)',
        'setAudioAttributes(1, 1)',
        'getVoices',
        'stop',
        'setVoice(it-it-x-itb-local)',
        'setSpeechRate(0.5)',
        'speak(Ciao)',
      ]);
      // Set-up and voice happen once.
      tts.calls.clear();
      await s.speak('Grazie', 'it', slow: true);
      expect(tts.calls, ['stop', 'setSpeechRate(0.3)', 'speak(Grazie)']);
    });

    test('a listed voice without its data: not installed, and nothing is spoken', () async {
      final tts = RecordingTts(voices: [_voice('nl-nl-x-lfc-local', 'nl-NL', notInstalled: true)]);
      final s = TtsSpeaker(tts: tts, platform: TtsPlatform.android);
      expect(await s.voiceStatus('nl'), VoiceStatus.notInstalled);
      await s.speak('Hallo', 'nl');
      expect(tts.calls.where((c) => c.startsWith('speak')), isEmpty);
    });

    test('"not installed" while speaking: the voice is dropped and the app is told', () async {
      final tts = RecordingTts(voices: [_voice('it-it-x-itb-local', 'it-IT')])..speakResult = kTtsErrorNotInstalled;
      final problems = <(String, VoiceStatus)>[];
      final s = TtsSpeaker(tts: tts, platform: TtsPlatform.android, onVoiceProblem: (l, st) => problems.add((l, st)));
      expect(await s.voiceStatus('it'), VoiceStatus.ready);
      await s.speak('Ciao', 'it');
      expect(problems, [('it', VoiceStatus.notInstalled)]);
      expect(await s.voiceStatus('it'), VoiceStatus.notInstalled);
      // Other engine errors (e.g. network) don't drop the voice.
      final tts2 = RecordingTts(voices: [_voice('it-it-x-itb-local', 'it-IT')])..speakResult = -6;
      final s2 = TtsSpeaker(tts: tts2, platform: TtsPlatform.android, onVoiceProblem: (l, st) => problems.add((l, st)));
      await s2.speak('Ciao', 'it');
      expect(problems, hasLength(1));
      expect(await s2.voiceStatus('it'), VoiceStatus.ready);
    });

    test('no voice list: falls back to the languages and isLanguageAvailable', () async {
      final tts = RecordingTts(languages: ['it-IT', 'en-US']);
      final s = TtsSpeaker(tts: tts, platform: TtsPlatform.android);
      expect(await s.voiceStatus('it'), VoiceStatus.ready);
      expect(tts.calls, containsAllInOrder(['getVoices', 'getLanguages', 'isLanguageAvailable(it-IT)']));
      await s.speak('Ciao', 'it');
      expect(tts.calls, contains('setLanguage(it-IT)'));
      tts.available = false;
      final s2 = TtsSpeaker(tts: tts, platform: TtsPlatform.android);
      expect(await s2.voiceStatus('it'), VoiceStatus.notInstalled);
      expect(await s2.voiceStatus('hns'), VoiceStatus.missing);
    });

    test('an engine that does not answer yet is asked again later (not cached)', () async {
      final tts = RecordingTts(voices: [_voice('it-it-x-itb-local', 'it-IT')])
        ..voicesError = StateError('not bound')
        ..languagesError = StateError('not bound');
      final s = TtsSpeaker(tts: tts, platform: TtsPlatform.android);
      expect(await s.voiceStatus('it'), VoiceStatus.unavailable);
      await pumpEventQueue();
      tts
        ..voicesError = null
        ..languagesError = null;
      expect(await s.voiceStatus('it'), VoiceStatus.ready);
      expect(tts.calls.where((c) => c == 'awaitSpeakCompletion(true)'), hasLength(1), reason: 'set-up runs once');
    });
  });

  test('TtsSpeaker on iOS: the shared playback session, mixing with other audio, before the languages', () async {
    final tts = RecordingTts(languages: ['it-IT']);
    final s = TtsSpeaker(tts: tts, platform: TtsPlatform.ios);
    expect(await s.voiceStatus('it'), VoiceStatus.ready);
    expect(tts.calls, [
      'awaitSpeakCompletion(true)',
      'setSharedInstance(true)',
      'setIosAudioCategory(playback, mixWithOthers)',
      'getLanguages',
    ]);
  });

  test('TtsSpeaker elsewhere (web, macOS): no platform audio set-up', () async {
    final tts = RecordingTts(languages: ['it-IT']);
    final s = TtsSpeaker(tts: tts, platform: TtsPlatform.other);
    expect(await s.voiceStatus('it'), VoiceStatus.ready);
    expect(tts.calls, ['awaitSpeakCompletion(true)', 'getLanguages']);
  });

  group('voice notice', () {
    test('only on Android; not installed, or missing for a two-letter language', () {
      expect(
        voiceNoticeFor('it', VoiceStatus.notInstalled, android: true)!.message,
        contains('Install an Italian voice in Android text-to-speech settings'),
      );
      expect(voiceNoticeFor('nl', VoiceStatus.missing, android: true)!.languageName, 'Dutch');
      expect(
        voiceNoticeFor('hns', VoiceStatus.missing, android: true),
        isNull,
        reason: 'Sarnami has no voice anywhere',
      );
      expect(voiceNoticeFor('hns', VoiceStatus.notInstalled, android: true), isNotNull);
      expect(voiceNoticeFor('it', VoiceStatus.ready, android: true), isNull);
      expect(voiceNoticeFor('it', VoiceStatus.unavailable, android: true), isNull);
      expect(voiceNoticeFor('it', VoiceStatus.notInstalled, android: false), isNull);
    });

    test('shown once per language (device-only setting)', () async {
      final store = TestProgressStore();
      expect(await claimVoiceNotice(store, 'it'), isTrue);
      expect(await claimVoiceNotice(store, 'it'), isFalse);
      expect(await claimVoiceNotice(store, 'nl'), isTrue);
      expect(await store.getSetting(SettingKeys.voiceNoticeShown), 'it,nl');
      expect(SettingKeys.all, isNot(contains(SettingKeys.voiceNoticeShown)));
    });
  });

  test('sound effects play on the media stream without taking focus; iOS playback mixing', () {
    final android = kSfxAudioContext.android;
    expect(android.usageType, AndroidUsageType.media);
    expect(android.contentType, AndroidContentType.sonification);
    expect(android.audioFocus, AndroidAudioFocus.none);
    final ios = kSfxAudioContext.iOS;
    expect(ios.category, AVAudioSessionCategory.playback);
    expect(ios.options, {AVAudioSessionOptions.mixWithOthers});
  });
}
