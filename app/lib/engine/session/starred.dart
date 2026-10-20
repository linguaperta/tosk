/// "Practice starred": a session over the learner's bookmarks (starred words,
/// sentences and exercises). See docs/engine.md, "Starred practice".
library;

import '../../core/interfaces/course_data.dart';
import '../../core/interfaces/session.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import 'engine_session.dart';

/// Exercise types that show a whole sentence.
const Set<ExerciseType> kSentenceExerciseTypes = {
  ExerciseType.cloze,
  ExerciseType.sentenceBuilder,
  ExerciseType.spotError,
  ExerciseType.transform,
};

/// Plans a starred-practice session.
///
/// * **Exercises** are served again exactly as they were starred (the decoded
///   snapshot) when the course still trains every facet they grade and still
///   has their sentence; otherwise a fresh exercise of the same type on the
///   same facet (any type when that can't be built). Facets the course no
///   longer trains are skipped.
/// * **Words**: every facet the course trains for the item, weakest first
///   (reviewed facets by predicted recall, then new ones in course order).
/// * **Sentences**: the facets of the sentence's aligned words (a verb form
///   asks its tense's `#form` facet, an inflected word its `#infl` facet,
///   other words `#prod`, else `#rec`), as sentence exercises where one can be
///   built ([kSentenceExerciseTypes]), with the sentence itself preferred by
///   every template that can show it ([EngineSession.preferredSentences]; it
///   passes the grammar gate, since the learner has seen it).
///
/// The three queues are interleaved (exercise, word, sentence, ...), each
/// facet planned once, up to [length] slots.
class StarredBuilder {
  const StarredBuilder(this.starred, {this.length = 12});

  final StarredPractice starred;
  final int length;

  Future<StarredSession> start(SessionEnv env) async {
    final course = env.course;
    final byItem = facetsByItem(course);
    final wanted = <String>{
      for (final id in starred.itemIds) ...?byItem[id]?.map((f) => f.facetId),
      for (final e in starred.exercises) ...e.facetIds,
    };
    final states = await env.store.states(wanted);
    final now = env.now();

    SkillFacet? facetFor(String facetId, String? skillId) {
      for (final s in [?skillId, ...course.skillsForFacet(facetId)]) {
        for (final f in course.skillFacets(s)) {
          if (f.facetId == facetId) return f;
        }
      }
      return null;
    }

    // Exercises.
    final exercises = <SessionSlot>[];
    for (final e in starred.exercises) {
      final facet = facetFor(e.facetId, e.skillId);
      if (facet == null) continue; // the course no longer trains it
      final sentence = sentenceIdOf(e);
      final intact =
          e.facetIds.every((f) => facetFor(f, e.skillId) != null) &&
          (sentence == null || course.sentence(sentence) != null);
      exercises.add(intact ? SessionSlot(facet, fixed: e) : SessionSlot(facet, only: {e.type}));
    }

    // Words, weakest facet first.
    List<SkillFacet> ordered(List<SkillFacet> facets) {
      final reviewed = [
        for (final f in facets)
          if (states[f.facetId] != null) f,
      ]..sort((a, b) => env.scheduler
          .retrievability(states[a.facetId], now)
          .compareTo(env.scheduler.retrievability(states[b.facetId], now)));
      return [
        ...reviewed,
        for (final f in facets)
          if (states[f.facetId] == null) f,
      ];
    }

    final words = [
      for (final id in starred.itemIds)
        if (byItem[id] case final facets?) ordered(facets),
    ];

    // Sentences: the facets of their aligned words.
    final preferred = <String>{};
    final sentences = <List<SkillFacet>>[];
    for (final id in starred.sentenceIds) {
      final s = course.sentence(id);
      if (s == null) continue;
      preferred.add(id);
      final facets = <SkillFacet>[];
      for (final t in s.tokens) {
        final item = t.lex;
        if (item == null) continue;
        final f = _sentenceFacet(byItem[item] ?? const [], t.form);
        if (f != null && !facets.any((x) => x.facetId == f.facetId)) facets.add(f);
      }
      if (facets.isNotEmpty) sentences.add(facets);
    }

    // Interleave: exercise, word, sentence, ...; each facet once.
    final planned = <SessionSlot>[];
    final used = <String>{};
    final wordQueue = _roundRobin(words);
    final sentenceQueue = _roundRobin(sentences);
    var ei = 0, wi = 0, si = 0;
    while (planned.length < length &&
        (ei < exercises.length || wi < wordQueue.length || si < sentenceQueue.length)) {
      if (ei < exercises.length) {
        final slot = exercises[ei++];
        planned.add(slot);
        used.add(slot.facet.facetId);
      }
      while (planned.length < length && wi < wordQueue.length) {
        final f = wordQueue[wi++];
        if (used.add(f.facetId)) {
          planned.add(SessionSlot(f));
          break;
        }
      }
      while (planned.length < length && si < sentenceQueue.length) {
        final f = sentenceQueue[si++];
        if (used.add(f.facetId)) {
          // A sentence exercise first (it shows the starred sentence); any
          // type when none can be built for this facet.
          planned.add(SessionSlot(f, only: kSentenceExerciseTypes));
          break;
        }
      }
    }
    final allStates = await env.store.states({for (final s in planned) ...s.fixed?.facetIds ?? [s.facet.facetId]});
    return StarredSession._(env, allStates, planned, preferred);
  }

