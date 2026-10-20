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
import 'text/answer_diff.dart';
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
/// The sentence's tokens with their alignment, for tap-for-gloss in the UI.
List<TokenRef> tokenRefsOf(Sentence s) => [
      for (final t in s.tokens) TokenRef(t.t, pre: t.pre, itemId: t.lex, form: t.form, isWord: t.isWord),
    ];

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

/// Partial credit for a partly right sentence answer, by token index into
/// [AnswerDiff.expected]: the words that carry the tested facet ([target];
/// that facet is right when all of them are right, in place or moved) and
/// the facet each other aligned word trains ([others]; graded only when the
/// word is wrong or missing). Null: no facet mapping for this answer.
typedef PartialCredit = ({Set<int> target, Map<int, String> others});

/// Facet mapping of the closest accepted answer of a diff.
typedef CreditMap = PartialCredit? Function(AnswerDiff diff);

/// Grades a tile sequence (or typed text) against accepted word sequences.
/// Tapped tiles are compared with exact diacritics; typed/ink answers use the
/// strictness setting. Word boundaries after elisions are ignored
/// (`l' acqua` == `l'acqua`).
///
/// A wrong answer gets a [Result.diff] against the closest accepted answer
/// ([accepted]: display tokens parallel to [answers], with alignment where
/// known; by default the answers' words). When the diff is
/// [AnswerDiff.partial] and [credit] maps its words to facets, the outcomes
/// give per-facet credit ([partialOutcomes]).
Result gradeTiles(
  Exercise e,
  Answer a,
  List<List<String>> answers, {
  required Duration elapsed,
  required GradeOptions grade,
  List<List<TokenRef>>? accepted,
  CreditMap? credit,
}) {
  final parts = switch (a) {
    TilesAnswer(:final words) => words,
    TextAnswer(:final text) => [text],
    _ => const <String>[],
  };
  final given = switch (a) {
    TilesAnswer(:final words) => words.join(' '),
    TextAnswer(:final text) => text,
    _ => '',
  };
  final strict = a.inputMode == InputMode.tap ? AccentStrictness.strict : grade.accents;
  final candidates = a is TextAnswer ? a.candidates : const <String>[];
  final m = matchAnswer(given, [for (final ws in answers) ws.join(' ')], strict, candidates: candidates);
  final diff = m.correct || parts.isEmpty
      ? null
      : bestAnswerDiff(parts, accepted ?? [for (final ws in answers) textTokens(ws.join(' '))], strict);
  return Result(
    correct: m.correct,
    expected: answers.first.join(' '),
    given: given,
    accentSlip: m.accentSlip,
    diff: diff,
    outcomes: partialOutcomes(e, diff, credit) ??
        [
          rateOutcome(e.type, e.facetId, correct: m.correct, elapsed: elapsed, options: grade, accentSlip: m.accentSlip),
        ],
  );
}

/// Per-facet outcomes of a partly right answer, or null for whole-answer
/// grading (no diff, not [AnswerDiff.partial], no mapping, or no word of the
/// answer carries the tested facet). The tested facet is right (Good, never
/// Easy: the answer was wrong) when all its words are right, else Again;
/// every other mapped facet with a wrong or missing word gets Again as a
/// [FacetOutcome.secondary] outcome.
List<FacetOutcome>? partialOutcomes(Exercise e, AnswerDiff? diff, CreditMap? credit) {
  if (diff == null || credit == null || !diff.partial) return null;
  final c = credit(diff);
  if (c == null || c.target.isEmpty) return null;
  bool ok(int j) => diff.expected[j].mark == DiffMark.same || diff.expected[j].mark == DiffMark.moved;
  final targetOk = c.target.every(ok);
  final others = <String>{
    for (final MapEntry(key: j, value: f) in c.others.entries)
      if (f != e.facetId && !c.target.contains(j) && !ok(j)) f,
  };
  return [
    FacetOutcome(
      facetId: e.facetId,
      correct: targetOk,
      rating: targetOk ? Rating.good : Rating.again,
      partial: targetOk,
    ),
    for (final f in others) FacetOutcome(facetId: f, correct: false, rating: Rating.again, secondary: true),
  ];
}

