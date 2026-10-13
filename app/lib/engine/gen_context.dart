/// Everything a template needs to generate one exercise.
library;

import 'dart:math';

import '../core/interfaces/course_data.dart';
import '../core/interfaces/session.dart';
import '../core/models/course.dart';
import '../core/models/progress.dart';
import 'course_index.dart';

/// How well a facet is known; drives the choice of exercise type.
enum FacetStage {
  /// Never reviewed: introduce with recognition / choice exercises.
  fresh,

  /// Reviewed, but stability below [StagePolicy.stableDays].
  learning,

  /// Stability at or above [StagePolicy.stableDays]: production exercises.
  stable,
}

/// Thresholds that turn a facet state into a [FacetStage].
class StagePolicy {
  const StagePolicy({this.stableDays = 5, this.freeTextDays = 0});

  /// Stability (days) from which a facet counts as stable.
  final double stableDays;

  /// Stability (days) from which cloze uses free text, for learners whose
  /// preferred input is keyboard or ink (0: always). Typing is never required:
  /// with tap input cloze always offers choices, however stable the facet.
  final double freeTextDays;

  FacetStage stageOf(FacetState? s) {
    if (s == null || s.reps == 0) return FacetStage.fresh;
    return s.stability >= stableDays ? FacetStage.stable : FacetStage.learning;
  }
}

class GenContext {
  GenContext({
    required this.course,
    required this.options,
    required this.random,
    this.states = const {},
    this.skill,
    DateTime? now,
    this.stagePolicy = const StagePolicy(),
    String Function()? nextId,
  })  : now = now ?? DateTime.now().toUtc(),
        _nextId = nextId; // ignore: prefer_initializing_formals

  final CourseData course;
  final SessionOptions options;
  final Random random;

  /// Known facet states (facets never reviewed are absent).
  final Map<String, FacetState> states;

  /// The skill the exercise is generated for (sets [Exercise.skillId] and
  /// restricts exercise types via [Skill.exercises]).
  final Skill? skill;
  final DateTime now;
  final StagePolicy stagePolicy;
  final String Function()? _nextId;
  int _counter = 0;

  CourseIndex get index => CourseIndex.of(course);
  String get lang => options.sourceLang;

  String nextId() => _nextId?.call() ?? 'ex${_counter++}';

  FacetState? state(String facetId) => states[facetId];
  FacetStage stage(String facetId) => stagePolicy.stageOf(states[facetId]);

  /// Free-text input (instead of choices) for cloze: only when the learner
  /// prefers keyboard/ink (typing is never required), and the facet has reached
  /// [StagePolicy.freeTextDays].
  bool freeText(String facetId) {
    if (options.preferredInput != InputMode.keyboard && options.preferredInput != InputMode.ink) {
      return false;
    }
    if (stagePolicy.freeTextDays <= 0) return true;
    final s = states[facetId];
    return s != null && s.reps > 0 && s.stability >= stagePolicy.freeTextDays;
  }

  /// A copy for another skill (same random, ids and states).
  GenContext forSkill(Skill? skill) => GenContext(
        course: course,
        options: options,
        random: random,
        states: states,
        skill: skill,
        now: now,
        stagePolicy: stagePolicy,
        nextId: nextId,
      );

  /// Picks a random element.
  T pick<T>(List<T> list) => list[random.nextInt(list.length)];

  /// Returns a shuffled copy.
  List<T> shuffled<T>(Iterable<T> items) => items.toList()..shuffle(random);
}
