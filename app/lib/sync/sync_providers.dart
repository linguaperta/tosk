/// Riverpod wiring for cloud sync. [syncServiceProvider] is null (no sync UI,
/// fully offline) unless `main.dart` found a Firebase configuration.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../ui/settings/learner_settings.dart';
import 'report_outbox.dart';
import 'sync_service.dart';

/// Set by `main.dart` (see `AppBoot.overrides`); null without sync.
final syncServiceProvider = Provider<SyncService?>((ref) => null);

/// The sync status (null without sync). Watching it also wires the refresh:
/// after a sync brings new answers or settings, everything derived from
/// progress and settings reloads (the app root listens to it).
final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus?>(SyncStatusNotifier.new);

class SyncStatusNotifier extends Notifier<SyncStatus?> {
  @override
  SyncStatus? build() {
    final service = ref.watch(syncServiceProvider);
    if (service == null) return null;
    void listener() => state = service.status;
    service.addListener(listener);
    service.onLocalChange = (r) {
      ref.read(progressRevisionProvider.notifier).bump();
      if (r.settingsApplied.isNotEmpty) {
        ref.invalidate(settingsProvider);
        ref.invalidate(learnerSettingsProvider);
      }
    };
    ref.onDispose(() {
      service.removeListener(listener);
      service.onLocalChange = null;
    });
    return service.status;
  }
}

/// Whether reports (flags, feedback, crash reports) go to the developer
/// automatically: signed in, in a build with sync. Without it they stay on
/// the device (flags export, copy, an email draft).
final canSendReportsProvider = Provider<bool>((ref) {
  final service = ref.watch(syncServiceProvider);
  final signedIn = ref.watch(syncStatusProvider.select((s) => s?.signedIn ?? false));
  return service != null && service.outbox != null && signedIn;
});

/// Whether this build can sign in at all (so "Sign in to send…" makes sense).
final canSignInProvider = Provider<bool>((ref) => ref.watch(syncServiceProvider) != null);

/// Queues [report] for the developer when signed in; false (nothing queued)
/// otherwise or on failure. Never throws.
Future<bool> queueReport(WidgetRef ref, OutgoingReport report) async {
  final service = ref.read(syncServiceProvider);
  if (service == null || !service.canSendReports) return false;
  try {
    return await service.sendReport(report);
  } on Object catch (e) {
    debugPrint('[reports] not queued: $e');
    return false;
  }
}
