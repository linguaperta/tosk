import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/progress/event_importer.dart';
import '../../data/sync/progress_backup.dart';
import '../../providers.dart';
import '../../sync/sync_providers.dart';
import 'learner_settings.dart';
import 'setting_keys.dart';
import 'settings_parts.dart';

/// Where backups are written and read. The real one uses file_picker, whose
/// save flow fits each platform: a save dialog on desktop, the system
/// document picker on Android (Downloads, Drive, …) and the Files picker on
/// iOS, a browser download on the web. Tests inject a fake.
abstract interface class BackupFiles {
  /// Saves [bytes] as [fileName]; returns where (for the message), or null
  /// when the user cancelled.
  Future<String?> save(String fileName, Uint8List bytes);

  /// Lets the user pick a backup; null when cancelled.
  Future<({String name, Uint8List bytes})?> pick();
}

class FilePickerBackupFiles implements BackupFiles {
  const FilePickerBackupFiles();

  @override
  Future<String?> save(String fileName, Uint8List bytes) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/x-ndjson',
      dialogTitle: 'Save progress backup',
    );
    if (uri == null) return null;
    return uri.scheme == 'file' ? uri.toFilePath() : fileName;
  }

  @override
  Future<({String name, Uint8List bytes})?> pick() async {
    final f = await FilePicker.pickFile(dialogTitle: 'Choose a progress backup (.jsonl)');
    if (f == null) return null;
    return (name: f.name, bytes: await f.readAsBytes());
  }
}

final backupFilesProvider = Provider<BackupFiles>((ref) => const FilePickerBackupFiles());

/// `tosk-backup-YYYYMMDD.jsonl` (local date).
String backupFileName(DateTime now) {
  final l = now.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'tosk-backup-${l.year}${two(l.month)}${two(l.day)}.jsonl';
}

/// ", 4 starred items" (bookmarks in the file, not counting unstarred ones).
String _starredLine(ProgressBackup b) {
  final n = b.bookmarks.values.fold(0, (n, s) => n + s.length);
  return n == 0 ? '' : ', $n starred item${n == 1 ? '' : 's'}';
}

String _date(DateTime? t) {
  if (t == null) return '?';
  final l = t.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// Settings → Backup: export all progress to one file, and import (merge) one.
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _busy = false;

  void _snack(String text, {Key? key}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(key: key, content: Text(text)));

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final store = ref.read(progressStoreProvider);
      final now = ref.read(clockProvider)();
      final backup = await exportBackup(
        store,
        bookmarks: ref.read(bookmarkRepoProvider),
        keys: [...SettingKeys.all, ...LearnerSettingKeys.all],
        app: 'tosk',
        now: now,
      );
      final bytes = Uint8List.fromList(utf8.encode(encodeBackup(backup, now: now)));
      final where = await ref.read(backupFilesProvider).save(backupFileName(now), bytes);
      if (!mounted || where == null) return;
      final n = {for (final e in backup.events) e.id}.length;
      _snack('Saved $n answer${n == 1 ? '' : 's'} to $where', key: const ValueKey('backup-saved'));
    } catch (e) {
      if (mounted) _snack('Could not save the backup: $e', key: const ValueKey('backup-error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await ref.read(backupFilesProvider).pick();
    if (picked == null || !mounted) return;
    final ProgressBackup backup;
    try {
      backup = decodeBackup(utf8.decode(picked.bytes, allowMalformed: true));
    } on FormatException catch (e) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('backup-invalid'),
          title: const Text('Not a progress backup'),
          content: Text('${picked.name} can\'t be read: ${e.message}'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    if (!mounted) return;
    final answers = {for (final e in backup.events) e.id}.length;
    final range = answers == 0 ? '' : ' from ${_date(backup.firstAt)} to ${_date(backup.lastAt)}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('backup-confirm'),
        title: const Text('Import this backup?'),
        content: Text(
          '${picked.name} has $answers answer${answers == 1 ? '' : 's'}$range, '
          '${backup.mistakes.length} mistake${backup.mistakes.length == 1 ? '' : 's'} and '
          '${backup.settings.length} setting${backup.settings.length == 1 ? '' : 's'}'
          '${_starredLine(backup)}.\n\n'
          'They are merged with the progress on this device. Nothing is deleted, and answers '
          'already here are skipped.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('backup-import-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('backup-import-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    // Used after the result dialog, when this widget may have been rebuilt.
    final container = ProviderScope.containerOf(context, listen: false);
    void refresh() {
      // Everything derived from progress and settings reloads.
      container.read(progressRevisionProvider.notifier).bump();
      container.invalidate(settingsProvider);
      container.invalidate(learnerSettingsProvider);
    }

    try {
      final store = ref.read(progressStoreProvider);
      if (store is! EventImporter) throw StateError('This progress store cannot import');
      final report = await importBackup(
        backup,
        store: store,
        importer: store as EventImporter,
        bookmarks: ref.read(bookmarkRepoProvider),
      );
      // Signed in: upload the imported answers soon (after a sync that is
      // running now, never alongside it).
      if (report.eventsAdded > 0 || report.settingsAdded > 0) container.read(syncServiceProvider)?.localDataChanged();
      if (!mounted) {
        refresh();
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('backup-import-result'),
          title: const Text('Backup imported'),
          content: Text(
            '${report.eventsAdded} new answer${report.eventsAdded == 1 ? '' : 's'} '
            '(${report.eventsKnown} already here), '
            '${report.mistakesAdded} mistake${report.mistakesAdded == 1 ? '' : 's'} and '
            '${report.settingsAdded} setting${report.settingsAdded == 1 ? '' : 's'} added'
            '${report.bookmarksChanged == 0 ? '' : '; ${report.bookmarksChanged} starred item${report.bookmarksChanged == 1 ? '' : 's'} updated'}.',
          ),
          actions: [
            FilledButton(
              key: const ValueKey('backup-result-ok'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      refresh();
    } catch (e) {
      if (mounted) _snack('Import failed: $e', key: const ValueKey('backup-error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeader('Backup'),
        ListTile(
          key: const ValueKey('backup-export'),
          enabled: !_busy,
          leading: const Icon(Icons.upload_file),
          title: const Text('Export progress'),
          subtitle: const Text('All answers, mistakes and settings in one file'),
          onTap: _export,
        ),
        ListTile(
          key: const ValueKey('backup-import'),
          enabled: !_busy,
          leading: const Icon(Icons.download),
          title: const Text('Import progress'),
          subtitle: const Text('Merge a backup into this device. Nothing is deleted'),
          onTap: _import,
        ),
      ],
    );
  }
}
