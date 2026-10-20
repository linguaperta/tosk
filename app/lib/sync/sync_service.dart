/// The account and sync lifecycle around [SyncEngine]: sign-in with Google,
/// the persisted Firebase session, when to sync (start-up, app resume and
/// pause, a minute after the last answer, "Sync now"), and the status the
/// Settings screen shows. Created only when the build has a Firebase
/// configuration and the platform can sign in (`sync_bootstrap.dart`).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../ai/secret_store.dart';
import '../core/core.dart';
import 'firebase_auth.dart';
import 'firestore_backend.dart';
import 'google_identity.dart';
import 'sync_engine.dart';

enum SyncPhase { signedOut, signingIn, idle, syncing, error }

@immutable
class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.email,
    this.name,
    this.lastSync,
    this.lastError,
    this.pending = 0,
    this.offline = false,
  });

  final SyncPhase phase;
  final String? email;
  final String? name;
  final DateTime? lastSync;
  final String? lastError;

  /// Answers not uploaded yet.
  final int pending;

  /// The last attempt failed for lack of a connection (answers wait locally).
  final bool offline;

  bool get signedIn => phase == SyncPhase.idle || phase == SyncPhase.syncing || phase == SyncPhase.error;

  SyncStatus copyWith({
    SyncPhase? phase,
    String? email,
    String? name,
    DateTime? lastSync,
    String? lastError,
    bool clearError = false,
    int? pending,
    bool? offline,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        email: email ?? this.email,
        name: name ?? this.name,
        lastSync: lastSync ?? this.lastSync,
        lastError: clearError ? null : (lastError ?? this.lastError),
        pending: pending ?? this.pending,
        offline: offline ?? this.offline,
      );
}

/// Builds the backend for a session (Firestore in the app, a fake in tests).
typedef SyncBackendFactory = SyncBackend Function(FirebaseTokens tokens);

