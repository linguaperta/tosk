import 'dart:convert';
import 'dart:io';

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RatingPolicy', () {
    const p = RatingPolicy();
    test('wrong -> again', () {
      expect(p.rate(ExerciseType.cloze, correct: false, elapsed: const Duration(seconds: 1)), Rating.again);
    });
    test('right -> good; fast -> easy', () {
      expect(p.rate(ExerciseType.cloze, correct: true, elapsed: const Duration(seconds: 9)), Rating.good);
      expect(p.rate(ExerciseType.cloze, correct: true, elapsed: const Duration(seconds: 2)), Rating.easy);
    });
    test('threshold per type', () {
      const d = Duration(seconds: 8);
      expect(p.rate(ExerciseType.conjGrid, correct: true, elapsed: d), Rating.easy);
      expect(p.rate(ExerciseType.conjPick, correct: true, elapsed: d), Rating.good);
    });
    test('accent slip caps at good', () {
      expect(p.rate(ExerciseType.cloze, correct: true, elapsed: Duration.zero, accentSlip: true), Rating.good);
    });
    test('configurable table', () {
      const custom = RatingPolicy(fastMs: {ExerciseType.cloze: 100});
      expect(custom.rate(ExerciseType.cloze, correct: true, elapsed: const Duration(milliseconds: 500)), Rating.good);
      expect(custom.rate(ExerciseType.multipleChoice, correct: true, elapsed: Duration.zero), Rating.good);
    });
    test('flashcards are self-graded', () {
      const t = FlashcardTemplate();
      const e = FlashcardExercise(id: 'x', facetId: 'it:ciao#rec', front: 'ciao', back: 'hi', direction: Direction.recognize);
      for (final r in Rating.values) {
        final res = t.grade(e, SelfGradeAnswer(r), elapsed: Duration.zero);
        expect(res.outcomes.single.rating, r);
        expect(res.correct, r != Rating.again);
      }
    });
  });

  group('FocusPresets', () {
    test('the asset matches the embedded defaults', () {
      final json = jsonDecode(File('assets/config/focus_presets.json').readAsStringSync()) as Map<String, dynamic>;
      final parsed = FocusPresets.fromJson(json);
      for (final f in LessonFocus.values) {
        expect(parsed.weights[f], kDefaultFocusWeights[f], reason: f.name);
      }
    });
    test('vocab and grammar presets select the spec types', () {
      const p = FocusPresets.defaults;
      expect(p.typesFor(LessonFocus.vocab), {
        ExerciseType.flashcard,
        ExerciseType.matchPairs,
        ExerciseType.multipleChoice,
        ExerciseType.sentenceBuilder,
      });
      expect(p.typesFor(LessonFocus.grammar), {
        ExerciseType.conjPick,
        ExerciseType.conjGrid,
        ExerciseType.cloze,
        ExerciseType.transform,
        ExerciseType.spotError,
      });
      expect(p.typesFor(LessonFocus.mixed), ExerciseType.values.toSet());
    });
    test('parsing ignores unknown keys and keeps defaults for missing foci', () {
      final p = FocusPresets.fromJsonString(
          '{"presets": {"vocab": {"flashcard": 2, "listen_pick": 1, "cloze": "x"}, "speed": {"cloze": 1}}}');
      expect(p.weights[LessonFocus.vocab], {ExerciseType.flashcard: 2.0});
      expect(p.weights[LessonFocus.grammar], kDefaultFocusWeights[LessonFocus.grammar]);
    });
  });
}
