// SyncService under concurrency: one signInWithIdp per sign-in however many
// taps and token reports arrive (the v0.7.2 DUPLICATE_RAW_ID report), a retry
// that heals DUPLICATE_RAW_ID without showing it, and syncs that never
// overlap (triggers during a run queue exactly one more, which picks up what
// changed meanwhile, e.g. an imported backup).
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:tosk/ai/secret_store.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/sync/fake_sync_backend.dart';
import 'package:tosk/sync/firebase_auth.dart';
import 'package:tosk/sync/sync_engine.dart';
import 'package:tosk/sync/sync_errors.dart';
import 'package:tosk/sync/sync_service.dart';
import 'package:tosk/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/sample_log.dart';
import 'sync_service_test.dart' show FakeIdentity;

/// Identity Toolkit as far as sign-in goes: the first `signInWithIdp` for a
/// Google account creates the Firebase user, and another call for the same
/// new account while that one is still running gets `DUPLICATE_RAW_ID`.
class FakeIdentityToolkit {
  final _users = <String>{};
  int _creating = 0;
  int signInCalls = 0;

  /// Error codes for the next calls, one per call.
  final failNext = <String>[];
  Duration latency = const Duration(milliseconds: 20);

  late final http.Client client = MockClient((req) async {
    if (req.url.path.endsWith('accounts:signInWithIdp')) {
      signInCalls++;
      await Future<void>.delayed(latency);
      if (failNext.isNotEmpty) return _error(failNext.removeAt(0));
      const sub = 'google-sub-1';
      if (!_users.contains(sub)) {
        if (_creating > 0) return _error('DUPLICATE_RAW_ID');
        _creating++;
        await Future<void>.delayed(latency);
        _creating--;
        _users.add(sub);
      }
      return http.Response(
        jsonEncode({'localId': 'uid1', 'idToken': 't', 'refreshToken': 'r1', 'expiresIn': '3600', 'email': 'me@example.com'}),
        200,
      );
    }
    if (req.url.host == 'securetoken.googleapis.com') {
      return http.Response(jsonEncode({'id_token': 't2', 'refresh_token': 'r1', 'expires_in': '3600'}), 200);
    }
    return http.Response('{}', 200);
  });

  static http.Response _error(String code) =>
      http.Response(jsonEncode({'error': {'code': 400, 'message': code}}), 400);
}

/// Counts runs and how many overlap; [gateBefore]/[gateAfter] hold a run
/// before or after the real work.
class ProbedEngine extends SyncEngine {
  ProbedEngine({
    required super.store,
    required super.progress,
    required super.importer,
    required super.log,
    required super.backend,
    required super.syncedSettings,
    super.clock,
  });

  int runs = 0;
  int active = 0;
  int maxActive = 0;

  /// Runs whose real work (pull, push, settings) is done.
  int worked = 0;
  Completer<void>? gateBefore;
  Completer<void>? gateAfter;

  @override
  Future<SyncResult> sync() async {
    runs++;
    active++;
    maxActive = max(maxActive, active);
    try {
      await gateBefore?.future;
      final r = await super.sync();
      worked++;
      await gateAfter?.future;
      return r;
    } finally {
      active--;
    }
  }
}

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue);
}

/// Every event the account holds, counting duplicates across batches.
Future<List<String>> storedEventIds(FakeSyncServer server, String account) async {
  final b = FakeSyncBackend(server, account: account);
  final ids = <String>[];
  SyncCursor? after;
  while (true) {
    final page = await b.pullEvents(after: after);
    for (final batch in page.items) {
      ids.addAll(batch.events.map((e) => e.event.id));
      after = batch.cursor;
    }
    if (!page.hasMore || page.items.isEmpty) break;
  }
  return ids;
}

