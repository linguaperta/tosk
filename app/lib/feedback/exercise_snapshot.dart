/// Full JSON snapshots of exercises, for flags: every field of the core
/// [Exercise] (type, ids, options, correct answers, sentence id, facets), so a
/// flagged exercise can be reproduced exactly with [exerciseFromJson].
///
/// Format: `{"type": ExerciseType.id, "id", "facet_id", "skill_id",
/// "instruction", ...type-specific fields in snake_case}`. See docs/feedback.md.
library;

import '../core/core.dart';

/// Snapshot of [e] (plain JSON values only).
Map<String, Object?> exerciseToJson(Exercise e) {
  final base = <String, Object?>{
    'type': e.type.id,
    'id': e.id,
    'facet_id': e.facetId,
    'skill_id': e.skillId,
    'instruction': e.instruction,
  };
  final specific = switch (e) {
    FlashcardExercise() => {'front': e.front, 'back': e.back, 'direction': e.direction.name, 'hint': e.hint},
    MultipleChoiceExercise() => {
      'prompt': e.prompt,
      'options': e.options,
      'correct_index': e.correctIndex,
      'direction': e.direction.name,
      'is_sentence': e.isSentence,
      'hint': e.hint,
    },
    MatchPairsExercise() => {
      'left': e.left,
      'right': e.right,
      'solution': {for (final s in e.solution.entries) '${s.key}': s.value},
      'pair_facet_ids': {for (final p in e.pairFacetIds.entries) '${p.key}': p.value},
    },
    ConjPickExercise() => {
      'lemma': e.lemma,
      'gloss': e.gloss,
      'tense': e.tense,
      'tense_label': e.tenseLabel,
      'person': e.person,
      'person_label': e.personLabel,
      'stem': e.stem,
      'endings': e.endings,
      'correct_index': e.correctIndex,
      'full_form': e.fullForm,
    },
    ConjGridExercise() => {
      'lemma': e.lemma,
      'gloss': e.gloss,
      'tense': e.tense,
      'tense_label': e.tenseLabel,
      'cells': [
        for (final c in e.cells)
          {
            'person': c.person,
            'person_label': c.personLabel,
            'expected': c.expected,
            'accepted': c.accepted,
            'prefilled': c.prefilled,
          },
      ],
      'tiles': e.tiles,
    },
    SentenceBuilderExercise() => {
      'prompt': e.prompt,
      'tiles': e.tiles,
      'answers': e.answers,
      'sentence_id': e.sentenceId,
    },
    ClozeExercise() => {
      'before': e.before,
      'after': e.after,
      'expected': e.expected,
      'accepted': e.accepted,
      'options': e.options,
      'correct_index': e.correctIndex,
      'hint': e.hint,
      'translation': e.translation,
      'sentence_id': e.sentenceId,
    },
    SpotErrorExercise() => {
      'tokens': e.tokens,
      'token_pre': e.tokenPre,
      'token_is_word': e.tokenIsWord,
      'error_index': e.errorIndex,
      'correction': e.correction,
      'translation': e.translation,
      'sentence_id': e.sentenceId,
    },
    TransformExercise() => {
      'source': e.source,
      'target_description': e.targetDescription,
      'tiles': e.tiles,
      'answers': e.answers,
      'sentence_id': e.sentenceId,
      'translation': e.translation,
    },
  };
  return {...base, ...specific, 'facet_ids': e.facetIds};
}

