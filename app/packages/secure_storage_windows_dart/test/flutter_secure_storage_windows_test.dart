import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_windows/flutter_secure_storage_windows.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCredentialStore implements CredentialStore {
  final Map<String, Uint8List> blobs = {};
  final Map<String, String> userNames = {};

  @override
  Uint8List? read(String target) => blobs[target];

  @override
  void write(String target, Uint8List blob, {required String userName}) {
    blobs[target] = Uint8List.fromList(blob);
    userNames[target] = userName;
  }

  @override
  void delete(String target) => blobs.remove(target);

  // Like CredEnumerateW's "prefix*" filter (case-insensitive on Windows).
  @override
  List<String> targetsWithPrefix(String prefix) => [
    for (final t in blobs.keys)
      if (t.toLowerCase().startsWith(prefix.toLowerCase())) t,
  ];
}

void main() {
  group('appNameFromExecutable', () {
    test('strips the directory and the extension', () {
      expect(
        appNameFromExecutable(r'C:\Apps\tosk\tosk.exe'),
        'tosk',
      );
      expect(appNameFromExecutable('C:/x/y/my.app.exe'), 'my.app');
      expect(appNameFromExecutable('tosk'), 'tosk');
    });

    test('never yields an empty name or a wildcard', () {
      expect(appNameFromExecutable(r'C:\dir\'), 'app');
      expect(appNameFromExecutable(r'C:\dir\.exe'), '.exe');
      expect(appNameFromExecutable(r'C:\dir\a*b.exe'), 'a_b');
    });
  });

  group('CredentialNaming', () {
    final naming = CredentialNaming('tosk');

    test('targets are prefixed per app', () {
      expect(naming.prefix, 'tosk/flutter_secure_storage/');
      expect(
        naming.targetFor('tosk.ai.api_key'),
        'tosk/flutter_secure_storage/tosk.ai.api_key',
      );
      expect(
        CredentialNaming.forExecutable(r'C:\a\tosk.exe').prefix,
        naming.prefix,
      );
    });

    test('keyFor inverts targetFor and rejects foreign targets', () {
      for (final key in ['k', '', 'a/b*c', 'ünï €']) {
        expect(naming.keyFor(naming.targetFor(key)), key);
      }
      expect(naming.keyFor('other/flutter_secure_storage/k'), isNull);
      expect(naming.keyFor('git:https://github.com'), isNull);
      expect(naming.keyFor('tosk'), isNull);
      // Credential Manager target names are case-insensitive.
      expect(naming.keyFor('tosk/Flutter_Secure_Storage/Key'), 'Key');
    });

    test('overlong keys are rejected', () {
      expect(
        () => naming.targetFor('x' * maxTargetNameLength),
        throwsA(isA<PlatformException>()),
      );
    });

    test('values round-trip as UTF-8', () {
      for (final value in ['', 'sk-ant-abc123', 'ünï €😀', 'x' * 2560]) {
        final blob = CredentialNaming.encode(value);
        expect(blob, utf8.encode(value));
        expect(CredentialNaming.decode(blob), value);
      }
    });

    test('values over the blob limit are rejected', () {
      expect(
        () => CredentialNaming.encode('x' * (maxCredentialBlobBytes + 1)),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'value_too_large',
          ),
        ),
      );
      // 1280 two-byte characters fit exactly; one more does not.
      expect(CredentialNaming.encode('é' * 1280), hasLength(2560));
      expect(
        () => CredentialNaming.encode('é' * 1281),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('FlutterSecureStorageWindows', () {
    late FakeCredentialStore store;
    late FlutterSecureStorageWindows storage;
    const options = <String, String>{'useBackwardCompatibility': 'false'};

    setUp(() {
      store = FakeCredentialStore();
      storage = FlutterSecureStorageWindows(
        store: store,
        naming: CredentialNaming('tosk'),
      );
    });

    test('write, read, containsKey, delete', () async {
      expect(await storage.read(key: 'k', options: options), isNull);
      expect(await storage.containsKey(key: 'k', options: options), isFalse);

      await storage.write(key: 'k', value: 'sécret', options: options);
      expect(store.blobs.keys, ['tosk/flutter_secure_storage/k']);
      expect(store.blobs.values.single, utf8.encode('sécret'));
      expect(store.userNames.values.single, 'tosk');
      expect(await storage.read(key: 'k', options: options), 'sécret');
      expect(await storage.containsKey(key: 'k', options: options), isTrue);

      await storage.write(key: 'k', value: 'new', options: options);
      expect(await storage.read(key: 'k', options: options), 'new');

      await storage.delete(key: 'k', options: options);
      expect(await storage.read(key: 'k', options: options), isNull);
      await storage.delete(key: 'k', options: options); // missing: no error
    });

    test('empty values are kept', () async {
      await storage.write(key: 'k', value: '', options: options);
      expect(await storage.read(key: 'k', options: options), '');
    });

    test('readAll and deleteAll only touch this app', () async {
      store.write(
        'other/flutter_secure_storage/k',
        utf8.encode('x'),
        userName: 'other',
      );
      await storage.write(key: 'a', value: '1', options: options);
      await storage.write(key: 'b', value: '2', options: options);

      expect(await storage.readAll(options: options), {'a': '1', 'b': '2'});

      await storage.deleteAll(options: options);
      expect(await storage.readAll(options: options), isEmpty);
      expect(store.blobs.keys, ['other/flutter_secure_storage/k']);
    });
  });
}
