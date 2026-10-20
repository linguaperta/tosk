/// Riverpod wiring for cloud sync. [syncServiceProvider] is null (no sync UI,
/// fully offline) unless `main.dart` found a Firebase configuration.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../ui/settings/learner_settings.dart';
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
