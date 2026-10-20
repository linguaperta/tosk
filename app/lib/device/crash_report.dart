/// Crash reports without a cable or a server (v0.5.2).
///
/// * Android JVM crashes and Onyx-SDK native crashes are written by
///   `ToskApplication.kt` to `last_crash_native.txt` in the app support
///   directory.
/// * Uncaught Dart/Flutter errors are written here to `last_crash_dart.txt`.
///
/// On the next start [takeCrashReport] returns (and deletes) both, and
/// [CrashReportGate] shows them once, with a Copy button, before the app.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _nativeFile = 'last_crash_native.txt';
const _dartFile = 'last_crash_dart.txt';

bool get _supported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isMacOS || Platform.isLinux);

Directory? _dir;
int _written = 0;

/// Records uncaught Dart and Flutter framework errors (the first few per run).
Future<void> installCrashLogging() async {
  if (!_supported) return;
  try {
    _dir = await getApplicationSupportDirectory();
  } catch (_) {
    return;
  }
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    _record('Flutter error: ${details.exceptionAsString()}\n${details.stack ?? ''}');
    previousFlutter?.call(details);
  };
  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    _record('Uncaught error: $error\n$stack');
    return previousPlatform?.call(error, stack) ?? false;
  };
}

void _record(String text) {
  final dir = _dir;
  if (dir == null || _written >= 3) return;
  _written++;
  try {
    final f = File('${dir.path}/$_dartFile');
    f.writeAsStringSync(
      '${DateTime.now().toIso8601String()}\n$text\n\n',
      mode: _written == 1 ? FileMode.write : FileMode.append,
    );
  } catch (_) {}
}

/// The report left by the previous run, or null; the files are deleted.
Future<String?> takeCrashReport() async {
  if (!_supported) return null;
  try {
    final dir = _dir ?? await getApplicationSupportDirectory();
    final parts = <String>[];
    for (final name in [_nativeFile, _dartFile]) {
      final f = File('${dir.path}/$name');
      if (f.existsSync()) {
        final text = f.readAsStringSync().trim();
        if (text.isNotEmpty) parts.add(text);
        f.deleteSync();
      }
    }
    return parts.isEmpty ? null : parts.join('\n\n---\n\n');
  } catch (_) {
    return null;
  }
}

/// Shows [report] once (selectable, with Copy) before [child].
class CrashReportGate extends StatefulWidget {
  const CrashReportGate({super.key, required this.report, required this.child});

  final String report;
  final Widget child;

  @override
  State<CrashReportGate> createState() => _CrashReportGateState();
}

class _CrashReportGateState extends State<CrashReportGate> {
  bool _dismissed = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blueGrey, useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'The app stopped unexpectedly last time',
                  key: ValueKey('crash-title'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Please copy these details and send them to the developer.'),
                const SizedBox(height: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Border.all(width: 2)),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: SelectableText(
                        widget.report,
                        key: const ValueKey('crash-text'),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('crash-copy'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: widget.report));
                    if (mounted) setState(() => _copied = true);
                  },
                  icon: Icon(_copied ? Icons.check : Icons.copy),
                  label: Text(_copied ? 'Copied' : 'Copy details'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('crash-continue'),
                  onPressed: () => setState(() => _dismissed = true),
                  child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Continue')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
