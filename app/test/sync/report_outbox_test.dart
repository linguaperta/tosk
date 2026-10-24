// Reports for the developer: the outbox (batches, offline, backoff, a
// rejected report, the cap), its SQLite table and the v1 → v2 migration, the
// report builders (fields and limits the Firestore rules accept), the
// Firestore requests (reports in the user's tree, size-split batches), and
// SyncService (only signed in; uploaded after a sync; deleted by "Delete my
// cloud data", which re-authenticates when the account needs a fresh sign-in).
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tosk/ai/secret_store.dart';
import 'package:tosk/app_version.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/feedback/flags_export.dart';
import 'package:tosk/feedback/reports.dart';
import 'package:tosk/sync/fake_sync_backend.dart';
import 'package:tosk/sync/firebase_auth.dart';
import 'package:tosk/sync/firestore_backend.dart';
import 'package:tosk/sync/report_outbox.dart';
import 'package:tosk/sync/sync_engine.dart';
import 'package:tosk/sync/sync_errors.dart';
import 'package:tosk/sync/sync_service.dart';
import 'package:tosk/sync/sync_store.dart';

import '../fixtures/sample_log.dart';
import 'sync_service_test.dart' show FakeIdentity, fakeAuthServer;

FlagRecord sampleFlag({String id = '3f2b1c4e-0d6a-4b8e-9f00-1234567890ab', String comment = 'Both should work?'}) =>
    FlagRecord(
      id: id,
      createdAt: DateTime.utc(2026, 10, 14, 9, 30),
      courseId: 'it',
      skillId: 'present_are',
      facetId: 'it:mangiare#form:presente',
      exerciseType: 'cloze',
      exercise: const {'type': 'cloze', 'before': 'Noi ', 'after': ' il pane.', 'expected': 'mangiamo'},
      given: 'mangiate',
      expected: 'mangiamo',
      correct: false,
      reasons: const [FlagReason.multipleAnswers],
      comment: comment,
      appVersion: '0.7.6+19',
      packVersion: '1.5.0',
      sourceLang: 'en',
    );

OutgoingReport report(String id, {int at = 1000, String text = 'hi'}) => OutgoingReport(
  id: id,
  collection: ReportCollections.feedback,
  createdAtMs: at,
  fields: {'v': 1, 'kind': 'general', 'app': 'x', 'platform': 'android', 'at': at, 'text': text},
);

/// A [ReportSender] that records batches and can fail on demand.
class RecordingSender implements ReportSender {
  final batches = <List<String>>[];
  Object? fail;
  String? rejectText;

  @override
  Future<void> sendReports(List<OutgoingReport> reports) async {
    if (fail case final e?) throw e;
    if (rejectText != null && reports.any((r) => r.fields['text'] == rejectText)) {
      throw const ReportRejected('bad');
    }
    batches.add([for (final r in reports) r.id]);
  }
}

/// A signed-in [SyncService] on a [FakeSyncServer] with an in-memory outbox.
Future<(SyncService, FakeSyncServer, InMemoryOutboxStore)> reportingService({
  bool signIn = true,
  InMemoryProgressStore? progress,
  http.Client? authClient,
  FakeIdentity? identity,
}) async {
  final server = FakeSyncServer(clock: () => DateTime.utc(2026, 10, 3));
  final p = progress ?? InMemoryProgressStore();
  final store = InMemoryOutboxStore();
  final s = SyncService(
    engine: SyncEngine(
      store: InMemorySyncStore(),
      progress: p,
      importer: p,
      log: p,
      backend: const NullSyncBackend(),
      syncedSettings: const {},
      clock: server.clock,
    ),
    auth: FirebaseAuthClient(apiKey: 'k', client: authClient ?? fakeAuthServer()),
    secrets: MemorySecretStore(),
    identity: identity ?? FakeIdentity('google-token'),
    backendFor: (t) => FakeSyncBackend(server, account: t.uid),
    outbox: ReportOutbox(store, clock: server.clock),
  );
  await s.start(lifecycle: false);
  if (signIn) await s.signIn();
  return (s, server, store);
}

