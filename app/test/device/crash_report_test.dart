import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/device/crash_report.dart';
import 'package:tosk/device/device_info.dart';
import 'package:tosk/device/device_providers.dart';
import 'package:tosk/sync/sync_providers.dart';
import 'package:tosk/sync/sync_service.dart';
import 'package:tosk/ui/common/external_link.dart';
import 'package:tosk/ui/common/links.dart';

import '../sync/report_outbox_test.dart' show reportingService;

const _report = 'tosk 0.5.2 · ONYX MaxLumi\n\nUncaught exception: boom';

Widget gate({SyncService? service, List<Uri>? opened, bool native = true}) => ProviderScope(
  overrides: [
    if (service != null) syncServiceProvider.overrideWithValue(service),
    deviceInfoProvider.overrideWith((ref) async => const DeviceInfo(manufacturer: 'ONYX', model: 'MaxLumi')),
    if (opened != null) externalLinkOpenerProvider.overrideWithValue((u) async => (opened..add(u)).isNotEmpty),
  ],
  child: CrashReportGate(
    report: _report,
    native: native,
    child: const MaterialApp(home: Text('the app', key: ValueKey('app'))),
  ),
);

void main() {
  testWidgets('crash gate shows the report, copies it and continues to the app', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    final opened = <Uri>[];
    await tester.pumpWidget(gate(opened: opened));
    expect(find.byKey(const ValueKey('crash-title')), findsOneWidget);
    expect(find.text('The app stopped unexpectedly last time'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byKey(const ValueKey('crash-send')), findsNothing, reason: 'no sync in this build');
    await tester.tap(find.byKey(const ValueKey('crash-copy')));
    await tester.pump();
    expect(copied, contains('boom'));
    expect(find.text('Copied'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('crash-issues')));
    await tester.pump();
    expect(opened.single.toString(), kIssuesUrl);
    await tester.tap(find.byKey(const ValueKey('crash-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app')), findsOneWidget);
  });

  testWidgets('an error the app survived (e.g. on the web) is "something went wrong"', (tester) async {
    await tester.pumpWidget(gate(native: false));
    expect(find.text('Something went wrong last time'), findsOneWidget);
  });

  testWidgets('signed in: "Send to the developer" queues the report with the device model', (tester) async {
    late SyncService service;
    late Map<String, Map<String, Object>> received;
    await tester.runAsync(() async {
      final (s, server, _) = await reportingService();
      service = s;
      received = server.reports;
    });
    addTearDown(service.dispose);
    await tester.pumpWidget(gate(service: service));
    expect(find.textContaining('the app version and your device model, nothing else'), findsOneWidget);
    expect(find.byKey(const ValueKey('crash-issues')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('crash-send')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Sent. Thank you!'), findsOneWidget);
    await tester.pump(SyncService.localChangeDelay + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    final crash = received.entries.single;
    expect(crash.key, startsWith('crashes/'));
    expect(crash.value['report'], _report);
    expect(crash.value['device'], 'ONYX MaxLumi');
    expect(crash.value['uid'], 'uid1');
  });

  testWidgets('signed out with sync: a hint to sign in, no send button', (tester) async {
    late SyncService service;
    await tester.runAsync(() async {
      final (s, _, _) = await reportingService(signIn: false);
      service = s;
    });
    addTearDown(service.dispose);
    await tester.pumpWidget(gate(service: service));
    expect(find.byKey(const ValueKey('crash-send')), findsNothing);
    expect(find.textContaining('If you sign in'), findsOneWidget);
  });

  test('the error hooks keep the first few unsilenced errors', () {
    final saved = <(String, bool)>[];
    final previousFlutter = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    final forwarded = <Object>[];
    FlutterError.onError = (d) => forwarded.add(d.exception);
    try {
      installCrashHooks((text, {required append}) => saved.add((text, append)), max: 2);
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('quiet'), silent: true));
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('first')));
      PlatformDispatcher.instance.onError!(StateError('second'), StackTrace.empty);
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('third')));
    } finally {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
    }
    expect(saved.length, 2);
    expect(saved[0].$1, contains('Flutter error: Bad state: first'));
    expect(saved[0].$1, contains('· tosk '));
    expect(saved[0].$2, isFalse);
    expect(saved[1].$1, contains('Uncaught error: Bad state: second'));
    expect(saved[1].$2, isTrue);
    expect(forwarded.length, 3, reason: 'the previous handler still sees everything');
  });
}