/// Partial credit by alignment: the words aligned to the tested facet's item
/// carry it; every other aligned word maps to [facetOfToken].
PartialCredit? creditByAlignment(String facetId, AnswerDiff diff) {
  final hash = facetId.indexOf('#');
  final item = hash < 0 ? facetId : facetId.substring(0, hash);
  final target = <int>{};
  final others = <int, String>{};
  for (var j = 0; j < diff.expected.length; j++) {
    final t = diff.expected[j];
    if (!t.isWord || t.itemId == null) continue;
    if (t.itemId == item) {
      target.add(j);
    } else {
      final f = facetOfToken(t.itemId, t.form);
      if (f != null) others[j] = f;
    }
  }
  return target.isEmpty ? null : (target: target, others: others);
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

/// Whether two stems end alike (both in a vowel or both in a consonant), so an
/// ending taken from a verb with one stem is a plausible wrong ending for the
/// other: `ga` + `n` gives `gan`, but `denk` + `n` gives the unlikely `denkn`.
bool stemsEndAlike(String a, String b) {
  if (a.isEmpty || b.isEmpty) return a.isEmpty == b.isEmpty;
  bool vowel(String s) => 'aeiouy'.contains(foldDiacritics(s.substring(s.length - 1).toLowerCase()));
  return vowel(a) == vowel(b);
}

/// Display name of a verb for hints: `mangiare (noi, present)`.
String formHint(CourseMeta meta, Item verb, String person, String tense, String lang) =>
    '${verb.lemma} (${meta.personLabel(person, lang)}, ${meta.tenseLabel(tense, lang)})';

final RegExp _glossParens = RegExp(r'\([^)]*\)');
final RegExp _nonLetters = RegExp(r"[^\p{L}\p{N}']+", unicode: true);

/// Function words ignored when matching a gloss against a translation
/// (English and Dutch glosses), unless the gloss has nothing else (`it`, `the`).
const Set<String> _glossStopWords = {
  'to', 'a', 'an', 'the', 'of', 'be', 'one', "one's", 'someone', 'something', 'sb', 'sth', 'oneself',
  'te', 'de', 'het', 'een', 'iets', 'iemand', 'zich',
};

List<String> _glossWords(String s) => [
      for (final w in foldDiacritics(s.toLowerCase()).split(_nonLetters))
        if (w.isNotEmpty) w,
    ];

bool _wordMatch(String g, String t) {
  if (g == t) return true;
  final short = g.length < t.length ? g : t;
  final long = g.length < t.length ? t : g;
  // eat/eats/eating, house/houses, werk/werken: an inflection of the same word.
  if (short.length >= 3 && long.startsWith(short) && long.length - short.length <= 3) return true;
  var p = 0;
  while (p < short.length && short.codeUnitAt(p) == long.codeUnitAt(p)) {
    p++;
  }
  return p >= 5;
}

/// The meaning of [item] to show as a hint for its use in [sentence]: the
/// gloss (in [lang]) whose words best match the sentence's translation, so
/// `lo` in "I know it" hints `it`, not `the`. When no gloss matches, all
/// glosses (at most three) joined: `it, the`.
String contextGloss(Item item, Sentence sentence, String lang) {
  final glosses = [for (final g in item.glosses(lang)) if (g.trim().isNotEmpty) g];
  if (glosses.isEmpty) return '';
  if (glosses.length == 1) return glosses.first;
  final translation = sentence.translation(lang);
  final words = translation == null ? const <String>[] : _glossWords(translation);
  var best = 0.0;
  String? bestGloss;
  for (final g in glosses) {
    final all = _glossWords(g.replaceAll(_glossParens, ' '));
    final content = [for (final w in all) if (!_glossStopWords.contains(w)) w];
    final ws = content.isEmpty ? all : content;
    if (ws.isEmpty) continue;
    final hit = ws.where((w) => words.any((t) => _wordMatch(w, t))).length / ws.length;
    if (hit > best) {
      best = hit;
      bestGloss = g;
    }
  }
  return bestGloss ?? glosses.take(3).join(', ');
}
