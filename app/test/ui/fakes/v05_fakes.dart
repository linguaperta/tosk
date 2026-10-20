/// Test fakes for v0.5: the handwriting recognizer (ML Kit), text-to-speech,
/// the ONYX device, its e-ink screen and the Onyx pen surface.
library;

import 'dart:async';
import 'dart:ui' show Rect, Size;

import 'package:tosk/device/device_info.dart';
import 'package:tosk/device/device_providers.dart';
import 'package:tosk/device/onyx.dart';
import 'package:tosk/ink/ink_recognizer.dart';
import 'package:tosk/speech/speaker.dart';
import 'package:tosk/speech/speech_providers.dart';
import 'package:tosk/ui/ink/ink_providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// A recognizer whose models and readings the test sets.
class FakeInkRecognizer implements InkRecognizer {
  FakeInkRecognizer({this.status = InkModelStatus.ready, List<String>? reading, this.supportedTags})
      : reading = reading ?? const ['ciao'];

  /// Status of every supported model until downloaded.
  InkModelStatus status;

  /// Candidates returned for any ink (best first); [readings] wins when set.
  List<String> reading;

  /// Readings returned one after the other (then [reading]).
  final List<List<String>> readings = [];

  /// Tags with a model (null: all).
  final Set<String>? supportedTags;

  /// Completes downloads when set (else they finish at once).
  Completer<void>? downloadGate;
  final List<String> downloads = [];

  /// (stroke count, preContext, tag) per recognition.
  final List<(int, String?, String)> calls = [];
  final List<List<InkStroke>> inks = [];

  @override
  bool get platformSupported => true;

  @override
  Future<InkModelStatus> modelStatus(String tag) async {
    if (supportedTags != null && !supportedTags!.contains(tag)) return InkModelStatus.unsupported;
    return status;
  }

  @override
  Future<void> downloadModel(String tag) async {
    downloads.add(tag);
    final gate = downloadGate;
    if (gate != null) await gate.future;
    status = InkModelStatus.ready;
  }

  @override
  Future<void> deleteModel(String tag) async => status = InkModelStatus.missing;

  @override
  Future<List<String>> recognize(List<InkStroke> strokes, String tag, {String? preContext, Size? area}) async {
    calls.add((strokes.length, preContext, tag));
    inks.add([for (final s in strokes) List.of(s)]);
    return readings.isNotEmpty ? readings.removeAt(0) : reading;
  }
}

/// A speaker with voices for [languages]; records what it says.
class FakeSpeaker implements Speaker {
  FakeSpeaker({this.languages = const {'it', 'nl'}, this.statuses = const {}});
  final Set<String> languages;
  final List<(String, String, bool)> spoken = [];

  @override
  Future<VoiceStatus> voiceStatus(String languageCode) async =>
      languages.contains(languageCode) ? VoiceStatus.ready : (statuses[languageCode] ?? VoiceStatus.missing);

  /// Statuses of languages without a voice (default: missing).
  final Map<String, VoiceStatus> statuses;

  @override
  Future<void> speak(String text, String languageCode, {bool slow = false}) async {
    if (languages.contains(languageCode)) spoken.add((text, languageCode, slow));
  }

  @override
  Future<void> stop() async {}
}

class FakeEinkScreen implements EinkScreen {
  int refreshes = 0;
  @override
  bool get supported => true;
  @override
  Future<bool> fullRefresh() async {
    refreshes++;
    return true;
  }
}

/// The Onyx pen surface: records calls; the test feeds strokes.
class FakePenSurface implements PenSurface {
  FakePenSurface({this.opens = true});
  bool opens;
  final List<String> log = [];
  Rect? rect;
  bool enabled = false;
  final _strokes = StreamController<PenPoints>.broadcast();
  final _erasures = StreamController<PenPoints>.broadcast();

  void emitStroke(PenPoints p) => _strokes.add(p);
  void emitErase(PenPoints p) => _erasures.add(p);

  @override
  Stream<PenPoints> get strokes => _strokes.stream;
  @override
  Stream<PenPoints> get erasures => _erasures.stream;

  @override
  Future<bool> open(Rect physicalRect, {double strokeWidth = 3}) async {
    log.add('open');
    if (!opens) return false;
    rect = physicalRect;
    enabled = true;
    return true;
  }

  @override
  Future<void> setRect(Rect physicalRect) async {
    log.add('setRect');
    rect = physicalRect;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    log.add('setEnabled($enabled)');
    this.enabled = enabled;
  }

  @override
  Future<void> clear() async => log.add('clear');

  @override
  Future<void> close() async {
    log.add('close');
    enabled = false;
  }
}

const onyxDevice = DeviceInfo(manufacturer: 'ONYX', brand: 'ONYX', model: 'NoteAir3');

/// Overrides for handwriting with [ink] (and optionally a voice and ONYX).
List<Override> v05Overrides({
  FakeInkRecognizer? ink,
  FakeSpeaker? speaker,
  bool onyx = false,
  FakeEinkScreen? eink,
  FakePenSurface? pen,
}) => [
  if (ink != null) inkRecognizerProvider.overrideWithValue(ink),
  if (speaker != null) speakerProvider.overrideWithValue(speaker),
  if (onyx) deviceInfoProvider.overrideWith((ref) async => onyxDevice),
  if (eink != null) einkScreenProvider.overrideWithValue(eink),
  if (onyx || pen != null) penSurfaceProvider.overrideWithValue(pen),
];
