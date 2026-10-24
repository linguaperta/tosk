/// [SyncBackend] on Cloud Firestore, over its REST API (no native SDK; see
/// `firebase_auth.dart` for why). Pure Dart (package:http).
///
/// Data model (one Firebase user = one `users/{uid}` subtree; the security
/// rules in `firebase/firestore.rules` let a user touch only their own):
///
/// ```
/// users/{uid}/batches/{batchId}   v: 1, dev: device id, n: event count,
///                                 events: JSON lines (review event + "off": UTC offset in minutes),
///                                 up: server time (REQUEST_TIME)
/// users/{uid}/settings/{key}      k: key, v: value or null, t: change time (client ms),
///                                 dev: device id, up: server time
/// ```
///
/// Reports for the developer ([ReportSender], `report_outbox.dart`) go to
/// `users/{uid}/feedback/{id}` and `users/{uid}/crashes/{id}` (their fields
/// plus `up`), written with an update mask so a re-send leaves the owner's
/// `seen` mark alone; [deleteAll] removes them too.
///
/// A batch whose events would pass [maxEventsChars] (the rules cap them at
/// 250,000 characters) is split over `batchId`, `batchId-2`, … (the same
/// split every time, so a retry still overwrites itself).
///
/// Events travel in batches (up to 400 per document) to stay well inside the
/// free tier (20k writes and 50k reads a day): a year of daily practice is a
/// few hundred documents. Pulls query `up` in order, so each run reads only
/// what was written since the last one.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/core.dart';
import '../data/sync/review_log_sync.dart';
import 'firebase_auth.dart';
import 'report_outbox.dart';

class FirestoreException implements Exception {
  const FirestoreException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'FirestoreException(HTTP $status: $message)';
}

class FirestoreSyncBackend implements SyncBackend, ReportSender {
  FirestoreSyncBackend({required this.projectId, required this.client, required this.tokens});

  final String projectId;
  final http.Client client;
  final FirebaseTokens tokens;

  static const _timeout = Duration(seconds: 45);
  static const _maxWrites = 400;

  /// The most characters of event lines in one batch document.
  static const maxEventsChars = 200000;

  /// A typed answer longer than this is cut (no real answer is).
  static const maxAnswerChars = 2000;

  @override
  String get id => 'firestore';
  @override
  bool get isConfigured => true;
  @override
  String? get accountId => tokens.uid;

  String get _db => 'projects/$projectId/databases/(default)';
  String get _docs => '$_db/documents';
  String get _user => '$_docs/users/${tokens.uid}';
  Uri _url(String path, [Map<String, String>? query]) =>
      Uri.https('firestore.googleapis.com', '/v1/$path', query);

