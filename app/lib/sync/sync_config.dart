/// Firebase sync configuration (v0.7). Without it the app has no account or
/// sync UI and stays fully offline, exactly as before.
///
/// The values come from compile-time defines, so nothing about the Firebase
/// project is committed. Build with
///
/// ```
/// flutter build apk --release --dart-define-from-file=firebase-config.json
/// ```
///
/// where `app/firebase-config.json` (git-ignored; template:
/// `app/firebase-config.example.json`) holds:
///
/// ```json
/// {
///   "TOSK_FIREBASE_PROJECT_ID": "tosk-12345",
///   "TOSK_FIREBASE_API_KEY": "AIza...",
///   "TOSK_GOOGLE_WEB_CLIENT_ID": "1234-abc.apps.googleusercontent.com",
///   "TOSK_GOOGLE_IOS_CLIENT_ID": ""
/// }
/// ```
///
/// See docs/firebase-setup.md for where each value comes from.
library;

import 'package:flutter/foundation.dart';

@immutable
class FirebaseSyncConfig {
  const FirebaseSyncConfig({
    required this.projectId,
    required this.apiKey,
    required this.webClientId,
    this.iosClientId = '',
  });

  /// From `--dart-define`s (empty strings when absent).
  const FirebaseSyncConfig.fromEnvironment()
      : projectId = const String.fromEnvironment('TOSK_FIREBASE_PROJECT_ID'),
        apiKey = const String.fromEnvironment('TOSK_FIREBASE_API_KEY'),
        webClientId = const String.fromEnvironment('TOSK_GOOGLE_WEB_CLIENT_ID'),
        iosClientId = const String.fromEnvironment('TOSK_GOOGLE_IOS_CLIENT_ID');

  /// Firebase project id (Firestore and Auth live there).
  final String projectId;

  /// The project's Web API key (Firebase console → Project settings). Not a
  /// secret: it only identifies the project; Firestore security rules decide
  /// who may read what.
  final String apiKey;

  /// OAuth client id of type "Web application" (the one Firebase creates when
  /// Google sign-in is enabled). Google ID tokens are issued for it (Android
  /// passes it as the server client id; the web uses it directly).
  final String webClientId;

  /// OAuth client id of the iOS app (optional; without it iOS has no sync).
  final String iosClientId;

  /// Project id, API key and web client id are all set.
  bool get isComplete => projectId.isNotEmpty && apiKey.isNotEmpty && webClientId.isNotEmpty;
}

/// The build's configuration.
const kFirebaseSyncConfig = FirebaseSyncConfig.fromEnvironment();

/// Whether Google sign-in (and so sync) can work on this platform with
/// [config]: the web, Android, and iOS when its client id is set. Windows,
/// Linux and macOS have no sign-in yet (google_sign_in has no desktop part),
/// so they simply show no sync UI.
bool syncSupported(FirebaseSyncConfig config, {TargetPlatform? platform, bool? web}) {
  if (!config.isComplete) return false;
  if (web ?? kIsWeb) return true;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => true,
    TargetPlatform.iOS => config.iosClientId.isNotEmpty,
    _ => false,
  };
}
