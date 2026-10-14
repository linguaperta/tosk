/// Graded mini-stories: short texts per unit that use only the vocabulary and
/// grammar taught up to that unit, with comprehension questions. Mirrors the
/// `stories`, `story_sentences` and `story_questions` tables of
/// `schema/course_db.sql`; see docs/ARCHITECTURE.md, "Stories".
library;

import 'package:meta/meta.dart';

import 'course.dart';
import 'progress.dart';

@immutable
class Story {
  const Story({
    required this.id,
    required this.unitId,
    required this.ord,
    required this.title,
    required this.titleTr,
    required this.sentences,
    required this.questions,
    this.newWords = const [],
    this.src,
  });

  /// Permanent within the course, e.g. `u1-bar`.
  final String id;

  /// The unit whose vocabulary and grammar the story uses; it unlocks there.
  final String unitId;
  final int ord;

  /// Target-language title and its translations.
  final String title;
  final I18n titleTr;

  /// The text, in reading order. Their tokens are aligned like any sentence
  /// (tap a word for its gloss); they are not part of the exercise pool.
  final List<Sentence> sentences;
  final List<StoryQuestion> questions;

  /// Item ids taught after [unitId] (at most one), glossed in the reader.
  final List<String> newWords;
  final String? src;
}

@immutable
class StoryQuestion {
  const StoryQuestion({
    required this.promptTr,
    required this.options,
    required this.correct,
    this.prompt,
    this.explanationTr = const {},
  });

  /// The question in the target language, if the story has one.
  final String? prompt;

  /// The question in the source language.
  final I18n promptTr;
  final List<StoryOption> options;

  /// Index of the correct option.
  final int correct;
  final I18n explanationTr;
}

/// A target-language answer ([text]) or one in the source language ([tr]).
@immutable
class StoryOption {
  const StoryOption.target(String this.text) : tr = null;
  const StoryOption.translated(I18n this.tr) : text = null;

  final String? text;
  final I18n? tr;

  bool get isTarget => text != null;

  String label(String lang) => text ?? pickLang(tr!, lang);
}

/// [ReviewEvent.exerciseType] of a *story read*: finishing a story's questions
/// appends one event on the story's own pseudo-facet [storyFacetId], rating
/// Good, `correct` true, input `tap`, mode `story`, `responseMs` the reading
/// time and the score `'{correct}/{total}'` in [ReviewEvent.answer].
///
/// The pseudo-facet belongs to no skill, so it never reaches a lesson, the
/// map or any skill statistic, and no real facet's FSRS state changes (reading
/// is not a graded recall of any word). Replays fold it like any facet, so
/// `rebuildStates()` stays exact. Progression gives it fixed, light XP
/// ([XpRules.xpFor]: first read 5 + 1 per correct answer, rereads 2), so a
/// story counts toward the daily goal and the streak, but challenges don't
/// count it as answers or new words. See docs/ARCHITECTURE.md, "Stories".
const String kStoryReadType = 'story';

/// Mode of a story read event.
const String kStoryMode = 'story';

/// `{courseId}:story:{storyId}#story`: the course prefix keeps it in the
/// course's log and states; the `#` keeps facet-id parsers safe.
String storyFacetId(String courseId, String storyId) => '$courseId:story:$storyId#story';

/// The story id of a story facet id, or null.
String? storyIdOfFacet(String facetId) {
  final i = facetId.indexOf(':story:');
  if (i < 0 || !facetId.endsWith('#story')) return null;
  return facetId.substring(i + 7, facetId.length - 6);
}

/// `(correct, total)` stored in a story read event, or null.
({int correct, int total})? storyScoreOf(ReviewEvent e) {
  final m = RegExp(r'^(\d+)/(\d+)$').firstMatch(e.answer ?? '');
  if (m == null) return null;
  return (correct: int.parse(m.group(1)!), total: int.parse(m.group(2)!));
}
