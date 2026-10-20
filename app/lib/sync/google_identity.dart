/// Google ID tokens for Firebase sign-in, behind an interface so the sync UI
/// and controller can be tested without Google.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_button.dart';
import 'sync_config.dart';

abstract interface class GoogleIdentity {
  /// True where the app shows its own button and calls [signIn]; false on
  /// the web, where [button] (Google's) must be shown instead.
  bool get canCallSignIn;

  /// Interactive sign-in; returns a Google ID token, or null if cancelled.
  Future<String?> signIn();

  /// Google's own button (web).
  Widget button();

  /// ID tokens from sign-ins through [button] (web).
  Stream<String> get idTokens;

  Future<void> signOut();
}

/// google_sign_in (v7): Credential Manager on Android, the Google SDK on iOS,
/// Google Identity Services on the web.
class PluginGoogleIdentity implements GoogleIdentity {
  PluginGoogleIdentity(this.config);

  final FirebaseSyncConfig config;
  Future<void>? _init;
  final _tokens = StreamController<String>.broadcast();

  Future<void> _ready() => _init ??= () async {
        final gs = GoogleSignIn.instance;
        if (kIsWeb) {
          await gs.initialize(clientId: config.webClientId);
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          await gs.initialize(clientId: config.iosClientId, serverClientId: config.webClientId);
        } else {
          // Android: the ID token is issued for the web client (the "server").
          await gs.initialize(serverClientId: config.webClientId);
        }
        gs.authenticationEvents.listen((e) {
          if (e case GoogleSignInAuthenticationEventSignIn(:final user)) {
            final t = user.authentication.idToken;
            if (t != null) _tokens.add(t);
          }
        }, onError: (Object _) {});
      }();

  @override
  bool get canCallSignIn => !kIsWeb;

  @override
  Future<String?> signIn() async {
    await _ready();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Widget button() => FutureBuilder<void>(
        future: _ready(),
        builder: (context, snap) =>
            snap.connectionState == ConnectionState.done ? renderGoogleButton() : const SizedBox(height: 40),
      );

  @override
  Stream<String> get idTokens {
    unawaited(_ready());
    return _tokens.stream;
  }

  @override
  Future<void> signOut() async {
    if (_init == null) return;
    await _ready();
    await GoogleSignIn.instance.signOut();
  }
}
