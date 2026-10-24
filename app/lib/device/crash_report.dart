/// Crash reports without a cable (v0.5.2), sent to the developer only when the
/// learner chooses to (after v0.7.6).
///
/// * Android JVM crashes and Onyx-SDK native crashes are written by
///   `ToskApplication.kt` to `last_crash_native.txt` in the app support
///   directory.
/// * Uncaught Dart/Flutter errors ([installCrashLogging]:
///   `FlutterError.onError` and `PlatformDispatcher.onError`, the first few
///   per run) are kept in `last_crash_dart.txt`, or on the web in the
///   browser's localStorage (`crash_log.dart`).
///
/// On the next start [takeCrashReport] returns (and deletes) them, and
/// [CrashReportGate] shows them once before the app: selectable, with Copy,
/// **Send to the developer** when signed in (queued like a flag:
/// `report_outbox.dart`, Firestore `crashes/`), an email draft when the build
/// has `TOSK_FEEDBACK_EMAIL`, and the GitHub issues link.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_version.dart';
import '../feedback/reports.dart';
import '../providers.dart' show clockProvider;
import '../sync/sync_providers.dart';
import '../ui/common/external_link.dart';
import '../ui/common/links.dart';
import 'crash_log.dart';
import 'device_providers.dart';

final _store = CrashLogStore();

/// Records uncaught Dart and Flutter framework errors (the first few per run).
Future<void> installCrashLogging() async {
  if (!await _store.init()) return;
  installCrashHooks(_store.writeDart);
}

/// Chains [FlutterError.onError] and [PlatformDispatcher.onError] so the
/// first [max] uncaught errors of this run go to [write] (the first replaces
/// what is stored, the next ones are appended). Silent framework reports
/// (e.g. a failed image download the framework already handles) are skipped.
@visibleForTesting
void installCrashHooks(
  void Function(String text, {required bool append}) write, {
  int max = 3,
  DateTime Function()? clock,
}) {
  var written = 0;
  final now = clock ?? DateTime.now;
  void record(String text) {
    if (written >= max) return;
    written++;
    try {
      write(
        '${now().toUtc().toIso8601String()} · tosk $kAppVersion · ${reportPlatform()}\n$text\n\n',
        append: written > 1,
      );
    } catch (_) {}
  }

  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    if (!details.silent) record('Flutter error: ${details.exceptionAsString()}\n${details.stack ?? ''}');
    previousFlutter?.call(details);
  };
  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    record('Uncaught error: $error\n$stack');
    return previousPlatform?.call(error, stack) ?? false;
  };
}

/// The details the previous run left.
@immutable
class CrashReport {
  const CrashReport(this.text, {this.native = false});
  final String text;

  /// The app was killed (a JVM or native crash), not just an error caught.
  final bool native;
}

/// The report left by the previous run, or null; the stored copy is deleted.
Future<CrashReport?> takeCrashReport() async {
  final parts = await _store.take();
  final texts = [?parts.native, ?parts.dart];
  if (texts.isEmpty) return null;
  return CrashReport(texts.join('\n\n---\n\n'), native: parts.native != null);
}

/// Shows [report] once before [child]: what happened, the details (with
/// Copy), "Send to the developer" when signed in, otherwise an email draft
/// (when the build has an address) and the issues link; Continue.
class CrashReportGate extends ConsumerStatefulWidget {
  const CrashReportGate({super.key, required this.report, required this.child, this.native = true});

  final String report;

  /// The app stopped (else: an error it survived, e.g. on the web).
  final bool native;
  final Widget child;

  @override
  ConsumerState<CrashReportGate> createState() => _CrashReportGateState();
}

enum _SendState { idle, sending, sent, failed }

class _CrashReportGateState extends ConsumerState<CrashReportGate> {
  bool _dismissed = false;
  bool _copied = false;
  _SendState _send = _SendState.idle;
  String? _linkError;

  Future<void> _sendReport() async {
    setState(() => _send = _SendState.sending);
    var device = '';
    try {
      final d = await ref.read(deviceInfoProvider.future).timeout(const Duration(seconds: 2));
      device = [d.manufacturer, d.model].where((s) => s.isNotEmpty).join(' ');
    } on Object {
      // Unknown device: the report still goes.
    }
    final ok = await queueReport(
      ref,
      crashReport(report: widget.report, now: ref.read(clockProvider)(), device: device),
    );
    if (mounted) setState(() => _send = ok ? _SendState.sent : _SendState.failed);
  }

  Future<void> _open(Uri url) async {
    final ok = await ref.read(externalLinkOpenerProvider)(url);
    if (mounted) setState(() => _linkError = ok ? null : "Couldn't open it. Copy the details instead.");
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return widget.child;
    final canSend = ref.watch(canSendReportsProvider);
    final canSignIn = ref.watch(canSignInProvider);
    final mail = feedbackMailto(
      kFeedbackEmail,
      subject: 'tosk crash report ($kAppVersion)',
      body: widget.report.length > 6000 ? '${widget.report.substring(0, 6000)}\n…' : widget.report,
    );
    final explanation = canSend
        ? 'You can send these details to the developer. They contain the error, the app version and '
              'your device model, nothing else.'
        : canSignIn
        ? 'Please copy these details and send them to the developer. If you sign in '
              '(Settings → Account & sync), the app can send reports like this for you.'
        : 'Please copy these details and send them to the developer.';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blueGrey, useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.native ? 'The app stopped unexpectedly last time' : 'Something went wrong last time',
                      key: const ValueKey('crash-title'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(explanation, key: const ValueKey('crash-explanation')),
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
                    if (canSend) ...[
                      FilledButton.icon(
                        key: const ValueKey('crash-send'),
                        onPressed: _send == _SendState.idle || _send == _SendState.failed ? _sendReport : null,
                        icon: Icon(_send == _SendState.sent ? Icons.check : Icons.send_outlined),
                        label: Text(switch (_send) {
                          _SendState.idle => 'Send to the developer',
                          _SendState.sending => 'Sending…',
                          _SendState.sent => 'Sent. Thank you!',
                          _SendState.failed => "Couldn't send it. Try again",
                        }),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('crash-copy'),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: widget.report));
                            if (mounted) setState(() => _copied = true);
                          },
                          icon: Icon(_copied ? Icons.check : Icons.copy),
                          label: Text(_copied ? 'Copied' : 'Copy details'),
                        ),
                        if (mail != null && !canSend)
                          OutlinedButton.icon(
                            key: const ValueKey('crash-email'),
                            onPressed: () => unawaited(_open(mail)),
                            icon: const Icon(Icons.mail_outline),
                            label: const Text('Email'),
                          ),
                        if (!canSend)
                          OutlinedButton.icon(
                            key: const ValueKey('crash-issues'),
                            onPressed: () => unawaited(_open(Uri.parse(kIssuesUrl))),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Report on GitHub'),
                          ),
                      ],
                    ),
                    if (_linkError case final e?) ...[const SizedBox(height: 8), Text(e)],
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      key: const ValueKey('crash-continue'),
                      onPressed: () => setState(() => _dismissed = true),
                      child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Continue')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
