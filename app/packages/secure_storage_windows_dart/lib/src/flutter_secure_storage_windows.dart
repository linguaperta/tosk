import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'credential_store.dart';
import 'win_credential_store.dart';

/// flutter_secure_storage on Windows: each key is a generic credential in the
/// user's Windows Credential Manager (`<app>/flutter_secure_storage/<key>`,
/// persisted for this user on this machine). The Windows options
/// (`useBackwardCompatibility`) are ignored: there is no older store to
/// migrate from.
class FlutterSecureStorageWindows extends FlutterSecureStoragePlatform {
  FlutterSecureStorageWindows({
    CredentialStore? store,
    CredentialNaming? naming,
  }) : _store = store ?? WinCredentialStore(),
       _naming =
           naming ??
           CredentialNaming.forExecutable(Platform.resolvedExecutable);

  final CredentialStore _store;
  final CredentialNaming _naming;

  /// Registers this implementation (dartPluginClass).
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWindows();
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => _store.write(
    _naming.targetFor(key),
    CredentialNaming.encode(value),
    userName: _naming.appName,
  );

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final blob = _store.read(_naming.targetFor(key));
    return blob == null ? null : CredentialNaming.decode(blob);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => _store.read(_naming.targetFor(key)) != null;

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => _store.delete(_naming.targetFor(key));

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    final result = <String, String>{};
    for (final target in _store.targetsWithPrefix(_naming.prefix)) {
      final key = _naming.keyFor(target);
      final blob = _store.read(target);
      if (key != null && blob != null) {
        result[key] = CredentialNaming.decode(blob);
      }
    }
    return result;
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    for (final target in _store.targetsWithPrefix(_naming.prefix)) {
      if (_naming.keyFor(target) != null) _store.delete(target);
    }
  }
}
