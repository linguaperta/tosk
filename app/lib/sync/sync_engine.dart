/// The sync algorithm (v0.7), independent of Firebase and of Flutter.
///
/// **Review log: union by event id.** The log is append-only and every event
/// has a permanent UUID, so merging two devices' logs is their union; facet
/// states are recomputed from the merged log (`rebuildStates()`), so there is
/// nothing to resolve. One run:
///
/// 1. **Pull** batches written since the last run (with a 2-minute overlap;
///    re-reading a batch is harmless) and import their events by id.
///    **Clock skew:** an event can't have happened after the server received
///    it, so a time more than 5 minutes after its batch's server time is
///    clamped to the server time. Every device clamps the same way, so they
///    all replay the same log (the device with the wrong clock keeps its own
///    copy, which it already has).
/// 2. `rebuildStates()` when anything new arrived.
/// 3. **Push** the upload queue: every event inserted into the local log after
///    the last uploaded position ([SequencedLog]), minus events the account
///    already has (pulled ones), in batches of [batchSize]. A batch's id is a
///    hash of its event ids, so a retried batch overwrites itself. The
///    position only moves after a batch is stored, so a crash or a lost
///    connection just means the batch is sent again next time (offline-first:
///    the queue is the log itself and survives restarts).
/// 4. **Settings, last writer wins** per key, on the change time (clamped to
///    the server time the same way) with the device id as tie-break. The first
///    sync of a device with an account *joins* it: values already in the
///    account win over this device's, except the set-like keys
///    ([SyncEngine.unionKeys], e.g. "my courses"), which become the union.
///
/// **UTC offsets.** Each event carries the user's UTC offset when it was
/// recorded ([SyncedEvent]); [EventOffsets] maps event times to them so local
/// days (streaks, the heatmap, the daily goal) are those the learner lived,
/// whichever time zone the viewing device is in.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../core/core.dart';
import '../data/progress/event_importer.dart';
import '../data/progress/sequenced_log.dart';
import 'sync_store.dart';

/// Event time (UTC ms) → the UTC offset it was recorded with; other instants
/// (and events recorded before sync was set up) use [fallback], the device's
/// own time zone rules.
class EventOffsets {
  EventOffsets({Map<int, int>? minutesByAtMs, Duration Function(DateTime utc)? fallback})
      : _m = minutesByAtMs ?? {},
        fallback = fallback ?? ((u) => u.toLocal().timeZoneOffset);

  final Map<int, int> _m;
  final Duration Function(DateTime utc) fallback;

  Duration offsetAt(DateTime utc) {
    final m = _m[utc.millisecondsSinceEpoch];
    return m == null ? fallback(utc) : Duration(minutes: m);
  }

  void add(int atMs, int minutes) => _m[atMs] = minutes;
  void addAll(Map<int, int> m) => _m.addAll(m);
  int get length => _m.length;
}

/// What one [SyncEngine.sync] did.
class SyncResult {
  const SyncResult({
    this.pulled = 0,
    this.imported = 0,
    this.pushed = 0,
    this.settingsApplied = const [],
    this.settingsPushed = 0,
    this.skipped = false,
  });

  static const notSignedIn = SyncResult(skipped: true);

  /// Events read from the account (new or not).
  final int pulled;

  /// Of those, events new to this device.
  final int imported;

  /// Events uploaded.
  final int pushed;

  /// Settings keys changed on this device by the merge.
  final List<String> settingsApplied;
  final int settingsPushed;

  /// No account: nothing was done.
  final bool skipped;

  bool get changedLocal => imported > 0 || settingsApplied.isNotEmpty;

  @override
  String toString() =>
      'SyncResult(pulled $pulled, imported $imported, pushed $pushed, settings +${settingsApplied.length}/^$settingsPushed)';
}

class SyncEngine {
  SyncEngine({
    required this.store,
    required this.progress,
    required this.importer,
    required this.log,
    required this.backend,
    required this.syncedSettings,
    this.unionKeys = const {},
    DateTime Function()? clock,
    EventOffsets? offsets,
    this.batchSize = 400,
  })  : clock = clock ?? DateTime.now,
        offsets = offsets ?? EventOffsets();

  final SyncStore store;
  final ProgressStore progress;
  final EventImporter importer;
  final SequencedLog log;
  SyncBackend backend;

  /// Setting keys that sync (the rest are device-only).
  final Set<String> syncedSettings;

  /// Comma-separated set settings merged as a union when a device joins.
  final Set<String> unionKeys;
  final DateTime Function() clock;
  final EventOffsets offsets;
  final int batchSize;

  /// Pulled events later than their batch's server time by more than this are clamped.
  static const clampTolerance = Duration(minutes: 5);

  /// Each run re-reads this much before the last cursor.
  static const pullOverlap = Duration(minutes: 2);

  final Map<String, String?> _applying = {};
  Future<SyncResult>? _running;
  String? _device;

  /// Loads the known offsets into [offsets] (call once at start).
  Future<void> loadOffsets() async => offsets.addAll(await store.offsets());

