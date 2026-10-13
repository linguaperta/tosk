import 'package:tosk/core/core.dart';
import 'package:tosk/progression/replay.dart';

/// In-memory [ProgressStore]: the log is a list, states are replayed on demand.
class FakeProgressStore implements ProgressStore {
  FakeProgressStore(this.scheduler, [Iterable<ReviewEvent> events = const []]) {
    this.events.addAll(events);
  }

  final Scheduler scheduler;
  final List<ReviewEvent> events = [];
  final Map<String, String> settings = {};
  final List<MistakeRecord> _mistakes = [];
  int logCalls = 0;

  Map<String, FacetState> _states() {
    final m = <String, FacetState>{};
    for (final e in canonicalOrder(events)) {
      m[e.facetId] = scheduler.review(e.facetId, m[e.facetId], e.rating, e.at);
    }
    return m;
  }

  @override
  Future<FacetState> record(ReviewEvent event) async {
    events.add(event);
    return _states()[event.facetId]!;
  }

  @override
  Future<FacetState?> state(String facetId) async => _states()[facetId];

  @override
  Future<Map<String, FacetState>> states(Iterable<String> facetIds) async {
    final all = _states();
    return {for (final f in facetIds) if (all[f] != null) f: all[f]!};
  }

  @override
  Future<List<FacetState>> allStates({String? courseId}) async =>
      _states().values.where((s) => courseId == null || s.facetId.startsWith('$courseId:')).toList();

  @override
  Future<List<ReviewEvent>> log({DateTime? since, String? courseId, String? facetId}) async {
    logCalls++;
    return canonicalOrder(events)
        .where((e) =>
            (since == null || !e.at.isBefore(since)) &&
            (courseId == null || e.facetId.startsWith('$courseId:')) &&
            (facetId == null || e.facetId == facetId))
        .toList();
  }

  @override
  Future<void> rebuildStates() async {}

  @override
  Future<List<MistakeRecord>> mistakes({String? courseId, int limit = 100}) async => _mistakes.take(limit).toList();

  @override
  Future<void> saveMistake(MistakeRecord mistake) async => _mistakes.add(mistake);

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      settings.remove(key);
    } else {
      settings[key] = value;
    }
  }
}