void main() {
  late FakeSyncServer server;
  late InMemoryProgressStore progress;
  late FakeIdentityToolkit toolkit;
  late FakeIdentity identity;
  late ProbedEngine engine;
  late List<SyncStatus> statuses;

  setUp(() {
    server = FakeSyncServer(clock: () => DateTime.utc(2026, 10, 3));
    progress = InMemoryProgressStore();
    toolkit = FakeIdentityToolkit();
    identity = FakeIdentity('google-token');
    statuses = [];
  });

  SyncService service() {
    engine = ProbedEngine(
      store: InMemorySyncStore(),
      progress: progress,
      importer: progress,
      log: progress,
      backend: const NullSyncBackend(),
      syncedSettings: const {},
      clock: server.clock,
    );
    final s = SyncService(
      engine: engine,
      auth: FirebaseAuthClient(apiKey: 'k', client: toolkit.client),
      secrets: MemorySecretStore(),
      identity: identity,
      backendFor: (tokens) => FakeSyncBackend(server, account: tokens.uid),
      signInRetryDelay: const Duration(milliseconds: 30),
    );
    s.addListener(() => statuses.add(s.status));
    addTearDown(s.dispose);
    return s;
  }

  void expectNoErrorShown() {
    for (final st in statuses) {
      expect(st.lastError, isNull, reason: 'status ${st.phase} showed an error');
    }
  }

  group('sign-in', () {
    test('Android: authenticate() also reports the sign-in on the token stream: one signInWithIdp, no error', () async {
      // The v0.7.2 report: the button's token and the stream's report of it
      // both went to signInWithIdp at once; the second got DUPLICATE_RAW_ID.
      identity = FakeIdentity('google-token', alsoOnStream: true);
      await progress.importEvents(sampleLog(count: 10));
      final s = service();
      await s.start(lifecycle: false);
      await s.signIn();
      await pumpEventQueue();
      expect(toolkit.signInCalls, 1);
      expect(s.status.phase, SyncPhase.idle);
      expectNoErrorShown();
      expect(engine.runs, 1);
      expect(server.eventIds('uid1').length, 10);
    });

    test('concurrent taps share one sign-in: one Google sheet, one account request', () async {
      final s = service();
      await s.start(lifecycle: false);
      identity.sheet = Completer<void>();
      final taps = [s.signIn(), s.signIn(), s.signIn()];
      identity.webSignIn('google-token'); // and a stray token report
      identity.sheet!.complete();
      await Future.wait(taps);
      await pumpEventQueue();
      expect(identity.signIns, 1);
      expect(toolkit.signInCalls, 1);
      expect(s.status.phase, SyncPhase.idle);
      expectNoErrorShown();
    });

    test('web: a double report from Google\'s button signs in once', () async {
      identity = FakeIdentity(null, web: true);
      final s = service();
      await s.start(lifecycle: false);
      identity
        ..webSignIn('google-token')
        ..webSignIn('google-token');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(toolkit.signInCalls, 1);
      expect(s.status.phase, SyncPhase.idle);
      // Reported again later (already signed in): ignored.
      identity.webSignIn('google-token');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(toolkit.signInCalls, 1);
    });

    test('DUPLICATE_RAW_ID once: retried after a pause, signed in, no error shown', () async {
      await progress.importEvents(sampleLog(count: 5));
      toolkit.failNext.add('DUPLICATE_RAW_ID');
      final s = service();
      await s.start(lifecycle: false);
      await s.signIn();
      expect(toolkit.signInCalls, 2);
      expect(s.status.phase, SyncPhase.idle);
      expect(s.status.email, 'me@example.com');
      expectNoErrorShown();
      expect(statuses.any((st) => st.notice == SyncMessages.retrying), isTrue);
      expect(s.status.notice, isNull);
      expect(server.eventIds('uid1').length, 5);
    });

    test('a sign-in racing another for the same new account (another device) recovers by the retry', () async {
      final s = service();
      await s.start(lifecycle: false);
      final other = FirebaseAuthClient(apiKey: 'k', client: toolkit.client).signInWithGoogle('google-token');
      await s.signIn();
      await other;
      expect(toolkit.signInCalls, 3); // other, ours (DUPLICATE_RAW_ID), our retry
      expect(s.status.phase, SyncPhase.idle);
      expectNoErrorShown();
    });

    test('DUPLICATE_RAW_ID twice: a friendly message, never the code', () async {
      toolkit.failNext.addAll(['DUPLICATE_RAW_ID', 'DUPLICATE_RAW_ID']);
      final s = service();
      await s.start(lifecycle: false);
      await s.signIn();
      expect(toolkit.signInCalls, 2);
      expect(s.status.phase, SyncPhase.signedOut);
      expect(s.status.lastError, SyncMessages.hiccup);
      expect(statuses.every((st) => !(st.lastError ?? '').contains('DUPLICATE')), isTrue);
    });

    test('a non-retryable error is not retried and is shown in words', () async {
      toolkit.failNext.add('INVALID_IDP_RESPONSE : Invalid Idp Response');
      final s = service();
      await s.start(lifecycle: false);
      await s.signIn();
      expect(toolkit.signInCalls, 1);
      expect(s.status.lastError, SyncMessages.expired);
    });

    test('"Sync now" during a sign-in waits for it; the first sync starts only after the sign-in', () async {
      await progress.importEvents(sampleLog(count: 4));
      final s = service();
      await s.start(lifecycle: false);
      identity.sheet = Completer<void>();
      final signIn = s.signIn();
      final sync = s.syncNow();
      expect(engine.runs, 0);
      identity.sheet!.complete();
      final r = await sync;
      await signIn;
      expect(engine.runs, 1);
      expect(r!.pushed, 4);
    });
  });

  group('one sync at a time', () {
    Future<SyncService> signedIn() async {
      final s = service();
      await s.start(lifecycle: false);
      await s.signIn();
      expect(engine.runs, 1);
      engine
        ..runs = 0
        ..worked = 0;
      return s;
    }

    test('triggers during a run queue exactly one more; no run overlaps, no event is uploaded twice', () async {
      final s = await signedIn();
      for (final e in sampleLog(seed: 1, count: 5)) {
        await progress.record(e);
      }
      engine.gateAfter = Completer<void>();
      final first = s.syncNow();
      await until(() => engine.worked == 1); // run 1 has uploaded, not finished
      for (final e in sampleLog(seed: 2, count: 3)) {
        await progress.record(e);
      }
      final queued = [s.syncNow(), s.syncNow(), s.syncNow()];
      s.answerRecorded();
      await pumpEventQueue();
      expect(engine.runs, 1);
      engine.gateAfter!.complete();
      final r1 = await first;
      final r2 = await Future.wait(queued);
      expect(engine.runs, 2);
      expect(engine.maxActive, 1);
      expect(r1!.pushed, 5);
      expect(r2.map((r) => r!.pushed), [3, 3, 3]); // the one queued run, shared
      final stored = await storedEventIds(server, 'uid1');
      expect(stored.length, 8);
      expect(stored.toSet().length, 8);
      expect(s.status.pending, 0);
    });

    test('a backup imported during the first sync is uploaded by the run queued after it', () async {
      await progress.importEvents(sampleLog(seed: 3, count: 10));
      final s = service();
      await s.start(lifecycle: false);
      engine.gateAfter = Completer<void>();
      final signIn = s.signIn();
      await until(() => engine.worked == 1);
      // The import lands after the first run's upload (what importBackup does,
      // then the trigger it fires).
      await progress.importEvents(sampleLog(seed: 4, count: 20));
      await progress.rebuildStates();
      final follow = s.syncNow();
      engine.gateAfter!.complete();
      await signIn;
      final r = await follow;
      expect(engine.runs, 2);
      expect(engine.maxActive, 1);
      expect(r!.pushed, 20);
      final stored = await storedEventIds(server, 'uid1');
      expect(stored.length, 30);
      expect(stored.toSet().length, 30);
    });

    test('signing out during a sync: the run ends quietly and the status stays signed out', () async {
      final s = await signedIn();
      engine.gateBefore = Completer<void>();
      final run = s.syncNow();
      await pumpEventQueue();
      await s.signOut();
      engine.gateBefore!.complete();
      expect(await run, isNull);
      expect(s.status.phase, SyncPhase.signedOut);
      expect(s.status.lastError, isNull);
    });

    test('a failed sync shows words, not the exception', () async {
      final s = await signedIn();
      engine.backend = _FailingBackend(server);
      await s.syncNow();
      expect(s.status.phase, SyncPhase.error);
      expect(s.status.lastError, SyncMessages.unreachable);
    });
  });
}

class _FailingBackend extends FakeSyncBackend {
  _FailingBackend(super.server) : super(account: 'uid1');
  @override
  Future<SyncPage<EventBatch>> pullEvents({SyncCursor? after, int limit = 50}) async =>
      throw const FirebaseAuthException('UNAVAILABLE', 503);
}
