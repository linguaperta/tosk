/// Cloud sync contracts (v0.7). What syncs is the append-only review log plus
/// a few settings. Merging the log is the union of events by id, after which
/// facet states are recomputed, so conflicts cannot happen; settings are
/// last-writer-wins per key. The merge itself lives in `lib/sync/sync_engine.dart`;
/// a backend only stores and returns batches. Pure Dart.
///
/// Implementations: [NullSyncBackend] (no account, the default),
/// `FirestoreSyncBackend` (Firebase, `lib/sync/firestore_backend.dart`) and
/// `FakeSyncBackend` (in memory with a server clock, for tests).
library;

import 'package:meta/meta.dart';

import '../models/progress.dart';

/// A review event as it travels: the event plus the user's UTC offset when it
/// was recorded, so local calendar days (streaks, the heatmap, the daily goal)
/// stay right on every device, whatever time zone that device is in.
@immutable
class SyncedEvent {
  const SyncedEvent(this.event, this.utcOffsetMinutes);
  final ReviewEvent event;
  final int utcOffsetMinutes;
}

/// Position in a backend's stream of writes: the server time of a write plus
/// its document id (to order writes with the same time). Opaque to the engine
/// except for [serverTime], which is used for the overlap window and clamping.
@immutable
class SyncCursor {
  const SyncCursor(this.serverTime, this.id);

  /// Server time as the backend reports it (RFC 3339; kept as text so no
  /// precision is lost).
  final String serverTime;
  final String id;

  /// [serverTime] parsed (fractions beyond microseconds are dropped).
  DateTime get time =>
      DateTime.parse(serverTime.replaceFirstMapped(RegExp(r'(\.\d{6})\d+'), (m) => m[1]!)).toUtc();

  String encode() => '$serverTime|$id';
  static SyncCursor? decode(String? s) {
    if (s == null || !s.contains('|')) return null;
    final i = s.indexOf('|');
    return SyncCursor(s.substring(0, i), s.substring(i + 1));
  }

  @override
  bool operator ==(Object other) => other is SyncCursor && other.serverTime == serverTime && other.id == id;
  @override
  int get hashCode => Object.hash(serverTime, id);
  @override
  String toString() => encode();
}

/// One uploaded batch of events, as read back.
@immutable
class EventBatch {
  const EventBatch({required this.id, required this.cursor, required this.device, required this.events});
  final String id;

  /// Where this batch sits in the write stream; [SyncCursor.time] is the
  /// server time it was written, which bounds its events' timestamps.
  final SyncCursor cursor;
  final String device;
  final List<SyncedEvent> events;
}

/// One synced setting: its value (null = cleared), when it was changed
/// (client clock, UTC ms) and on which device.
@immutable
class SyncedSetting {
  const SyncedSetting({required this.key, required this.value, required this.changedAtMs, required this.device, this.cursor});
  final String key;
  final String? value;
  final int changedAtMs;
  final String device;

  /// Set on settings read back from a backend (null when pushing).
  final SyncCursor? cursor;
}

/// A page of results plus whether more follow.
@immutable
class SyncPage<T> {
  const SyncPage(this.items, {required this.hasMore});
  final List<T> items;
  final bool hasMore;
}

/// Thrown for failures the user may need to act on (signed out, permission
/// denied). Network errors surface as the client's own exceptions and are
/// simply retried at the next sync.
class SyncAuthException implements Exception {
  const SyncAuthException(this.message);
  final String message;
  @override
  String toString() => 'SyncAuthException: $message';
}

/// Storage for one signed-in account's synced data.
abstract interface class SyncBackend {
  /// Stable id: 'none', 'firestore', 'fake', ...
  String get id;

  /// Whether the backend is set up and signed in.
  bool get isConfigured;

  /// The account the data belongs to (null when signed out).
  String? get accountId;

  /// Writes [events] as batch [batchId]. Writing the same batch id again
  /// replaces it, so a retried upload never duplicates anything.
  Future<void> pushEvents(String batchId, String device, List<SyncedEvent> events);

  /// Batches written after [after] (all when null), oldest first.
  Future<SyncPage<EventBatch>> pullEvents({SyncCursor? after, int limit = 50});

  /// Writes settings (one record per key; a newer write of a key replaces it).
  Future<void> pushSettings(List<SyncedSetting> settings);

  /// Settings written after [after] (all when null), oldest first.
  Future<SyncPage<SyncedSetting>> pullSettings({SyncCursor? after, int limit = 200});

  /// Deletes everything this account stored.
  Future<void> deleteAll();
}

/// Sync disabled (no configuration or not signed in).
class NullSyncBackend implements SyncBackend {
  const NullSyncBackend();
  @override
  String get id => 'none';
  @override
  bool get isConfigured => false;
  @override
  String? get accountId => null;
  @override
  Future<void> pushEvents(String batchId, String device, List<SyncedEvent> events) async {}
  @override
  Future<SyncPage<EventBatch>> pullEvents({SyncCursor? after, int limit = 50}) async =>
      const SyncPage([], hasMore: false);
  @override
  Future<void> pushSettings(List<SyncedSetting> settings) async {}
  @override
  Future<SyncPage<SyncedSetting>> pullSettings({SyncCursor? after, int limit = 200}) async =>
      const SyncPage([], hasMore: false);
  @override
  Future<void> deleteAll() async {}
}
