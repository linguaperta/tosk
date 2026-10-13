import 'dart:math' as math;

import 'package:tosk/core/core.dart';

/// Deterministic FSRS-like scheduler for progression tests.
///
/// * Recall decays as R = 0.9^(t / S), so R = 0.9 when t = S (as in FSRS).
/// * New facets enter learning (step 0, or step 1 after Good); Good at step 1
///   graduates to review. Easy graduates at once. Learning steps are 10 minutes.
/// * In review: Again lapses into relearning (S × 0.3); Hard ×1.2, Good ×2.5, Easy ×3.5
///   when reviewed at or after S days; earlier reviews grow S proportionally less.
///   Good in relearning graduates back to review.
class FakeScheduler implements Scheduler {
  const FakeScheduler();

  static const learningStep = Duration(minutes: 10);

  static Duration days(double d) => Duration(microseconds: (d * Duration.microsecondsPerDay).round());

  @override
  double retrievability(FacetState? state, DateTime now) {
    if (state == null) return 0;
    final t = now.difference(state.lastReview).inMicroseconds / Duration.microsecondsPerDay;
    return math.pow(0.9, math.max(0, t) / state.stability).toDouble();
  }

  @override
  FacetState review(String facetId, FacetState? previous, Rating rating, DateTime now) {
    final p = previous;
    if (p == null) {
      final s = switch (rating) {
        Rating.again => 0.1,
        Rating.hard => 0.5,
        Rating.good => 1.0,
        Rating.easy => 3.0,
      };
      final d = switch (rating) {
        Rating.again => 7.0,
        Rating.hard => 6.0,
        Rating.good => 5.0,
        Rating.easy => 3.0,
      };
      if (rating == Rating.easy) {
        return FacetState(
          facetId: facetId, stability: s, difficulty: d, due: now.add(days(s)), lastReview: now,
          reps: 1, lapses: 0, phase: CardPhase.review);
      }
      return FacetState(
        facetId: facetId, stability: s, difficulty: d, due: now.add(learningStep), lastReview: now,
        reps: 1, lapses: 0, phase: CardPhase.learning, step: rating == Rating.good ? 1 : 0);
    }
    final reps = p.reps + 1;
    switch (p.phase) {
      case CardPhase.learning:
      case CardPhase.relearning:
        switch (rating) {
          case Rating.again:
            return p.copyWith(
                reps: reps, step: 0, lastReview: now, due: now.add(learningStep),
                difficulty: math.min(10, p.difficulty + 0.5));
          case Rating.hard:
            return p.copyWith(reps: reps, lastReview: now, due: now.add(learningStep));
          case Rating.good:
            final step = (p.step ?? 0) + 1;
            if (p.phase == CardPhase.relearning || step >= 2) {
              final s = math.max(p.stability, 1.0);
              return p.copyWith(
                  reps: reps, stability: s, lastReview: now, due: now.add(days(s)),
                  phase: CardPhase.review, clearStep: true);
            }
            return p.copyWith(reps: reps, step: step, lastReview: now, due: now.add(learningStep));
          case Rating.easy:
            final s = math.max(p.stability * 2, 3.0);
            return p.copyWith(
                reps: reps, stability: s, lastReview: now, due: now.add(days(s)),
                phase: CardPhase.review, clearStep: true, difficulty: math.max(1, p.difficulty - 0.5));
        }
      case CardPhase.review:
        switch (rating) {
          case Rating.again:
            return p.copyWith(
                reps: reps, lapses: p.lapses + 1, stability: math.max(0.1, p.stability * 0.3),
                difficulty: math.min(10, p.difficulty + 1), lastReview: now, due: now.add(learningStep),
                phase: CardPhase.relearning, step: 0);
          case Rating.hard:
          case Rating.good:
          case Rating.easy:
            final f = rating == Rating.hard ? 1.2 : (rating == Rating.good ? 2.5 : 3.5);
            final dd = rating == Rating.hard ? 0.5 : (rating == Rating.easy ? -0.5 : 0.0);
            // Early reviews grow stability less (like FSRS): scale by elapsed / S, capped at 1.
            final elapsed = now.difference(p.lastReview).inMicroseconds / Duration.microsecondsPerDay;
            final w = (elapsed / p.stability).clamp(0.0, 1.0);
            final s = math.min(36500.0, p.stability * (1 + (f - 1) * w));
            return p.copyWith(
                reps: reps, stability: s, difficulty: (p.difficulty + dd).clamp(1.0, 10.0),
                lastReview: now, due: now.add(days(s)));
        }
    }
  }
}
