import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import 'credential_store.dart';

/// [CredentialStore] on the Windows Credential Manager (Advapi32
/// CredReadW/CredWriteW/CredDeleteW/CredEnumerateW), generic credentials,
/// persisted per user on this machine (CRED_PERSIST_LOCAL_MACHINE).
class WinCredentialStore implements CredentialStore {
  @override
  Uint8List? read(String target) => using((arena) {
    final ppCredential = arena<Pointer<CREDENTIAL>>();
    final result = CredRead(
      PCWSTR(target.toNativeUtf16(allocator: arena)),
      CRED_TYPE_GENERIC,
      ppCredential,
    );
    if (!result.value) {
      if (result.error == ERROR_NOT_FOUND) return null;
      throw _failure('CredReadW', result.error);
    }
    final credential = ppCredential.value;
    try {
      final size = credential.ref.CredentialBlobSize;
      if (size == 0) return Uint8List(0);
      return Uint8List.fromList(
        credential.ref.CredentialBlob.asTypedList(size),
      );
    } finally {
      CredFree(credential);
    }
  });

  @override
  void write(String target, Uint8List blob, {required String userName}) =>
      using((arena) {
        final pBlob = arena<Uint8>(blob.isEmpty ? 1 : blob.length);
        pBlob.asTypedList(blob.length).setAll(0, blob);
        final credential = arena<CREDENTIAL>();
        credential.ref
          ..Type = CRED_TYPE_GENERIC
          ..TargetName = PWSTR(target.toNativeUtf16(allocator: arena))
          ..UserName = PWSTR(userName.toNativeUtf16(allocator: arena))
          ..CredentialBlobSize = blob.length
          ..CredentialBlob = pBlob
          ..Persist = CRED_PERSIST_LOCAL_MACHINE;
        final result = CredWrite(credential, 0);
        // Wipe the plaintext copy before the arena frees it.
        pBlob.asTypedList(blob.length).fillRange(0, blob.length, 0);
        if (!result.value) throw _failure('CredWriteW', result.error);
      });

  @override
  void delete(String target) => using((arena) {
    final result = CredDelete(
      PCWSTR(target.toNativeUtf16(allocator: arena)),
      CRED_TYPE_GENERIC,
    );
    if (!result.value && result.error != ERROR_NOT_FOUND) {
      throw _failure('CredDeleteW', result.error);
    }
  });

  @override
  List<String> targetsWithPrefix(String prefix) => using((arena) {
    final pCount = arena<Uint32>();
    final ppCredentials = arena<Pointer<Pointer<CREDENTIAL>>>();
    GetLastError(); // Resolve it first so the call below is not clobbered.
    final ok = _credEnumerate(
      '$prefix*'.toNativeUtf16(allocator: arena),
      0,
      pCount,
      ppCredentials,
    );
    if (ok == FALSE) {
      final error = GetLastError();
      if (error == ERROR_NOT_FOUND) return const <String>[];
      throw _failure('CredEnumerateW', error);
    }
    final credentials = ppCredentials.value;
    try {
      return [
        for (var i = 0; i < pCount.value; i++)
          if (credentials[i].ref.Type == CRED_TYPE_GENERIC)
            credentials[i].ref.TargetName.toDartString(),
      ];
    } finally {
      CredFree(credentials);
    }
  });

  static PlatformException _failure(String function, int error) =>
      PlatformException(
        code: 'credential_manager_error',
        message: '$function failed with Win32 error $error.',
      );
}

// Not bound by package:win32 6.x.
final _credEnumerate = DynamicLibrary.open('advapi32.dll').lookupFunction<
  Int32 Function(
    Pointer<Utf16> filter,
    Uint32 flags,
    Pointer<Uint32> count,
    Pointer<Pointer<Pointer<CREDENTIAL>>> credentials,
  ),
  int Function(
    Pointer<Utf16> filter,
    int flags,
    Pointer<Uint32> count,
    Pointer<Pointer<Pointer<CREDENTIAL>>> credentials,
  )
>('CredEnumerateW');
