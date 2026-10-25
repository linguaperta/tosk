// Packs from outside the app may be hostile SQLite files: views posing as the
// course tables (e.g. a query that never ends), triggers, virtual tables, a
// damaged file. They are refused before any course table is read.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_bytes.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/data/course/course_schema.dart';
import 'package:tosk/data/packs/blob_pack_file_store.dart';
import 'package:tosk/data/packs/local_pack_source.dart';
import 'package:tosk/data/platform/platform.dart' as platform;

import '../fixtures/course_fixture.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('tosk_evil_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// The fixture pack with [sql] run on it (read-write), as bytes and as a file.
  (Uint8List, String) evil(String name, String sql) {
    final path = writeFixtureCourseFile('${tmp.path}/$name.sqlite');
    final db = sqlite3.open(path);
    db.execute(sql);
    db.close();
    return (File(path).readAsBytesSync(), path);
  }

  final cases = {
    // A view that never ends, posing as the skills table.
    'looping-view': '''
      DROP TABLE skills;
      CREATE VIEW skills AS
        WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n)
        SELECT 'x' AS id, 'u1' AS unit_id, i AS ord, 'vocab' AS kind, '{}' AS title, NULL AS icon,
               NULL AS tense, NULL AS exercises, NULL AS pos_x, NULL AS pos_y, NULL AS query FROM n;
    ''',
    'trigger': '''
      CREATE TABLE log(x);
      CREATE TRIGGER t AFTER INSERT ON log BEGIN DELETE FROM items; END;
    ''',
    'view-elsewhere': 'CREATE VIEW extra AS SELECT * FROM items;',
  };

  for (final MapEntry(key: name, value: sql) in cases.entries) {
    test('$name: refused by every reader', () async {
      final (bytes, path) = evil(name, sql);
      Matcher refused = throwsA(isA<CourseFormatException>().having((e) => e.message, 'message', contains('Not a course pack')));
      expect(() => readCourseMetaFromBytes(sqlite3, bytes), refused);
      expect(() => loadCourseRepoFromBytes(sqlite3, bytes), refused);
      expect(() => readCourseMetaFile(path), refused);
      expect(() => loadCourseRepoFile(path), refused);
      final src = LocalPackSource(
        bundled: const NoBundledPacks(),
        store: BlobPackFileStore(MemoryBlobStore()),
        readMeta: platform.readPackMeta,
      );
      await expectLater(src.install(PackBytes(bytes)), throwsA(isA<CourseFormatException>()));
      expect(await src.available(), isEmpty);
    });
  }

  test('a virtual table is refused', () {
    final path = writeFixtureCourseFile('${tmp.path}/vt.sqlite');
    final db = sqlite3.open(path);
    try {
      db.execute('CREATE VIRTUAL TABLE v USING fts5(a)');
    } on SqliteException {
      markTestSkipped('fts5 not compiled in');
      db.close();
      return;
    }
    db.close();
    expect(() => readCourseMetaFile(path), throwsA(isA<CourseFormatException>()));
  });

  test('a damaged file fails the integrity check (packs from outside only)', () {
    final path = writeFixtureCourseFile('${tmp.path}/it.sqlite');
    final bytes = File(path).readAsBytesSync();
    final db = sqlite3.open(path);
    final pageSize = db.select('PRAGMA page_size').single.values.first! as int;
    // The root page of the items table: overwrite its b-tree header.
    final root = db.select("SELECT rootpage FROM sqlite_master WHERE name = 'items'").single.values.first! as int;
    db.close();
    final damaged = Uint8List.fromList(bytes);
    final at = (root - 1) * pageSize;
    for (var i = 0; i < 64; i++) {
      damaged[at + i] = 0x5a;
    }
    expect(() => readCourseMetaFromBytes(sqlite3, damaged, checkIntegrity: true), throwsA(isA<CourseFormatException>()));
    // The meta itself is still readable; only the deep check notices.
    expect(readCourseMetaFromBytes(sqlite3, damaged).id, 'it');
    expect(readCourseMetaFromBytes(sqlite3, bytes, checkIntegrity: true).id, 'it');
  });

  test('packs installed from outside are integrity-checked', () async {
    var deep = 0;
    final src = LocalPackSource(
      bundled: const NoBundledPacks(),
      store: BlobPackFileStore(MemoryBlobStore()),
      readMeta: platform.readPackMeta,
      readUntrustedMeta: (d) {
        deep++;
        return platform.readPackMeta(d, checkIntegrity: true);
      },
    );
    await src.install(PackBytes(fixtureCourseBytes()));
    expect(deep, 1);
  });
}