/// Rebuilds an exercise from [exerciseToJson]. Throws [FormatException] on an
/// unknown type or missing fields.
Exercise exerciseFromJson(Map<String, Object?> j) {
  T req<T>(String k) {
    final v = j[k];
    if (v is T) return v;
    throw FormatException('Exercise snapshot: "$k" missing or not ${T.toString()}', j);
  }

  List<String> strings(String k) => [for (final v in req<List<Object?>>(k)) '$v'];
  List<String>? maybeStrings(String k) => j[k] == null ? null : strings(k);
  List<List<String>> answers(String k) => [
    for (final a in req<List<Object?>>(k)) [for (final w in a as List<Object?>) '$w'],
  ];
  Direction dir() => Direction.values.byName(req<String>('direction'));
  Map<int, V> intMap<V>(String k) => {
    for (final e in req<Map<String, Object?>>(k).entries) int.parse(e.key): e.value as V,
  };

  final id = req<String>('id');
  final facetId = req<String>('facet_id');
  final skillId = j['skill_id'] as String?;
  final instruction = (j['instruction'] as String?) ?? '';
  final type = req<String>('type');
  return switch (type) {
    'flashcard' => FlashcardExercise(
      id: id,
      facetId: facetId,
      skillId: skillId,
      instruction: instruction,
      front: req('front'),
      back: req('back'),
      direction: dir(),
      hint: j['hint'] as String?,
    ),
    'multiple_choice' => MultipleChoiceExercise(
      id: id,
      facetId: facetId,
      skillId: skillId,
      instruction: instruction,
      prompt: req('prompt'),
      options: strings('options'),
      correctIndex: req('correct_index'),
      direction: dir(),
      isSentence: (j['is_sentence'] as bool?) ?? false,
      hint: j['hint'] as String?,
    ),
    'match_pairs' => MatchPairsExercise(
      id: id,
      facetId: facetId,
      skillId: skillId,
      instruction: instruction,
      left: strings('left'),
      right: strings('right'),
      solution: intMap<int>('solution'),
      pairFacetIds: intMap<String>('pair_facet_ids'),
    ),
    'conj_pick' => ConjPickExercise(
      id: id,
      facetId: facetId,
      skillId: skillId,
      instruction: instruction,
      lemma: req('lemma'),
      gloss: req('gloss'),
      tense: req('tense'),
      tenseLabel: req('tense_label'),
      person: req('person'),
      personLabel: req('person_label'),
      stem: req('stem'),
      endings: strings('endings'),
      correctIndex: req('correct_index'),
      fullForm: req('full_form'),
    ),
    'conj_grid' => ConjGridExercise(
      id: id,
      facetId: facetId,
      skillId: skillId,
      instruction: instruction,
      lemma: req('lemma'),
      gloss: req('gloss'),
      tense: req('tense'),
      tenseLabel: req('tense_label'),
      cells: [
        for (final c in req<List<Object?>>('cells').cast<Map<String, Object?>>())
          GridCell(
            person: c['person'] as String,
            personLabel: c['person_label'] as String,
            expected: c['expected'] as String,
            accepted: [for (final a in (c['accepted'] as List<Object?>? ?? const [])) '$a'],
            prefilled: (c['prefilled'] as bool?) ?? false,
          ),
      ],
      tiles: strings('tiles'),
    ),
    'sentence_builder' => SentenceBuilderExercise(
      id: id,
      facetId: facetId,
      skillId: skillId,
      instruction: instruction,
      prompt: req('prompt'),
      tiles: strings('tiles'),
      answers: answers('answers'),
      sentenceId: j['sentence_id'] as String?,
    ),
    'cloze' => ClozeExercise(
      id: id,
      facetId: facetId,
      skillId: skillId,
      instruction: instruction,
      before: req('before'),
      after: req('after'),
      expected: req('expected'),
      accepted: strings('accepted'),
      options: maybeStrings('options'),
      correctIndex: j['correct_index'] as int?,
      hint: j['hint'] as String?,
      translation: j['translation'] as String?,
      sentenceId: j['sentence_id'] as String?,
    ),
    'spot_error' => SpotErrorExercise(
      id: id,
      facetId: facetId,
      skillId: skillId,
      instruction: instruction,
      tokens: strings('tokens'),
      tokenPre: maybeStrings('token_pre'),
      tokenIsWord: [for (final b in req<List<Object?>>('token_is_word')) b as bool],
      errorIndex: req('error_index'),
      correction: req('correction'),
      translation: j['translation'] as String?,
      sentenceId: j['sentence_id'] as String?,
    ),
    'transform' => TransformExercise(
      id: id,
      facetId: facetId,
      skillId: skillId,
      instruction: instruction,
      source: req('source'),
      targetDescription: req('target_description'),
      tiles: strings('tiles'),
      answers: answers('answers'),
      sentenceId: j['sentence_id'] as String?,
      translation: j['translation'] as String?,
    ),
    _ => throw FormatException('Exercise snapshot: unknown type "$type"', j),
  };
}

/// The choices an exercise showed (options, endings, tiles, tokens), for prompts.
List<String> exerciseChoices(Exercise e) => switch (e) {
  FlashcardExercise() => const [],
  MultipleChoiceExercise() => e.options,
  MatchPairsExercise() => [...e.left, ...e.right],
  ConjPickExercise() => e.endings,
  ConjGridExercise() => e.tiles,
  SentenceBuilderExercise() => e.tiles,
  ClozeExercise() => e.options ?? const [],
  SpotErrorExercise() => e.tokens,
  TransformExercise() => e.tiles,
};

/// Accepted answers besides the canonical one, as display strings.
List<String> exerciseAlternatives(Exercise e) => switch (e) {
  SentenceBuilderExercise(:final answers) || TransformExercise(:final answers) => [
    for (final a in answers.skip(1)) a.join(' '),
  ],
  ClozeExercise() => [
    for (final a in e.accepted)
      if (a != e.expected) a,
  ],
  _ => const [],
};

/// The sentence id behind a sentence-based exercise.
String? exerciseSentenceId(Exercise e) => switch (e) {
  SentenceBuilderExercise() => e.sentenceId,
  ClozeExercise() => e.sentenceId,
  SpotErrorExercise() => e.sentenceId,
  TransformExercise() => e.sentenceId,
  _ => null,
};
