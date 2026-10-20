/// [InkRecognizer] over Google ML Kit Digital Ink Recognition
/// (`google_mlkit_digital_ink_recognition`): on-device, one model per
/// language (about 20 MB, downloaded once, then offline).
library;

import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import 'ink_recognizer.dart';

/// Whether ML Kit runs on this platform (Android and iOS; not web or desktop).
bool get mlKitInkPlatform =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

class MlKitInkRecognizer implements InkRecognizer {
  MlKitInkRecognizer();

  final _models = mlkit.DigitalInkRecognizerModelManager();
  final Map<String, mlkit.DigitalInkRecognizer> _recognizers = {};

  @override
  bool get platformSupported => mlKitInkPlatform;

  @override
  Future<InkModelStatus> modelStatus(String tag) async {
    if (!platformSupported) return InkModelStatus.unsupported;
    try {
      return await _models.isModelDownloaded(tag) ? InkModelStatus.ready : InkModelStatus.missing;
    } on PlatformException catch (e) {
      // "Failed to create model identifier" / "No model was found": ML Kit
      // has no model for this tag.
      final what = '${e.code} ${e.message}'.toLowerCase();
      if (what.contains('identifier') || what.contains('no model')) {
        return InkModelStatus.unsupported;
      }
      rethrow;
    }
  }

  @override
  Future<void> downloadModel(String tag) async {
    // Wi-Fi is not required (the UI suggests it); the download resumes in
    // the background if the app is closed (ML Kit's model manager).
    final ok = await _models.downloadModel(tag, isWifiRequired: false);
    if (!ok) throw StateError('Model $tag was not downloaded');
  }

  @override
  Future<void> deleteModel(String tag) async {
    await _recognizers.remove(tag)?.close();
    await _models.deleteModel(tag);
  }

  @override
  Future<List<String>> recognize(List<InkStroke> strokes, String tag, {String? preContext, Size? area}) async {
    final ink = mlkit.Ink()
      ..strokes = [
        for (final s in strokes)
          if (s.isNotEmpty) mlkit.Stroke()..points = [for (final p in s) mlkit.StrokePoint(x: p.x, y: p.y, t: p.t)],
      ];
    if (ink.strokes.isEmpty) return const [];
    final r = _recognizers[tag] ??= mlkit.DigitalInkRecognizer(languageCode: tag);
    final pre = preContext == null || preContext.isEmpty
        ? null
        : preContext.substring(preContext.length > 20 ? preContext.length - 20 : 0);
    final context = mlkit.DigitalInkRecognitionContext(
      preContext: pre,
      writingArea: area == null ? null : mlkit.WritingArea(width: area.width, height: area.height),
    );
    final candidates = await r.recognize(ink, context: context);
    return [for (final c in candidates) if (c.text.trim().isNotEmpty) c.text.trim()];
  }
}
