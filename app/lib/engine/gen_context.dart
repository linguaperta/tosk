/// Everything a template needs to generate one exercise.
library;

import 'dart:math';

import '../core/interfaces/course_data.dart';
import '../core/interfaces/session.dart';
import '../core/models/course.dart';
import '../core/models/progress.dart';
import 'course_index.dart';
import 'gating.dart';

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

/// Score per unknown word in [GenContext.prefer] (a seen sentence scores
/// 1–3, see [SentenceHistory.penalty], plus a random jitter below 1).
const double kUnknownWordWeight = 0.75;

/// Score added in [GenContext.prefer] to a generated sentence (`src` starting
/// with `claude-gen`): at least the jitter, so a real (Tatoeba) sentence with
/// the same number of unknown words always comes first while it is unseen.
const double kGeneratedSentenceWeight = 1.0;

/// Whether [s] was written for the course (pipeline `generate.py`) rather
/// than taken from a corpus.
bool isGeneratedSentence(Sentence s) => s.src?.startsWith('claude-gen') ?? false;

/// Score subtracted in [GenContext.prefer] from a sentence the session
/// prefers (starred practice: the learner's starred sentences), so it comes
/// first. Preferred sentences pass the grammar gate: the learner starred
/// them after seeing them.
const double kPreferredSentenceBonus = 10.0;

/// Score subtracted in [GenContext.prefer] from a sentence that shows a
/// grammar feature the exercise's skill introduces (the Italian `progressive`
/// skill trains `stare#form:presente`; its sentences with a gerund, `Sto
/// mangiando`, come before `Come stai?`). More than the jitter, less than two
/// unknown words.
const double kSkillFeatureBonus = 1.25;

/// See [GenContext.shownRecently].
const int kRecentSentenceWindow = 100;

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
    this.gate,
    this.history,
    this.wordCap = SentenceGate.vocabCap,
    this.preferredSentences = const {},
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

  /// Grammar gating: the sentences this learner may meet (null: every
  /// sentence, e.g. the validity suite and the sample printer).
  final SentenceGate? gate;

  /// Recently seen sentences, for variety (null: no preference).
  final SentenceHistory? history;

  /// Unknown-word cap for sentences under [gate] ([SentenceGate.capFor]).
  final int wordCap;

  /// Sentence ids [prefer] ranks first when eligible (starred sentences).
  final Set<String> preferredSentences;

  CourseIndex get index => CourseIndex.of(course);

  /// The non-base features [skill] introduces ([kSkillFeatureBonus]).
  late final Set<String> _ownFeatures = skill == null
      ? const {}
      : course.skillFeatures(skill!.id).difference(course.meta.baseFeatures.toSet());
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

  /// A copy for another skill (same random, ids, states, gate and history).
  GenContext forSkill(Skill? skill) => GenContext(
        course: course,
        options: options,
        random: random,
        states: states,
        skill: skill,
        now: now,
        stagePolicy: stagePolicy,
        nextId: nextId,
        gate: gate,
        history: history,
        wordCap: wordCap,
        preferredSentences: preferredSentences,
      );

  // ------------------------------------------------------------ sentences

  /// Whether [s] may be shown to this learner (always without a [gate]).
  bool sentenceOk(Sentence s) => preferredSentences.contains(s.id) || (gate?.allows(s, wordCap) ?? true);

  /// Whether a grammar feature is known (always without a [gate]).
  bool featureKnown(String feature) => gate?.featureKnown(feature) ?? true;

  /// Whether forms of [tense] may be shown, e.g. as a wrong option
  /// ([SentenceGate.tenseShowable]; always without a [gate]).
  bool tenseShowable(String tense) => gate?.tenseShowable(tense) ?? true;

  /// Memoizes a template's `canGenerate` answer: in the gate when there is
  /// one (the answer depends on what the learner knows), else per course.
  /// [key] must contain everything else the value depends on.
  T memo<T>(String key, T Function() compute) {
    final g = gate;
    return g == null ? index.memo(key, compute) : g.memo('$key|cap$wordCap', compute);
  }

  /// The candidates whose sentence may be shown, best first, at most [take]:
  /// fewer unknown words, then sentences never seen (or least recently seen)
  /// first, with a random jitter so equal candidates come in random order.
  /// A generated sentence ranks after the unseen real ones with as many
  /// unknown words ([kGeneratedSentenceWeight]), about level with a real one
  /// seen long ago. Sentences already used in this session come last (only when nothing
  /// else is left: a session never repeats a sentence while others remain).
  List<T> prefer<T>(Iterable<T> candidates, Sentence Function(T) sentenceOf, {int take = 1 << 30}) {
    final fresh = <(double, T)>[];
    final reused = <(double, T)>[];
    final g = gate;
    final h = history;
    final own = _ownFeatures;
    for (final c in candidates) {
      final s = sentenceOf(c);
      final preferred = preferredSentences.contains(s.id);
      if (g != null && !preferred && !g.allows(s, wordCap)) continue;
      final score = (g == null ? 0 : g.unknownWords(s) * kUnknownWordWeight) +
          (h == null ? 0 : h.penalty(s.id)) +
          (isGeneratedSentence(s) ? kGeneratedSentenceWeight : 0) -
          (preferred ? kPreferredSentenceBonus : 0) -
          (own.isNotEmpty && course.sentenceFeatures(s.id).any(own.contains) ? kSkillFeatureBonus : 0) +
          random.nextDouble();
      (h != null && h.usedInSession(s.id) ? reused : fresh).add((score, c));
    }
    int by((double, T) a, (double, T) b) => a.$1.compareTo(b.$1);
    fresh.sort(by);
    if (fresh.length < take) reused.sort(by);
    return [
      for (final e in fresh.take(take)) e.$2,
      if (fresh.length < take)
        for (final e in reused.take(take - fresh.length)) e.$2,
    ];
  }

  /// Whether this session already showed sentence [id].
  bool usedInSession(String id) => history?.usedInSession(id) ?? false;

  /// Whether sentence [id] was shown in this session or among the last
  /// [kRecentSentenceWindow] sentences before it. Templates whose facet can
  /// always be served without a sentence (inflection facets: the ending
  /// picker) skip such sentences instead of repeating them.
  bool shownRecently(String id) =>
      (history?.usedInSession(id) ?? false) || (history?.seenWithin(id, kRecentSentenceWindow) ?? false);

  /// Records that an exercise shows sentence [id] (for variety).
  void useSentence(String? id) {
    if (id != null) history?.use(id);
  }

  /// Picks a random element.
  T pick<T>(List<T> list) => list[random.nextInt(list.length)];

  /// Returns a shuffled copy.
  List<T> shuffled<T>(Iterable<T> items) => items.toList()..shuffle(random);
}
