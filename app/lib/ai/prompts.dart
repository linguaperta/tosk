/// Prompts for "Explain answer with AI" and "Confer with AI" (flag review),
/// and parsing of the flag verdict. Pure functions, unit-tested.
library;

import 'dart:convert';

import '../core/core.dart';

/// A system + user message pair.
class ChatPrompt {
  const ChatPrompt({required this.system, required this.user, this.maxTokens = 400});
  final String system;
  final String user;
  final int maxTokens;
}

/// English names for the languages the app deals with (prompts are in English;
/// the reply language is named explicitly).
const Map<String, String> kPromptLanguageNames = {
  'en': 'English',
  'nl': 'Dutch',
  'it': 'Italian',
  'hns': 'Sarnami Hindustani',
  'de': 'German',
  'fr': 'French',
  'es': 'Spanish',
};

String promptLanguage(String code) => kPromptLanguageNames[code] ?? code;

String _typeName(ExerciseType t) => switch (t) {
  ExerciseType.flashcard => 'flashcard (self-graded)',
  ExerciseType.multipleChoice => 'multiple choice',
  ExerciseType.matchPairs => 'match the pairs',
  ExerciseType.conjPick => 'pick the verb ending',
  ExerciseType.conjGrid => 'fill the conjugation table',
  ExerciseType.sentenceBuilder => 'build the translation from word tiles',
  ExerciseType.cloze => 'fill the gap',
  ExerciseType.spotError => 'spot the wrong word',
  ExerciseType.transform => 'transform the sentence',
  ExerciseType.listenPick => 'listen (text-to-speech) and pick the sentence or word heard',
};

/// Notes are trusted course content but can be long; the model needs the gist.
const int kMaxNoteChars = 2500;

String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}\n[…]';

String _exerciseBlock(ExplainContext c) {
  final b = StringBuffer()
    ..writeln('Course: learning ${promptLanguage(c.targetLang)} (${c.targetLang}), '
        'translations in ${promptLanguage(c.sourceLang)}.')
    ..writeln('Exercise type: ${_typeName(c.exerciseType)}.');
  if (c.instruction != null) b.writeln('Instruction: ${c.instruction}');
  b.writeln('Exercise: ${c.prompt}');
  if (c.options.isNotEmpty) b.writeln('Choices shown: ${c.options.join(' / ')}');
  b.writeln('Expected answer: ${c.expected}');
  if (c.accepted.isNotEmpty) b.writeln('Also accepted: ${c.accepted.join(' | ')}');
  b.writeln("Learner's answer: ${c.given.isEmpty ? '(empty)' : c.given} "
      "(${c.correct ? 'accepted as correct' : 'marked wrong'})");
  final note = c.note?.trim();
  if (note != null && note.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Grammar note of this skill (markdown):')
      ..writeln('"""')
      ..writeln(_clip(note, kMaxNoteChars))
      ..writeln('"""');
  }
  return b.toString().trimRight();
}

/// The explanation prompt: concise, friendly, in the reply language, why the
/// expected answer is right (and the learner's wrong), with the rule.
ChatPrompt explainPrompt(ExplainContext c) {
  final lang = promptLanguage(c.replyLang);
  final task = c.correct
      ? 'The learner answered correctly. Explain briefly why the answer is right, so the rule sticks. '
            'If their answer differs from the expected one but was accepted, say what the difference is.'
      : "The learner's answer was marked wrong. Explain why the expected answer is right and "
            'what exactly is wrong with theirs.';
  return ChatPrompt(
    system: 'You are a friendly, precise language tutor inside tosk, a language-learning app with a '
        'strong grammar focus. Write in $lang, at most 150 words. Name the grammar rule involved '
        '(use the grammar note when it applies) and quote the relevant forms in **bold**. '
        'Use short paragraphs or a short bullet list; no headings, no tables, no greeting. '
        'If the exercise itself looks wrong or ambiguous, say so in one sentence.',
    user: '${_exerciseBlock(c)}\n\n$task',
    maxTokens: 450,
  );
}

/// The flag-review prompt ("Confer with AI"): judge the learner's report.
ChatPrompt flagReviewPrompt({
  required ExplainContext context,
  required List<FlagReason> reasons,
  required String comment,
  Map<String, Object?>? snapshot,
}) {
  final lang = promptLanguage(context.replyLang);
  final b = StringBuffer(_exerciseBlock(context))
    ..writeln()
    ..writeln()
    ..writeln("The learner reported this exercise. Reasons: "
        "${reasons.isEmpty ? '(none given)' : reasons.map((r) => r.label).join('; ')}.")
    ..writeln('Their comment: ${comment.trim().isEmpty ? '(none)' : comment.trim()}');
  if (snapshot != null) {
    b
      ..writeln()
      ..writeln('Full exercise data (JSON):')
      ..writeln(jsonEncode(snapshot));
  }
  return ChatPrompt(
    system: 'You review learner reports about exercises in tosk, a language-learning app. Judge carefully '
        'and honestly whether the exercise is actually wrong (its expected answer, translation or prompt is '
        'incorrect), ambiguous (another answer should also be accepted, or the prompt is unclear), or correct '
        "(the learner's objection is mistaken). Do not simply agree with the learner. "
        'The first line of your reply must be exactly one of: '
        '"VERDICT: exercise_wrong", "VERDICT: ambiguous" or "VERDICT: exercise_correct". '
        'Then, in $lang and at most 120 words, give your reasoning; if the exercise is wrong or ambiguous, '
        'give the correct or additional answer. No headings, no tables.',
    user: b.toString().trimRight(),
    maxTokens: 400,
  );
}

/// Verdict and reasoning parsed from a flag-review reply.
class ParsedVerdict {
  const ParsedVerdict(this.verdict, this.reasoning);

  /// Null when the reply had no recognizable verdict line.
  final FlagVerdict? verdict;
  final String reasoning;
}

final _verdictLine = RegExp(
  r'^\W*verdict\W*[:\-]?\s*\W*(exercise[_ ]wrong|ambiguous|exercise[_ ]correct)\W*$',
  caseSensitive: false,
  multiLine: true,
);

ParsedVerdict parseVerdict(String reply) {
  final m = _verdictLine.firstMatch(reply);
  if (m == null) return ParsedVerdict(null, reply.trim());
  final id = m.group(1)!.toLowerCase().replaceAll(' ', '_');
  final reasoning = (reply.substring(0, m.start) + reply.substring(m.end)).trim();
  return ParsedVerdict(FlagVerdict.byId(id), reasoning);
}