void main() {
  group('ReportOutbox', () {
    late InMemoryOutboxStore store;
    late RecordingSender sender;
    var now = DateTime.utc(2026, 10, 20, 12);
    ReportOutbox outbox({int batchSize = 20, int maxQueued = 200}) =>
        ReportOutbox(store, clock: () => now, batchSize: batchSize, maxQueued: maxQueued);

    setUp(() {
      store = InMemoryOutboxStore();
      sender = RecordingSender();
      now = DateTime.utc(2026, 10, 20, 12);
    });

    test('sends due reports in batches, oldest first, and forgets them', () async {
      final box = outbox(batchSize: 2);
      for (var i = 0; i < 5; i++) {
        await box.add(report('r$i', at: i));
      }
      final r = await box.flush(sender);
      expect(r.sent, 5);
      expect(sender.batches, [
        ['r0', 'r1'],
        ['r2', 'r3'],
        ['r4'],
      ]);
      expect(await box.pending(), 0);
      expect((await box.flush(sender)).sent, 0);
    });

    test('offline: nothing is lost and no backoff starts', () async {
      final box = outbox();
      await box.add(report('a'));
      sender.fail = http.ClientException('Failed host lookup');
      final r = await box.flush(sender);
      expect(r.offline, isTrue);
      expect(r.sent, 0);
      expect(store.items.single.attempts, 0);
      sender.fail = null;
      expect((await box.flush(sender)).sent, 1);
    });

    test('other failures back off: 30 s, doubling, at most an hour', () async {
      expect(ReportOutbox.backoff(1), const Duration(seconds: 30));
      expect(ReportOutbox.backoff(2), const Duration(minutes: 1));
      expect(ReportOutbox.backoff(5), const Duration(minutes: 8));
      expect(ReportOutbox.backoff(30), const Duration(hours: 1));
      final box = outbox();
      await box.add(report('a'));
      sender.fail = const SyncAuthException('Firestore refused access (HTTP 403)'); // rules not deployed yet
      expect((await box.flush(sender)).failed, 1);
      expect(store.items.single.attempts, 1);
      sender.fail = null;
      expect((await box.flush(sender)).sent, 0, reason: 'still waiting for the backoff');
      now = now.add(const Duration(seconds: 31));
      expect((await box.flush(sender)).sent, 1);
      expect(await box.pending(), 0);
    });

    test('a report the server rejects is dropped; the rest of its batch still goes', () async {
      final box = outbox();
      await box.add(report('a', at: 1));
      await box.add(report('bad', at: 2, text: 'BAD'));
      await box.add(report('c', at: 3));
      sender.rejectText = 'BAD';
      final r = await box.flush(sender);
      expect(r.sent, 2);
      expect(r.dropped, 1);
      expect(sender.batches, [
        ['a'],
        ['c'],
      ]);
      expect(await box.pending(), 0);
    });

    test('the queue keeps only the newest reports', () async {
      final box = outbox(maxQueued: 3);
      for (var i = 0; i < 5; i++) {
        await box.add(report('r$i', at: i));
      }
      expect(store.items.map((r) => r.id), ['r2', 'r3', 'r4']);
    });
  });

  group('DriftOutboxStore (sync.sqlite)', () {
    test('stores, orders, reschedules, trims and clears', () async {
      final db = SyncDb(NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftOutboxStore(db);
      await store.put([report('b', at: 2), report('a', at: 1)]);
      await store.put([report('a', at: 1).retryLater(attempts: 2, nextAtMs: 5000)]);
      expect((await store.due(1000)).map((r) => r.id), ['b']);
      final all = await store.due(5000);
      expect(all.map((r) => r.id), ['a', 'b']);
      expect(all.first.attempts, 2);
      expect(all.first.fields, report('a', at: 1).fields);
      expect(await store.count(), 2);
      await store.trim(1);
      expect((await store.due(9999)).map((r) => r.id), ['b']);
      await store.clear();
      expect(await store.count(), 0);
    });

    test('a v1 sync.sqlite gains the outbox table and keeps its data', () async {
      final raw = sqlite.sqlite3.openInMemory();
      raw.execute('CREATE TABLE kv (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)');
      raw.execute("INSERT INTO kv VALUES ('device', 'dev-1')");
      raw.execute('PRAGMA user_version = 1');
      final db = SyncDb(NativeDatabase.opened(raw));
      addTearDown(db.close);
      expect(await DriftSyncStore(db).get('device'), 'dev-1');
      final store = DriftOutboxStore(db);
      await store.put([report('a')]);
      expect(await store.count(), 1);
    });
  });

  group('report builders', () {
    test('a flag carries the exported flag, its comment and course', () {
      final r = flagReport(sampleFlag(), platform: 'android');
      expect(r.id, sampleFlag().id);
      expect(r.collection, 'feedback');
      expect(r.fields['kind'], 'flag');
      expect(r.fields['text'], 'Both should work?');
      expect(r.fields['course'], 'it');
      expect(r.fields['app'], '0.7.6+19');
      expect(r.fields['platform'], 'android');
      expect(r.fields['at'], DateTime.utc(2026, 10, 14, 9, 30).millisecondsSinceEpoch);
      final flag = jsonDecode(r.fields['flag']! as String) as Map<String, Object?>;
      expect(flag, flagToJson(sampleFlag()));
      expect(r.fields.keys, isNot(contains('email')));
      expect(r.fields.keys, isNot(contains('uid')));
    });

    test('general feedback: trimmed text, an email only when given, limits', () {
      final now = DateTime.utc(2026, 10, 20);
      final r = generalFeedbackReport(text: '  Great app \n', email: ' me@example.com ', now: now, courseId: 'nl');
      expect(r.fields['kind'], 'general');
      expect(r.fields['text'], 'Great app');
      expect(r.fields['email'], 'me@example.com');
      expect(r.fields['course'], 'nl');
      expect(r.fields['app'], kAppVersion);
      expect(generalFeedbackReport(text: 'x', now: now).fields.keys, isNot(contains('email')));
      expect((generalFeedbackReport(text: 'y' * 9000, now: now).fields['text']! as String).length, ReportLimits.text);
      expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(r.id), isTrue, reason: 'the rules\' document id shape');
    });

    test('a crash report keeps its start and end within the limit', () {
      final text = 'Uncaught error: boom\n${'#1 frame\n' * 5000}#999 main';
      final r = crashReport(report: text, now: DateTime.utc(2026), device: 'Google Pixel 8', platform: 'android');
      expect(r.collection, 'crashes');
      final kept = r.fields['report']! as String;
      expect(kept.length, lessThanOrEqualTo(ReportLimits.crash));
      expect(kept, startsWith('Uncaught error: boom'));
      expect(kept, endsWith('#999 main'));
      expect(r.fields['device'], 'Google Pixel 8');
      expect(crashReport(report: '  ', now: DateTime.utc(2026)).fields['report'], '(empty report)');
    });

    test('mailto links encode spaces as %20 and need an address', () {
      expect(feedbackMailto('', subject: 's', body: 'b'), isNull);
      final u = feedbackMailto('dev@example.org', subject: 'tosk feedback', body: 'a b\nc & d')!;
      expect(u.toString(), 'mailto:dev@example.org?subject=tosk%20feedback&body=a%20b%0Ac%20%26%20d');
      expect(feedbackPlainText('hello ', platform: 'web'), 'hello\n\n— tosk $kAppVersion · web');
    });
  });

  test('Firestore: reports go to the user\'s feedback/ and crashes/ with an update mask and the server time', () async {
    final bodies = <Map<String, Object?>>[];
    var status = 200;
    final client = MockClient((req) async {
      if (req.url.host == 'securetoken.googleapis.com') {
        return http.Response(jsonEncode({'id_token': 't2', 'refresh_token': 'r', 'expires_in': '3600'}), 200);
      }
      expect(req.url.path, '/v1/projects/p/databases/(default)/documents:commit');
      bodies.add((jsonDecode(req.body) as Map).cast<String, Object?>());
      return http.Response(status == 200 ? '{}' : '{"error":{"message":"Invalid argument"}}', status);
    });
    final auth = FirebaseAuthClient(apiKey: 'k', client: client);
    final backend = FirestoreSyncBackend(
      projectId: 'p',
      client: client,
      tokens: FirebaseTokens(auth, const FirebaseSession(uid: 'alice', refreshToken: 'r')),
    );
    await backend.sendReports([
      flagReport(sampleFlag(), platform: 'android'),
      crashReport(report: 'boom', now: DateTime.utc(2026), device: 'Pixel', id: 'crash-0001', platform: 'android'),
    ]);
    final writes = (bodies.single['writes']! as List).cast<Map<String, Object?>>();
    final flag = writes[0];
    final update = flag['update']! as Map;
    expect(update['name'], 'projects/p/databases/(default)/documents/users/alice/feedback/${sampleFlag().id}');
    final fields = (update['fields']! as Map).cast<String, Object?>();
    expect(fields.keys, isNot(contains('uid')), reason: 'the path says whose it is');
    expect(fields['kind'], {'stringValue': 'flag'});
    expect(fields['v'], {'integerValue': '1'});
    expect(fields.keys, isNot(contains('up')));
    expect(((flag['updateMask']! as Map)['fieldPaths']! as List).toSet(), {...fields.keys});
    expect(flag['updateTransforms'], [
      {'fieldPath': 'up', 'setToServerValue': 'REQUEST_TIME'},
    ]);
    expect(
      (writes[1]['update']! as Map)['name'],
      'projects/p/databases/(default)/documents/users/alice/crashes/crash-0001',
    );
    status = 400;
    await expectLater(backend.sendReports([report('abcdefgh')]), throwsA(isA<ReportRejected>()));
  });

  test('Firestore: a big batch is split under the rules\' size cap, the same way every time', () async {
    final log = sampleLog(count: 400);
    final events = [
      for (final e in log)
        SyncedEvent(
          ReviewEvent(
            id: e.id,
            facetId: e.facetId,
            at: e.at,
            rating: e.rating,
            exerciseType: e.exerciseType,
            inputMode: e.inputMode,
            responseMs: e.responseMs,
            correct: e.correct,
            answer: 'a' * 900,
          ),
          60,
        ),
    ];
    final parts = FirestoreSyncBackend.splitEvents(events);
    expect(parts.length, greaterThan(1));
    expect(parts.every((p) => p.$1.length <= FirestoreSyncBackend.maxEventsChars), isTrue);
    expect(parts.fold<int>(0, (n, p) => n + p.$2), 400);
    expect(FirestoreSyncBackend.splitEvents(events).map((p) => p.$1), parts.map((p) => p.$1));
    // A silly-long answer is cut.
    final huge = FirestoreSyncBackend.splitEvents([
      SyncedEvent(
        ReviewEvent(
          id: 'x',
          facetId: 'f',
          at: DateTime.utc(2026),
          rating: log.first.rating,
          exerciseType: 'cloze',
          inputMode: log.first.inputMode,
          responseMs: 1,
          correct: false,
          answer: 'b' * 50000,
        ),
        0,
      ),
    ]);
    expect(huge.single.$1.length, lessThan(FirestoreSyncBackend.maxAnswerChars + 400));

    final names = <String>[];
    final client = MockClient((req) async {
      if (req.url.host == 'securetoken.googleapis.com') {
        return http.Response(jsonEncode({'id_token': 't2', 'refresh_token': 'r', 'expires_in': '3600'}), 200);
      }
      for (final w in ((jsonDecode(req.body) as Map)['writes'] as List).cast<Map>()) {
        names.add(((w['update'] as Map)['name'] as String).split('/').last);
      }
      return http.Response('{}', 200);
    });
    final backend = FirestoreSyncBackend(
      projectId: 'p',
      client: client,
      tokens: FirebaseTokens(
        FirebaseAuthClient(apiKey: 'k', client: client),
        const FirebaseSession(uid: 'alice', refreshToken: 'r'),
      ),
    );
    await backend.pushEvents('0123abcd', 'dev', events);
    expect(names, ['0123abcd', for (var i = 2; i <= parts.length; i++) '0123abcd-$i']);
  });

  group('SyncService', () {
    test('signed out: nothing is queued', () async {
      final (s, server, store) = await reportingService(signIn: false);
      addTearDown(s.dispose);
      expect(s.canSendReports, isFalse);
      expect(await s.sendReport(report('abcdefgh')), isFalse);
      expect(store.items, isEmpty);
      expect(server.reports, isEmpty);
    });

    test('signed in: queued, uploaded with the next sync under the account', () async {
      final (s, server, store) = await reportingService();
      addTearDown(s.dispose);
      expect(s.canSendReports, isTrue);
      server.offline = true;
      expect(await s.sendReport(flagReport(sampleFlag())), isTrue);
      expect(s.status.reports, 1);
      await s.syncNow();
      expect(server.reports, isEmpty, reason: 'offline: it waits');
      expect(store.items.single.attempts, 0);
      server.offline = false;
      await s.syncNow();
      final stored = server.reports['feedback/${sampleFlag().id}']!;
      // (The fake notes the account; Firestore keeps reports in users/{uid}/.)
      expect(stored['uid'], 'uid1');
      expect(stored['kind'], 'flag');
      expect(store.items, isEmpty);
      expect(s.status.reports, 0);
    });

    test('a refused upload never shows as a sync error', () async {
      final (s, server, store) = await reportingService();
      addTearDown(s.dispose);
      server.refuseReports = true;
      await s.sendReport(report('abcdefgh'));
      await s.syncNow();
      expect(s.status.lastError, isNull);
      expect(s.status.phase, SyncPhase.idle);
      expect(s.status.reports, 1);
      expect(store.items.single.attempts, 1);
    });

    test('"Delete my cloud data" deletes sent reports too', () async {
      final (s, server, _) = await reportingService();
      addTearDown(s.dispose);
      await s.sendReport(report('abcdefgh'));
      await s.syncNow();
      expect(server.reports, hasLength(1));
      expect(await s.deleteCloudData(), CloudDeleteOutcome.deleted);
      expect(server.reports, isEmpty);
    });

    /// Identity Toolkit that refuses the first account deletion as too old a sign-in.
    (http.Client, List<String>) staleLoginAuth() {
      final calls = <String>[];
      var deletes = 0;
      return (
        MockClient((req) async {
          calls.add(req.url.path.split('/').last);
          if (req.url.path.endsWith('accounts:delete') && deletes++ == 0) {
            return http.Response(jsonEncode({'error': {'message': 'CREDENTIAL_TOO_OLD_LOGIN_AGAIN'}}), 400);
          }
          if (req.url.path.endsWith('accounts:signInWithIdp')) {
            return http.Response(
              jsonEncode({'localId': 'uid1', 'idToken': 't', 'refreshToken': 'r1', 'expiresIn': '3600'}),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
        calls,
      );
    }

    test('deleting the account after an old sign-in: a fresh Google sign-in, then it goes', () async {
      final (client, calls) = staleLoginAuth();
      final identity = FakeIdentity('google-token');
      final (s, _, _) = await reportingService(authClient: client, identity: identity);
      addTearDown(s.dispose);
      expect(identity.signIns, 1);
      expect(await s.deleteCloudData(), CloudDeleteOutcome.deleted);
      expect(identity.signIns, 2, reason: 're-authenticated');
      expect(calls.where((c) => c == 'accounts:delete'), hasLength(2));
      expect(s.status.phase, SyncPhase.signedOut);
      expect(s.status.lastError, isNull);
    });

    test('when re-authenticating is not possible (web) or is cancelled, it says the account remains', () async {
      for (final identity in [FakeIdentity('google-token', web: true), FakeIdentity('google-token')]) {
        final (client, _) = staleLoginAuth();
        final (s, server, _) = await reportingService(authClient: client, identity: identity);
        if (identity.web) {
          identity.webSignIn('google-token');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        } else {
          identity.token = null; // the re-authentication is cancelled
        }
        expect(s.status.signedIn, isTrue);
        expect(await s.deleteCloudData(), CloudDeleteOutcome.accountKept);
        expect(s.status.phase, SyncPhase.signedOut);
        expect(s.status.lastError, SyncMessages.accountKept);
        expect(server.reports, isEmpty);
        s.dispose();
      }
    });

    test('"Delete my cloud data" drops unsent reports', () async {
      final progress = InMemoryProgressStore();
      await progress.importEvents(sampleLog(count: 3));
      final (s, server, store) = await reportingService(progress: progress);
      addTearDown(s.dispose);
      server.offline = true;
      await s.sendReport(report('abcdefgh'));
      server.offline = false;
      await s.deleteCloudData();
      expect(store.items, isEmpty);
      expect(server.reports, isEmpty);
      expect(s.canSendReports, isFalse);
    });
  });
}
