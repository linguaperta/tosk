/// Exercise contract between the engine (generates and grades) and the UI (renders and collects answers).
///
/// Rules:
/// * Every field the UI needs to render is here; the UI never queries the course itself.
/// * Text the user sees is resolved by the engine for the active source language.
/// * The engine may ADD optional fields; renaming or removing fields is a breaking change to the UI.
library;

import 'package:meta/meta.dart';

import 'progress.dart';

/// Base of all exercises. One subtype per [ExerciseType].
@immutable
sealed class Exercise {
  const Exercise({
    required this.id,
    required this.facetId,
    this.skillId,
    this.instruction = '',
  });

  /// Unique within a session.
  final String id;

  /// Primary facet trained. Match pairs trains several (see [MatchPairsExercise.facetIds]).
  final String facetId;
  final String? skillId;

  /// Short instruction line, e.g. "Pick the right ending" (already localized).
  final String instruction;

  ExerciseType get type;

  /// All facets this exercise grades.
  List<String> get facetIds => [facetId];
}

/// Direction of a vocabulary exercise.
enum Direction {
  recognize, // prompt in target language, answer in source language
  produce, // prompt in source language, answer in target language
}

/// One displayed token of a target-language sentence, aligned to a course
/// item where the pipeline aligned it. The UI makes aligned words tappable for
/// their gloss (lemma, person and tense for verb forms, article for nouns).
/// Rendering `pre + text` for every token gives the sentence.
@immutable
class TokenRef {
  const TokenRef(this.text, {this.pre = '', this.itemId, this.form, this.isWord = true});

  final String text;

  /// Whitespace before the token.
  final String pre;

  /// Aligned item id (`Token.lex`), null for unaligned words and punctuation.
  final String? itemId;

  /// `'{tense}.{person}'` when the token is a verb form, `'infl:{table}.{cell}'`
  /// when it is an inflected non-verb (`Token.form`).
  final String? form;
  final bool isWord;
}

/// Renders tokens back into text.
String renderTokenRefs(Iterable<TokenRef> tokens) => tokens.map((t) => '${t.pre}${t.text}').join();

@immutable
class FlashcardExercise extends Exercise {
  const FlashcardExercise({
    required super.id,
    required super.facetId,
    super.skillId,
    super.instruction,
    required this.front,
    required this.back,
    required this.direction,
    this.hint,
  });
  final String front;
  final String back;
  final Direction direction;
  final String? hint; // e.g. article/gender or POS
  @override
  ExerciseType get type => ExerciseType.flashcard;
}

@immutable
class MultipleChoiceExercise extends Exercise {
  const MultipleChoiceExercise({
    required super.id,
    required super.facetId,
    super.skillId,
    super.instruction,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.direction,
    this.isSentence = false,
    this.hint,
    this.sentenceTokens,
  });
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final Direction direction;
  final bool isSentence;

  /// Optional context line, e.g. the meaning of the noun in an article question
  /// (prompt `'___ ragazzo'`, hint `'boy'`).
  final String? hint;

  /// Sentence variant: the target-language sentence's tokens: the [prompt]
  /// when recognizing, the correct option when producing (tap-for-gloss).
  final List<TokenRef>? sentenceTokens;
  @override
  ExerciseType get type => ExerciseType.multipleChoice;
}

@immutable
class MatchPairsExercise extends Exercise {
  const MatchPairsExercise({
    required super.id,
    required super.facetId,
    super.skillId,
    super.instruction,
    required this.left,
    required this.right,
    required this.solution,
    required this.pairFacetIds,
  });

  /// Target-language words, in display order.
  final List<String> left;

  /// Meanings, shuffled, in display order.
  final List<String> right;

  /// left index -> right index.
  final Map<int, int> solution;

  /// left index -> facet id graded for that pair.
  final Map<int, String> pairFacetIds;

  @override
  List<String> get facetIds => [for (var i = 0; i < left.length; i++) pairFacetIds[i]!];
  @override
  ExerciseType get type => ExerciseType.matchPairs;
}

