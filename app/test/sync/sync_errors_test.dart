// Identity Toolkit and Firestore errors → the sentences the user reads.
import 'dart:async';

import 'package:tosk/core/core.dart';
import 'package:tosk/sync/fake_sync_backend.dart';
import 'package:tosk/sync/firebase_auth.dart';
import 'package:tosk/sync/firestore_backend.dart';
import 'package:tosk/sync/sync_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('Identity Toolkit codes map to a few plain sentences', () {
    String m(String code, [int? status = 400]) => friendlySyncError(FirebaseAuthException(code, status), signIn: true);
    expect(m('DUPLICATE_RAW_ID'), SyncMessages.hiccup);
    expect(m('FEDERATED_USER_ID_ALREADY_LINKED'), SyncMessages.hiccup);
    expect(m('INVALID_IDP_RESPONSE : Invalid Idp Response: the Google id_token is not allowed'), SyncMessages.expired);
    expect(m('TOKEN_EXPIRED'), SyncMessages.expired);
    expect(m('INVALID_REFRESH_TOKEN'), SyncMessages.expired);
    expect(m('USER_DISABLED'), SyncMessages.expired);
    expect(m('CREDENTIAL_TOO_OLD_LOGIN_AGAIN'), SyncMessages.expired);
    expect(m('TOO_MANY_ATTEMPTS_TRY_LATER'), SyncMessages.unreachable);
    expect(m('HTTP_503', 503), SyncMessages.unreachable);
    expect(m('API_KEY_INVALID'), SyncMessages.signInFailed);
    expect(friendlySyncError(const FirebaseAuthException('OPERATION_NOT_ALLOWED', 400)), SyncMessages.syncFailed);
  });

  test('Firestore and network errors', () {
    expect(friendlySyncError(const SyncAuthException('Firestore refused access (HTTP 403)')), SyncMessages.expired);
    expect(friendlySyncError(const FirestoreException(503, 'The service is currently unavailable.')), SyncMessages.unreachable);
    expect(friendlySyncError(const FirestoreException(429, 'Quota exceeded.')), SyncMessages.unreachable);
    expect(friendlySyncError(const FirestoreException(400, 'Invalid value')), SyncMessages.syncFailed);
    expect(friendlySyncError(TimeoutException('slow')), SyncMessages.unreachable);
    expect(friendlySyncError(http.ClientException('Connection closed')), SyncMessages.unreachable);
    expect(friendlySyncError(const FakeOfflineException()), SyncMessages.unreachable);
    expect(friendlySyncError(StateError('boom')), SyncMessages.syncFailed);
    expect(friendlySyncError(StateError('boom'), fallback: 'Please try again.'), 'Please try again.');
  });

  test('no message carries a raw code', () {
    for (final m in [
      SyncMessages.hiccup,
      SyncMessages.retrying,
      SyncMessages.unreachable,
      SyncMessages.expired,
      SyncMessages.signInFailed,
      SyncMessages.syncFailed,
    ]) {
      expect(m, isNot(matches(RegExp('[A-Z]{2,}_[A-Z]'))));
    }
  });

  test('only races and server trouble are retried', () {
    expect(isRetryableSignIn(const FirebaseAuthException('DUPLICATE_RAW_ID', 400)), isTrue);
    expect(isRetryableSignIn(const FirebaseAuthException('HTTP_503', 503)), isTrue);
    expect(isRetryableSignIn(const FirebaseAuthException('INVALID_IDP_RESPONSE', 400)), isFalse);
    expect(isRetryableSignIn(TimeoutException('slow')), isFalse);
  });
}