  Future<Object?> _call(String method, Uri url, {Object? body}) async {
    for (var attempt = 0;; attempt++) {
      final token = await tokens.idToken(forceRefresh: attempt > 0);
      final req = http.Request(method, url)
        ..headers['authorization'] = 'Bearer $token'
        ..headers['content-type'] = 'application/json';
      if (body != null) req.body = jsonEncode(body);
      final res = await http.Response.fromStream(await client.send(req).timeout(_timeout)).timeout(_timeout);
      if (res.statusCode == 401 && attempt == 0) continue; // expired token: refresh once
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw SyncAuthException('Firestore refused access (HTTP ${res.statusCode})');
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        var msg = res.reasonPhrase ?? '';
        try {
          final e = (jsonDecode(res.body) as Map)['error'];
          if (e is Map && e['message'] is String) msg = e['message'] as String;
        } on Object {
          // not JSON
        }
        throw FirestoreException(res.statusCode, msg);
      }
      return res.body.isEmpty ? null : jsonDecode(res.body);
    }
  }

  // ------------------------------------------------------------------ values

  static Map<String, Object?> _str(String s) => {'stringValue': s};
  static Map<String, Object?> _int(int i) => {'integerValue': '$i'};
  static const Map<String, Object?> _null = {'nullValue': null};

  static String? _readStr(Map<String, Object?> f, String k) => (f[k] as Map?)?['stringValue'] as String?;
  static int? _readInt(Map<String, Object?> f, String k) => int.tryParse('${(f[k] as Map?)?['integerValue']}');
  static String? _readTime(Map<String, Object?> f, String k) => (f[k] as Map?)?['timestampValue'] as String?;

  Map<String, Object?> _write(String name, Map<String, Object?> fields) => {
        'update': {'name': name, 'fields': fields},
        'updateTransforms': [
          {'fieldPath': 'up', 'setToServerValue': 'REQUEST_TIME'},
        ],
      };

  Future<void> _commit(List<Map<String, Object?>> writes) async {
    for (var i = 0; i < writes.length; i += _maxWrites) {
      final part = writes.sublist(i, i + _maxWrites > writes.length ? writes.length : i + _maxWrites);
      await _call('POST', _url('$_docs:commit'), body: {'writes': part});
    }
  }

  /// Documents of [collection] after [after] in `(up, name)` order: a query
  /// with one more than [limit] tells whether more follow.
  Future<(List<Map<String, Object?>>, bool)> _query(String collection, SyncCursor? after, int limit) async {
    final q = <String, Object?>{
      'from': [
        {'collectionId': collection},
      ],
      'orderBy': [
        {
          'field': {'fieldPath': 'up'},
          'direction': 'ASCENDING',
        },
        {
          'field': {'fieldPath': '__name__'},
          'direction': 'ASCENDING',
        },
      ],
      'limit': limit + 1,
    };
    if (after != null && after.id.isEmpty) {
      q['where'] = {
        'fieldFilter': {
          'field': {'fieldPath': 'up'},
          'op': 'GREATER_THAN_OR_EQUAL',
          'value': {'timestampValue': after.serverTime},
        },
      };
    } else if (after != null) {
      q['startAt'] = {
        'values': [
          {'timestampValue': after.serverTime},
          {'referenceValue': '$_user/$collection/${after.id}'},
        ],
        'before': false,
      };
    }
    final res = await _call('POST', _url('$_user:runQuery'), body: {'structuredQuery': q});
    final docs = <Map<String, Object?>>[
      for (final r in (res as List? ?? const []))
        if ((r as Map)['document'] case final Map d) d.cast<String, Object?>(),
    ];
    final more = docs.length > limit;
    return (more ? docs.sublist(0, limit) : docs, more);
  }

  static String _docId(Map<String, Object?> doc) => (doc['name']! as String).split('/').last;

  // ------------------------------------------------------------------ events

  /// The event lines of [events] in documents of at most [maxEventsChars].
  static List<(String lines, int n)> splitEvents(List<SyncedEvent> events) {
    final parts = <(String, int)>[];
    var b = StringBuffer();
    var n = 0;
    for (final s in events) {
      final j = {...reviewEventToJson(s.event), 'off': s.utcOffsetMinutes};
      if (j['answer'] case final String a when a.length > maxAnswerChars) j['answer'] = a.substring(0, maxAnswerChars);
      final line = '${jsonEncode(j)}\n';
      if (n > 0 && b.length + line.length > maxEventsChars) {
        parts.add((b.toString(), n));
        b = StringBuffer();
        n = 0;
      }
      b.write(line);
      n++;
    }
    if (n > 0) parts.add((b.toString(), n));
    return parts;
  }

  @override
  Future<void> pushEvents(String batchId, String device, List<SyncedEvent> events) async {
    final parts = splitEvents(events);
    await _commit([
      for (var i = 0; i < parts.length; i++)
        _write('$_user/batches/${i == 0 ? batchId : '$batchId-${i + 1}'}', {
          'v': _int(1),
          'dev': _str(device),
          'n': _int(parts[i].$2),
          'events': _str(parts[i].$1),
        }),
    ]);
  }

  @override
  Future<SyncPage<EventBatch>> pullEvents({SyncCursor? after, int limit = 50}) async {
    final (docs, more) = await _query('batches', after, limit);
    final out = <EventBatch>[];
    for (final d in docs) {
      final f = (d['fields'] as Map? ?? const {}).cast<String, Object?>();
      final id = _docId(d);
      final up = _readTime(f, 'up');
      if (up == null) continue;
      if ((_readInt(f, 'v') ?? 1) > 1) continue; // written by a newer app version
      final events = <SyncedEvent>[];
      for (final line in const LineSplitter().convert(_readStr(f, 'events') ?? '')) {
        if (line.trim().isEmpty) continue;
        try {
          final j = (jsonDecode(line) as Map).cast<String, Object?>();
          events.add(SyncedEvent(reviewEventFromJson(j), (j['off'] as num?)?.toInt() ?? 0));
        } on Object {
          // A damaged line is skipped; the rest of the batch still merges.
        }
      }
      out.add(EventBatch(id: id, cursor: SyncCursor(up, id), device: _readStr(f, 'dev') ?? '', events: events));
    }
    return SyncPage(out, hasMore: more);
  }

  // ------------------------------------------------------------------ settings

  @override
  Future<void> pushSettings(List<SyncedSetting> settings) async {
    if (settings.isEmpty) return;
    await _commit([
      for (final s in settings)
        _write('$_user/settings/${Uri.encodeComponent(s.key)}', {
          'k': _str(s.key),
          'v': s.value == null ? _null : _str(s.value!),
          't': _int(s.changedAtMs),
          'dev': _str(s.device),
        }),
    ]);
  }

  @override
  Future<SyncPage<SyncedSetting>> pullSettings({SyncCursor? after, int limit = 200}) async {
    final (docs, more) = await _query('settings', after, limit);
    final out = <SyncedSetting>[];
    for (final d in docs) {
      final f = (d['fields'] as Map? ?? const {}).cast<String, Object?>();
      final up = _readTime(f, 'up');
      final key = _readStr(f, 'k');
      if (up == null || key == null) continue;
      out.add(SyncedSetting(
        key: key,
        value: _readStr(f, 'v'),
        changedAtMs: _readInt(f, 't') ?? 0,
        device: _readStr(f, 'dev') ?? '',
        cursor: SyncCursor(up, _docId(d)),
      ));
    }
    return SyncPage(out, hasMore: more);
  }

  // ------------------------------------------------------------------ reports

  @override
  Future<void> sendReports(List<OutgoingReport> reports) async {
    if (reports.isEmpty) return;
    Map<String, Object?> value(Object v) => v is int ? _int(v) : _str('$v');
    final writes = [
      for (final r in reports)
        {
          'update': {
            'name': '$_user/${r.collection}/${r.id}',
            'fields': {
              for (final e in r.fields.entries)
                if (e.key != 'up') e.key: value(e.value),
            },
          },
          'updateMask': {
            'fieldPaths': [
              for (final k in r.fields.keys)
                if (k != 'up') k,
            ],
          },
          'updateTransforms': [
            {'fieldPath': 'up', 'setToServerValue': 'REQUEST_TIME'},
          ],
        },
    ];
    try {
      await _call('POST', _url('$_docs:commit'), body: {'writes': writes});
    } on FirestoreException catch (e) {
      if (e.status == 400) throw ReportRejected(e.message);
      rethrow;
    }
  }

  // ------------------------------------------------------------------ delete

  Future<List<String>> _names(String collection) async {
    final names = <String>[];
    String? page;
    do {
      final res = await _call(
        'GET',
        _url('$_user/$collection', {'pageSize': '300', 'mask.fieldPaths': 'n', 'pageToken': ?page}),
      ) as Map?;
      for (final d in (res?['documents'] as List? ?? const [])) {
        names.add((d as Map)['name']! as String);
      }
      page = res?['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    return names;
  }

  @override
  Future<void> deleteAll() async {
    final names = [
      ...await _names('batches'),
      ...await _names('settings'),
      ...await _names(ReportCollections.feedback),
      ...await _names(ReportCollections.crashes),
      _user,
    ];
    await _commit([
      for (final n in names) {'delete': n},
    ]);
  }
}
