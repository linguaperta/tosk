// Round-trips a secret through the real platform secure storage, in the built
// app. On Windows this exercises the local pure-Dart plugin
// (packages/secure_storage_windows_dart) against the Credential Manager:
//
//   flutter test integration_test/secure_storage_test.dart -d windows
import 'dart:io';

import 'package:tosk/ai/secret_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final key =
      'tosk.integration_test.${DateTime.now().microsecondsSinceEpoch}';
  const store = SecureSecretStore();

  tearDown(() => store.delete(key));

  testWidgets('SecureSecretStore writes, reads and deletes a key', (
    tester,
  ) async {
    expect(await store.read(key), isNull);

    await store.write(key, 'sk-test-ünï €');
    expect(await store.read(key), 'sk-test-ünï €');

    await store.write(key, 'replaced');
    expect(await store.read(key), 'replaced');

    const storage = FlutterSecureStorage();
    expect(await storage.containsKey(key: key), isTrue);
    expect((await storage.readAll())[key], 'replaced');

    await store.delete(key);
    expect(await store.read(key), isNull);
    expect(await storage.containsKey(key: key), isFalse);
    await store.delete(key); // deleting a missing key is fine
  });

  testWidgets('on Windows the key is a Credential Manager entry', (
    tester,
  ) async {
    final target = 'tosk/flutter_secure_storage/$key';
    Future<String> list() async =>
        (await Process.run('cmdkey', ['/list:$target'])).stdout as String;

    await store.write(key, 'x');
    // cmdkey echoes the filter in its header, so match the entry line.
    final entry = 'Target: $target';
    final listed = await list();
    expect(listed, contains(entry), reason: listed);
    expect(listed, contains('Generic'), reason: listed);
    await store.delete(key);
    expect(await list(), isNot(contains(entry)));
  }, skip: !Platform.isWindows);
}
