/// Handwriting recognition (v0.5): strokes in, text candidates out.
///
/// [InkRecognizer] is the seam between the writing pad (`ui/ink/`) and the
/// recognizer: `MlKitInkRecognizer` (Google ML Kit Digital Ink, on-device,
/// Android and iOS) in the app, fakes in tests. Pure Dart apart from the
/// geometry types.
library;

import 'dart:ui' show Size;

import 'package:meta/meta.dart';

/// One sampled point of a stroke, in logical pixels relative to the writing
/// area, with a timestamp in milliseconds.
@immutable
class InkPoint {
  const InkPoint(this.x, this.y, this.t);
  final double x;
  final double y;
  final int t;

  @override
  bool operator ==(Object other) => other is InkPoint && other.x == x && other.y == y && other.t == t;
  @override
  int get hashCode => Object.hash(x, y, t);
  @override
  String toString() => '($x, $y @$t)';
}

/// Pen down to pen up.
typedef InkStroke = List<InkPoint>;

/// State of the recognition model for one language.
enum InkModelStatus {
  /// Not known yet (being checked).
  checking,

  /// The recognizer has no model for this language (or the platform has no
  /// recognizer at all).
  unsupported,

  /// Supported, not on the device yet: needs a download (about 20 MB).
  missing,

  /// Downloading.
  downloading,

  /// On the device: recognition works offline.
  ready,

  /// The check or the download failed (offline, storage); can be retried.
  error,
}

/// Recognizes handwriting on the device.
abstract interface class InkRecognizer {
  /// Whether the platform has a recognizer at all (ML Kit: Android and iOS).
  bool get platformSupported;

  /// [InkModelStatus.ready], [InkModelStatus.missing] or
  /// [InkModelStatus.unsupported] for the model [tag] (a BCP-47 tag from
  /// [inkLanguageTags]). Throws when the check itself fails.
  Future<InkModelStatus> modelStatus(String tag);

  /// Downloads the model [tag]; completes when it is on the device. Throws
  /// on failure. ML Kit reports no byte progress, so the UI shows an
  /// indeterminate indicator.
  Future<void> downloadModel(String tag);

  /// Deletes the model [tag] (Settings, to free space).
  Future<void> deleteModel(String tag);

  /// Recognizes [strokes] with the model [tag]; candidates best first (may
  /// be empty). [preContext] is the text just before the writing (the words
  /// before a gap, a verb stem), which helps the language model; [area] is
  /// the writing area's size in the strokes' units.
  Future<List<String>> recognize(List<InkStroke> strokes, String tag, {String? preContext, Size? area});
}

/// No recognizer (web, desktop, tests without a fake).
class UnavailableInkRecognizer implements InkRecognizer {
  const UnavailableInkRecognizer();
  @override
  bool get platformSupported => false;
  @override
  Future<InkModelStatus> modelStatus(String tag) async => InkModelStatus.unsupported;
  @override
  Future<void> downloadModel(String tag) async => throw UnsupportedError('No handwriting recognizer on this platform');
  @override
  Future<void> deleteModel(String tag) async {}
  @override
  Future<List<String>> recognize(List<InkStroke> strokes, String tag, {String? preContext, Size? area}) async => const [];
}

/// Recognition models to try for a course's target language, best first.
///
/// ML Kit Digital Ink names its models by BCP-47 tag. Most course languages
/// map to themselves (`it`, `nl`, `es`, `fr`, `sv`, `da`); a few need a
/// region or another tag. **Sarnami (`hns`)** has no model: it is written in
/// a Latin script with Dutch spelling conventions (`toe`, `oe`, `hamlog`,
/// `pahiela`), so the Dutch model (`nl`) is used. It recognizes the plain
/// letters well but never produces the course's special letters (`ṯ ḏ ṟ ã õ`);
/// with lenient accents (the default) such an answer is still accepted as an
/// accent slip ("watch the accent"), with strict accents it is wrong, so
/// Sarnami learners who want strict grading should type instead.
List<String> inkLanguageTags(String target) {
  final t = target.toLowerCase();
  return switch (t) {
    'hns' => const ['nl'],
    'pt' => const ['pt-PT', 'pt-BR', 'pt'],
    'nb' || 'no' => const ['nb', 'no'],
    'en' => const ['en-US', 'en'],
    _ => [t],
  };
}
