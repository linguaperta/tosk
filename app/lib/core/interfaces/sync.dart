/// Review-log sync. What syncs is the append-only review log; merging is the
/// union of events by id, after which facet states are recomputed, so conflicts
/// cannot happen. v1 ships [NullSyncBackend] (and a file export/import backend
/// in `data/sync/`); a Google Drive `appDataFolder` backend comes later. Pure Dart.
library;

import '../models/progress.dart';

abstract interface class SyncBackend {
  /// Stable id: 'none', 'file', 'drive', ...
  String get id;

  /// Whether the backend is set up and can be used now.
  bool get isConfigured;

  /// Sends local events to the remote. Implementations dedupe by event id, so
  /// pushing the whole log (or overlapping batches) is always safe.
  Future<void> push(List<ReviewEvent> events);

  /// Fetches remote events (all, or only those at/after [since]). The caller
  /// merges them into the local log by event id.
  Future<List<ReviewEvent>> pull({DateTime? since});
}

/// Sync disabled.
class NullSyncBackend implements SyncBackend {
  const NullSyncBackend();
  @override
  String get id => 'none';
  @override
  bool get isConfigured => false;
  @override
  Future<void> push(List<ReviewEvent> events) async {}
  @override
  Future<List<ReviewEvent>> pull({DateTime? since}) async => const [];
}
