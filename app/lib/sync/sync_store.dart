/// Local sync bookkeeping, kept apart from the progress database (its own
/// small SQLite file, `sync.sqlite`), so sync never needs a progress-DB
/// migration and deleting it loses nothing but bookkeeping. Pure Dart.
///
/// * `kv`: the account the bookkeeping belongs to, the upload position in the
///   review log, the pull cursors, the device id.
/// * `event_meta`: per event id, the UTC offset when it was recorded (local
///   events, noted as they are recorded; pulled events, from the batch) and
///   whether the account already has it.
/// * `setting_stamps`: per synced setting, the last value seen and when and
///   where it was changed, plus whether the change still has to be pushed.
library;

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

/// UTC offset and upload state of one event.
@immutable
class EventMeta {
  const EventMeta(this.id, this.atMs, this.offsetMinutes, {this.uploaded = false});
  final String id;
  final int atMs;
  final int offsetMinutes;
  final bool uploaded;
}

/// The last known state of one synced setting.
@immutable
class SettingStamp {
  const SettingStamp({
    required this.key,
    required this.value,
    required this.changedAtMs,
    required this.device,
    required this.dirty,
  });
  final String key;
  final String? value;
  final int changedAtMs;
  final String device;

  /// Changed on this device and not pushed yet.
  final bool dirty;

  SettingStamp copyWith({bool? dirty}) =>
      SettingStamp(key: key, value: value, changedAtMs: changedAtMs, device: device, dirty: dirty ?? this.dirty);

  @override
  bool operator ==(Object other) =>
      other is SettingStamp &&
      other.key == key &&
      other.value == value &&
      other.changedAtMs == changedAtMs &&
      other.device == device &&
      other.dirty == dirty;
  @override
  int get hashCode => Object.hash(key, value, changedAtMs, device, dirty);
}

abstract interface class SyncStore {
  Future<String?> get(String key);
  Future<void> set(String key, String? value);

  /// Notes the offsets of events recorded on this device (existing entries win).
  Future<void> noteOffsets(Iterable<EventMeta> metas);

  /// Marks events as present in the account, adding their offsets if unknown.
  Future<void> markUploaded(Iterable<EventMeta> metas);

  Future<Map<String, EventMeta>> meta(Iterable<String> ids);

  /// Event time (UTC ms) → UTC offset in minutes, for every known event.
  Future<Map<int, int>> offsets();

  Future<Map<String, SettingStamp>> stamps();
  Future<void> putStamps(Iterable<SettingStamp> stamps);

  /// Forgets everything tied to an account (cursors, uploaded flags, setting
  /// stamps); keeps the device id and the offsets.
  Future<void> resetAccount();

  Future<void> close();
}

/// Keys in [SyncStore.get]/[SyncStore.set].
abstract final class SyncKeys {
  static const device = 'device';
  static const account = 'account';
  static const uploadSeq = 'upload.seq';
  static const eventsCursor = 'pull.events';
  static const settingsCursor = 'pull.settings';
  static const joined = 'settings.joined';
  static const lastSync = 'last_sync';
  static const accountScoped = [account, uploadSeq, eventsCursor, settingsCursor, joined, lastSync];
}

// -------------------------------------------------------------------- memory

class InMemorySyncStore implements SyncStore {
  final Map<String, String> _kv = {};
  final Map<String, EventMeta> _meta = {};
  final Map<String, SettingStamp> _stamps = {};

  @override
  Future<String?> get(String key) async => _kv[key];

  @override
  Future<void> set(String key, String? value) async => value == null ? _kv.remove(key) : _kv[key] = value;

  @override
  Future<void> noteOffsets(Iterable<EventMeta> metas) async {
    for (final m in metas) {
      _meta.putIfAbsent(m.id, () => m);
    }
  }

  @override
  Future<void> markUploaded(Iterable<EventMeta> metas) async {
    for (final m in metas) {
      final old = _meta[m.id] ?? m;
      _meta[m.id] = EventMeta(old.id, old.atMs, old.offsetMinutes, uploaded: true);
    }
  }

  @override
  Future<Map<String, EventMeta>> meta(Iterable<String> ids) async => {
        for (final id in ids) id: ?_meta[id],
      };

  @override
  Future<Map<int, int>> offsets() async => {for (final m in _meta.values) m.atMs: m.offsetMinutes};

  @override
  Future<Map<String, SettingStamp>> stamps() async => Map.of(_stamps);

  @override
  Future<void> putStamps(Iterable<SettingStamp> stamps) async {
    for (final s in stamps) {
      _stamps[s.key] = s;
    }
  }

  @override
  Future<void> resetAccount() async {
    for (final k in SyncKeys.accountScoped) {
      _kv.remove(k);
    }
    _stamps.clear();
    for (final e in _meta.entries.toList()) {
      _meta[e.key] = EventMeta(e.value.id, e.value.atMs, e.value.offsetMinutes);
    }
  }

  @override
  Future<void> close() async {}
}