@immutable
class ConjPickExercise extends Exercise {
  const ConjPickExercise({
    required super.id,
    required super.facetId,
    super.skillId,
    super.instruction,
    required this.lemma,
    required this.gloss,
    required this.tense,
    required this.tenseLabel,
    required this.person,
    required this.personLabel,
    required this.stem,
    required this.endings,
    required this.correctIndex,
    required this.fullForm,
    this.accepted = const [],
    this.inflection = false,
  });
  final String lemma;
  final String gloss;

  /// The tense (for an inflection table: the table name, `number`).
  final String tense;
  final String tenseLabel;

  /// The person (for an inflection table: the cell, `pl`, `f.sg`).
  final String person;
  final String personLabel;

  /// An inflection table of a non-verb (`#infl` facet), not a conjugation:
  /// [tense]/[tenseLabel] are the table and [person]/[personLabel] the cell
  /// (`ragazzo` · plural: `ragazz___`).
  final bool inflection;
  final String stem; // shown as `mang___`
  final List<String> endings; // options
  final int correctIndex;
  final String fullForm; // shown in feedback

  /// Every accepted spelling of the full form (empty: just [fullForm]). A
  /// typed ending (`TextAnswer`, typing mode) is graded as `stem + ending`
  /// against these, with the accent setting.
  final List<String> accepted;
  @override
  ExerciseType get type => ExerciseType.conjPick;
}

@immutable
class GridCell {
  const GridCell({
    required this.person,
    required this.personLabel,
    required this.expected,
    this.accepted = const [],
    this.prefilled = false,
  });
  final String person;
  final String personLabel;
  final String expected; // canonical form
  final List<String> accepted; // all accepted spellings incl. expected
  final bool prefilled; // shown as a given, not asked
}

@immutable
class ConjGridExercise extends Exercise {
  const ConjGridExercise({
    required super.id,
    required super.facetId,
    super.skillId,
    super.instruction,
    required this.lemma,
    required this.gloss,
    required this.tense,
    required this.tenseLabel,
    required this.cells,
    required this.tiles,
    this.inflection = false,
  });
  final String lemma;
  final String gloss;

  /// The tense (for an inflection table: the table name; its cells are [GridCell.person]).
  final String tense;
  final String tenseLabel;
  final List<GridCell> cells;

  /// An inflection table of a non-verb (`bello`: m.sg, f.sg, m.pl, f.pl), not a conjugation.
  final bool inflection;

  /// Tap mode: a bank of forms (correct ones plus distractors), shuffled.
  final List<String> tiles;
  @override
  ExerciseType get type => ExerciseType.conjGrid;
}

@immutable
class SentenceBuilderExercise extends Exercise {
  const SentenceBuilderExercise({
    required super.id,
    required super.facetId,
    super.skillId,
    super.instruction,
    required this.prompt,
    required this.tiles,
    required this.answers,
    this.sentenceId,
    this.answerTokens,
  });

  /// The sentence to translate (source language).
  final String prompt;

  /// Word tiles (correct words plus distractors), shuffled.
  final List<String> tiles;

  /// Accepted answers as tile-word sequences; the first is canonical.
  final List<List<String>> answers;
  final String? sentenceId;

  /// Tokens of the canonical target sentence (tap-for-gloss after answering).
  final List<TokenRef>? answerTokens;
  @override
  ExerciseType get type => ExerciseType.sentenceBuilder;
}

@immutable
class ClozeExercise extends Exercise {
  const ClozeExercise({
    required super.id,
    required super.facetId,
    super.skillId,
    super.instruction,
    required this.before,
    required this.after,
    required this.expected,
    required this.accepted,
    this.options,
    this.correctIndex,
    this.hint,
    this.translation,
    this.sentenceId,
    this.tokens,
    this.gapFrom,
    this.gapTo,
  });
  final String before; // sentence text before the gap
  final String after; // sentence text after the gap
  final String expected;
  final List<String> accepted;

  /// Choice mode when non-null; free text (keyboard/ink) when null.
  final List<String>? options;
  final int? correctIndex;
  final String? hint; // e.g. "mangiare (noi, presente)"
  final String? translation;
  final String? sentenceId;