class SyncService extends ChangeNotifier {
  SyncService({
    required this.engine,
    required this.auth,
    required this.secrets,
    required this.identity,
    required this.backendFor,
    this.debounce = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// The app's wiring: Firestore over [client].
  factory SyncService.firestore({
    required SyncEngine engine,
    required String projectId,
    required FirebaseAuthClient auth,
    required http.Client client,
    required SecretStore secrets,
    required GoogleIdentity identity,
  }) =>
      SyncService(
        engine: engine,
        auth: auth,
        secrets: secrets,
        identity: identity,
        backendFor: (tokens) => FirestoreSyncBackend(projectId: projectId, client: client, tokens: tokens),
      );

  final SyncEngine engine;
  final FirebaseAuthClient auth;
  final SecretStore secrets;
  final GoogleIdentity identity;
  final SyncBackendFactory backendFor;
  final Duration debounce;
  final DateTime Function() clock;

  static const sessionKey = 'tosk.sync.session';

  SyncStatus _status = const SyncStatus(phase: SyncPhase.signedOut);
  SyncStatus get status => _status;

  /// Called after a sync changed local data (new answers or settings), so
  /// the app can refresh what it shows.
  void Function(SyncResult result)? onLocalChange;

  FirebaseTokens? _tokens;
  Timer? _timer;
  StreamSubscription<String>? _webTokens;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  void _set(SyncStatus s) {
    if (_disposed) return;
    _status = s;
    notifyListeners();
  }

  /// Restores a saved session and starts the triggers. Never throws.
  Future<void> start({bool lifecycle = true, Duration firstSyncDelay = const Duration(seconds: 3)}) async {
    _webTokens = identity.idTokens.listen((t) => unawaited(_completeSignIn(t)));
    if (lifecycle) {
      _lifecycle = AppLifecycleListener(
        onResume: () => unawaited(syncNow()),
        onPause: () => unawaited(syncNow()),
      );
    }
    try {
      final saved = FirebaseSession.decode(await secrets.read(sessionKey));
      if (saved != null) {
        _attach(saved);
        _set(SyncStatus(phase: SyncPhase.idle, email: saved.email, name: saved.displayName, pending: await engine.pending()));
        _schedule(firstSyncDelay);
      }
    } on Object catch (e) {
      debugPrint('[sync] could not restore the session: $e');
    }
  }

  void _attach(FirebaseSession s) {
    final tokens = FirebaseTokens(
      auth,
      s,
      onChanged: (n) => unawaited(secrets.write(sessionKey, n.encode())),
      onSignedOut: () => unawaited(_signedOutRemotely()),
    );
    _tokens = tokens;
    engine.backend = backendFor(tokens);
  }

  /// A new answer was recorded: sync a little later (answers arrive in bursts).
  void answerRecorded() {
    if (_tokens == null) return;
    _schedule(debounce);
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, () => unawaited(syncNow()));
  }

  /// Interactive sign-in (Android, iOS); the web signs in through [GoogleIdentity.button].
  Future<void> signIn() async {
    final before = _status;
    _set(_status.copyWith(phase: SyncPhase.signingIn, clearError: true));
    try {
      final token = await identity.signIn();
      if (token == null) {
        _set(before);
        return;
      }
      await _completeSignIn(token);
    } on Object catch (e) {
      _set(before.copyWith(phase: SyncPhase.signedOut, lastError: 'Sign-in failed: ${_describe(e)}'));
    }
  }

  Future<void> _completeSignIn(String googleIdToken) async {
    try {
      _set(_status.copyWith(phase: SyncPhase.signingIn, clearError: true));
      final session = await auth.signInWithGoogle(googleIdToken);
      await secrets.write(sessionKey, session.encode());
      _attach(session);
      _set(SyncStatus(phase: SyncPhase.idle, email: session.email, name: session.displayName));
      await syncNow();
    } on Object catch (e) {
      _set(const SyncStatus(phase: SyncPhase.signedOut).copyWith(lastError: 'Sign-in failed: ${_describe(e)}'));
    }
  }

  /// One sync now (no-op when signed out or already running). Errors end up
  /// in [status]; the answers stay queued.
  Future<SyncResult?> syncNow() async {
    if (_tokens == null || _disposed) return null;
    _timer?.cancel();
    _set(_status.copyWith(phase: SyncPhase.syncing));
    try {
      final r = await engine.sync();
      _set(_status.copyWith(
        phase: SyncPhase.idle,
        lastSync: clock(),
        clearError: true,
        offline: false,
        pending: await engine.pending(),
      ));
      if (r.changedLocal) onLocalChange?.call(r);
      return r;
    } on SyncAuthException catch (e) {
      _set(_status.copyWith(phase: SyncPhase.error, lastError: e.message, pending: await _pending()));
    } on Object catch (e) {
      final offline = _looksOffline(e);
      _set(_status.copyWith(
        phase: _tokens == null ? SyncPhase.signedOut : SyncPhase.error,
        lastError: offline ? null : _describe(e),
        clearError: offline,
        offline: offline,
        pending: await _pending(),
      ));
    }
    return null;
  }

  Future<int> _pending() async {
    try {
      return await engine.pending();
    } on Object {
      return _status.pending;
    }
  }

  Future<void> _forgetSession() async {
    _timer?.cancel();
    _tokens = null;
    engine.backend = const NullSyncBackend();
    await secrets.delete(sessionKey);
    try {
      await identity.signOut();
    } on Object {
      // Google's own state; nothing to do.
    }
  }

  Future<void> _signedOutRemotely() async {
    await _forgetSession();
    _set(const SyncStatus(phase: SyncPhase.signedOut, lastError: 'Signed out. Sign in again to keep syncing.'));
  }

  /// Signs out on this device. Progress stays here and in the account.
  Future<void> signOut() async {
    await _forgetSession();
    _set(const SyncStatus(phase: SyncPhase.signedOut));
  }

  /// Deletes everything stored in the account (answers, settings and the
  /// account itself), then signs out. Progress on this device is kept.
  Future<void> deleteCloudData() async {
    final tokens = _tokens;
    if (tokens == null) return;
    _set(_status.copyWith(phase: SyncPhase.syncing));
    try {
      await engine.deleteRemote();
      try {
        await auth.deleteAccount(await tokens.idToken());
      } on Object catch (e) {
        // The data is gone; an account without data holds nothing.
        debugPrint('[sync] account not deleted: $e');
      }
      await _forgetSession();
      _set(const SyncStatus(phase: SyncPhase.signedOut));
    } on Object catch (e) {
      _set(_status.copyWith(phase: SyncPhase.error, lastError: 'Could not delete the cloud data: ${_describe(e)}'));
      rethrow;
    }
  }

  static bool _looksOffline(Object e) {
    final s = e.toString();
    return e is TimeoutException ||
        e is http.ClientException ||
        s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('XMLHttpRequest error') ||
        s.contains('No network');
  }

  static String _describe(Object e) => switch (e) {
        FirebaseAuthException(:final code) => code,
        SyncAuthException(:final message) => message,
        _ => '$e',
      };

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _lifecycle?.dispose();
    unawaited(_webTokens?.cancel());
    super.dispose();
  }
}
