/// Where the AI API key is kept: the platform's secure storage (Keychain,
/// Android Keystore-backed storage, Windows Credential Manager, libsecret) via
/// flutter_secure_storage. On the web that is the browser's storage (encrypted
/// with a key that also lives in the browser), which the settings screen says.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretStore implements SecretStore {
  const SecureSecretStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In memory (tests, and a fallback when secure storage is unavailable).
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? initial]) : _values = {...?initial};
  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
