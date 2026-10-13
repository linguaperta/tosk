import 'package:tosk/core/core.dart';

import 'events.dart';
import 'fake_scheduler.dart';

/// Events that take [facetId] from new to stability ≥ [targetStability] days by
/// answering Good every time it falls due, starting at [start].
/// Returns the events; the last event's time is when the target was reached.
List<ReviewEvent> trainFacet(
  EventFactory f,
  String facetId,
  DateTime start, {
  double targetStability = 0,
  String? session,
  String? mode,
  String type = 'multiple_choice',
}) {
  const sch = FakeScheduler();
  final out = <ReviewEvent>[];
  FacetState? s;
  var at = start;
  // Learn: Good, then Good one step later -> graduates (stability 1 day).
  while (s == null || s.phase != CardPhase.review || s.stability < targetStability) {
    final e = f.ev(facetId, at, session: session, mode: mode, type: type);
    out.add(e);
    s = sch.review(facetId, s, e.rating, at);
    at = s.due;
  }
  return out;
}

/// The final state after replaying [events] for one facet.
FacetState stateAfter(List<ReviewEvent> events) {
  const sch = FakeScheduler();
  FacetState? s;
  for (final e in events) {
    s = sch.review(e.facetId, s, e.rating, e.at);
  }
  return s!;
}
