// The Firestore and Firebase Auth REST clients against a small fake of the
// REST API (MockClient): request shapes, paging with (up, name) cursors,
// token refresh on 401, error mapping, and a full sync between two devices.
import 'dart:convert';

import 'package:tosk/ai/secret_store.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/sync/firebase_auth.dart';
import 'package:tosk/sync/firestore_backend.dart';
import 'package:tosk/sync/sync_engine.dart';
import 'package:tosk/sync/sync_service.dart';
import 'package:tosk/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/sample_log.dart';
import 'sync_service_test.dart' show FakeIdentity;

const project = 'tosk-test';
const docsRoot = 'projects/$project/databases/(default)/documents';

/// Just enough of Firestore's REST API: commit (update + REQUEST_TIME transform,
/// delete), runQuery (collection, orderBy up/__name__, where up >=, startAt
/// after, limit), list with a page size. Also Identity Toolkit and Secure Token.
class FakeFirebase {
  final docs = <String, Map<String, Object?>>{}; // name -> fields
  final ups = <String, String>{};
  var clock = DateTime.utc(2026, 10, 1, 12);
  var tokenSerial = 0;
  final validTokens = <String>{};
  final requests = <String>[];
  int commits = 0;

  String _now() {
    clock = clock.add(const Duration(milliseconds: 1));
    return clock.toIso8601String();
  }

  String issue() {
    final t = 'idtoken-${++tokenSerial}';
    validTokens.add(t);
    return t;
  }

  http.Client get client => MockClient((req) async {
    requests.add('${req.method} ${req.url.path}');
    final host = req.url.host;
    if (host == 'identitytoolkit.googleapis.com') {
      final body = jsonDecode(req.body) as Map;
      if (req.url.path.endsWith('accounts:signInWithIdp')) {
        final post = Uri.splitQueryString(body['postBody'] as String);
        if (post['providerId'] != 'google.com' || post['id_token'] != 'google-ok') {
          return http.Response(jsonEncode({'error': {'message': 'INVALID_IDP_RESPONSE'}}), 400);
        }
        return http.Response(
          jsonEncode({'localId': 'uid1', 'idToken': issue(), 'refreshToken': 'refresh1', 'expiresIn': '3600', 'email': 'a@b.c'}),
          200,
        );
      }
      if (req.url.path.endsWith('accounts:delete')) return http.Response('{}', 200);
    }
    if (host == 'securetoken.googleapis.com') {
      final form = Uri.splitQueryString(req.body);
      if (form['refresh_token'] == 'revoked') {
        return http.Response(jsonEncode({'error': {'message': 'TOKEN_EXPIRED'}}), 400);
      }
      return http.Response(jsonEncode({'id_token': issue(), 'refresh_token': form['refresh_token'], 'expires_in': '3600'}), 200);
    }
    if (host != 'firestore.googleapis.com') return http.Response('?', 404);
    final auth = req.headers['authorization'] ?? '';
    if (!validTokens.contains(auth.replaceFirst('Bearer ', ''))) return http.Response('{"error":{"message":"unauth"}}', 401);
    final path = Uri.decodeFull(req.url.path).replaceFirst('/v1/', '');
    if (path.endsWith(':commit')) {
      commits++;
      final writes = (jsonDecode(req.body) as Map)['writes'] as List;
      for (final w in writes.cast<Map>()) {
        if (w['delete'] case final String name) {
          docs.remove(name);
          ups.remove(name);
          continue;
        }
        final u = w['update'] as Map;
        final name = u['name'] as String;
        expect(name, startsWith('$docsRoot/users/uid1/'), reason: 'writes stay in the user\'s tree');
        final t = _now();
        docs[name] = {...(u['fields'] as Map).cast<String, Object?>(), 'up': {'timestampValue': t}};
        expect((w['updateTransforms'] as List).single, {'fieldPath': 'up', 'setToServerValue': 'REQUEST_TIME'});
        ups[name] = t;
      }
      return http.Response(jsonEncode({'commitTime': clock.toIso8601String()}), 200);
    }
    if (path.endsWith(':runQuery')) {
      final parent = path.substring(0, path.length - ':runQuery'.length);
      final q = (jsonDecode(req.body) as Map)['structuredQuery'] as Map;
      final coll = ((q['from'] as List).single as Map)['collectionId'];
      var list = [
        for (final n in docs.keys)
          if (n.startsWith('$parent/$coll/') && !n.substring('$parent/$coll/'.length).contains('/')) n,
      ]..sort((a, b) {
          final c = DateTime.parse(ups[a]!).compareTo(DateTime.parse(ups[b]!));
          return c != 0 ? c : a.compareTo(b);
        });
      if (q['where'] case final Map w) {
        final f = w['fieldFilter'] as Map;
        expect(f['op'], 'GREATER_THAN_OR_EQUAL');
        final from = DateTime.parse((f['value'] as Map)['timestampValue'] as String);
        list = [for (final n in list) if (!DateTime.parse(ups[n]!).isBefore(from)) n];
      }
      if (q['startAt'] case final Map s) {
        expect(s['before'], isFalse);
        final v = s['values'] as List;
        final t = DateTime.parse((v[0] as Map)['timestampValue'] as String);
        final ref = (v[1] as Map)['referenceValue'] as String;
        list = [
          for (final n in list)
            if (DateTime.parse(ups[n]!).isAfter(t) || (DateTime.parse(ups[n]!) == t && n.compareTo(ref) > 0)) n,
        ];
      }
      list = list.take(q['limit'] as int).toList();
      return http.Response(
        jsonEncode(list.isEmpty
            ? [{'readTime': clock.toIso8601String()}]
            : [for (final n in list) {'document': {'name': n, 'fields': docs[n]}, 'readTime': 'x'}]),
        200,
      );
    }
    if (req.method == 'GET') {
      final size = int.parse(req.url.queryParameters['pageSize']!);
      final start = int.tryParse(req.url.queryParameters['pageToken'] ?? '') ?? 0;
      final all = [for (final n in docs.keys.toList()..sort()) if (n.startsWith('$path/')) n];
      final page = all.skip(start).take(size).toList();
      return http.Response(
        jsonEncode({
          'documents': [for (final n in page) {'name': n}],
          if (start + size < all.length) 'nextPageToken': '${start + size}',
        }),
        200,
      );
    }
    return http.Response('?', 400);
  });
}

