import 'package:tosk/device/crash_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('crash gate shows the report, copies it and continues to the app', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.pumpWidget(const CrashReportGate(
      report: 'tosk 0.5.2 · ONYX MaxLumi\n\nUncaught exception: boom',
      child: MaterialApp(home: Text('the app', key: ValueKey('app'))),
    ));
    expect(find.byKey(const ValueKey('crash-title')), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('crash-copy')));
    await tester.pump();
    expect(copied, contains('boom'));
    expect(find.text('Copied'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('crash-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app')), findsOneWidget);
  });
}
