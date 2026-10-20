/// What cloud sync needs from a progress store beyond [ProgressStore]: the log
/// in insertion order (the upload queue) and change notifications. Pure Dart.
library;

import '../../core/core.dart';

/// The review log in insertion order. Positions only grow, so "everything
/// after position N" is a crash-safe upload queue: an event is in it from the
/// moment its insert commits, whatever happens to the app afterwards.
///
/// `ProgressRepo` uses SQLite's `rowid` of `review_log` (the table has a text
/// primary key, so rowids are assigned in insert order; the database is never
/// `VACUUM`ed, which could renumber them). `InMemoryProgressStore` uses its
/// insertion order.
abstract interface class SequencedLog {
  /// Events inserted after position [after] (0 = from the start), in
  /// insertion order, at most [limit], each with its position.
  Future<List<(int, ReviewEvent)>> eventsAfter(int after, {int limit = 500});

  /// How many events were inserted after position [after].
  Future<int> countAfter(int after);
}

/// Listeners for changes made through a store's own API (not imports).
class ProgressListeners {
  final List<void Function(ReviewEvent event)> _recorded = [];
  final List<void Function(String key, String? value)> _settings = [];

  /// Called after [ProgressStore.record] stored a new event.
  void Function() onRecorded(void Function(ReviewEvent event) f) {
    _recorded.add(f);
    return () => _recorded.remove(f);
  }

  /// Called after [ProgressStore.setSetting].
  void Function() onSettingChanged(void Function(String key, String? value) f) {
    _settings.add(f);
    return () => _settings.remove(f);
  }

  void recorded(ReviewEvent e) {
    for (final f in List.of(_recorded)) {
      f(e);
    }
  }

  void settingChanged(String key, String? value) {
    for (final f in List.of(_settings)) {
      f(key, value);
    }
  }
}