  Future<String> deviceId() async {
    if (_device != null) return _device!;
    var d = await store.get(SyncKeys.device);
    if (d == null) {
      d = const Uuid().v4();
      await store.set(SyncKeys.device, d);
    }
    return _device = d;
  }

  // ------------------------------------------------------------------ hooks

  /// Notes the UTC offset of an event just recorded on this device.
  Future<void> noteRecorded(ReviewEvent e) async {
    final at = e.at.toUtc();
    final minutes = offsets.fallback(at).inMinutes;
    offsets.add(at.millisecondsSinceEpoch, minutes);
    await store.noteOffsets([EventMeta(e.id, at.millisecondsSinceEpoch, minutes)]);
  }

  /// Notes a setting changed on this device (LWW needs the change time).
  Future<void> noteSettingChanged(String key, String? value) async {
    if (!syncedSettings.contains(key)) return;
    if (_applying.containsKey(key) && _applying[key] == value) return; // our own merge
    await store.putStamps([
      SettingStamp(
        key: key,
        value: value,
        changedAtMs: clock().toUtc().millisecondsSinceEpoch,
        device: await deviceId(),
        dirty: true,
      ),
    ]);
  }

  /// Events in the upload queue (some may turn out to be known to the account).
  Future<int> pending() async => log.countAfter(int.tryParse(await store.get(SyncKeys.uploadSeq) ?? '') ?? 0);

  // ------------------------------------------------------------------ sync

