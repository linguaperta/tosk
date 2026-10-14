/// Pure-Dart Windows implementation of flutter_secure_storage: secrets live in
/// the Windows Credential Manager, reached through FFI. No C++ plugin, so the
/// Windows build does not need ATL.
library;

export 'src/credential_store.dart';
export 'src/flutter_secure_storage_windows.dart';
