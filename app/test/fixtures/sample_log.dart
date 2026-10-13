/// Seeded random review logs for progress tests (reusable).
library;

import 'dart:math';

import 'package:tosk/core/core.dart';

/// A seeded random log: [count] events over 25 facets of [course] (plus one
/// `nl:` facet) spread over ~120 days. About 10% of the events share a handful
/// of identical timestamps, so ordering ties are broken by event id.
List<ReviewEvent> sampleLog({int seed = 42, int count = 600, String course = 'it'}) {
  final rnd = Random(seed);
  final facets = [
    for (var i = 0; i < 25; i++) '$course:w$i#${['rec', 'prod', 'form:presente'][i % 3]}',
    'nl:huis#rec', // another course
  ];
  final start = DateTime.utc(2026, 6, 1).millisecondsSinceEpoch;
  final events = <ReviewEvent>[];
  for (var i = 0; i < count; i++) {
    final facet = facets[rnd.nextInt(facets.length)];
    final at = rnd.nextInt(10) == 0
        ? start + 86400000 * 30 + rnd.nextInt(4) * 1000 // exact ties
        : start + rnd.nextInt(86400 * 120) * 1000 + rnd.nextInt(1000);
    final rating = Rating.values[[0, 1, 2, 2, 2, 2, 3][rnd.nextInt(7)]];
    events.add(ReviewEvent(
      id: _uuid(rnd),
      facetId: facet,
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      rating: rating,
      exerciseType: ExerciseType.values[rnd.nextInt(ExerciseType.values.length)].id,
      inputMode: InputMode.values[rnd.nextInt(InputMode.values.length)],
      responseMs: rnd.nextInt(20000),
      correct: rating != Rating.again,
      answer: rnd.nextBool() ? 'answer $i' : null,
      sessionId: 'session-${i ~/ 12}',
      mode: 'lesson',
    ));
  }
  return events;
}

String _uuid(Random r) {
  String hex(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
}
