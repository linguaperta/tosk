/// The account and sync lifecycle around [SyncEngine]: sign-in with Google,
/// the persisted Firebase session, when to sync (start-up, app resume and
/// pause, a minute after the last answer, "Sync now"), and the status the
/// Settings screen shows. Created only when the build has a Firebase
/// configuration and the platform can sign in (`sync_bootstrap.dart`).
///
/// **One at a time.** There is at most one sign-in in flight (button taps and
/// web tokens join it) and at most one sync running, with at most one more
/// queued behind it (every trigger that arrives meanwhile shares that one).
/// The first sync after a sign-in starts only once the session is stored.
///
/// **Reports for the developer** (flags, feedback, crash reports; only while
/// signed in, [sendReport]) wait in the [ReportOutbox] and are uploaded after
/// each sync, with the outbox's own batching and backoff; their failures never
/// show as sync errors.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../ai/secret_store.dart';
import '../core/core.dart';
import 'firebase_auth.dart';
import 'firestore_backend.dart';
import 'google_identity.dart';
import 'report_outbox.dart';
import 'sync_engine.dart';
import 'sync_errors.dart';

enum SyncPhase { signedOut, signingIn, idle, syncing, error }

/// What "Delete my cloud data" achieved.
enum CloudDeleteOutcome {
  /// The data and the sign-in account are gone.
  deleted,

  /// The data is gone, but the sign-in account could not be removed (it
  /// needs a recent sign-in): sign in again and delete once more.
  accountKept,
}

