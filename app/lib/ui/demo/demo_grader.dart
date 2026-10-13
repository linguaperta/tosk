import '../../core/core.dart';

/// Grades every exercise type for the fake session. The real grading (with
/// spelling variants, per-language normalization and fast-answer thresholds)
/// lives in the engine.
class DemoGrader {
  const DemoGrader({this.accents = AccentStrictness.lenient, this.fastAnswer = const Duration(seconds: 3)});

  final AccentStrictness accents;
  final Duration fastAnswer;

  Result grade(Exercise exercise, Answer answer, {Duration elapsed = Duration.zero}) {
    Rating auto(bool ok) =>
        !ok ? Rating.again : (elapsed > Duration.zero && elapsed < fastAnswer ? Rating.easy : Rating.good);
    Result single(bool ok, String expected, String given) => Result(
      correct: ok,
      expected: expected,
      given: given,
      outcomes: [FacetOutcome(facetId: exercise.facetId, correct: ok, rating: auto(ok))],
    );

    switch (exercise) {
      case FlashcardExercise e:
        final rating = answer is SelfGradeAnswer ? answer.rating : Rating.again;
        final ok = rating != Rating.again;
        return Result(
          correct: ok,
          expected: e.back,
          given: rating.name,
          outcomes: [FacetOutcome(facetId: e.facetId, correct: ok, rating: rating)],
        );
      case MultipleChoiceExercise e:
        final i = answer is ChoiceAnswer ? answer.index : -1;
        return single(i == e.correctIndex, e.options[e.correctIndex], _at(e.options, i));
      case MatchPairsExercise e:
        final m = answer is MatchAnswer ? answer : const MatchAnswer({});
        final outcomes = <FacetOutcome>[];
        var allOk = true;
        for (var i = 0; i < e.left.length; i++) {
          final ok = m.matches[i] == e.solution[i] && !m.missed.contains(i);
          allOk &= ok;
          outcomes.add(FacetOutcome(facetId: e.pairFacetIds[i]!, correct: ok, rating: ok ? Rating.good : Rating.again));
        }
        return Result(
          correct: allOk,
          expected: [for (var i = 0; i < e.left.length; i++) '${e.left[i]} = ${e.right[e.solution[i]!]}'].join(', '),
          given: [for (final p in m.matches.entries) '${_at(e.left, p.key)} = ${_at(e.right, p.value)}'].join(', '),
          outcomes: outcomes,
        );
      case ConjPickExercise e:
        final i = answer is ChoiceAnswer ? answer.index : -1;
        return single(i == e.correctIndex, e.fullForm, i < 0 ? '' : '${e.stem}${_at(e.endings, i)}');
      case ConjGridExercise e:
        final cells = answer is GridAnswer ? answer.cells : const <String>[];
        final marks = <bool>[];
        for (var i = 0; i < e.cells.length; i++) {
          final c = e.cells[i];
          if (c.prefilled) {
            marks.add(true);
            continue;
          }
          final given = i < cells.length ? cells[i] : '';
          final accepted = {c.expected, ...c.accepted}.map(normalize);
          marks.add(accepted.contains(normalize(given)));
        }
        final ok = marks.every((m) => m);
        return Result(
          correct: ok,
          expected: [for (final c in e.cells) '${c.personLabel} ${c.expected}'].join(', '),
          given: cells.join(', '),
          outcomes: [FacetOutcome(facetId: e.facetId, correct: ok, rating: auto(ok))],
          cellCorrect: marks,
        );
      case SentenceBuilderExercise e:
        return _tiles(e.answers, answer, single);
      case TransformExercise e:
        return _tiles(e.answers, answer, single);
      case ClozeExercise e:
        if (answer is ChoiceAnswer && e.options != null) {
          final ok = answer.index == e.correctIndex;
          return single(ok, e.expected, _at(e.options!, answer.index));
        }
        final text = answer is TextAnswer ? answer.text : '';
        final candidates = answer is TextAnswer ? [text, ...answer.candidates] : [text];
        final accepted = {e.expected, ...e.accepted}.map(normalize).toSet();
        final ok = candidates.any((c) => accepted.contains(normalize(c)));
        return single(ok, e.expected, text);
      case SpotErrorExercise e:
        final i = answer is TokenAnswer ? answer.index : -1;
        return single(i == e.errorIndex, '${e.tokens[e.errorIndex]} → ${e.correction}', _at(e.tokens, i));
    }
  }

  Result _tiles(List<List<String>> answers, Answer answer, Result Function(bool, String, String) single) {
    final words = answer is TilesAnswer ? answer.words : const <String>[];
    final given = words.join(' ');
    final ok = answers.any((a) => normalize(a.join(' ')) == normalize(given));
    return single(ok, answers.first.join(' '), given);
  }

  /// Case-folds, trims, collapses spaces, drops punctuation and (lenient) diacritics.
  String normalize(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'[.,!?;:¿¡«»“”"]'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    if (accents == AccentStrictness.lenient) t = stripDiacritics(t);
    return t;
  }
}

String _at(List<String> list, int i) => i >= 0 && i < list.length ? list[i] : '';

const _diacritics = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

String stripDiacritics(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_diacritics[ch] ?? ch);
  }
  return b.toString();
}
