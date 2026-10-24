/// Reports for the developer (flags, general feedback, crash reports) that a
/// signed-in learner chose to send: queued on the device (the `outbox` table
/// of `sync.sqlite`) and uploaded by [SyncService] after each sync, a batch
/// per request, with exponential backoff after failures. Offline, reports
/// simply wait. Pure Dart.
///
/// Firestore layout (`firebase/firestore.rules`): `users/{uid}/feedback/{id}`
/// and `users/{uid}/crashes/{id}`, the report's [OutgoingReport.fields] plus
/// `up` (server time). Only the sender (and the owner, with admin
/// credentials) can read them; nobody can change them; "Delete my cloud data"
/// deletes them. A report's document id is its own UUID, so a retried upload
/// rewrites the same document, which the rules allow only unchanged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import 'sync_errors.dart';
import 'sync_store.dart';

/// The Firestore collections reports go to.
abstract final class ReportCollections {
  static const feedback = 'feedback';
  static const crashes = 'crashes';
}

/// One report waiting to be uploaded.
@immutable
class OutgoingReport {
  const OutgoingReport({
    required this.id,
    required this.collection,
    required this.fields,
    required this.createdAtMs,
    this.attempts = 0,
    this.nextAtMs = 0,
  });

  /// The document id (a UUID).
  final String id;

  /// [ReportCollections.feedback] or [ReportCollections.crashes].
  final String collection;

  /// The document's fields: strings and ints only (`up` is added when it is
  /// uploaded).
  final Map<String, Object> fields;
  final int createdAtMs;

  /// Failed uploads so far (offline attempts don't count).
  final int attempts;

  /// Not before this time (UTC ms): the backoff after a failure.
  final int nextAtMs;

  OutgoingReport retryLater({required int attempts, required int nextAtMs}) => OutgoingReport(
    id: id,
    collection: collection,
    fields: fields,
    createdAtMs: createdAtMs,
    attempts: attempts,
    nextAtMs: nextAtMs,
  );

  String encodeFields() => jsonEncode(fields);

  static Map<String, Object> decodeFields(String s) => {
    for (final e in (jsonDecode(s) as Map).entries)
      if (e.value is String || e.value is int) '${e.key}': e.value as Object,
  };

  @override
  String toString() => 'OutgoingReport($collection/$id, attempts $attempts)';
}

/// Stores reports for the developer (Firestore in the app, a fake in tests).
abstract interface class ReportSender {
  /// Uploads [reports] in one request, all or none. Sending a report that is
  /// already stored again changes nothing. Throws [ReportRejected] when the
  /// server refuses the request as invalid (retrying won't help).
  Future<void> sendReports(List<OutgoingReport> reports);
}

/// The server refused a report as malformed (HTTP 400): it is dropped.
class ReportRejected implements Exception {
  const ReportRejected(this.message);
  final String message;
  @override
  String toString() => 'ReportRejected: $message';
}

/// What one [ReportOutbox.flush] did.
@immutable
class OutboxResult {
  const OutboxResult({this.sent = 0, this.dropped = 0, this.failed = 0, this.offline = false});
  final int sent;
  final int dropped;

  /// Reports that failed and wait for their backoff.
  final int failed;
  final bool offline;
  @override
  String toString() => 'OutboxResult(sent $sent, dropped $dropped, failed $failed${offline ? ', offline' : ''})';
}

class ReportOutbox {
  ReportOutbox(this.store, {DateTime Function()? clock, this.batchSize = 20, this.maxQueued = 200})
    : clock = clock ?? DateTime.now;

  final OutboxStore store;
  final DateTime Function() clock;

  /// Reports per upload request.
  final int batchSize;

  /// The queue never holds more (the oldest are dropped).
  final int maxQueued;

  /// The pause before the next try after [attempts] failures: 30 s, doubling,
  /// at most an hour.
  static Duration backoff(int attempts) =>
      Duration(seconds: math.min(3600, 30 * math.pow(2, math.max(0, attempts - 1)).toInt()));

  Future<void> add(OutgoingReport report) async {
    await store.put([report]);
    await store.trim(maxQueued);
  }

  Future<int> pending() => store.count();

  Future<void> clear() => store.clear();

  /// Uploads the reports that are due through [sender], in batches. Stops at
  /// the first failure: offline, nothing changes; otherwise the batch backs
  /// off ([backoff]). A batch the server rejects as invalid is retried one
  /// report at a time, and a single rejected report is dropped. Never throws.
  Future<OutboxResult> flush(ReportSender sender) async {
    var sent = 0, dropped = 0;
    for (var round = 0; round < 20; round++) {
      final now = clock().toUtc().millisecondsSinceEpoch;
      final due = await store.due(now, limit: batchSize);
      if (due.isEmpty) break;
      try {
        await sender.sendReports(due);
        await store.remove(due.map((r) => r.id));
        sent += due.length;
      } on ReportRejected {
        if (due.length == 1) {
          await store.remove([due.single.id]);
          dropped++;
        } else {
          // Find the bad one: one at a time.
          for (final r in due) {
            try {
              await sender.sendReports([r]);
              sent++;
            } on ReportRejected {
              dropped++;
            } on Object catch (e) {
              return _failed([r], e, now, sent, dropped);
            }
            await store.remove([r.id]);
          }
        }
      } on Object catch (e) {
        return _failed(due, e, now, sent, dropped);
      }
    }
    return OutboxResult(sent: sent, dropped: dropped);
  }

