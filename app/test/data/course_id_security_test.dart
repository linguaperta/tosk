// A pack's course id names its file (`courses/{id}.sqlite`), so ids from a
// pack, a course index or packs.json must never escape the courses folder.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:tosk/data/course/course_schema.dart';
import 'package:tosk/data/packs/blob_pack_file_store.dart';
import 'package:tosk/data/packs/local_pack_source.dart';
import 'package:tosk/data/packs/pack_file_store.dart';
import 'package:tosk/data/platform/platform.dart' as platform;
import 'package:tosk/data/platform/platform_native.dart' show NativePackFileStore;

import '../fixtures/course_fixture.dart';

const _malicious = [
  '',
  '.',
  '..',
  '../progress',
  '..\\progress',
  'it/../progress',
  'it/x',
  'it\\x',
  '/etc/passwd',
  r'C:\Users\x\AppData\Roaming\places',
  'C:places',
  r'\\server\share\x',
  '//server/share/x',
  'it..x',
  'it.',
  '.it',
  'it.a.b',
  'IT',
  'it ',
  ' it',
  'it\n',
  'it\u0000',
  'it:stream',
  'ìt', // non-ASCII letter
  'it\u2215x', // DIVISION SLASH
  'it\uFF0Fx', // FULLWIDTH SOLIDUS
  'i\u0307t', // combining dot
  'con',
  'nul',
  'com1',
  'lpt9.x',
  'aux.cucina',
  '0it',
  '-it',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
];

void main() {
  test('valid course ids', () {
    for (final id in ['it', 'nl', 'hns', 'x', 'it-montalbano', 'it.cucina', 'es_mx', 'it.2024-story', 'cont']) {
      expect(isValidCourseId(id), isTrue, reason: id);
    }
  });

  test('malicious course ids are rejected', () {
    for (final id in _malicious) {
      expect(isValidCourseId(id), isFalse, reason: jsonEncode(id));
    }
  });

  test('parseCourseMeta rejects a bad course_id', () {
    for (final id in ['../progress', r'C:\x\places', '/tmp/x', '']) {
      final raw = {
        'course_id': id,
        'version': '1.0.0',
        'title': '{"en":"X"}',
        'target': 'it',
        'schema_version': '$kCourseDbSchemaVersion',
        'translations': '["en"]',
      };
      for (final k in kRequiredCourseMetaKeys) {
        raw.putIfAbsent(k, () => '[]');
      }
      expect(() => parseCourseMeta(raw), throwsA(isA<CourseFormatException>()), reason: id);
    }
  });

  test('RemotePack.fromJson and RemoteIndex.parse reject a bad id', () {
    Map<String, dynamic> entry(String id) => {'id': id, 'url': 'https://x/$id.sqlite', 'sha256': 'ab', 'size': 1};
    expect(RemotePack.fromJson(entry('it')).id, 'it');
    for (final id in ['../progress', r'C:\x', 'it/../x', '\\\\h\\s']) {
      expect(() => RemotePack.fromJson(entry(id)), throwsFormatException, reason: id);
      final index = jsonEncode({
        'index_version': 1,
        'courses': [entry(id)],
      });
      expect(() => RemoteIndex.parse(index), throwsFormatException, reason: id);
    }
  });

  group('NativePackFileStore', () {
    late Directory tmp;
    late NativePackFileStore store;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('tosk_ids_');
      store = NativePackFileStore(Directory('${tmp.path}/courses'));
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('never writes, stages or deletes outside courses/', () async {
      final progress = File('${tmp.path}/progress.sqlite')..writeAsStringSync('keep me');
      for (final id in _malicious) {
        await expectLater(store.writeBytes(id, Uint8List(1)), throwsArgumentError, reason: jsonEncode(id));
        await expectLater(store.copyFile(id, progress.path), throwsArgumentError, reason: jsonEncode(id));
        await expectLater(store.stage(id), throwsArgumentError, reason: jsonEncode(id));
        await expectLater(store.delete(id), throwsArgumentError, reason: jsonEncode(id));
        await expectLater(store.data(id), throwsArgumentError, reason: jsonEncode(id));
      }
      expect(progress.readAsStringSync(), 'keep me');
      // Nothing else was created, not even the courses folder.
      expect(tmp.listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last).toSet(), {'progress.sqlite'});
    });

    test('an expansion id stays a plain file in courses/', () async {
      await store.writeBytes('it.cucina', Uint8List(3));
      expect(File('${tmp.path}/courses/it.cucina.sqlite').lengthSync(), 3);
      expect(await store.installedIds(), ['it.cucina']);
    });

    test('files with invalid names in courses/ are skipped with a warning', () async {
      Directory('${tmp.path}/courses').createSync();
      writeFixtureCourseFile('${tmp.path}/courses/Bad Name.sqlite');
      final warnings = <String>[];
      final src = LocalPackSource(
        bundled: const NoBundledPacks(),
        store: store,
        readMeta: platform.readPackMeta,
        onWarning: warnings.add,
      );
      expect(await src.available(), isEmpty);
      expect(warnings.single, contains('Bad Name.sqlite'));
    });

    test('installing a pack whose meta says course_id = ../progress fails and writes nothing', () async {
      final progress = File('${tmp.path}/progress.sqlite')..writeAsStringSync('keep me');
      final src = LocalPackSource(bundled: const NoBundledPacks(), store: store, readMeta: platform.readPackMeta);
      for (final id in ['../progress', '..\\progress', progress.path]) {
        final evil = fixtureCourseBytes(overrideMeta: {'course_id': id});
        await expectLater(src.install(PackBytes(evil)), throwsA(isA<CourseFormatException>()), reason: id);
        final file = File('${tmp.path}/evil.sqlite')..writeAsBytesSync(evil);
        await expectLater(src.install(PackFile(file.path)), throwsA(isA<CourseFormatException>()), reason: id);
      }
      expect(progress.readAsStringSync(), 'keep me');
      expect(await src.available(), isEmpty);
    });

    test('a packs.json entry with a bad key is ignored', () async {
      Directory('${tmp.path}/courses').createSync();
      File('${tmp.path}/courses/packs.json').writeAsStringSync(
        jsonEncode({
          'packs': {
            '../progress': {'version': '1.0.0', 'title': {'en': 'X'}, 'origin': 'remote'},
          },
        }),
      );
      final src = LocalPackSource(bundled: const NoBundledPacks(), store: store, readMeta: platform.readPackMeta);
      expect(await src.available(), isEmpty);
      expect(await src.remove('../progress'), isFalse);
    });
  });

  test('web and memory stores reject bad ids too', () async {
    for (final PackFileStore store in [BlobPackFileStore(MemoryBlobStore()), MemoryPackFileStore()]) {
      for (final id in ['../progress', r'C:\x', '']) {
        await expectLater(store.writeBytes(id, Uint8List(1)), throwsArgumentError, reason: id);
        await expectLater(store.stage(id), throwsArgumentError, reason: id);
      }
    }
    // A planted IndexedDB key is never listed as a course.
    final blobs = MemoryBlobStore();
    await blobs.put('../x', fixtureCourseBytes(overrideMeta: {'course_id': '../x'}));
    final src = LocalPackSource(
      bundled: const NoBundledPacks(),
      store: BlobPackFileStore(blobs),
      readMeta: platform.readPackMeta,
    );
    expect(await src.available(), isEmpty);
  });
}
