/// A [ProgressStore] kept entirely in memory, with the same semantics as the
/// drift-backed `ProgressRepo`. Pure Dart: for engine/progression tests and
/// anything that needs a store without a database.
library;

import '../../core/core.dart';
import '../fsrs/fsrs_scheduler.dart';
import '../sync/progress_backup.dart' show SettingsLister;
import 'event_importer.dart';
import 'replay.dart';
import 'sequenced_log.dart';

class InMemoryProgressStore implements ProgressStore, EventImporter, SettingsLister, SequencedLog {
  InMemoryProgressStore({Scheduler? scheduler}) : scheduler = scheduler ?? FsrsScheduler();

  final Scheduler scheduler;

  /// Same notifications as `ProgressRepo.listeners`.
  final ProgressListeners listeners = ProgressListeners();

  final Map<String, ReviewEvent> _events = {}; // id -> event
  final Map<String, List<ReviewEvent>> _byFacet = {}; // kept in (at, id) order
  final Map<String, FacetState> _states = {};
  final Map<String, MistakeRecord> _mistakes = {};
  final Map<String, String> _settings = {};

  @override
  Future<FacetState> record(ReviewEvent event) async {
    final e = normalizeEvent(event);
    final fresh = !_events.containsKey(e.id);
    final s = _record(e);
    if (fresh) listeners.recorded(e);
    return s;
  }

  /// Insertion order (the map keeps it): position i+1 is the i-th event inserted.
  @override
  Future<List<(int, ReviewEvent)>> eventsAfter(int after, {int limit = 500}) async {
    final all = _events.values.toList();
    final out = <(int, ReviewEvent)>[];
    for (var i = after; i < all.length && out.length < limit; i++) {
      out.add((i + 1, all[i]));
    }
    return out;
  }

  @override
  Future<int> countAfter(int after) async => (_events.length - after).clamp(0, 1 << 62);

  FacetState _record(ReviewEvent e) {
    if (_events.containsKey(e.id)) {
      // Idempotent: the same event (e.g. from a sync merge) is applied once.
      return _states[e.facetId] ?? _replayFacet(e.facetId)!;
    }
    _events[e.id] = e;
    final list = _byFacet[e.facetId] ??= [];
    final isLatest = list.isEmpty || compareEvents(e, list.last) > 0;
    // An override rewrites an earlier event: always replay the facet.
    if (isLatest && !e.isOverride && (list.isEmpty || _states.containsKey(e.facetId))) {
      list.add(e);
      return _states[e.facetId] = scheduler.review(e.facetId, _states[e.facetId], e.rating, e.at);
    }
    // Out of order (or missing state): insert in place and replay this facet.
    list
      ..add(e)
      ..sort(compareEvents);
    return _replayFacet(e.facetId)!;
  }

  FacetState? _replayFacet(String facetId) {
    final s = foldFacet(scheduler, facetId, _byFacet[facetId] ?? const []);
    if (s == null) {
      _states.remove(facetId);
    } else {
      _states[facetId] = s;
    }
    return s;
  }

  /// Merges events (e.g. from sync or an import), ignoring ids already present.
  /// Returns how many were new.
  @override
  Future<int> importEvents(Iterable<ReviewEvent> events) async {
    final touched = <String>{};
    var added = 0;
    for (final raw in events) {
      final e = normalizeEvent(raw);
      if (_events.containsKey(e.id)) continue;
      _events[e.id] = e;
      (_byFacet[e.facetId] ??= []).add(e);
      touched.add(e.facetId);
      added++;
    }
    for (final f in touched) {
      _byFacet[f]!.sort(compareEvents);
      _replayFacet(f);
    }
    return added;
  }

  @override
  Future<FacetState?> state(String facetId) async => _states[facetId];

  @override
  Future<Map<String, FacetState>> states(Iterable<String> facetIds) async => {
        for (final id in facetIds)
          if (_states[id] != null) id: _states[id]!,
      };

  @override
  Future<List<FacetState>> allStates({String? courseId}) async => [
        for (final s in _states.values)
          if (courseId == null || facetInCourse(s.facetId, courseId)) s,
      ]..sort((a, b) => a.facetId.compareTo(b.facetId));

  @override
  Future<List<ReviewEvent>> log({DateTime? since, String? courseId, String? facetId}) async {
    final sinceMs = since?.millisecondsSinceEpoch;
    return [
      for (final e in _events.values)
        if ((sinceMs == null || e.at.millisecondsSinceEpoch >= sinceMs) &&
            (courseId == null || facetInCourse(e.facetId, courseId)) &&
            (facetId == null || e.facetId == facetId))
          e,
    ]..sort(compareEvents);
  }

  @override
  Future<void> rebuildStates() async {
    _states
      ..clear()
      ..addAll(replayLog(scheduler, _events.values));
    for (final l in _byFacet.values) {
      l.sort(compareEvents);
    }
  }

  @override
  Future<List<MistakeRecord>> mistakes({String? courseId, int limit = 100}) async {
    final list = [
      for (final m in _mistakes.values)
        if (courseId == null || facetInCourse(m.facetId, courseId)) m,
    ]..sort((a, b) {
        final c = b.at.compareTo(a.at);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    return list.take(limit).toList();
  }

  @override
  Future<void> saveMistake(MistakeRecord mistake) async => _mistakes[mistake.id] = MistakeRecord(
        id: mistake.id,
        facetId: mistake.facetId,
        at: toStoredTime(mistake.at),
        exerciseType: mistake.exerciseType,
        prompt: mistake.prompt,
        expected: mistake.expected,
        given: mistake.given,
        skillId: mistake.skillId,
        note: mistake.note,
        explanation: mistake.explanation,
      );

  @override
  Future<Map<String, String>> allSettings() async => Map.of(_settings);

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      _settings.remove(key);
    } else {
      _settings[key] = value;
    }
    listeners.settingChanged(key, value);
  }
}
