/// Lesson focus presets: a weight per exercise type for mixed / vocab /
/// grammar lessons. The app loads `assets/config/focus_presets.json` and
/// passes the decoded JSON to [FocusPresets.fromJson]; the same defaults are
/// embedded here as a fallback (a test keeps both in sync).
library;

import 'dart:convert';

import '../core/interfaces/session.dart';
import '../core/models/progress.dart';

const Map<LessonFocus, Map<ExerciseType, double>> kDefaultFocusWeights = {
  LessonFocus.mixed: {
    ExerciseType.flashcard: 1.0,
    ExerciseType.multipleChoice: 1.0,
    ExerciseType.matchPairs: 0.8,
    ExerciseType.conjPick: 1.0,
    ExerciseType.conjGrid: 0.8,
    ExerciseType.sentenceBuilder: 1.0,
    ExerciseType.cloze: 1.0,
    ExerciseType.spotError: 0.7,
    ExerciseType.transform: 0.7,
  },
  LessonFocus.vocab: {
    ExerciseType.flashcard: 1.0,
    ExerciseType.multipleChoice: 1.0,
    ExerciseType.matchPairs: 1.0,
    ExerciseType.sentenceBuilder: 1.0,
  },
  LessonFocus.grammar: {
    ExerciseType.conjPick: 1.0,
    ExerciseType.conjGrid: 1.0,
    ExerciseType.cloze: 1.0,
    ExerciseType.transform: 1.0,
    ExerciseType.spotError: 1.0,
  },
};

class FocusPresets {
  const FocusPresets(this.weights);

  static const FocusPresets defaults = FocusPresets(kDefaultFocusWeights);

  final Map<LessonFocus, Map<ExerciseType, double>> weights;

  /// Parses `{"presets": {"mixed": {"flashcard": 1.0, ...}, ...}}` (a bare
  /// `{"mixed": {...}}` map works too). Unknown foci and exercise types are
  /// ignored; a focus missing from the JSON keeps its default weights.
  factory FocusPresets.fromJson(Map<String, dynamic> json) {
    final raw = json['presets'] is Map ? json['presets'] as Map : json;
    final out = <LessonFocus, Map<ExerciseType, double>>{
      for (final e in kDefaultFocusWeights.entries) e.key: Map.of(e.value),
    };
    for (final f in LessonFocus.values) {
      final m = raw[f.name];
      if (m is! Map) continue;
      out[f] = {
        for (final e in m.entries)
          if (ExerciseType.tryParse('${e.key}') != null && e.value is num)
            ExerciseType.parse('${e.key}'): (e.value as num).toDouble(),
      };
    }
    return FocusPresets(out);
  }

  factory FocusPresets.fromJsonString(String source) =>
      FocusPresets.fromJson(jsonDecode(source) as Map<String, dynamic>);

  double weight(LessonFocus focus, ExerciseType type) => weights[focus]?[type] ?? 0;

  /// Exercise types with a positive weight in [focus].
  Set<ExerciseType> typesFor(LessonFocus focus) => {
        for (final e in (weights[focus] ?? const <ExerciseType, double>{}).entries)
          if (e.value > 0) e.key,
      };
}
