/// Mistake review: which stored mistakes are still open, and a session that
/// practices their facets.
library;

import '../../core/interfaces/course_data.dart';
import '../../core/interfaces/progress_store.dart';
import '../../core/interfaces/session.dart';
import '../../core/models/facet.dart';
import '../../core/models/progress.dart';
import 'engine_session.dart';

/// A facet with an unresolved mistake: its latest [record] and the facet as
/// the course trains it.
class OpenMistake {
  const OpenMistake({required this.record, required this.facet, required this.count, required this.recall});

  /// The most recent mistake on this facet.
  final MistakeRecord record;

  /// The facet to practice (in the mistake's skill when it still trains it).
  final SkillFacet facet;

  /// Mistakes on this facet among the scanned records (1 or more).
  final int count;

  /// Predicted recall now (0..1).
  final double recall;

  /// The exercise type that was missed, when known.
  ExerciseType? get missedType => ExerciseType.tryParse(record.exerciseType);
}

/// Recall below which an open mistake counts as "still weak" and is reviewed first.
const double kMistakeWeakRecall = 0.9;

/// The open mistakes of [course], one per facet, in review order: still weak
/// (recall < [kMistakeWeakRecall]) first, then the rest; most recent first
/// within each group.
///
/// **Resolution rule.** A mistake is resolved once its facet has been answered
/// correctly in a *later session* (any review event for that facet with
/// `correct`, `at` after the mistake, and a session id other than the
/// mistake's own). The re-ask in the same session does not count: getting it
/// right two exercises later is short-term memory. A new mistake on the facet
/// (e.g. during mistake review) opens it again. Mistakes on facets the course
/// no longer trains (a pack update) are skipped.
Future<List<OpenMistake>> openMistakes({
  required ProgressStore store,
  required CourseData course,
  required Scheduler scheduler,
  required DateTime now,
  int scan = 300,
}) async {
  final records = await store.mistakes(courseId: course.meta.id, limit: scan);
  if (records.isEmpty) return const [];
  // Latest record per facet (records come most recent first).
  final latest = <String, MistakeRecord>{};
  final counts = <String, int>{};
  for (final m in records) {
    latest.putIfAbsent(m.facetId, () => m);
    counts[m.facetId] = (counts[m.facetId] ?? 0) + 1;
  }
  final oldest = latest.values.map((m) => m.at).reduce((a, b) => a.isBefore(b) ? a : b);
  final log = await store.log(since: oldest, courseId: course.meta.id);
  final sessionOf = {for (final e in log) e.id: e.sessionId};
  final byFacet = <String, List<ReviewEvent>>{};
  for (final e in log) {
    if (latest.containsKey(e.facetId)) (byFacet[e.facetId] ??= []).add(e);
  }

  bool resolved(MistakeRecord m) {
    final session = sessionOf[m.id];
    for (final e in byFacet[m.facetId] ?? const <ReviewEvent>[]) {
      if (!e.correct || !e.at.isAfter(m.at)) continue;
      if (session == null || e.sessionId == null || e.sessionId != session) return true;
    }
    return false;
  }

  final states = await store.states(latest.keys);
  final open = <OpenMistake>[];
  for (final m in latest.values) {
    if (resolved(m)) continue;
    final facet = _facetFor(course, m.facetId, m.skillId);
    if (facet == null) continue;
    open.add(OpenMistake(
      record: m,
      facet: facet,
      count: counts[m.facetId]!,
      recall: scheduler.retrievability(states[m.facetId], now),
    ));
  }
  open.sort((a, b) {
    final wa = a.recall < kMistakeWeakRecall, wb = b.recall < kMistakeWeakRecall;
    if (wa != wb) return wa ? -1 : 1;
    final c = b.record.at.compareTo(a.record.at);
    return c != 0 ? c : a.record.facetId.compareTo(b.record.facetId);
  });
  return open;
}

SkillFacet? _facetFor(CourseData course, String facetId, String? skillId) {
  for (final s in [?skillId, ...course.skillsForFacet(facetId)]) {
    for (final f in course.skillFacets(s)) {
      if (f.facetId == facetId) return f;
    }
  }
  return null;
}

/// Mistake review (mode `review`): one exercise per open mistake, in
/// [openMistakes] order, up to [length]. Each facet is asked with the
/// exercise type that was missed when that type can still be built for it
/// (not for flashcards, whose "Again" is a self-grade); otherwise the
/// selector picks by stage. Wrong answers are re-queued as in any session.
class ReviewBuilder {
  const ReviewBuilder({this.length = 12});

  final int length;

  Future<MistakeReviewSession> start(SessionEnv env) async {
    final open = await openMistakes(store: env.store, course: env.course, scheduler: env.scheduler, now: env.now());
    final states = await env.store.states(open.map((m) => m.facet.facetId));
    return build(env, open, states);
  }

  MistakeReviewSession build(SessionEnv env, List<OpenMistake> open, Map<String, FacetState> states) =>
      MistakeReviewSession._(env, states, open.take(length).toList());
}

class MistakeReviewSession extends EngineSession {
  MistakeReviewSession._(super.env, Map<String, FacetState> states, this.mistakes)
      : super(mode: SessionMode.review, states: states);

  /// The mistakes this session reviews, in order.
  final List<OpenMistake> mistakes;
  int _i = 0;

  /// The slot handed out last and the planned count at that moment: when
  /// [nextSlot] is asked again before anything was served, that slot could
  /// not be generated with the missed type, so it is retried unrestricted.
  SessionSlot? _pending;
  int _pendingServed = -1;

  @override
  int? get targetLength => mistakes.length;

  @override
  SessionSlot? nextSlot() {
    final pending = _pending;
    if (pending != null && pending.only != null && servedPlanned == _pendingServed) {
      _pending = null;
      return SessionSlot(pending.facet);
    }
    if (_i >= mistakes.length) return null;
    final m = mistakes[_i++];
    final slot = SessionSlot(m.facet, only: _preferredTypes(m));
    _pending = slot;
    _pendingServed = servedPlanned;
    return slot;
  }

  Set<ExerciseType>? _preferredTypes(OpenMistake m) {
    final t = m.missedType;
    if (t == null || t == ExerciseType.flashcard) return null;
    final ctx = genContext(m.facet);
    if (!env.selector.allowedTypes(m.facet, ctx, only: {t}).contains(t)) return null;
    if (!(env.selector.template(t)?.canGenerate(m.facet, ctx) ?? false)) return null;
    return {t};
  }
}
