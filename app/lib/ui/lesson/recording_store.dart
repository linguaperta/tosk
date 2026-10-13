import '../../core/core.dart';

/// A [ProgressStore] decorator that remembers the last event recorded per
/// session, so the player can feed non-stop scoring with **exactly** the `at`
/// the session wrote to the review log (the replayed best-run record then
/// equals the live score; see `docs/progression.md`, "Non-stop extras").
///
/// Sessions must record through this store (`recordingStoreProvider`), and
/// record every facet outcome of one exercise with the same `at`.
class RecordingProgressStore implements ProgressStore {
  RecordingProgressStore(this.inner);

  final ProgressStore inner;
  final Map<String, ReviewEvent> _lastBySession = {};

  /// The last event recorded for [sessionId] (with `at` in stored precision:
  /// UTC, whole milliseconds), or null.
  ReviewEvent? lastRecorded(String sessionId) => _lastBySession[sessionId];

  /// `at` of the last event recorded for [sessionId], or null.
  DateTime? lastRecordedAt(String sessionId) => _lastBySession[sessionId]?.at;

  /// Forgets [sessionId] (when its player closes).
  void forget(String sessionId) => _lastBySession.remove(sessionId);

  @override
  Future<FacetState> record(ReviewEvent event) async {
    final state = await inner.record(event);
    final sid = event.sessionId;
    if (sid != null) _lastBySession[sid] = _stored(event);
    return state;
  }

  static ReviewEvent _stored(ReviewEvent e) {
    final at = DateTime.fromMillisecondsSinceEpoch(e.at.millisecondsSinceEpoch, isUtc: true);
    return at == e.at
        ? e
        : ReviewEvent(
            id: e.id,
            facetId: e.facetId,
            at: at,
            rating: e.rating,
            exerciseType: e.exerciseType,
            inputMode: e.inputMode,
            responseMs: e.responseMs,
            correct: e.correct,
            answer: e.answer,
            sessionId: e.sessionId,
            mode: e.mode,
          );
  }

  @override
  Future<FacetState?> state(String facetId) => inner.state(facetId);

  @override
  Future<Map<String, FacetState>> states(Iterable<String> facetIds) => inner.states(facetIds);

  @override
  Future<List<FacetState>> allStates({String? courseId}) => inner.allStates(courseId: courseId);

  @override
  Future<List<ReviewEvent>> log({DateTime? since, String? courseId, String? facetId}) =>
      inner.log(since: since, courseId: courseId, facetId: facetId);

  @override
  Future<void> rebuildStates() => inner.rebuildStates();

  @override
  Future<List<MistakeRecord>> mistakes({String? courseId, int limit = 100}) =>
      inner.mistakes(courseId: courseId, limit: limit);

  @override
  Future<void> saveMistake(MistakeRecord mistake) => inner.saveMistake(mistake);

  @override
  Future<String?> getSetting(String key) => inner.getSetting(key);

  @override
  Future<void> setSetting(String key, String? value) => inner.setSetting(key, value);
}
