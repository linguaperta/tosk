import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'interop_types.dart';

enum TtsState { playing, stopped, paused, continued }

class FlutterTtsPlugin {
  static const String platformChannel = "flutter_tts";
  static late MethodChannel channel;
  bool awaitSpeakCompletion = false;

  TtsState ttsState = TtsState.stopped;

  Completer<dynamic>? _speechCompleter;

  bool get isPlaying => ttsState == TtsState.playing;

  bool get isStopped => ttsState == TtsState.stopped;

  bool get isPaused => ttsState == TtsState.paused;

  bool get isContinued => ttsState == TtsState.continued;

  static void registerWith(Registrar registrar) {
    channel =
        MethodChannel(platformChannel, const StandardMethodCodec(), registrar);
    final instance = FlutterTtsPlugin();
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  // tosk patch: a new utterance for every speak(), with the settings
  // kept here. Upstream reused one utterance and only marked it stopped when
  // the browser's (asynchronous) cancel event arrived, so a speak() right
  // after stop() (a replay, the next exercise) was dropped and its awaited
  // future never completed; a cancelled utterance's error also dropped the
  // pending completer instead of completing it. Events of an utterance that
  // is no longer the current one are ignored now.
  SpeechSynthesisUtterance? _current;
  SpeechSynthesisVoice? _voice;
  String? _lang;
  double _rate = 1.0;
  double _volume = 1.0;
  double _pitch = 1.0;
  List<SpeechSynthesisVoice> voices = [];
  List<String> languages = [];
  Timer? t;
  bool supported = false;

  FlutterTtsPlugin() {
    try {
      SpeechSynthesisUtterance();
      supported = true;
    } catch (e) {
      print('Initialization of TTS failed. Functions are disabled. Error: $e');
    }
  }

  /// Completes the awaited speak(), if any.
  void _complete() {
    final c = _speechCompleter;
    _speechCompleter = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  SpeechSynthesisUtterance _newUtterance(String text) {
    final utterance = SpeechSynthesisUtterance();
    utterance.text = text;
    if (_voice != null) utterance.voice = _voice;
    if (_lang != null) utterance.lang = _lang!;
    utterance.rate = _rate;
    utterance.volume = _volume;
    utterance.pitch = _pitch;
    bool current() => identical(_current, utterance);

    utterance.onStart = (JSAny e) {
      if (!current()) return;
      ttsState = TtsState.playing;
      channel.invokeMethod("speak.onStart", null);
      var bLocal = (utterance.voice?.isLocalService ?? false);
      if (!bLocal) {
        t?.cancel();
        t = Timer.periodic(Duration(seconds: 14), (t) {
          if (current() && ttsState == TtsState.playing) {
            synth.pause();
            synth.resume();
          } else {
            t.cancel();
          }
        });
      }
    }.toJS;
    utterance.onEnd = (JSAny e) {
      if (!current()) return;
      _current = null;
      ttsState = TtsState.stopped;
      t?.cancel();
      _complete();
      channel.invokeMethod("speak.onComplete", null);
    }.toJS;

    utterance.onPause = (JSAny e) {
      if (!current()) return;
      ttsState = TtsState.paused;
      channel.invokeMethod("speak.onPause", null);
    }.toJS;

    utterance.onResume = (JSAny e) {
      if (!current()) return;
      ttsState = TtsState.continued;
      channel.invokeMethod("speak.onContinue", null);
    }.toJS;

    utterance.onError = (JSObject event) {
      if (!current()) return;
      _current = null;
      ttsState = TtsState.stopped;
      t?.cancel();
      _complete();
      final error = event["error"];
      channel.invokeMethod("speak.onError", error.isA<JSString>() ? (error as JSString).toDart : '$error');
    }.toJS;

    utterance.onBoundary = (JSObject event) {
      if (!current()) return;
      final charIndex = event['charIndex'];
      final name = event['name'];
      if (!charIndex.isA<JSNumber>()) return;
      if (name.isA<JSString>() && (name as JSString).toDart == 'sentence') return;
      final start = (charIndex as JSNumber).toDartInt;
      if (start > text.length) return;
      int endIndex = start;
      while (endIndex < text.length && !RegExp(r'[\s,.!?]').hasMatch(text[endIndex])) {
        endIndex++;
      }
      String word = text.substring(start, endIndex);
      Map<String, dynamic> progressArgs = {
        'text': text,
        'start': start,
        'end': endIndex,
        'word': word
      };
      channel.invokeMethod("speak.onProgress", progressArgs);
    }.toJS;
    return utterance;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    if (!supported) return;
    switch (call.method) {
      case 'speak':
        final text = call.arguments as String?;
        // tosk patch: a speak() still waiting is done (replaced).
        _complete();
        if (awaitSpeakCompletion) {
          _speechCompleter = Completer();
        }
        final future = _speechCompleter?.future;
        _speak(text);
        if (awaitSpeakCompletion) {
          return future;
        }
        break;
      case 'awaitSpeakCompletion':
        awaitSpeakCompletion = (call.arguments as bool?) ?? false;
        return 1;
      case 'stop':
        _stop();
        return 1;
      case 'pause':
        _pause();
        return 1;
      case 'setLanguage':
        final language = call.arguments as String;
        _setLanguage(language);
        return 1;
      case 'getLanguages':
        return _getLanguages();
      case 'getVoices':
        return getVoices();
      case 'setVoice':
        final tmpVoiceMap =
            Map<String, String>.from(call.arguments as LinkedHashMap);
        return _setVoice(tmpVoiceMap);
      case 'setSpeechRate':
        final rate = call.arguments as double;
        _setRate(rate);
        return 1;
      case 'setVolume':
        final volume = call.arguments as double;
        _setVolume(volume);
        return 1;
      case 'setPitch':
        final pitch = call.arguments as double;
        _setPitch(pitch);
        return 1;
      case 'isLanguageAvailable':
        final lang = call.arguments as String;
        return _isLanguageAvailable(lang);
      default:
        throw PlatformException(
            code: 'Unimplemented',
            details: "The flutter_tts plugin for web doesn't implement "
                "the method '${call.method}'");
    }
  }

  void _speak(String? text) {
    if (text == null || text.isEmpty) {
      _complete();
      return;
    }
    if (ttsState == TtsState.paused && _current != null) {
      synth.resume();
      return;
    }
    // tosk patch: whatever is still speaking is cancelled first.
    _cancelCurrent();
    final utterance = _newUtterance(text);
    _current = utterance;
    ttsState = TtsState.playing;
    synth.speak(utterance);
  }

  void _cancelCurrent() {
    if (_current == null && ttsState == TtsState.stopped) return;
    _current = null;
    ttsState = TtsState.stopped;
    t?.cancel();
    synth.cancel();
  }

  void _stop() {
    _cancelCurrent();
    _complete();
  }

  void _pause() {
    if (ttsState == TtsState.playing || ttsState == TtsState.continued) {
      synth.pause();
    }
  }

  void _setRate(double rate) => _rate = rate;
  void _setVolume(double volume) => _volume = volume;
  void _setPitch(double pitch) => _pitch = pitch;
  void _setLanguage(String language) {
    var targetList = synth.getVoices().toDart.where((e) {
      return e.lang.toLowerCase().startsWith(language.toLowerCase());
    });
    if (targetList.isNotEmpty) {
      _voice = targetList.first;
      _lang = targetList.first.lang;
    }
  }

  void _setVoice(Map<String?, String?> voice) {
    var tmpVoices = synth.getVoices().toDart;
    var targetList = tmpVoices.where((e) {
      return voice["name"] == e.name && voice["locale"] == e.lang;
    });
    if (targetList.isNotEmpty) {
      _voice = targetList.first;
      _lang = targetList.first.lang;
    }
  }

  bool _isLanguageAvailable(String? language) {
    if (voices.isEmpty) _setVoices();
    if (languages.isEmpty) _setLanguages();
    for (var lang in languages) {
      if (!language!.contains('-')) {
        lang = lang.split('-').first;
      }
      if (lang.toLowerCase() == language.toLowerCase()) return true;
    }
    return false;
  }

  List<String?>? _getLanguages() {
    if (voices.isEmpty) _setVoices();
    if (languages.isEmpty) _setLanguages();
    return languages;
  }

  void _setVoices() {
    voices = synth.getVoices().toDart;
  }

  Future<List<Map<String, String>>> getVoices() async {
    var tmpVoices = synth.getVoices().toDart;
    return tmpVoices
        .map((voice) => {"name": voice.name, "locale": voice.lang})
        .toList();
  }

  void _setLanguages() {
    var langs = <String>{};
    for (var v in voices) {
      langs.add(v.lang);
    }

    languages = langs.toList();
  }
}