void main() {
  late FakeFirebase fb;
  setUp(() => fb = FakeFirebase());

  FirebaseAuthClient auth() => FirebaseAuthClient(apiKey: 'key', client: fb.client, clock: () => fb.clock);

  Future<FirestoreSyncBackend> signedIn() async {
    final s = await auth().signInWithGoogle('google-ok');
    return FirestoreSyncBackend(projectId: project, client: fb.client, tokens: FirebaseTokens(auth(), s));
  }

  test('auth: Google ID token to a session; bad tokens and revoked refresh tokens fail cleanly', () async {
    final s = await auth().signInWithGoogle('google-ok');
    expect(s.uid, 'uid1');
    expect(s.email, 'a@b.c');
    expect(s.fresh(fb.clock), isTrue);
    expect(FirebaseSession.decode(s.encode())!.refreshToken, 'refresh1');
    expect(FirebaseSession.decode(s.encode())!.idToken, isNull); // never persisted
    await expectLater(
      auth().signInWithGoogle('google-bad'),
      throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'INVALID_IDP_RESPONSE')),
    );
    var signedOut = false;
    final tokens = FirebaseTokens(
      auth(),
      const FirebaseSession(uid: 'uid1', refreshToken: 'revoked'),
      onSignedOut: () => signedOut = true,
    );
    await expectLater(tokens.idToken(), throwsA(isA<SyncAuthException>()));
    expect(signedOut, isTrue);
  });

  test('events: batches round-trip with offsets; paging follows (up, name)', () async {
    final b = await signedIn();
    final log = sampleLog(count: 30);
    for (var i = 0; i < 6; i++) {
      await b.pushEvents('batch$i', 'dev1', [
        for (final e in log.sublist(i * 5, i * 5 + 5)) SyncedEvent(e, 60 * i),
      ]);
    }
    final p1 = await b.pullEvents(limit: 4);
    expect(p1.items.map((x) => x.id), ['batch0', 'batch1', 'batch2', 'batch3']);
    expect(p1.hasMore, isTrue);
    final p2 = await b.pullEvents(after: p1.items.last.cursor, limit: 4);
    expect(p2.items.map((x) => x.id), ['batch4', 'batch5']);
    expect(p2.hasMore, isFalse);
    final e = p1.items[1].events.first;
    expect(e.utcOffsetMinutes, 60);
    expect(e.event.id, log[5].id);
    expect(e.event.at, log[5].at);
    expect(e.event.answer, log[5].answer);
    // A rewrite of a batch replaces it (and moves it to the end of the stream).
    await b.pushEvents('batch0', 'dev1', [SyncedEvent(log.first, 0)]);
    final tail = await b.pullEvents(after: p2.items.last.cursor);
    expect(tail.items.single.id, 'batch0');
    // From a time (the overlap window): inclusive.
    final fromTime = await b.pullEvents(after: SyncCursor(p2.items.first.cursor.serverTime, ''));
    expect(fromTime.items.map((x) => x.id), ['batch4', 'batch5', 'batch0']);
  });

  test('settings and delete-all', () async {
    final b = await signedIn();
    await b.pushSettings(const [
      SyncedSetting(key: 'ui.theme_mode', value: 'dark', changedAtMs: 5, device: 'd1'),
      SyncedSetting(key: 'goal.daily_xp', value: null, changedAtMs: 6, device: 'd1'),
    ]);
    final page = await b.pullSettings();
    expect({for (final s in page.items) s.key: s.value}, {'ui.theme_mode': 'dark', 'goal.daily_xp': null});
    expect(page.items.first.changedAtMs, 5);
    expect(page.items.first.cursor, isNotNull);
    for (var i = 0; i < 7; i++) {
      await b.pushEvents('b$i', 'd', [SyncedEvent(sampleLog(count: 7)[i], 0)]);
    }
    expect(fb.docs.length, 9);
    await b.deleteAll();
    expect(fb.docs, isEmpty);
  });

  test('an expired ID token is refreshed once on 401', () async {
    final b = await signedIn();
    fb.validTokens.clear(); // the server no longer accepts the cached token
    await b.pushEvents('x', 'd', [SyncedEvent(sampleLog(count: 1).single, 0)]);
    expect(fb.requests.where((r) => r.contains('securetoken') || r.contains('/v1/token')).length, 1);
    expect(fb.docs.length, 1);
  });

  test('two devices sync through the REST backend, in batches', () async {
    final log = sampleLog(seed: 2, count: 300);
    Future<(InMemoryProgressStore, SyncEngine)> device(List<ReviewEvent> events) async {
      final p = InMemoryProgressStore();
      await p.importEvents(events);
      final e = SyncEngine(
        store: InMemorySyncStore(),
        progress: p,
        importer: p,
        log: p,
        backend: await signedIn(),
        syncedSettings: const {'ui.theme_mode'},
        clock: () => fb.clock,
        batchSize: 120,
      );
      return (p, e);
    }

    final (a, ea) = await device(log.sublist(0, 200));
    final (b, eb) = await device(log.sublist(150));
    await a.setSetting('ui.theme_mode', 'dark');
    await ea.sync();
    await eb.sync();
    await ea.sync();
    expect((await a.log()).length, 300);
    expect((await b.log()).length, 300);
    expect(await b.getSetting('ui.theme_mode'), 'dark');
    expect(fb.docs.keys.where((n) => n.contains('/batches/')).length, 3); // 120 + 80, then 100 new from b
  });

  test('the service: sign in, sync, sign out, delete', () async {
    final secrets = MemorySecretStore();
    final p = InMemoryProgressStore();
    await p.importEvents(sampleLog(count: 20));
    final engine = SyncEngine(
      store: InMemorySyncStore(),
      progress: p,
      importer: p,
      log: p,
      backend: const NullSyncBackend(),
      syncedSettings: const {},
      clock: () => fb.clock,
    );
    final service = SyncService.firestore(
      engine: engine,
      projectId: project,
      auth: auth(),
      client: fb.client,
      secrets: secrets,
      identity: FakeIdentity('google-ok'),
    );
    addTearDown(service.dispose);
    await service.start(lifecycle: false);
    expect(service.status.phase, SyncPhase.signedOut);
    await service.signIn();
    expect(service.status.phase, SyncPhase.idle);
    expect(service.status.email, 'a@b.c');
    expect(service.status.pending, 0);
    expect(fb.docs.keys.where((n) => n.contains('/batches/')).length, 1);
    expect(await secrets.read(SyncService.sessionKey), contains('refresh1'));
    await service.deleteCloudData();
    expect(fb.docs, isEmpty);
    expect(service.status.phase, SyncPhase.signedOut);
    expect(await secrets.read(SyncService.sessionKey), isNull);
    expect((await p.log()).length, 20);
  });
}
