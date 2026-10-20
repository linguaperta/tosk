/// Firebase Authentication over its REST API (Identity Toolkit and Secure
/// Token), with Google as the identity provider. Pure Dart (package:http).
///
/// Why REST and not the FlutterFire plugins: the plugins bring the native
/// Firebase SDKs into every build (a large C++ SDK on Windows, Play Services
/// on Android) and need `google-services.json` at build time. Over REST the
/// app builds and runs the same with or without a Firebase project, on every
/// platform; only the Google ID token comes from a plugin (google_sign_in).
///
/// * Sign-in: a Google ID token → `accounts:signInWithIdp` → a Firebase ID
///   token (1 hour) and a refresh token (kept in secure storage).
/// * Refresh: `securetoken.googleapis.com/v1/token`.
/// * Delete: `accounts:delete` (part of "Delete my cloud data").
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../core/core.dart';

/// A signed-in Firebase user. Only [uid], the profile and [refreshToken] are
/// persisted; the ID token lives in memory.
@immutable
class FirebaseSession {
  const FirebaseSession({
    required this.uid,
    required this.refreshToken,
    this.email,
    this.displayName,
    this.idToken,
    this.expiresAt,
  });

  final String uid;
  final String refreshToken;
  final String? email;
  final String? displayName;
  final String? idToken;
  final DateTime? expiresAt;

  bool fresh(DateTime now) =>
      idToken != null && expiresAt != null && now.isBefore(expiresAt!.subtract(const Duration(minutes: 2)));

  FirebaseSession withToken(String idToken, String refreshToken, DateTime expiresAt) => FirebaseSession(
        uid: uid,
        refreshToken: refreshToken,
        email: email,
        displayName: displayName,
        idToken: idToken,
        expiresAt: expiresAt,
      );

  String encode() => jsonEncode({
        'uid': uid,
        'refresh': refreshToken,
        if (email != null) 'email': email,
        if (displayName != null) 'name': displayName,
      });

  static FirebaseSession? decode(String? s) {
    if (s == null) return null;
    try {
      final j = (jsonDecode(s) as Map).cast<String, Object?>();
      return FirebaseSession(
        uid: j['uid']! as String,
        refreshToken: j['refresh']! as String,
        email: j['email'] as String?,
        displayName: j['name'] as String?,
      );
    } on Object {
      return null;
    }
  }
}

class FirebaseAuthException implements Exception {
  const FirebaseAuthException(this.code, [this.status]);
  final String code;
  final int? status;

  /// The refresh token no longer works: the user has to sign in again.
  bool get signedOut => const {
        'TOKEN_EXPIRED',
        'USER_DISABLED',
        'USER_NOT_FOUND',
        'INVALID_REFRESH_TOKEN',
        'INVALID_GRANT_TYPE',
        'MISSING_REFRESH_TOKEN',
      }.any(code.startsWith);

  @override
  String toString() => 'FirebaseAuthException($code${status == null ? '' : ', HTTP $status'})';
}

class FirebaseAuthClient {
  FirebaseAuthClient({required this.apiKey, required this.client, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  final String apiKey;
  final http.Client client;
  final DateTime Function() clock;

  static const _identity = 'https://identitytoolkit.googleapis.com/v1';
  static const _secureToken = 'https://securetoken.googleapis.com/v1/token';
  static const _timeout = Duration(seconds: 30);

  Future<Map<String, Object?>> _post(Uri url, {Object? json, Map<String, String>? form}) async {
    final res = await (json != null
            ? client.post(url, headers: {'content-type': 'application/json'}, body: jsonEncode(json))
            : client.post(url, body: form))
        .timeout(_timeout);
    Map<String, Object?> body;
    try {
      body = (jsonDecode(res.body) as Map).cast<String, Object?>();
    } on Object {
      body = const {};
    }
    if (res.statusCode != 200) {
      final err = body['error'];
      final code = err is Map ? (err['message'] as String? ?? 'HTTP_${res.statusCode}') : 'HTTP_${res.statusCode}';
      throw FirebaseAuthException(code, res.statusCode);
    }
    return body;
  }

  DateTime _expiry(Object? seconds) => clock().toUtc().add(Duration(seconds: int.tryParse('$seconds') ?? 3600));

  /// Exchanges a Google ID token for a Firebase session.
  Future<FirebaseSession> signInWithGoogle(String googleIdToken) async {
    final j = await _post(
      Uri.parse('$_identity/accounts:signInWithIdp?key=$apiKey'),
      json: {
        'postBody': 'id_token=${Uri.encodeQueryComponent(googleIdToken)}&providerId=google.com',
        'requestUri': 'http://localhost',
        'returnIdpCredential': true,
        'returnSecureToken': true,
      },
    );
    return FirebaseSession(
      uid: j['localId']! as String,
      refreshToken: j['refreshToken']! as String,
      email: j['email'] as String?,
      displayName: j['displayName'] as String?,
      idToken: j['idToken']! as String,
      expiresAt: _expiry(j['expiresIn']),
    );
  }

  /// A new ID token for [s].
  Future<FirebaseSession> refresh(FirebaseSession s) async {
    final j = await _post(
      Uri.parse('$_secureToken?key=$apiKey'),
      form: {'grant_type': 'refresh_token', 'refresh_token': s.refreshToken},
    );
    return s.withToken(j['id_token']! as String, j['refresh_token'] as String? ?? s.refreshToken, _expiry(j['expires_in']));
  }

  /// Deletes the Firebase user (needs a recent sign-in; may throw
  /// `CREDENTIAL_TOO_OLD_LOGIN_AGAIN`).
  Future<void> deleteAccount(String idToken) async {
    await _post(Uri.parse('$_identity/accounts:delete?key=$apiKey'), json: {'idToken': idToken});
  }
}

/// Hands out valid ID tokens for one session, refreshing when needed, and
/// reports a session that can no longer refresh.
class FirebaseTokens {
  FirebaseTokens(this.auth, this._session, {this.onChanged, this.onSignedOut});

  final FirebaseAuthClient auth;
  FirebaseSession _session;
  final void Function(FirebaseSession s)? onChanged;
  final void Function()? onSignedOut;
  Future<FirebaseSession>? _refreshing;

  FirebaseSession get session => _session;
  String get uid => _session.uid;

  Future<String> idToken({bool forceRefresh = false}) async {
    if (!forceRefresh && _session.fresh(auth.clock())) return _session.idToken!;
    final r = _refreshing ??= auth.refresh(_session);
    try {
      _session = await r;
      onChanged?.call(_session);
      return _session.idToken!;
    } on FirebaseAuthException catch (e) {
      if (e.signedOut) {
        onSignedOut?.call();
        throw const SyncAuthException('Signed out: please sign in again');
      }
      rethrow;
    } finally {
      _refreshing = null;
    }
  }
}
