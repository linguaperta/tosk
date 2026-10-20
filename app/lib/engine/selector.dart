/// Chooses an exercise type for a facet (by facet stability, focus preset
/// and restrictions) and generates the exercise.
library;

import '../core/interfaces/session.dart';
import '../core/models/exercise.dart';
import '../core/models/facet.dart';
import '../core/models/progress.dart';
import 'focus_presets.dart';
import 'gen_context.dart';
import 'template.dart';
import 'templates/templates.dart';

/// Base weight of each exercise type per facet stage. Fresh facets get
/// recognition and choice exercises (flashcard intro, multiple choice, conj
/// pick, a grid with prefilled cells); stable facets get production
/// (sentence builder, cloze, full grid, transform, spot the error).
const Map<ExerciseType, Map<FacetStage, double>> kStageAffinity = {
  ExerciseType.flashcard: {FacetStage.fresh: 5, FacetStage.learning: 1, FacetStage.stable: 0.3},
  ExerciseType.multipleChoice: {FacetStage.fresh: 3, FacetStage.learning: 3, FacetStage.stable: 1},
  ExerciseType.matchPairs: {FacetStage.fresh: 1, FacetStage.learning: 3, FacetStage.stable: 1},
  ExerciseType.conjPick: {FacetStage.fresh: 3, FacetStage.learning: 3, FacetStage.stable: 1},
  ExerciseType.conjGrid: {FacetStage.fresh: 3, FacetStage.learning: 2, FacetStage.stable: 3},
  ExerciseType.sentenceBuilder: {FacetStage.fresh: 0, FacetStage.learning: 1.5, FacetStage.stable: 3},
  ExerciseType.cloze: {FacetStage.fresh: 0.5, FacetStage.learning: 2, FacetStage.stable: 3},
  ExerciseType.spotError: {FacetStage.fresh: 0, FacetStage.learning: 1, FacetStage.stable: 3},
  ExerciseType.transform: {FacetStage.fresh: 0, FacetStage.learning: 0.5, FacetStage.stable: 3},
  // Only generated when the device can speak the course language.
  ExerciseType.listenPick: {FacetStage.fresh: 0.5, FacetStage.learning: 2, FacetStage.stable: 2},
};

class ExerciseSelector {
  ExerciseSelector({
    List<ExerciseTemplate>? templates,
    this.presets = FocusPresets.defaults,
    this.affinity = kStageAffinity,
    this.recentFactor = 0.6,
  }) : templates = {for (final t in templates ?? defaultTemplates()) t.type: t};

  final Map<ExerciseType, ExerciseTemplate> templates;
  final FocusPresets presets;
  final Map<ExerciseType, Map<FacetStage, double>> affinity;

  /// Weight factor per recent use of a type (see [generate]).
  final double recentFactor;

  ExerciseTemplate? template(ExerciseType type) => templates[type];

  /// Types that may serve [facet]: supported by a template, allowed by the
  /// skill's `exercises` list (unless [ignoreSkillRestriction]) and in [only].
  List<ExerciseType> allowedTypes(
    SkillFacet facet,
    GenContext ctx, {
    Set<ExerciseType>? only,
    bool ignoreSkillRestriction = false,
  }) {
    final skill = ctx.skill ?? ctx.course.skill(facet.skillId);
    final restrict = ignoreSkillRestriction || skill == null || skill.exercises.isEmpty
        ? null
        : {for (final id in skill.exercises) ?ExerciseType.tryParse(id)};
    return [
      for (final t in templates.values)
        if (t.supports(facet) &&
            (restrict == null || restrict.contains(t.type)) &&
            (only == null || only.contains(t.type)))
          t.type,
    ];
  }

  /// Generates an exercise for [facet]. Types are drawn by weight (stage
  /// affinity x focus weight); when no type has weight under the focus, the
  /// focus is ignored (e.g. a vocab-focus lesson on a pure grammar skill), and
  /// as a last resort every allowed type is tried.
  ///
  /// Variety: within each of those tiers, [avoid] (the previous exercise's
  /// type, or the type a re-asked mistake was missed with) is only tried after
  /// every other type of the tier failed, and types among [recent] (the last
  /// few exercises' types) weigh [recentFactor] less per occurrence.
  Exercise? generate(
    SkillFacet facet,
    GenContext ctx, {
    LessonFocus focus = LessonFocus.mixed,
    Set<ExerciseType>? only,
    bool ignoreSkillRestriction = false,
    ExerciseType? avoid,
    List<ExerciseType> recent = const [],
  }) {
    final types = allowedTypes(facet, ctx, only: only, ignoreSkillRestriction: ignoreSkillRestriction);
    if (types.isEmpty) return null;
    final stage = ctx.stage(facet.facetId);
    double base(ExerciseType t) {
      var w = affinity[t]?[stage] ?? 1;
      for (final r in recent) {
        if (r == t) w *= recentFactor;
      }
      return w;
    }

    final tiers = <Map<ExerciseType, double>>[
      {for (final t in types) t: base(t) * presets.weight(focus, t)},
      {for (final t in types) t: base(t)},
      {for (final t in types) t: 1},
    ];
    final tried = <ExerciseType>{};
    Exercise? attempt(ExerciseType t) {
      tried.add(t);
      final tpl = templates[t]!;
      if (!tpl.canGenerate(facet, ctx)) return null;
      return tpl.generate(facet, ctx);
    }

    for (final tier in tiers) {
      final pool = {
        for (final e in tier.entries)
          if (e.value > 0 && !tried.contains(e.key)) e.key: e.value,
      };
      final deferred = avoid != null && pool.remove(avoid) != null;
      while (pool.isNotEmpty) {
        final t = _draw(pool, ctx);
        pool.remove(t);
        final ex = attempt(t);
        if (ex != null) return ex;
      }
      if (deferred) {
        final ex = attempt(avoid);
        if (ex != null) return ex;
      }
    }
    return null;
  }

  ExerciseType _draw(Map<ExerciseType, double> pool, GenContext ctx) {
    final total = pool.values.fold<double>(0, (a, b) => a + b);
    var r = ctx.random.nextDouble() * total;
    for (final e in pool.entries) {
      r -= e.value;
      if (r <= 0) return e.key;
    }
    return pool.keys.last;
  }
}
