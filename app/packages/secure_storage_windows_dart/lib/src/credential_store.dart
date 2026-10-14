import 'dart:convert';

import 'package:flutter/services.dart';

/// The raw credential operations, one generic credential per target name.
/// [WinCredentialStore] talks to the Windows Credential Manager; tests use an
/// in-memory fake.
abstract interface class CredentialStore {
  /// The blob stored under [target], or null when there is none.
  Uint8List? read(String target);

  /// Creates or replaces the credential [target].
  void write(String target, Uint8List blob, {required String userName});

  /// Removes [target]; a missing credential is not an error.
  void delete(String target);

  /// Target names starting with [prefix].
  List<String> targetsWithPrefix(String prefix);
}

/// Largest blob a generic credential can hold (CRED_MAX_CREDENTIAL_BLOB_SIZE).
const int maxCredentialBlobBytes = 5 * 512;

/// Longest generic target name (CRED_MAX_GENERIC_TARGET_NAME_LENGTH).
const int maxTargetNameLength = 32767;

/// Maps flutter_secure_storage keys to Credential Manager target names and
/// values to credential blobs.
///
/// Every key of one app lives under `<app>/flutter_secure_storage/`, so apps do
/// not see each other's keys and readAll/deleteAll only touch this app's.
class CredentialNaming {
  CredentialNaming(this.appName)
    : assert(appName.isNotEmpty),
      assert(!appName.contains('*'), 'target filters use * as a wildcard');

  /// Derives the app name from the running executable, e.g.
  /// `C:\Apps\tosk\tosk.exe` -> `tosk`.
  factory CredentialNaming.forExecutable(String executablePath) =>
      CredentialNaming(appNameFromExecutable(executablePath));

  final String appName;

  String get prefix => '$appName/flutter_secure_storage/';

  String targetFor(String key) {
    final target = '$prefix$key';
    if (target.length > maxTargetNameLength) {
      throw PlatformException(
        code: 'key_too_long',
        message: 'Key is too long for a Credential Manager target name.',
      );
    }
    return target;
  }

  /// The key for [target], or null when [target] is not one of this app's.
  /// Target names are case-insensitive in the Credential Manager, so the
  /// prefix is too.
  String? keyFor(String target) =>
      target.length >= prefix.length &&
              target.substring(0, prefix.length).toLowerCase() ==
                  prefix.toLowerCase()
          ? target.substring(prefix.length)
          : null;

  /// Values are stored as UTF-8.
  static Uint8List encode(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length > maxCredentialBlobBytes) {
      throw PlatformException(
        code: 'value_too_large',
        message:
            'Value is ${bytes.length} bytes as UTF-8; the Windows Credential '
            'Manager holds at most $maxCredentialBlobBytes.',
      );
    }
    return bytes;
  }

  static String decode(Uint8List blob) => utf8.decode(blob);
}

/// The file name of [executablePath] without its extension; `app` if empty.
String appNameFromExecutable(String executablePath) {
  final slash = executablePath.lastIndexOf(RegExp(r'[\\/]'));
  var name = executablePath.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  name = name.replaceAll('*', '_');
  return name.isEmpty ? 'app' : name;
}
