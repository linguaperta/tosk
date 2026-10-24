/// What the user reads when sign-in or sync fails. Identity Toolkit and
/// Firestore report terse codes (`DUPLICATE_RAW_ID`, `INVALID_IDP_RESPONSE`,
/// HTTP 503…); those go to the log, and the Settings screen shows one of a
/// few plain sentences instead.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../core/core.dart';
import 'firebase_auth.dart';
import 'firestore_backend.dart';

abstract final class SyncMessages {
  /// Shown (not as an error) while a failed sign-in is retried.
  static const retrying = 'Sign-in hiccup, trying again…';
  static const hiccup = 'Sign-in hiccup. Please try again.';
  static const unreachable = "Couldn't reach the server. Please try again in a moment.";
  static const expired = 'Sign-in expired, please sign in again.';
  static const signInFailed = "Sign-in didn't work. Please try again.";
  static const syncFailed = "Sync didn't work this time. Your answers are kept and will sync later.";
  static const accountKept =
      'Your answers, settings and reports were deleted from the cloud, but your sign-in account could not be '
      'removed: Google needs a fresh sign-in for that. To finish, sign in again and choose '
      '"Delete my cloud data" once more.';
}

/// Identity Toolkit codes that mean "a sign-in for this Google account raced
/// another one" (two `signInWithIdp` calls creating the same user at once):
/// the account exists by now, so the same request succeeds when retried.
const _raceCodes = {'DUPLICATE_RAW_ID', 'DUPLICATE_LOCAL_ID', 'FEDERATED_USER_ID_ALREADY_LINKED'};

/// Codes after which the user has to sign in again (besides
/// [FirebaseAuthException.signedOut]).
const _expiredCodes = {
  'INVALID_IDP_RESPONSE',
  'INVALID_ID_TOKEN',
  'CREDENTIAL_TOO_OLD_LOGIN_AGAIN',
  'TOKEN_EXPIRED',
};

const _busyCodes = {'TOO_MANY_ATTEMPTS_TRY_LATER', 'QUOTA_EXCEEDED', 'UNAVAILABLE', 'INTERNAL_ERROR'};

bool _codeIn(String code, Set<String> set) => set.any(code.startsWith);

/// True for a `signInWithIdp` failure that one retry after a short pause
/// fixes: the [_raceCodes] and the server being briefly unavailable.
bool isRetryableSignIn(Object e) =>
    e is FirebaseAuthException && (_codeIn(e.code, _raceCodes) || (e.status ?? 0) >= 500);

/// No connection (or it timed out): answers simply wait locally.
bool looksOffline(Object e) {
  final s = e.toString();
  return e is TimeoutException ||
      e is http.ClientException ||
      s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('XMLHttpRequest error') ||
      s.contains('No network');
}

/// The sentence to show for [e]; [signIn] picks the generic fallback, which
/// [fallback] replaces.
String friendlySyncError(Object e, {bool signIn = false, String? fallback}) {
  fallback ??= signIn ? SyncMessages.signInFailed : SyncMessages.syncFailed;
  if (looksOffline(e)) return SyncMessages.unreachable;
  switch (e) {
    case FirebaseAuthException(:final code, :final status):
      if (_codeIn(code, _raceCodes)) return SyncMessages.hiccup;
      if (e.signedOut || _codeIn(code, _expiredCodes)) return SyncMessages.expired;
      if (_codeIn(code, _busyCodes) || (status ?? 0) >= 500 || status == 429) return SyncMessages.unreachable;
      return fallback;
    case SyncAuthException():
      return SyncMessages.expired;
    case FirestoreException(:final status):
      if (status >= 500 || status == 429 || status == 408) return SyncMessages.unreachable;
      return fallback;
    default:
      return fallback;
  }
}
