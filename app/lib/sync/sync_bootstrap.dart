/// Opens cloud sync for the app, or returns null when this build has no
/// Firebase configuration or this platform can't sign in (then nothing about
/// sync exists at run time: no database, no listeners, no UI).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ai/secret_store.dart';
import '../core/core.dart';
import '../data/progress/progress_connection.dart';
import '../data/progress/progress_repo.dart';
import 'firebase_auth.dart';
import 'google_identity.dart';
import 'sync_config.dart';
import 'sync_engine.dart';
import 'sync_service.dart';
import 'sync_store.dart';

class SyncSetup {
  SyncSetup({required this.engine, required this.service, required this.store, required this.unlisten});

  final SyncEngine engine;
  final SyncService service;
  final SyncStore store;
  final List<void Function()> unlisten;

  Future<void> close() async {
    for (final u in unlisten) {
      u();
    }
    service.dispose();
    await store.close();
  }
}

Future<SyncSetup?> openSync({
  required ProgressRepo progress,
  required Set<String> syncedSettings,
  Set<String> unionKeys = const {},
  FirebaseSyncConfig config = kFirebaseSyncConfig,
  String? directory,
  http.Client? client,
  SecretStore? secrets,
  GoogleIdentity? identity,
  List<SyncExtension> extensions = const [],
}) async {
  if (!syncSupported(config)) return null;
  final db = await openDriftDatabase(SyncDb.new, name: kIsWeb ? 'tosk-sync' : 'sync', directory: directory);
  final store = DriftSyncStore(db);
  final engine = SyncEngine(
    store: store,
    progress: progress,
    importer: progress,
    log: progress,
    backend: const NullSyncBackend(),
    syncedSettings: syncedSettings,
    unionKeys: unionKeys,
    extensions: [...extensions],
  );
  await engine.loadOffsets();
  final http.Client c = client ?? http.Client();
  final service = SyncService.firestore(
    engine: engine,
    projectId: config.projectId,
    auth: FirebaseAuthClient(apiKey: config.apiKey, client: c),
    client: c,
    secrets: secrets ?? const SecureSecretStore(),
    identity: identity ?? PluginGoogleIdentity(config),
  );
  void log(Object e, StackTrace _) => debugPrint('[sync] $e');
  final unlisten = [
    progress.listeners.onRecorded((e) {
      unawaited(engine.noteRecorded(e).catchError(log));
      service.answerRecorded();
    }),
    progress.listeners.onSettingChanged((k, v) => unawaited(engine.noteSettingChanged(k, v).catchError(log))),
  ];
  await service.start();
  return SyncSetup(engine: engine, service: service, store: store, unlisten: unlisten);
}
