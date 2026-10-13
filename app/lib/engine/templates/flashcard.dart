import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import '../gen_context.dart';
import '../grading/rating.dart';
import '../strings.dart';
import '../template.dart';

/// See the word, reveal it, grade yourself. Trains `#rec` and `#prod`.
class FlashcardTemplate extends ExerciseTemplate {
  const FlashcardTemplate();

  @override
  ExerciseType get type => ExerciseType.flashcard;

  @override
  Set<FacetKind> get kinds => const {FacetKind.rec, FacetKind.prod};

  @override
  bool canGenerate(SkillFacet facet, GenContext ctx) {
    if (!supports(facet)) return false;
    final item = ctx.course.item(facet.itemId);
    return item != null && item.lemma.trim().isNotEmpty && item.gloss(ctx.lang).trim().isNotEmpty;
  }

  @override
  Exercise? generate(SkillFacet facet, GenContext ctx) {
    if (!canGenerate(facet, ctx)) return null;
    final item = ctx.course.item(facet.itemId)!;
    final target = ctx.index.withArticle(item);
    final meaning = item.glosses(ctx.lang).join(', ');
    final rec = facet.kind == FacetKind.rec;
    return FlashcardExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction(rec ? 'flashcard.rec' : 'flashcard.prod', ctx.lang),
      front: rec ? target : meaning,
      back: rec ? meaning : target,
      direction: rec ? Direction.recognize : Direction.produce,
      hint: item.pos,
    );
  }

  @override
  Result grade(Exercise exercise, Answer answer, {required Duration elapsed, GradeOptions options = const GradeOptions()}) {
    final e = exercise as FlashcardExercise;
    if (answer is! SelfGradeAnswer) return wrongKind(e, answer, e.back);
    final correct = answer.rating != Rating.again;
    return Result(
      correct: correct,
      expected: e.back,
      given: answer.rating.name,
      outcomes: [FacetOutcome(facetId: e.facetId, correct: correct, rating: answer.rating)],
    );
  }
}
