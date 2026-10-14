/// Builds the [ExplainContext] of a checked answer (right or wrong) from the
/// exercise, its result and the course. Used by "Explain answer with AI" and
/// by "Confer with AI" on a flag.
library;

import '../core/core.dart';
import '../engine/debug/exercise_printer.dart' show exercisePrompt;
import 'exercise_snapshot.dart';

ExplainContext buildExplainContext({
  required Exercise exercise,
  required Result result,
  required String sourceLang,
  CourseData? course,
  String? explainLang,
  DateTime? at,
  MistakeContext? mistake,
}) {
  final skillId = exercise.skillId ?? mistake?.skillId ?? course?.skillsForFacet(exercise.facetId).firstOrNull;
  String? note = mistake?.note;
  if (note == null && skillId != null && course != null) {
    try {
      note = course.note(skillId, sourceLang);
    } catch (_) {
      note = null;
    }
  }
  return ExplainContext(
    courseId: course?.meta.id ?? mistake?.courseId ?? '',
    facetId: mistake?.facetId ?? exercise.facetId,
    exerciseType: exercise.type,
    // Same prompt text the engine stores with a mistake, so the fingerprint
    // (and the cached explanation) is shared with mistake review.
    prompt: mistake?.prompt ?? exercisePrompt(exercise),
    expected: result.expected,
    given: result.given,
    sourceLang: sourceLang,
    targetLang: course?.meta.target ?? mistake?.targetLang ?? '',
    correct: result.correct,
    skillId: skillId,
    note: note,
    sentenceId: exerciseSentenceId(exercise),
    at: at ?? mistake?.at,
    options: exerciseChoices(exercise),
    accepted: exerciseAlternatives(exercise),
    instruction: exercise.instruction.isEmpty ? null : exercise.instruction,
    explainLang: explainLang,
  );
}
