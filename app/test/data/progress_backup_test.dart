// Progress backup (Settings → Backup): export to one JSON-lines file and a
// merging import, round-tripped through on-disk progress databases.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/data/sync/progress_backup.dart';
import 'package:tosk/data/sync/review_log_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/ui/settings/learner_settings.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/settings/synced_settings.dart';

import '../fixtures/sample_log.dart';

final _t = DateTime.utc(2026, 10, 14, 9);

MistakeRecord _mistake(ReviewEvent e) => MistakeRecord(
  id: e.id,
  facetId: e.facetId,
  at: e.at,
  exerciseType: e.exerciseType,
  prompt: 'Fill the gap: Noi ___ il pane.',
  expected: 'mangiamo',
  given: 'mangiate',
  skillId: 'present-are',
  note: '# Present\nmang-iamo',
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  final scheduler = FsrsScheduler();

  setUp(() async => dir = await Directory.systemTemp.createTemp('tosk-backup-'));
  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<ProgressRepo> openRepo(String name) async {
    final repo = ProgressRepo(ProgressDb(NativeDatabase(File('${dir.path}/$name.sqlite'))), scheduler: scheduler);
    addTearDown(repo.close);
    return repo;
  }

  test('round trip between two on-disk databases; a second import adds nothing', () async {
    final a = await openRepo('a');
    final log = sampleLog(count: 300);
    for (final e in log) {
      await a.record(e);
    }
    final wrong = log.where((e) => !e.correct).take(5).toList();
    for (final e in wrong) {
      await a.saveMistake(_mistake(e));
    }
    await a.setSetting('course.active', 'it');
    await a.setSetting('courses.added', 'it');
    await a.setSetting('reminder.enabled', 'true');
    await a.setSetting('engine.recent_sentences.it', '["s:1","s:2"]');

    final backup = await exportBackup(a, app: '0.3.0', now: _t);
    final text = encodeBackup(backup);
    final file = File('${dir.path}/tosk-backup.jsonl')..writeAsStringSync(text);
    expect(text.split('\n').first, contains(kBackupFormat));

    // Device B has its own history and settings.
    final b = await openRepo('b');
    final own = sampleLog(count: 40, seed: 99);
    for (final e in own) {
      await b.record(e);
    }
    await b.setSetting('course.active', 'nl');
    await b.setSetting('courses.added', 'nl');

    final decoded = decodeBackup(file.readAsStringSync());
    expect(decoded.events, hasLength(log.length));
    expect(decoded.mistakes, hasLength(5));
    expect(decoded.exportedAt, _t);
    expect(decoded.app, '0.3.0');

    final report = await importBackup(decoded, store: b, importer: b);
    expect(report.eventsInFile, log.length);
    expect(report.eventsAdded, log.length);
    expect(report.mistakesAdded, 5);
    // Missing keys come over; "my courses" is a union; the active course and
    // the reminder (device-only) stay as they are.
    expect(await b.getSetting('course.active'), 'nl');
    expect(await b.getSetting('courses.added'), 'nl,it');
    expect(await b.getSetting('reminder.enabled'), isNull);
    expect(await b.getSetting('engine.recent_sentences.it'), '["s:1","s:2"]');

    // B now holds the union, and its states equal a replay of that union.
    expect(await b.logCount(), log.length + own.length);
    final union = InMemoryProgressStore(scheduler: scheduler);
    for (final e in [...log, ...own]) {
      await union.record(e);
    }
    final bStates = {for (final s in await b.allStates()) s.facetId: s};
    final uStates = {for (final s in await union.allStates()) s.facetId: s};
    expect(bStates, uStates);
    expect((await b.mistakes(limit: 100)).map((m) => m.id).toSet(), wrong.map((e) => e.id).toSet());

    // Importing the same file again changes nothing.
    final again = await importBackup(decodeBackup(file.readAsStringSync()), store: b, importer: b);
    expect(again.eventsAdded, 0);
    expect(again.eventsKnown, log.length);
    expect(again.mistakesAdded, 0);
    expect(again.settingsAdded, 0);
    expect(await b.logCount(), log.length + own.length);
    expect({for (final s in await b.allStates()) s.facetId: s}, uStates);
  });

  test('a plain review-log file (sync export) imports too', () async {
    final log = sampleLog(count: 20);
    final b = await openRepo('plain');
    final report = await importBackup(decodeBackup(encodeReviewLogJsonl(log)), store: b, importer: b);
    expect(report.eventsAdded, 20);
    expect(report.mistakesAdded, 0);
  });

  test('exported file layout: header, events in (at, id) order, mistakes, sorted settings', () async {
    final store = InMemoryProgressStore(scheduler: scheduler);
    final log = sampleLog(count: 4);
    for (final e in log.reversed) {
      await store.record(e);
    }
    await store.saveMistake(_mistake(log.first));
    await store.setSetting('z.key', '1');
    await store.setSetting('a.key', '2');
    final lines = encodeBackup(await exportBackup(store, now: _t)).trim().split('\n');
    expect(lines, hasLength(1 + 4 + 1 + 2));
    expect(lines[1], encodeReviewLogJsonl(log).split('\n').first);
    expect(lines[5], contains('"kind":"mistake"'));
    expect(lines[6], contains('"a.key"'));
    expect(lines[7], contains('"z.key"'));
  });

  test('bad files are refused with a FormatException', () {
    expect(() => decodeBackup('not json'), throwsFormatException);
    expect(() => decodeBackup('{"format":"something-else/1"}'), throwsFormatException);
    expect(() => decodeBackup('{"format":"tosk-backup/2"}'), throwsFormatException);
    expect(() => decodeBackup('{"id":"x"}'), throwsFormatException);
    // Unknown sections of a newer minor version are skipped.
    expect(decodeBackup('{"format":"tosk-backup/1"}\n{"kind":"later","x":1}\n').events, isEmpty);
    // Backups written before the rename to tosk still import (split so a rename never touches it).
    expect(decodeBackup('{"format":"due' 'lingo-backup/1"}\n').events, isEmpty);
  });
  test('a backup never imports AI, device-only or unknown settings', () async {
    final b = InMemoryProgressStore(scheduler: scheduler);
    final backup = ProgressBackup(
      events: const [],
      settings: {
        'ai.base_url': 'https://attacker.example',
        'ai.provider': 'openai',
        'ai.model': 'x',
        'ai.explain_lang': 'en',
        'tosk.ai.api_key': 'sk-ant-planted',
        'packs.index_url': 'http://attacker.example/index.json',
        'reminder.enabled': 'true',
        'chat.conversations.it': '[]',
        'something.new': '1',
        'ui.theme_mode': 'dark',
        'engine.recent_sentences.it': '["s:1"]',
      },
    );
    final report = await importBackup(backup, store: b, importer: b);
    expect(report.settingsAdded, 2);
    expect(await b.getSetting('ui.theme_mode'), 'dark');
    expect(await b.getSetting('engine.recent_sentences.it'), '["s:1"]');
    for (final k in backup.settings.keys.where((k) => k != 'ui.theme_mode' && !k.startsWith('engine.'))) {
      expect(await b.getSetting(k), isNull, reason: k);
    }
  });

  test('every learner preference is importable; AI and device-only keys are not', () async {
    for (final k in {...SettingKeys.all, ...kSyncedSettingKeys}) {
      expect(isImportableSetting(k), isTrue, reason: k);
    }
    for (final k in [
      'ai.provider',
      'ai.model',
      'ai.base_url',
      'ai.explain_lang',
      SettingKeys.packIndexUrl,
      SettingKeys.packIndexCache,
      SettingKeys.welcomeDone,
      LearnerSettingKeys.reminderEnabled,
      LearnerSettingKeys.onyxPen,
    ]) {
      expect(isImportableSetting(k), isFalse, reason: k);
    }
    // The AI settings are not exported either.
    final a = InMemoryProgressStore(scheduler: scheduler);
    await a.setSetting('ai.base_url', 'http://localhost:1234');
    await a.setSetting('ui.theme_mode', 'dark');
    final exported = await exportBackup(a, keys: ['ai.base_url', 'ui.theme_mode']);
    expect(exported.settings, {'ui.theme_mode': 'dark'});
  });
}
