import 'dart:math' as math;

import 'package:tosk/core/core.dart';

import 'fake_course.dart';

/// A plausible random review log over [days] days: sessions of lessons,
/// non-stop runs and lab drills, at varied times of day, on all course facets.
List<ReviewEvent> randomLog({int seed = 1, int days = 60, DateTime? start}) {
  final rnd = math.Random(seed);
  final facets = [...greetingFacets, ...presentFacets, ...pastFacets, 'nl:huis#rec'];
  final types = ['multiple_choice', 'flashcard', 'conj_pick', 'conj_grid', 'cloze', 'match_pairs'];
  final modes = ['lesson', 'nonstop', 'lab'];
  final t0 = start ?? DateTime.utc(2026, 8, 1);
  final out = <ReviewEvent>[];
  var n = 0;
  for (var d = 0; d < days; d++) {
    if (rnd.nextDouble() < 0.2) continue; // skipped day
    final sessions = 1 + rnd.nextInt(3);
    for (var s = 0; s < sessions; s++) {
      final sid = 's$d-$s';
      final mode = modes[rnd.nextInt(modes.length)];
      var at = t0.add(Duration(days: d, hours: rnd.nextInt(24), minutes: rnd.nextInt(60)));
      final len = 5 + rnd.nextInt(30);
      for (var i = 0; i < len; i++) {
        at = at.add(Duration(seconds: 3 + rnd.nextInt(20)));
        final ok = rnd.nextDouble() < 0.82;
        final rating = ok ? (rnd.nextDouble() < 0.2 ? Rating.easy : Rating.good) : Rating.again;
        out.add(ReviewEvent(
          id: 'r${(n++).toString().padLeft(6, '0')}',
          facetId: facets[rnd.nextInt(facets.length)],
          at: at,
          rating: rating,
          exerciseType: types[rnd.nextInt(types.length)],
          inputMode: InputMode.tap,
          responseMs: 1000 + rnd.nextInt(5000),
          correct: ok,
          sessionId: sid,
          mode: mode,
        ));
      }
    }
  }
  return out;
}
