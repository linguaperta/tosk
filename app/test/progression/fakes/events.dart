import 'package:tosk/core/core.dart';

/// Builds review events with sequential ids.
class EventFactory {
  int _n = 0;

  ReviewEvent ev(
    String facetId,
    DateTime at, {
    bool correct = true,
    Rating? rating,
    String type = 'multiple_choice',
    String? session,
    String? mode,
    String? id,
  }) =>
      ReviewEvent(
        id: id ?? 'e${(_n++).toString().padLeft(6, '0')}',
        facetId: facetId,
        at: at.toUtc(),
        rating: rating ?? (correct ? Rating.good : Rating.again),
        exerciseType: type,
        inputMode: InputMode.tap,
        responseMs: 1500,
        correct: correct,
        sessionId: session,
        mode: mode,
      );

  /// [n] events on [facetId] (or cycling through [facets]) spaced [gap] apart.
  List<ReviewEvent> many(
    List<String> facets,
    DateTime start,
    int n, {
    Duration gap = const Duration(seconds: 10),
    bool correct = true,
    String type = 'multiple_choice',
    String? session,
    String? mode,
  }) =>
      [
        for (var i = 0; i < n; i++)
          ev(facets[i % facets.length], start.add(gap * i),
              correct: correct, type: type, session: session, mode: mode),
      ];
}

DateTime utc(int y, int m, int d, [int h = 0, int min = 0, int s = 0]) => DateTime.utc(y, m, d, h, min, s);
