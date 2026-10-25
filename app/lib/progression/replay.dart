/// Chronological replay of the review log through a [Scheduler].
///
/// Everything in progression derives from this: for each event we know the
/// facet's state just before and just after it, and the XP it earned. The
/// replay is canonical: events are de-duplicated by id and ordered by
/// `(at, id)`, so any insertion order (e.g. after a sync merge) gives the same
/// steps, XP and states.
library;

import 'dart:collection';

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'xp.dart';

/// One replayed review event.
@immutable
class ReplayStep {
  const ReplayStep({
    required this.index,
    required this.event,
    required this.before,
    required this.after,
    required this.xp,
    required this.cumulativeXp,
  });

  /// Position in canonical order.
  final int index;
  final ReviewEvent event;

  /// The facet's state just before this event (null = first review ever).
  final FacetState? before;

  /// The facet's state just after this event.
  final FacetState after;

  /// XP this event earned.
  final int xp;

  /// Total XP up to and including this event.
  final int cumulativeXp;

  bool get isFirstReview => before == null;
}

/// The canonical order of review events: by instant, then by id.
int compareEvents(ReviewEvent a, ReviewEvent b) {
  final c = a.at.compareTo(b.at);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// De-duplicates [events] by id, sorts them canonically and applies answer
/// overrides ([applyOverrides]: an overridden answer counts as right, the
/// override events themselves are not steps). Skill resets and their undos
/// ([kResetType], [kResetUndoType]) are no steps either: [LogReplay] applies
/// resets to the facet states only ([activeResets]).
List<ReviewEvent> canonicalOrder(Iterable<ReviewEvent> events) {
  final sorted = List<ReviewEvent>.of(events)..sort(compareEvents);
  final seen = <String>{};
  return [
    for (final e in applyOverrides([for (final e in sorted) if (seen.add(e.id)) e]))
      if (!e.isReset && !e.isResetUndo) e,
  ];
}

/// The skill resets of [events] that are not undone, canonically ordered
/// and de-duplicated.
List<ReviewEvent> activeResets(Iterable<ReviewEvent> events) {
  final sorted = List<ReviewEvent>.of([for (final e in events) if (e.isReset || e.isResetUndo) e])
    ..sort(compareEvents);
  final seen = <String>{};
  return [for (final e in resolveResets([for (final e in sorted) if (seen.add(e.id)) e])) if (e.isReset) e];
}

/// What [LogReplay.update] had to do.
enum ReplayUpdate { unchanged, appended, rebuilt }

/// Incrementally maintained replay of a review log.
///
/// [update] accepts the full log in any order. When the new canonical log
/// extends the old one (the common case: new answers appended at the end) only
/// the new events are replayed; otherwise (an older event arrived, e.g. from a
/// sync merge) everything is rebuilt. Either way the result equals a full replay.
class LogReplay {
  LogReplay({required this.scheduler, this.xpRules = const XpRules()});

  final Scheduler scheduler;
  final XpRules xpRules;

  final List<ReplayStep> _steps = [];
  final Map<String, FacetState> _states = {};
  final Set<String> _ids = {};
  int _version = 0;

  /// Active skill resets ([activeResets]), in order, and per facet.
  List<ReviewEvent> _resets = const [];
  final Map<String, List<ReviewEvent>> _resetsByFacet = {};

  /// The reset and undo events of the last [update] (they are no steps),
  /// kept for a rebuild by [add].
  final Map<String, ReviewEvent> _markers = {};

  /// The last step applied per facet.
  final Map<String, ReviewEvent> _lastByFacet = {};

  /// Replayed steps in canonical order.
  List<ReplayStep> get steps => UnmodifiableListView(_steps);

  /// Current state of every reviewed facet.
  Map<String, FacetState> get states => UnmodifiableMapView(_states);

  int get totalXp => _steps.isEmpty ? 0 : _steps.last.cumulativeXp;

  int get length => _steps.length;

  /// Incremented whenever the steps change; lets callers cache derived data.
  int get version => _version;

  /// Replays [events] (any order, duplicates allowed).
  ReplayUpdate update(Iterable<ReviewEvent> events) {
    final all = events is List<ReviewEvent> ? events : events.toList();
    final canon = canonicalOrder(all);
    final resets = activeResets(all);
    final resetsSame = resets.length == _resets.length &&
        [for (var i = 0; i < resets.length; i++) resets[i].id == _resets[i].id].every((b) => b);
    var prefixOk = resetsSame && canon.length >= _steps.length;
    if (prefixOk) {
      for (var i = 0; i < _steps.length; i++) {
        final a = canon[i], b = _steps[i].event;
        // An override changes an earlier event's verdict, not its id.
        if (a.id != b.id || a.rating != b.rating || a.correct != b.correct) {
          prefixOk = false;
          break;
        }
      }
    }
    _markers
      ..clear()
      ..addAll({for (final e in all) if (e.isReset || e.isResetUndo) e.id: e});
    if (prefixOk && canon.length == _steps.length) return ReplayUpdate.unchanged;
    if (!prefixOk) {
      _reset();
      _setResets(resets);
      canon.forEach(_apply);
      _settleResets();
      _version++;
      return ReplayUpdate.rebuilt;
    }
    for (var i = _steps.length; i < canon.length; i++) {
      _apply(canon[i]);
    }
    _settleResets();
    _version++;
    return ReplayUpdate.appended;
  }

  void _setResets(List<ReviewEvent> resets) {
    _resets = resets;
    _resetsByFacet.clear();
    for (final r in resets) {
      (_resetsByFacet[r.facetId] ??= []).add(r);
    }
  }

  /// Whether a reset of [facetId] lies after [from] (null: the start) and
  /// before [to] (null: the end).
  bool _resetBetween(String facetId, ReviewEvent? from, ReviewEvent? to) {
    final list = _resetsByFacet[facetId];
    if (list == null) return false;
    for (final r in list) {
      if ((from == null || compareEvents(from, r) < 0) && (to == null || compareEvents(r, to) < 0)) return true;
    }
    return false;
  }

  /// Facets whose last word is a reset have no state.
  void _settleResets() {
    for (final f in _resetsByFacet.keys) {
      if (_states.containsKey(f) && _resetBetween(f, _lastByFacet[f], null)) _states.remove(f);
    }
  }

  /// Adds one event. Cheap when it sorts after every known event; otherwise
  /// the whole log is rebuilt. Duplicates (same id) are ignored.
  ReplayUpdate add(ReviewEvent event) {
    if (_ids.contains(event.id) || _markers.containsKey(event.id)) return ReplayUpdate.unchanged;
    if (event.isOverride || event.isReset || event.isResetUndo) {
      return update([for (final s in _steps) s.event, ..._markers.values, event]);
    }
    if (_steps.isEmpty || compareEvents(_steps.last.event, event) < 0) {
      _apply(event);
      _version++;
      return ReplayUpdate.appended;
    }
    return update([for (final s in _steps) s.event, ..._markers.values, event]);
  }

  void _reset() {
    _steps.clear();
    _states.clear();
    _ids.clear();
    _lastByFacet.clear();
  }

  void _apply(ReviewEvent e) {
    // A reset since the facet's last step: it starts again from scratch.
    final before = _resetBetween(e.facetId, _lastByFacet[e.facetId], e) ? null : _states[e.facetId];
    _lastByFacet[e.facetId] = e;
    final after = scheduler.review(e.facetId, before, e.rating, e.at);
    final xp = xpRules.xpFor(e, before, scheduler);
    _states[e.facetId] = after;
    _ids.add(e.id);
    _steps.add(ReplayStep(
      index: _steps.length,
      event: e,
      before: before,
      after: after,
      xp: xp,
      cumulativeXp: totalXp + xp,
    ));
  }

  /// Facet states after the first [count] steps (i.e. just before step [count]).
  Map<String, FacetState> statesAfterSteps(int count) {
    final n = count.clamp(0, _steps.length);
    final m = <String, FacetState>{};
    final last = <String, ReviewEvent>{};
    for (var i = 0; i < n; i++) {
      final s = _steps[i];
      m[s.event.facetId] = s.after;
      last[s.event.facetId] = s.event;
    }
    if (_resets.isNotEmpty) {
      final cutoff = n < _steps.length ? _steps[n].event : null;
      for (final f in _resetsByFacet.keys) {
        if (m.containsKey(f) && _resetBetween(f, last[f], cutoff)) m.remove(f);
      }
    }
    return m;
  }

  /// Index of the first step at or after [instant] (== length when none).
  int firstStepAtOrAfter(DateTime instant) {
    var lo = 0, hi = _steps.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_steps[mid].event.at.isBefore(instant)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