  /// One full run (see the library comment). Concurrent calls share one run.
  Future<SyncResult> sync() {
    final running = _running;
    if (running != null) return running;
    final run = _sync();
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<SyncResult> _sync() async {
    final b = backend;
    final account = b.accountId;
    if (!b.isConfigured || account == null) return SyncResult.notSignedIn;
    if (await store.get(SyncKeys.account) != account) {
      // Another account (or the first one): start over for it.
      await store.resetAccount();
      await store.set(SyncKeys.account, account);
    }
    final device = await deviceId();

    final (:pulled, :imported) = await _pullEvents(b);
    if (imported > 0) await progress.rebuildStates();
    final pushed = await _pushEvents(b, device);
    final (:applied, :pushedSettings) = await _syncSettings(b, device);
    await store.set(SyncKeys.lastSync, clock().toUtc().toIso8601String());
    return SyncResult(
      pulled: pulled,
      imported: imported,
      pushed: pushed,
      settingsApplied: applied,
      settingsPushed: pushedSettings,
    );
  }

  static int _compare(SyncCursor a, SyncCursor b) {
    final t = a.time.compareTo(b.time);
    return t != 0 ? t : a.id.compareTo(b.id);
  }

  static SyncCursor? _overlapped(SyncCursor? c) =>
      c == null ? null : SyncCursor(c.time.subtract(pullOverlap).toIso8601String(), '');

  Future<({int pulled, int imported})> _pullEvents(SyncBackend b) async {
    var cursor = SyncCursor.decode(await store.get(SyncKeys.eventsCursor));
    var after = _overlapped(cursor);
    var pulled = 0, imported = 0;
    while (true) {
      final page = await b.pullEvents(after: after, limit: 50);
      final events = <ReviewEvent>[];
      final metas = <EventMeta>[];
      for (final batch in page.items) {
        final server = batch.cursor.time;
        final bound = server.add(clampTolerance);
        for (final se in batch.events) {
          var e = se.event;
          if (e.at.isAfter(bound)) e = e.copyWith(at: server);
          events.add(e);
          metas.add(EventMeta(e.id, e.at.toUtc().millisecondsSinceEpoch, se.utcOffsetMinutes, uploaded: true));
        }
        after = batch.cursor;
        if (cursor == null || _compare(batch.cursor, cursor) > 0) cursor = batch.cursor;
      }
      if (events.isNotEmpty) {
        // Offsets first: an event is only in the log once its offset is known.
        await store.markUploaded(metas);
        final known = await store.meta(metas.map((m) => m.id));
        for (final m in known.values) {
          offsets.add(m.atMs, m.offsetMinutes);
        }
        imported += await importer.importEvents(events);
        pulled += events.length;
      }
      if (cursor != null) await store.set(SyncKeys.eventsCursor, cursor.encode());
      if (!page.hasMore || page.items.isEmpty) break;
    }
    return (pulled: pulled, imported: imported);
  }

  /// Batch id: a hash of the event ids, so a retry overwrites the same batch.
  static String batchIdFor(Iterable<String> eventIds) =>
      sha256.convert(utf8.encode(eventIds.join('\n'))).toString().substring(0, 32);

  Future<int> _pushEvents(SyncBackend b, String device) async {
    var seq = int.tryParse(await store.get(SyncKeys.uploadSeq) ?? '') ?? 0;
    var pushed = 0;
    // Fill each batch up to batchSize, skipping events the account has, so
    // pulled events between local ones don't split batches.
    var send = <SyncedEvent>[];
    var scanned = seq;
    Future<void> flush() async {
      if (send.isNotEmpty) {
        await b.pushEvents(batchIdFor(send.map((s) => s.event.id)), device, send);
        await store.markUploaded([
          for (final s in send)
            EventMeta(s.event.id, s.event.at.toUtc().millisecondsSinceEpoch, s.utcOffsetMinutes),
        ]);
        pushed += send.length;
        send = [];
      }
      if (scanned != seq) {
        seq = scanned;
        await store.set(SyncKeys.uploadSeq, '$seq');
      }
    }

    while (true) {
      final rows = await log.eventsAfter(scanned, limit: batchSize - send.length);
      if (rows.isEmpty) break;
      final meta = await store.meta(rows.map((r) => r.$2.id));
      for (final (_, e) in rows) {
        final m = meta[e.id];
        if (m != null && m.uploaded) continue;
        send.add(SyncedEvent(e, m?.offsetMinutes ?? offsets.offsetAt(e.at.toUtc()).inMinutes));
      }
      scanned = rows.last.$1;
      if (send.length >= batchSize) await flush();
    }
    await flush();
    return pushed;
  }

  static bool _newer(int t1, String d1, int t2, String d2) => t1 != t2 ? t1 > t2 : d1.compareTo(d2) > 0;

  static String _union(String a, String b) => {
        for (final id in [...a.split(','), ...b.split(',')])
          if (id.trim().isNotEmpty) id.trim(),
      }.join(',');

  Future<({List<String> applied, int pushedSettings})> _syncSettings(SyncBackend b, String device) async {
    final now = clock().toUtc().millisecondsSinceEpoch;
    final stamps = await store.stamps();
    final joined = await store.get(SyncKeys.joined) == 'true';

    // Changes the listener missed (made before sync was set up, or by code
    // that bypassed it): stamp them now.
    for (final key in syncedSettings) {
      final local = await progress.getSetting(key);
      final s = stamps[key];
      if (s == null ? local != null : s.value != local) {
        stamps[key] = SettingStamp(key: key, value: local, changedAtMs: now, device: device, dirty: true);
      }
    }

    // Remote changes.
    var cursor = joined ? SyncCursor.decode(await store.get(SyncKeys.settingsCursor)) : null;
    var after = _overlapped(cursor);
    final remote = <String, SyncedSetting>{};
    while (true) {
      final page = await b.pullSettings(after: after);
      for (final r in page.items) {
        final c = r.cursor!;
        after = c;
        if (cursor == null || _compare(c, cursor) > 0) cursor = c;
        if (!syncedSettings.contains(r.key)) continue;
        final serverMs = c.time.millisecondsSinceEpoch;
        final t = r.changedAtMs > serverMs ? serverMs : r.changedAtMs;
        final prev = remote[r.key];
        if (prev == null || _newer(t, r.device, prev.changedAtMs, prev.device)) {
          remote[r.key] = SyncedSetting(key: r.key, value: r.value, changedAtMs: t, device: r.device);
        }
      }
      if (!page.hasMore || page.items.isEmpty) break;
    }

    final applied = <String>[];
    Future<void> apply(String key, String? value) async {
      if (await progress.getSetting(key) == value) return;
      _applying[key] = value;
      try {
        await progress.setSetting(key, value);
      } finally {
        _applying.remove(key);
      }
      applied.add(key);
    }

    for (final r in remote.values) {
      final s = stamps[r.key];
      final clean = SettingStamp(key: r.key, value: r.value, changedAtMs: r.changedAtMs, device: r.device, dirty: false);
      if (!joined) {
        // Joining: the account's value wins; set-like keys become the union.
        final local = s?.value;
        if (unionKeys.contains(r.key) && local != null && r.value != null) {
          final u = _union(r.value!, local);
          await apply(r.key, u);
          stamps[r.key] = u == r.value
              ? clean
              : SettingStamp(key: r.key, value: u, changedAtMs: now, device: device, dirty: true);
        } else {
          await apply(r.key, r.value);
          stamps[r.key] = clean;
        }
        continue;
      }
      if (s == null || _newer(r.changedAtMs, r.device, s.changedAtMs, s.device)) {
        await apply(r.key, r.value);
        stamps[r.key] = clean;
      }
    }

    final dirty = [for (final s in stamps.values) if (s.dirty) s];
    if (dirty.isNotEmpty) {
      await b.pushSettings([
        for (final s in dirty) SyncedSetting(key: s.key, value: s.value, changedAtMs: s.changedAtMs, device: s.device),
      ]);
      for (final s in dirty) {
        stamps[s.key] = s.copyWith(dirty: false);
      }
    }
    await store.putStamps(stamps.values);
    if (cursor != null) await store.set(SyncKeys.settingsCursor, cursor.encode());
    await store.set(SyncKeys.joined, 'true');
    return (applied: applied, pushedSettings: dirty.length);
  }

  // ------------------------------------------------------------------ delete

  /// Deletes the account's data and forgets the account locally (the local
  /// progress stays).
  Future<void> deleteRemote() async {
    await _running?.catchError((Object _) => SyncResult.notSignedIn);
    await backend.deleteAll();
    await store.resetAccount();
  }

}
