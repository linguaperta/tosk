/// "Tough words" (leeches): facets the learner keeps forgetting. Derived from
/// the facet states (themselves derived from the log), so it syncs.
library;

import 'package:meta/meta.dart';

import '../core/interfaces/course_data.dart';
import '../core/models/facet.dart';
import '../core/models/progress.dart';

/// Lapses (forgotten after graduating: an Again in review) from which a
/// facet counts as a tough word. The setting `lesson.leech_lapses` overrides it.
const int kToughWordLapses = 4;

@immutable
class ToughWord {
  const ToughWord(this.facet, this.state);
  final SkillFacet facet;
  final FacetState state;
  int get lapses => state.lapses;
}

/// The course's tough words: facets trained by some skill with at least
/// [minLapses] lapses, one per facet, most lapses first (then by facet id).
List<ToughWord> toughWords(CourseData course, Iterable<FacetState> states, {int minLapses = kToughWordLapses}) {
  final byId = {
    for (final s in states)
      if (s.lapses >= minLapses) s.facetId: s,
  };
  if (byId.isEmpty) return const [];
  final seen = <String>{};
  final out = <ToughWord>[
    for (final skill in course.skills)
      for (final f in course.skillFacets(skill.id))
        if (byId[f.facetId] case final s? when seen.add(f.facetId)) ToughWord(f, s),
  ];
  out.sort((a, b) {
    final c = b.lapses.compareTo(a.lapses);
    return c != 0 ? c : a.facet.facetId.compareTo(b.facet.facetId);
  });
  return out;
}
