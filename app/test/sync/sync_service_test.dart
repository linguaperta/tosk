// SyncService: session restore, sign-in (and cancel), offline status with the
// queue count, the refresh callback, sign-out. Google and Firebase are faked.
import 'dart:async';
import 'dart:convert';

import 'package:tosk/ai/secret_store.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/sync/fake_sync_backend.dart';
import 'package:tosk/sync/firebase_auth.dart';
import 'package:tosk/sync/google_identity.dart';
import 'package:tosk/sync/sync_engine.dart';
import 'package:tosk/sync/sync_service.dart';
import 'package:tosk/sync/sync_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/sample_log.dart';

/// Hands out a fixed Google ID token (null = the user cancels).
class FakeIdentity implements GoogleIdentity {
  FakeIdentity(this.token, {this.web = false, this.alsoOnStream = false});
  String? token;
  final bool web;

  /// Like google_sign_in's authenticate(): a sign-in is returned *and*
  /// reported on [idTokens].
  final bool alsoOnStream;

  /// When set, [signIn] waits for it (the Google sheet is open).
  Completer<void>? sheet;
  int signIns = 0;
  final _tokens = StreamController<String>.broadcast();
  int signOuts = 0;

  /// What a click on Google's web button would do.
  void webSignIn(String t) => _tokens.add(t);

  @override
  bool get canCallSignIn => !web;
  @override
  Future<String?> signIn() async {
    signIns++;
    await sheet?.future;
    final t = token;
    if (alsoOnStream && t != null) _tokens.add(t);
    return t;
  }
  @override
  Widget button() => const SizedBox(key: ValueKey('google-web-button'), width: 200, height: 40);
  @override
  Stream<String> get idTokens => _tokens.stream;
  @override
  Future<void> signOut() async => signOuts++;
}

http.Client fakeAuthServer() => MockClient((req) async {
  if (req.url.path.endsWith('accounts:signInWithIdp')) {
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

void main() {
  late FakeSyncServer server;
  late InMemoryProgressStore progress;
  late MemorySecretStore secrets;
  late FakeIdentity identity;

  setUp(() {
    server = FakeSyncServer(clock: () => DateTime.utc(2026, 10, 3));
    progress = InMemoryProgressStore();
    secrets = MemorySecretStore();
    identity = FakeIdentity('google-token');
  });

  SyncService service() {
    final engine = SyncEngine(
      store: InMemorySyncStore(),
      progress: progress,
      importer: progress,
      log: progress,
      backend: const NullSyncBackend(),
      syncedSettings: const {'ui.theme_mode'},
      clock: server.clock,
    );
    final s = SyncService(
      engine: engine,
      auth: FirebaseAuthClient(apiKey: 'k', client: fakeAuthServer()),
      secrets: secrets,
      identity: identity,
      backendFor: (tokens) => FakeSyncBackend(server, account: tokens.uid),
    );
    addTearDown(s.dispose);
    return s;
  }

  test('signed out until the user signs in; a cancelled sign-in changes nothing', () async {
    final s = service();
    await s.start(lifecycle: false);
    expect(s.status.phase, SyncPhase.signedOut);
    expect(await s.syncNow(), isNull);
    identity.token = null;
    await s.signIn();
    expect(s.status.phase, SyncPhase.signedOut);
    expect(s.status.lastError, isNull);
  });

  test('sign-in uploads the log; the session is restored on the next start', () async {
    await progress.importEvents(sampleLog(count: 40));
    final s = service();
    await s.start(lifecycle: false);
    await s.signIn();
    expect(s.status.phase, SyncPhase.idle);
    expect(s.status.email, 'me@example.com');
    expect(server.eventIds('uid1').length, 40);
    expect(FirebaseSession.decode(await secrets.read(SyncService.sessionKey))!.refreshToken, 'r1');

    final again = service();
    await again.start(lifecycle: false, firstSyncDelay: const Duration(hours: 1));
    expect(again.status.signedIn, isTrue);
    expect(again.status.email, 'me@example.com');
    expect((await again.syncNow())!.pushed, 0);
  });

  test('web: a sign-in through Google\'s button completes the same way', () async {
    identity = FakeIdentity(null, web: true);
    final s = service();
    await s.start(lifecycle: false);
    identity.webSignIn('google-token');
    await pumpEventQueue();
    expect(s.status.phase, SyncPhase.idle);
  });

  test('offline: the status says so and counts the waiting answers; new answers arrive with a refresh', () async {
    final s = service();
    await s.start(lifecycle: false);
    await s.signIn();
    final changes = <SyncResult>[];
    s.onLocalChange = changes.add;
    for (final e in sampleLog(count: 7)) {
      await progress.record(e);
    }
    server.offline = true;
    await s.syncNow();
    expect(s.status.offline, isTrue);
    expect(s.status.pending, 7);
    expect(s.status.lastError, isNull);
    expect(s.status.signedIn, isTrue);
    server.offline = false;
    await s.syncNow();
    expect(s.status.offline, isFalse);
    expect(s.status.pending, 0);
    expect(changes, isEmpty); // nothing new came down

    // Another device's answers come down: the app is told to refresh.
    await FakeSyncBackend(server, account: 'uid1').pushEvents('other', 'd2', [
      for (final e in sampleLog(seed: 99, count: 3)) SyncedEvent(e, 120),
    ]);
    await s.syncNow();
    expect(changes.single.imported, 3);
  });

  test('sign-out forgets the session but keeps local progress', () async {
    await progress.importEvents(sampleLog(count: 5));
    final s = service();
    await s.start(lifecycle: false);
    await s.signIn();
    await s.signOut();
    expect(s.status.phase, SyncPhase.signedOut);
    expect(await secrets.read(SyncService.sessionKey), isNull);
    expect(identity.signOuts, 1);
    expect((await progress.log()).length, 5);
    expect(server.eventIds('uid1').length, 5); // the account keeps its copy
  });
}
