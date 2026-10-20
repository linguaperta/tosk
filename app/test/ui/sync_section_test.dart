import 'package:tosk/ai/secret_store.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/sync/fake_sync_backend.dart';
import 'package:tosk/sync/firebase_auth.dart';
import 'package:tosk/sync/sync_config.dart';
import 'package:tosk/sync/sync_engine.dart';
import 'package:tosk/sync/sync_providers.dart';
import 'package:tosk/sync/sync_service.dart';
import 'package:tosk/sync/sync_store.dart';
import 'package:tosk/ui/settings/sync_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/sample_log.dart';
import '../sync/sync_service_test.dart' show FakeIdentity, fakeAuthServer;

Widget host({SyncService? service}) => ProviderScope(
  overrides: [if (service != null) syncServiceProvider.overrideWithValue(service)],
  child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SyncSection()))),
);

void main() {
  testWidgets('no configuration: no account UI at all', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Account & sync'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  test('sync is offered only with a complete configuration on a platform that can sign in', () {
    const none = FirebaseSyncConfig.fromEnvironment(); // the test build has no defines
    expect(none.isComplete, isFalse);
    expect(syncSupported(none, platform: TargetPlatform.android, web: false), isFalse);
    const full = FirebaseSyncConfig(projectId: 'p', apiKey: 'k', webClientId: 'w');
    expect(syncSupported(full, platform: TargetPlatform.android, web: false), isTrue);
    expect(syncSupported(full, web: true), isTrue);
    expect(syncSupported(full, platform: TargetPlatform.windows, web: false), isFalse);
    expect(syncSupported(full, platform: TargetPlatform.iOS, web: false), isFalse); // needs the iOS client id
    const ios = FirebaseSyncConfig(projectId: 'p', apiKey: 'k', webClientId: 'w', iosClientId: 'i');
    expect(syncSupported(ios, platform: TargetPlatform.iOS, web: false), isTrue);
  });

  testWidgets('sign in, sync, delete the cloud data', (tester) async {
    final server = FakeSyncServer(clock: () => DateTime.utc(2026, 10, 3));
    final progress = InMemoryProgressStore();
    late SyncService service;
    await tester.runAsync(() async {
      await progress.importEvents(sampleLog(count: 12));
      service = SyncService(
        engine: SyncEngine(
          store: InMemorySyncStore(),
          progress: progress,
          importer: progress,
          log: progress,
          backend: const NullSyncBackend(),
          syncedSettings: const {},
          clock: server.clock,
        ),
        auth: FirebaseAuthClient(apiKey: 'k', client: fakeAuthServer()),
        secrets: MemorySecretStore(),
        identity: FakeIdentity('google-token'),
        backendFor: (t) => FakeSyncBackend(server, account: t.uid),
      );
      await service.start(lifecycle: false);
    });
    addTearDown(service.dispose);
    await tester.pumpWidget(host(service: service));
    expect(find.text('Account & sync'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sync-sign-in')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.textContaining('Synced 2026-'), findsOneWidget);
    expect(server.eventIds('uid1').length, 12);

    await tester.tap(find.byKey(const ValueKey('sync-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-delete-confirm')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sync-delete-yes')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(server.eventIds('uid1'), isEmpty);
    expect(find.byKey(const ValueKey('sync-sign-in')), findsOneWidget);
    expect((await progress.log()).length, 12);
  });
}