  /// The facet a sentence token trains: its verb form's tense, its
  /// inflection table, else production, else recognition.
  static SkillFacet? _sentenceFacet(List<SkillFacet> facets, String? form) {
    SkillFacet? find(bool Function(SkillFacet f) test) {
      for (final f in facets) {
        if (test(f)) return f;
      }
      return null;
    }

    if (form != null && form.startsWith('infl:')) {
      final table = form.substring(5).split('.').first;
      final f = find((f) => f.kind == FacetKind.infl && f.tense == table);
      if (f != null) return f;
    } else if (form != null) {
      final tense = form.split('.').first;
      final f = find((f) => f.kind == FacetKind.form && f.tense == tense);
      if (f != null) return f;
    }
    return find((f) => f.kind == FacetKind.prod) ?? find((f) => f.kind == FacetKind.rec);
  }

  static List<T> _roundRobin<T>(List<List<T>> lists) {
    final out = <T>[];
    for (var round = 0; ; round++) {
      var any = false;
      for (final l in lists) {
        if (round < l.length) {
          out.add(l[round]);
          any = true;
        }
      }
      if (!any) return out;
    }
  }

  /// Every facet the course trains, by item, in course order (each facet
  /// once, in the first skill that trains it).
  static Map<String, List<SkillFacet>> facetsByItem(CourseData course) {
    final out = <String, List<SkillFacet>>{};
    final seen = <String>{};
    for (final s in course.skills) {
      for (final f in course.skillFacets(s.id)) {
        if (seen.add(f.facetId)) (out[f.itemId] ??= []).add(f);
      }
    }
    return out;
  }
}

/// A starred-practice session (mode `starred`). Wrong answers are re-asked
/// like in any session (with a freshly generated exercise).
class StarredSession extends EngineSession {
  StarredSession._(super.env, Map<String, FacetState> states, this.slots, this._preferred)
    : super(mode: SessionMode.starred, states: states);

  /// The planned slots, in order.
  final List<SessionSlot> slots;
  final Set<String> _preferred;
  int _i = 0;

  /// A restricted slot that failed is retried once with any type.
  SessionSlot? _retry;

  @override
  int? get targetLength => slots.length;

  @override
  Set<String> get preferredSentences => _preferred;

  @override
  SessionSlot? nextSlot() {
    final retry = _retry;
    if (retry != null) {
      _retry = null;
      return retry;
    }
    if (_i >= slots.length) return null;
    return slots[_i++];
  }

  @override
  void onGenerateFailed(SessionSlot slot) {
    if (slot.only != null && !slot.reask) _retry = SessionSlot(slot.facet);
  }
}
