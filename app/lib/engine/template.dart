/// The exercise template contract and helpers shared by all templates.
library;

import 'dart:math';

import '../core/interfaces/session.dart' show AccentStrictness;
import '../core/models/course.dart';
import '../core/models/exercise.dart';
import '../core/models/facet.dart';
import '../core/models/progress.dart';
import 'gen_context.dart';
import 'grading/rating.dart';
import 'text/normalize.dart';

/// Generates and grades one [ExerciseType] from course data.
///
/// * [canGenerate] is a cheap-ish, deterministic check that [generate] can
///   succeed for the facet (it may still fail for an unlucky random draw).
/// * [generate] never returns an exercise with an accidentally-correct wrong
///   option, a duplicate option, or a missing correct answer.
/// * [grade] is pure: it needs only the exercise and the answer.
abstract class ExerciseTemplate {
  const ExerciseTemplate();

  ExerciseType get type;

  /// Facet kinds this template can train.
  Set<FacetKind> get kinds;

  bool supports(SkillFacet facet) => kinds.contains(facet.kind);

  bool canGenerate(SkillFacet facet, GenContext ctx);

  Exercise? generate(SkillFacet facet, GenContext ctx);

  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()});
}

/// Collects wrong options: rejects empty options, options equal (after
/// folding case, punctuation and diacritics) to a [forbidden] answer, and
/// duplicates.
class OptionPicker {
  OptionPicker({Iterable<String> forbidden = const [], this.max = 3})
      : _keys = {for (final f in forbidden) foldAnswer(f)};

  final Set<String> _keys;
  final int max;
  final List<String> picked = [];

  bool get full => picked.length >= max;

  /// Adds [option] if valid; returns whether it was added.
  bool add(String option) {
    if (full) return false;
    final k = foldAnswer(option);
    if (k.isEmpty || _keys.contains(k)) return false;
    _keys.add(k);
    picked.add(option);
    return true;
  }

  /// Adds from [groups] in priority order, shuffling within each group.
  void addGroups(Iterable<Iterable<String>> groups, Random random) {
    for (final g in groups) {
      if (full) return;
      for (final o in (g.toList()..shuffle(random))) {
        if (full) return;
        add(o);
      }
    }
  }
}

/// Shuffles [correct] into [distractors]; returns the options and the correct index.
(List<String>, int) placeOptions(String correct, List<String> distractors, Random random) {
  final options = [correct, ...distractors]..shuffle(random);
  return (options, options.indexOf(correct));
}

/// One outcome for [facetId], rated by [GradeOptions.rating].
FacetOutcome rateOutcome(
  ExerciseType type,
  String facetId, {
  required bool correct,
  required Duration elapsed,
  required GradeOptions options,
  bool accentSlip = false,
}) =>
    FacetOutcome(
      facetId: facetId,
      correct: correct,
      rating: options.rating.rate(type, correct: correct, elapsed: elapsed, accentSlip: accentSlip),
    );

/// Grades a [ChoiceAnswer] against [correctIndex].
Result gradeChoice(
  Exercise e,
  Answer a,
  List<String> options,
  int correctIndex, {
  required Duration elapsed,
  required GradeOptions grade,
}) {
  final idx = a is ChoiceAnswer ? a.index : -1;
  final correct = idx == correctIndex;
  return Result(
    correct: correct,
    expected: options[correctIndex],
    given: idx >= 0 && idx < options.length ? options[idx] : _given(a),
    outcomes: [rateOutcome(e.type, e.facetId, correct: correct, elapsed: elapsed, options: grade)],
  );
}

/// Grades a tile sequence (or typed text) against accepted word sequences.
/// Tapped tiles are compared with exact diacritics; typed/ink answers use the
/// strictness setting. Word boundaries after elisions are ignored
/// (`l' acqua` == `l'acqua`).
Result gradeTiles(
  Exercise e,
  Answer a,
  List<List<String>> answers, {
  required Duration elapsed,
  required GradeOptions grade,
}) {
  final given = switch (a) {
    TilesAnswer(:final words) => words.join(' '),
    TextAnswer(:final text) => text,
    _ => '',
  };
  final strict = a.inputMode == InputMode.tap ? AccentStrictness.strict : grade.accents;
  final candidates = a is TextAnswer ? a.candidates : const <String>[];
  final m = matchAnswer(given, [for (final ws in answers) ws.join(' ')], strict, candidates: candidates);
  return Result(
    correct: m.correct,
    expected: answers.first.join(' '),
    given: given,
    accentSlip: m.accentSlip,
    outcomes: [
      rateOutcome(e.type, e.facetId, correct: m.correct, elapsed: elapsed, options: grade, accentSlip: m.accentSlip),
    ],
  );
}

String _given(Answer a) => switch (a) {
      ChoiceAnswer(:final index) => '#$index',
      TextAnswer(:final text) => text,
      SelfGradeAnswer(:final rating) => rating.name,
      MatchAnswer() => '',
      GridAnswer(:final cells) => cells.join(', '),
      TilesAnswer(:final words) => words.join(' '),
      TokenAnswer(:final index) => '#$index',
    };

/// Text of an answer for logs and feedback.
String answerText(Answer a) => _given(a);

/// A wrong result for an answer of the wrong kind.
Result wrongKind(Exercise e, Answer a, String expected) => Result(
      correct: false,
      expected: expected,
      given: _given(a),
      outcomes: [FacetOutcome(facetId: e.facetId, correct: false, rating: Rating.again)],
    );

/// Display name of a verb for hints: `mangiare (noi, present)`.
String formHint(CourseMeta meta, Item verb, String person, String tense, String lang) =>
    '${verb.lemma} (${meta.personLabel(person, lang)}, ${meta.tenseLabel(tense, lang)})';