// -------------------------------------------------------------------- SQLite

/// The sync database. Hand-written (raw SQL, no generated code): three small
/// tables that only [DriftSyncStore] touches.
class SyncDb extends GeneratedDatabase {
  SyncDb(super.executor);

  static const _ddl = [
    'CREATE TABLE IF NOT EXISTS kv (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS event_meta (id TEXT NOT NULL PRIMARY KEY, at INTEGER NOT NULL, '
        'off INTEGER NOT NULL, uploaded INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS setting_stamps (key TEXT NOT NULL PRIMARY KEY, value TEXT, '
        't INTEGER NOT NULL, device TEXT NOT NULL, dirty INTEGER NOT NULL)',
  ];

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          for (final s in _ddl) {
            await customStatement(s);
          }
        },
        onUpgrade: (m, from, to) async {
          if (from > to) throw StateError('sync.sqlite is from a newer app version ($from > $to)');
        },
      );
}

class DriftSyncStore implements SyncStore {
  DriftSyncStore(this.db);
  final SyncDb db;

  static const _chunk = 400;

  @override
  Future<String?> get(String key) async {
    final r = await db.customSelect('SELECT value FROM kv WHERE key = ?', variables: [Variable.withString(key)]).get();
    return r.isEmpty ? null : r.first.read<String>('value');
  }

  @override
  Future<void> set(String key, String? value) => value == null
      ? db.customStatement('DELETE FROM kv WHERE key = ?', [key])
      : db.customStatement('INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)', [key, value]);

  Future<void> _insertMeta(Iterable<EventMeta> metas, String conflict) async {
    final list = metas.toList();
    if (list.isEmpty) return;
    await db.transaction(() async {
      for (var i = 0; i < list.length; i += _chunk) {
        final part = list.sublist(i, i + _chunk > list.length ? list.length : i + _chunk);
        final values = List.filled(part.length, '(?, ?, ?, ?)').join(', ');
        await db.customStatement(
          'INSERT INTO event_meta (id, at, off, uploaded) VALUES $values $conflict',
          [for (final m in part) ...[m.id, m.atMs, m.offsetMinutes, m.uploaded ? 1 : 0]],
        );
      }
    });
  }

  @override
  Future<void> noteOffsets(Iterable<EventMeta> metas) => _insertMeta(metas, 'ON CONFLICT(id) DO NOTHING');

  @override
  Future<void> markUploaded(Iterable<EventMeta> metas) => _insertMeta(
        [for (final m in metas) EventMeta(m.id, m.atMs, m.offsetMinutes, uploaded: true)],
        'ON CONFLICT(id) DO UPDATE SET uploaded = 1',
      );

  @override
  Future<Map<String, EventMeta>> meta(Iterable<String> ids) async {
    final list = ids.toList();
    final out = <String, EventMeta>{};
    for (var i = 0; i < list.length; i += _chunk) {
      final part = list.sublist(i, i + _chunk > list.length ? list.length : i + _chunk);
      final rows = await db.customSelect(
        'SELECT id, at, off, uploaded FROM event_meta WHERE id IN (${List.filled(part.length, '?').join(', ')})',
        variables: [for (final id in part) Variable.withString(id)],
      ).get();
      for (final r in rows) {
        final id = r.read<String>('id');
        out[id] = EventMeta(id, r.read<int>('at'), r.read<int>('off'), uploaded: r.read<int>('uploaded') != 0);
      }
    }
    return out;
  }

  @override
  Future<Map<int, int>> offsets() async => {
        for (final r in await db.customSelect('SELECT at, off FROM event_meta').get())
          r.read<int>('at'): r.read<int>('off'),
      };

  @override
  Future<Map<String, SettingStamp>> stamps() async => {
        for (final r in await db.customSelect('SELECT key, value, t, device, dirty FROM setting_stamps').get())
          r.read<String>('key'): SettingStamp(
            key: r.read<String>('key'),
            value: r.readNullable<String>('value'),
            changedAtMs: r.read<int>('t'),
            device: r.read<String>('device'),
            dirty: r.read<int>('dirty') != 0,
          ),
      };

  @override
  Future<void> putStamps(Iterable<SettingStamp> stamps) => db.transaction(() async {
        for (final s in stamps) {
          await db.customStatement(
            'INSERT OR REPLACE INTO setting_stamps (key, value, t, device, dirty) VALUES (?, ?, ?, ?, ?)',
            [s.key, s.value, s.changedAtMs, s.device, s.dirty ? 1 : 0],
          );
        }
      });

  @override
  Future<void> resetAccount() => db.transaction(() async {
        await db.customStatement(
          'DELETE FROM kv WHERE key IN (${List.filled(SyncKeys.accountScoped.length, '?').join(', ')})',
          SyncKeys.accountScoped,
        );
        await db.customStatement('DELETE FROM setting_stamps');
        await db.customStatement('UPDATE event_meta SET uploaded = 0');
      });

  @override
  Future<void> close() => db.close();
}