  Future<OutboxResult> _failed(List<OutgoingReport> batch, Object e, int now, int sent, int dropped) async {
    if (looksOffline(e)) return OutboxResult(sent: sent, dropped: dropped, failed: batch.length, offline: true);
    await store.put([
      for (final r in batch)
        r.retryLater(attempts: r.attempts + 1, nextAtMs: now + backoff(r.attempts + 1).inMilliseconds),
    ]);
    return OutboxResult(sent: sent, dropped: dropped, failed: batch.length);
  }
}

// -------------------------------------------------------------------- stores

abstract interface class OutboxStore {
  /// Adds or replaces reports (by id).
  Future<void> put(Iterable<OutgoingReport> reports);

  /// Reports whose backoff has passed, oldest first.
  Future<List<OutgoingReport>> due(int nowMs, {int limit = 20});
  Future<void> remove(Iterable<String> ids);
  Future<int> count();

  /// Keeps the newest [max] reports.
  Future<void> trim(int max);
  Future<void> clear();
}

class InMemoryOutboxStore implements OutboxStore {
  final Map<String, OutgoingReport> _items = {};

  List<OutgoingReport> get items => _sorted(_items.values);

  static List<OutgoingReport> _sorted(Iterable<OutgoingReport> it) =>
      it.toList()..sort((a, b) => a.createdAtMs != b.createdAtMs ? a.createdAtMs.compareTo(b.createdAtMs) : a.id.compareTo(b.id));

  @override
  Future<void> put(Iterable<OutgoingReport> reports) async {
    for (final r in reports) {
      _items[r.id] = r;
    }
  }

  @override
  Future<List<OutgoingReport>> due(int nowMs, {int limit = 20}) async =>
      _sorted(_items.values.where((r) => r.nextAtMs <= nowMs)).take(limit).toList();

  @override
  Future<void> remove(Iterable<String> ids) async => ids.forEach(_items.remove);

  @override
  Future<int> count() async => _items.length;

  @override
  Future<void> trim(int max) async {
    final all = _sorted(_items.values);
    for (final r in all.take(math.max(0, all.length - max))) {
      _items.remove(r.id);
    }
  }

  @override
  Future<void> clear() async => _items.clear();
}

/// The `outbox` table of `sync.sqlite` ([SyncDb], schema v2).
class DriftOutboxStore implements OutboxStore {
  DriftOutboxStore(this.db);
  final SyncDb db;

  @override
  Future<void> put(Iterable<OutgoingReport> reports) => db.transaction(() async {
    for (final r in reports) {
      await db.customStatement(
        'INSERT OR REPLACE INTO outbox (id, coll, fields, created, attempts, next_at) VALUES (?, ?, ?, ?, ?, ?)',
        [r.id, r.collection, r.encodeFields(), r.createdAtMs, r.attempts, r.nextAtMs],
      );
    }
  });

  @override
  Future<List<OutgoingReport>> due(int nowMs, {int limit = 20}) async {
    final rows = await db
        .customSelect(
          'SELECT id, coll, fields, created, attempts, next_at FROM outbox WHERE next_at <= ? '
          'ORDER BY created, id LIMIT ?',
          variables: [Variable.withInt(nowMs), Variable.withInt(limit)],
        )
        .get();
    final out = <OutgoingReport>[];
    for (final r in rows) {
      try {
        out.add(OutgoingReport(
          id: r.read<String>('id'),
          collection: r.read<String>('coll'),
          fields: OutgoingReport.decodeFields(r.read<String>('fields')),
          createdAtMs: r.read<int>('created'),
          attempts: r.read<int>('attempts'),
          nextAtMs: r.read<int>('next_at'),
        ));
      } on Object {
        await remove([r.read<String>('id')]); // damaged: nothing to send
      }
    }
    return out;
  }

  @override
  Future<void> remove(Iterable<String> ids) => db.transaction(() async {
    for (final id in ids) {
      await db.customStatement('DELETE FROM outbox WHERE id = ?', [id]);
    }
  });

  @override
  Future<int> count() async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM outbox').getSingle()).read<int>('n');

  @override
  Future<void> trim(int max) => db.customStatement(
    'DELETE FROM outbox WHERE id NOT IN (SELECT id FROM outbox ORDER BY created DESC, id DESC LIMIT ?)',
    [max],
  );

  @override
  Future<void> clear() => db.customStatement('DELETE FROM outbox');
}