@immutable
class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.email,
    this.name,
    this.lastSync,
    this.lastError,
    this.notice,
    this.pending = 0,
    this.reports = 0,
    this.offline = false,
  });

  final SyncPhase phase;
  final String? email;
  final String? name;
  final DateTime? lastSync;

  /// A sentence for the user (`sync_errors.dart`), never a raw error code.
  final String? lastError;

  /// A passing remark that is not an error ("Sign-in hiccup, trying
  /// again…"). Not carried over by [copyWith].
  final String? notice;

  /// Answers not uploaded yet.
  final int pending;

  /// Reports for the developer not uploaded yet.
  final int reports;

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
    String? notice,
    int? pending,
    int? reports,
    bool? offline,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        email: email ?? this.email,
        name: name ?? this.name,
        lastSync: lastSync ?? this.lastSync,
        lastError: clearError ? null : (lastError ?? this.lastError),
        notice: notice,
        pending: pending ?? this.pending,
        reports: reports ?? this.reports,
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
    this.signInRetryDelay = const Duration(milliseconds: 1500),
    this.outbox,
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
    ReportOutbox? outbox,
  }) =>
      SyncService(
        engine: engine,
        auth: auth,
        secrets: secrets,
        identity: identity,
        outbox: outbox,
        backendFor: (tokens) => FirestoreSyncBackend(projectId: projectId, client: client, tokens: tokens),
      );

  final SyncEngine engine;
  final FirebaseAuthClient auth;
  final SecretStore secrets;
  final GoogleIdentity identity;
  final SyncBackendFactory backendFor;
  final Duration debounce;

  /// Reports for the developer waiting to be uploaded (null: none can be sent).
  final ReportOutbox? outbox;

  /// The pause before `signInWithIdp` is retried ([isRetryableSignIn]).
  final Duration signInRetryDelay;
  final DateTime Function() clock;

  static const sessionKey = 'tosk.sync.session';

  /// How soon after a local bulk change ([localDataChanged]) to sync.
  static const localChangeDelay = Duration(seconds: 2);

  SyncStatus _status = const SyncStatus(phase: SyncPhase.signedOut);
  SyncStatus get status => _status;

  /// Called after a sync changed local data (new answers or settings), so
  /// the app can refresh what it shows.
  void Function(SyncResult result)? onLocalChange;

  FirebaseTokens? _tokens;

  /// The one sign-in in flight.
  Future<void>? _signingIn;

  /// The Google ID token of the last sign-in (a second report of it is ignored).
  String? _usedGoogleToken;
  SyncResult? _lastResult;

  /// The sync running now, and the one queued after it.
  Future<SyncResult?>? _current;
  Future<SyncResult?>? _next;

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
    _webTokens = identity.idTokens.listen(_onIdToken);
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
        _set(SyncStatus(
          phase: SyncPhase.idle,
          email: saved.email,
          name: saved.displayName,
          pending: await engine.pending(),
          reports: await _reportsPending(),
        ));
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

  /// Many answers or settings changed at once (a backup was imported): sync
  /// soon. A sync already running is followed by one more.
  void localDataChanged() {
    if (_tokens == null) return;
    _schedule(localChangeDelay);
  }

  // ------------------------------------------------------------------ reports

  /// Whether [sendReport] would queue a report (signed in, with an outbox).
  bool get canSendReports => outbox != null && _tokens != null && !_disposed;

  /// Queues [report] for the developer and syncs soon; false (nothing
  /// queued) when not signed in. Offline, it waits for the next sync.
  Future<bool> sendReport(OutgoingReport report) async {
    final box = outbox;
    if (box == null || !canSendReports) return false;
    await box.add(report);
    _set(_status.copyWith(reports: await _reportsPending()));
    _schedule(localChangeDelay);
    return true;
  }

  Future<int> _reportsPending() async {
    try {
      return await outbox?.pending() ?? 0;
    } on Object {
      return _status.reports;
    }
  }

  /// Uploads due reports through the current backend. Never throws.
  Future<void> _flushReports() async {
    final box = outbox;
    final backend = engine.backend;
    if (box == null || backend is! ReportSender) return;
    final sender = backend as ReportSender;
    try {
      final r = await box.flush(sender);
      if (r.sent > 0 || r.dropped > 0 || r.failed > 0) debugPrint('[sync] reports: $r');
    } on Object catch (e) {
      debugPrint('[sync] reports not sent: $e');
    }
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, () => unawaited(syncNow()));
  }

  // ------------------------------------------------------------------ sign-in

  /// Interactive sign-in (Android, iOS); the web signs in through
  /// [GoogleIdentity.button]. Taps while a sign-in is running join it.
  Future<void> signIn() => _signingIn ??= _track(_interactiveSignIn());

  /// A Google ID token from [GoogleIdentity.idTokens] (the web's button).
  /// Ignored while a sign-in is running, when already signed in, and when it
  /// is the token just used: google_sign_in's `authenticate()` also reports
  /// its sign-in on that stream, and handling that report as a second sign-in
  /// sent two `signInWithIdp` calls for one new account at once, which
  /// Identity Toolkit answers with `DUPLICATE_RAW_ID`.
  void _onIdToken(String googleIdToken) {
    if (_disposed) return;
    if (_signingIn != null || _tokens != null || googleIdToken == _usedGoogleToken) {
      debugPrint('[sync] ignoring a Google token (a sign-in is running or done)');
      return;
    }
    _signingIn = _track(_completeSignIn(googleIdToken));
  }

  Future<void> _track(Future<void> f) => f.whenComplete(() => _signingIn = null);

  Future<void> _interactiveSignIn() async {
    final before = _status;
    _set(_status.copyWith(phase: SyncPhase.signingIn, clearError: true));
    String? token;
    try {
      token = await identity.signIn();
    } on Object catch (e) {
      debugPrint('[sync] Google sign-in failed: $e');
      _set(before.copyWith(phase: SyncPhase.signedOut, lastError: friendlySyncError(e, signIn: true)));
      return;
    }
    if (token == null) {
      _set(before);
      return;
    }
    await _completeSignIn(token);
  }

  /// Google ID token → Firebase session; then the first sync, once the
  /// session is stored and attached. Never throws.
  Future<void> _completeSignIn(String googleIdToken) async {
    _usedGoogleToken = googleIdToken;
    _set(_status.copyWith(phase: SyncPhase.signingIn, clearError: true));
    final FirebaseSession session;
    try {
      session = await _signInWithIdp(googleIdToken);
      await secrets.write(sessionKey, session.encode());
    } on Object catch (e) {
      debugPrint('[sync] sign-in failed: $e');
      _set(SyncStatus(phase: SyncPhase.signedOut, lastError: friendlySyncError(e, signIn: true)));
      return;
    }
    if (_disposed) return;
    _attach(session);
    _set(SyncStatus(phase: SyncPhase.idle, email: session.email, name: session.displayName));
    await _enqueueSync();
  }

  /// `signInWithIdp`, retried once after [signInRetryDelay] when it failed
  /// for a reason a retry fixes ([isRetryableSignIn]; above all
  /// `DUPLICATE_RAW_ID`, a race with another sign-in that was creating the
  /// account: the retry signs in to it).
  Future<FirebaseSession> _signInWithIdp(String googleIdToken) async {
    try {
      return await auth.signInWithGoogle(googleIdToken);
    } on Object catch (e) {
      if (!isRetryableSignIn(e) || _disposed) rethrow;
      debugPrint('[sync] signInWithIdp failed ($e); retrying once');
      _set(_status.copyWith(phase: SyncPhase.signingIn, notice: SyncMessages.retrying));
      await Future<void>.delayed(signInRetryDelay);
      return auth.signInWithGoogle(googleIdToken);
    }
  }

  // ------------------------------------------------------------------ sync

  /// One sync now (no-op when signed out). Syncs never overlap: a call while
  /// one runs queues one more run after it (every such call shares it, and it
  /// picks up what changed meanwhile); a call before a sign-in has its
  /// session waits for the sign-in, which ends with its own first sync.
  /// Errors end up in [status]; the answers stay queued.
  Future<SyncResult?> syncNow() async {
    if (_disposed) return null;
    if (_tokens == null) {
      final signing = _signingIn;
      if (signing == null) return null;
      await signing;
      return _lastResult;
    }
    _timer?.cancel();
    return _enqueueSync();
  }

  Future<SyncResult?> _enqueueSync() {
    final current = _current;
    if (current == null) {
      final run = _runSync();
      _current = run;
      return run.whenComplete(() {
        if (identical(_current, run)) _current = null;
      });
    }
    return _next ??= current.then((_) {
      _next = null;
      return _enqueueSync();
    });
  }

  /// One engine run with its status. Never throws.
  Future<SyncResult?> _runSync() async {
    final tokens = _tokens;
    if (tokens == null || _disposed) return null;
    // Signed out meanwhile: leave the status alone.
    bool stale() => _disposed || !identical(_tokens, tokens);
    _set(_status.copyWith(phase: SyncPhase.syncing));
    try {
      final r = await engine.sync();
      if (!stale()) await _flushReports();
      final pending = await _pending();
      final reports = await _reportsPending();
      if (stale()) return null;
      _lastResult = r;
      _set(_status.copyWith(
        phase: SyncPhase.idle,
        lastSync: clock(),
        clearError: true,
        offline: false,
        pending: pending,
        reports: reports,
      ));
      if (r.changedLocal) onLocalChange?.call(r);
      return r;
    } on Object catch (e) {
      debugPrint('[sync] sync failed: $e');
      final offline = e is! SyncAuthException && looksOffline(e);
      // Reports go their own way (a sync error needn't be theirs).
      if (!offline && !stale()) await _flushReports();
      final pending = await _pending();
      final reports = await _reportsPending();
      if (stale()) return null;
      _set(_status.copyWith(
        phase: SyncPhase.error,
        lastError: offline ? null : friendlySyncError(e),
        clearError: offline,
        offline: offline,
        pending: pending,
        reports: reports,
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

  // ------------------------------------------------------------------ sign-out

  Future<void> _forgetSession() async {
    _timer?.cancel();
    _tokens = null;
    _usedGoogleToken = null;
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
    _set(const SyncStatus(phase: SyncPhase.signedOut, lastError: SyncMessages.expired));
  }

  /// Signs out on this device. Progress stays here and in the account.
  Future<void> signOut() async {
    await _forgetSession();
    _set(const SyncStatus(phase: SyncPhase.signedOut));
  }

  /// Deletes everything stored in the account (answers, settings, the
  /// reports sent to the developer, and the sign-in account itself), then
  /// signs out. Progress on this device is kept; reports not sent yet are
  /// dropped.
  ///
  /// Firebase removes a sign-in account only after a recent sign-in
  /// (`CREDENTIAL_TOO_OLD_LOGIN_AGAIN`). Where the app can start a Google
  /// sign-in (Android, iOS) it asks for one and retries; otherwise (the web)
  /// or when that fails, the data is still gone but the result is
  /// [CloudDeleteOutcome.accountKept] and the status says how to finish
  /// (sign in again and delete once more). Never reports success when the
  /// account remains. Throws (status: an error) when the data itself could
  /// not be deleted.
  Future<CloudDeleteOutcome> deleteCloudData() async {
    final tokens = _tokens;
    if (tokens == null) return CloudDeleteOutcome.deleted;
    // Not in the middle of a sync (a queued one then finds no session).
    await _current;
    _set(_status.copyWith(phase: SyncPhase.syncing));
    try {
      await engine.deleteRemote();
      final accountGone = await _deleteAccount(tokens);
      await _forgetSession();
      try {
        await outbox?.clear();
      } on Object {
        // Only unsent reports.
      }
      if (!accountGone) {
        _set(const SyncStatus(phase: SyncPhase.signedOut, lastError: SyncMessages.accountKept));
        return CloudDeleteOutcome.accountKept;
      }
      _set(const SyncStatus(phase: SyncPhase.signedOut));
      return CloudDeleteOutcome.deleted;
    } on Object catch (e) {
      debugPrint('[sync] could not delete the cloud data: $e');
      _set(_status.copyWith(phase: SyncPhase.error, lastError: 'Could not delete the cloud data. ${friendlySyncError(e, fallback: 'Please try again.')}'));
      rethrow;
    }
  }

  /// Deletes the Firebase account; on failure, re-authenticates with a fresh
  /// Google sign-in (where the app can start one) and tries once more.
  Future<bool> _deleteAccount(FirebaseTokens tokens) async {
    try {
      await auth.deleteAccount(await tokens.idToken());
      return true;
    } on Object catch (e) {
      debugPrint('[sync] account not deleted: $e');
      if (looksOffline(e) || !identity.canCallSignIn) return false;
    }
    try {
      final google = await identity.signIn();
      if (google == null) return false; // cancelled
      final fresh = await auth.signInWithGoogle(google);
      if (fresh.uid != tokens.uid || fresh.idToken == null) {
        debugPrint('[sync] re-authenticated as another account; the account stays');
        return false;
      }
      await auth.deleteAccount(fresh.idToken!);
      return true;
    } on Object catch (e) {
      debugPrint('[sync] account not deleted after re-authentication: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _lifecycle?.dispose();
    unawaited(_webTokens?.cancel());
    super.dispose();
  }
}