  /// Tokens of the whole (correct) sentence, for tap-for-gloss. The gap
  /// covers tokens [gapFrom]..[gapTo] (inclusive); an elided article gap
  /// covers only the start of token [gapFrom] (`l'` of `l'acqua`).
  final List<TokenRef>? tokens;
  final int? gapFrom;
  final int? gapTo;
  @override
  ExerciseType get type => ExerciseType.cloze;
}

@immutable
class SpotErrorExercise extends Exercise {
  const SpotErrorExercise({
    required super.id,
    required super.facetId,
    super.skillId,
    super.instruction,
    required this.tokens,
    required this.tokenIsWord,
    required this.errorIndex,
    required this.correction,
    this.translation,
    this.sentenceId,
    this.tokenPre,
    this.tokenRefs,
  });

  /// Displayed tokens; one of them is wrong.
  final List<String> tokens;

  /// Whitespace before each displayed token ('' or ' '), parallel to [tokens].
  /// Concatenating `tokenPre[i] + tokens[i]` renders the (wrong) sentence.
  final List<String>? tokenPre;
  final List<bool> tokenIsWord;
  final int errorIndex;
  final String correction; // the right form at errorIndex
  final String? translation;
  final String? sentenceId;

  /// Alignment of each displayed token, parallel to [tokens] (the error
  /// token carries the [correction]'s alignment). For tap-for-gloss, only
  /// after answering.
  final List<TokenRef>? tokenRefs;
  @override
  ExerciseType get type => ExerciseType.spotError;
}

@immutable
class TransformExercise extends Exercise {
  const TransformExercise({
    required super.id,
    required super.facetId,
    super.skillId,
    super.instruction,
    required this.source,
    required this.targetDescription,
    required this.tiles,
    required this.answers,
    this.sentenceId,
    this.translation,
    this.sourceTokens,
  });
  final String source; // original sentence
  final String targetDescription; // e.g. "→ passato prossimo" or "→ noi"
  final List<String> tiles;
  final List<List<String>> answers; // first is canonical
  final String? sentenceId;

  /// Translation of the source sentence (context only).
  final String? translation;

  /// Tokens of [source] (tap-for-gloss).
  final List<TokenRef>? sourceTokens;
  @override
  ExerciseType get type => ExerciseType.transform;
}

// ---------------------------------------------------------------- answers

@immutable
sealed class Answer {
  const Answer({this.inputMode = InputMode.tap});
  final InputMode inputMode;
}

class ChoiceAnswer extends Answer {
  const ChoiceAnswer(this.index, {super.inputMode});
  final int index;
}

class TextAnswer extends Answer {
  const TextAnswer(this.text, {super.inputMode = InputMode.keyboard, this.candidates = const []});
  final String text;

  /// Recognizer alternatives (ink); accepted if any normalized candidate matches.
  final List<String> candidates;
}

class SelfGradeAnswer extends Answer {
  const SelfGradeAnswer(this.rating) : super(inputMode: InputMode.self);
  final Rating rating;
}

class MatchAnswer extends Answer {
  /// left index -> right index as finally matched, plus left indices that had a wrong attempt.
  const MatchAnswer(this.matches, {this.missed = const {}});
  final Map<int, int> matches;
  final Set<int> missed;
}

class GridAnswer extends Answer {
  const GridAnswer(this.cells, {super.inputMode});
  final List<String> cells; // one per cell, '' for prefilled
}

class TilesAnswer extends Answer {
  const TilesAnswer(this.words, {super.inputMode});
  final List<String> words;
}

class TokenAnswer extends Answer {
  const TokenAnswer(this.index);
  final int index;
}

// ---------------------------------------------------------------- results

@immutable
class FacetOutcome {
  const FacetOutcome({required this.facetId, required this.correct, required this.rating});
  final String facetId;
  final bool correct;
  final Rating rating;
}

@immutable
class Result {
  const Result({
    required this.correct,
    required this.expected,
    required this.given,
    required this.outcomes,
    this.cellCorrect,
    this.accentSlip = false,
  });
  final bool correct;
  final String expected; // canonical correct answer for feedback
  final String given; // the user's answer as text
  final List<FacetOutcome> outcomes;
  final List<bool>? cellCorrect; // per-cell for grids

  /// Accepted only because accents were folded (lenient mode): show "watch the accent".
  final bool accentSlip;
}
