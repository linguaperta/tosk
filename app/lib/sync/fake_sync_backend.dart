/// An in-memory [SyncBackend] that behaves like the Firestore one: per-account
/// storage, server-assigned write times (strictly increasing), batches
/// replaced by id, paging, and a switch to simulate being offline. For tests
/// and the debug screen. Pure Dart.
library;

import '../core/core.dart';

/// The shared "server": several [FakeSyncBackend]s (devices) talk to one.
class FakeSyncServer {
  FakeSyncServer({DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  DateTime Function() clock;

  /// While true, every call throws (no network).
  bool offline = false;
  int writes = 0;
  int reads = 0;

  final Map<String, Map<String, _Stored<EventBatch>>> _batches = {};
  final Map<String, Map<String, _Stored<SyncedSetting>>> _settings = {};
  DateTime _last = DateTime.utc(2000);

  DateTime _now() {
    var t = clock().toUtc();
    if (!t.isAfter(_last)) t = _last.add(const Duration(microseconds: 1));
    return _last = t;
  }

  void _check() {
    if (offline) throw const FakeOfflineException();
  }

  /// Every event id the account holds (after union).
  Set<String> eventIds(String account) => {
        for (final b in (_batches[account] ?? const {}).values)
          for (final e in b.value.events) e.event.id,
      };

  int batchCount(String account) => _batches[account]?.length ?? 0;

  Map<String, String?> settings(String account) => {
        for (final s in (_settings[account] ?? const {}).values) s.value.key: s.value.value,
      };
}

class FakeOfflineException implements Exception {
  const FakeOfflineException();
  @override
  String toString() => 'No network (fake)';
}

class _Stored<T> {
  _Stored(this.cursor, this.value);
  final SyncCursor cursor;
  final T value;
}

int _cmp(SyncCursor a, SyncCursor b) {
  final t = a.time.compareTo(b.time);
  return t != 0 ? t : a.id.compareTo(b.id);
}

bool _isAfter(SyncCursor c, SyncCursor? after) {
  if (after == null) return true;
  if (after.id.isEmpty) return !c.time.isBefore(after.time); // from that time on
  return _cmp(c, after) > 0;
}

class FakeSyncBackend implements SyncBackend {
  FakeSyncBackend(this.server, {this.account});

  final FakeSyncServer server;

  /// Null = signed out.
  String? account;

  @override
  String get id => 'fake';
  @override
  bool get isConfigured => account != null;
  @override
  String? get accountId => account;

  String get _acct => account ?? (throw const SyncAuthException('Not signed in'));

  @override
  Future<void> pushEvents(String batchId, String device, List<SyncedEvent> events) async {
    server._check();
    final t = server._now();
    final c = SyncCursor(t.toIso8601String(), batchId);
    server.writes++;
    (server._batches[_acct] ??= {})[batchId] =
        _Stored(c, EventBatch(id: batchId, cursor: c, device: device, events: List.unmodifiable(events)));
  }

  @override
  Future<SyncPage<EventBatch>> pullEvents({SyncCursor? after, int limit = 50}) async {
    server._check();
    final all = [
      for (final s in (server._batches[_acct] ?? const <String, _Stored<EventBatch>>{}).values)
        if (_isAfter(s.cursor, after)) s,
    ]..sort((a, b) => _cmp(a.cursor, b.cursor));
    final page = all.take(limit).map((s) => s.value).toList();
    server.reads += page.isEmpty ? 1 : page.length;
    return SyncPage(page, hasMore: all.length > limit);
  }

  @override
  Future<void> pushSettings(List<SyncedSetting> settings) async {
    server._check();
    final t = server._now();
    final m = server._settings[_acct] ??= {};
    for (final s in settings) {
      final c = SyncCursor(t.toIso8601String(), s.key);
      server.writes++;
      m[s.key] = _Stored(
        c,
        SyncedSetting(key: s.key, value: s.value, changedAtMs: s.changedAtMs, device: s.device, cursor: c),
      );
    }
  }

  @override
  Future<SyncPage<SyncedSetting>> pullSettings({SyncCursor? after, int limit = 200}) async {
    server._check();
    final all = [
      for (final s in (server._settings[_acct] ?? const <String, _Stored<SyncedSetting>>{}).values)
        if (_isAfter(s.cursor, after)) s,
    ]..sort((a, b) => _cmp(a.cursor, b.cursor));
    final page = all.take(limit).map((s) => s.value).toList();
    server.reads += page.isEmpty ? 1 : page.length;
    return SyncPage(page, hasMore: all.length > limit);
  }

  @override
  Future<void> deleteAll() async {
    server._check();
    server._batches.remove(_acct);
    server._settings.remove(_acct);
  }
}
