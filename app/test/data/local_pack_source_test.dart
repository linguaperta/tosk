import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/app_data.dart';
import 'package:tosk/data/course/course_schema.dart';
import 'package:tosk/data/packs/local_pack_source.dart';
import 'package:tosk/data/packs/pack_file_store.dart';
import 'package:tosk/data/platform/platform.dart' as platform;
import 'package:tosk/data/platform/platform_native.dart' show NativePackFileStore;
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/course_fixture.dart';

class FakeBundled implements BundledPacks {
  FakeBundled(this.packs);
  final Map<String, Uint8List> packs;
  int loads = 0;
  @override
  Future<List<String>> list() async => packs.keys.toList();
  @override
  Future<Uint8List> load(String key) async {
    loads++;
    return packs[key]!;
  }
}

void main() {
  final v1 = fixtureCourseBytes();
  final v2 = fixtureCourseBytes(overrideMeta: {'version': '0.2.0'});
  final nl = fixtureCourseBytes(overrideMeta: {
    'course_id': 'nl',
    'title': '{"en":"Dutch","nl":"Nederlands"}',
    'version': '1.0.0',
  });
  final bad = fixtureCourseBytes(overrideMeta: {'schema_version': '9'});

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('tosk_packs_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  LocalPackSource source(BundledPacks bundled, PackFileStore store, [List<String>? warnings]) =>
      LocalPackSource(
        bundled: bundled,
        store: store,
        readMeta: platform.readPackMeta,
        onWarning: warnings?.add,
      );

  test('bundled packs are installed into courses/ once and listed', () async {
    final warnings = <String>[];
    final bundled = FakeBundled({
      'assets/courses/it.sqlite': v1,
      'assets/courses/nl.sqlite': nl,
      'assets/courses/broken.sqlite': bad,
    });
    final store = NativePackFileStore(Directory('${tmp.path}/courses'));
    final src = source(bundled, store, warnings);
    final packs = await src.available();
    expect(packs.map((p) => p.id), ['it', 'nl']);
    expect(packs.first.origin, PackOrigin.bundled);
    expect(packs.first.version, '0.1.0');
    expect(packs.last.title['nl'], 'Nederlands');
    expect(packs.first.sizeBytes, v1.length);
    expect(File('${tmp.path}/courses/it.sqlite').existsSync(), isTrue);
    expect(File('${tmp.path}/courses/packs.json').existsSync(), isTrue);
    expect(warnings.single, contains('broken.sqlite'));

    final h = await src.open('it');
    expect(h.data, isA<PackFile>());
    final course = await platform.loadCoursePack(h.data);
    expect(course.skills.length, 5);
    await expectLater(src.open('xx'), throwsStateError);

    // A second run with the same bundle does not rewrite the installed file.
    final stamp = File('${tmp.path}/courses/it.sqlite').lastModifiedSync();
    final again = source(bundled, NativePackFileStore(Directory('${tmp.path}/courses')));
    expect((await again.available()).length, 2);
    expect(File('${tmp.path}/courses/it.sqlite').lastModifiedSync(), stamp);
  });

  test('a newer bundled version replaces the installed copy', () async {
    final store = NativePackFileStore(Directory('${tmp.path}/courses'));
    await source(FakeBundled({'a/it.sqlite': v1}), store).available();
    final updated = await source(FakeBundled({'a/it.sqlite': v2}), store).available();
    expect(updated.single.version, '0.2.0');
    // ...but an older bundle does not downgrade it.
    final older = await source(FakeBundled({'a/it.sqlite': v1}), store).available();
    expect(older.single.version, '0.2.0');
  });

  test('install from a file and from bytes; remove falls back to bundled', () async {
    final store = NativePackFileStore(Directory('${tmp.path}/courses'));
    final src = source(FakeBundled({'a/it.sqlite': v1}), store);
    final path = writeFixtureCourseFile('${tmp.path}/picked.sqlite', overrideMeta: {'version': '0.3.0'});
    final info = await src.install(PackFile(path));
    expect(info.origin, PackOrigin.local);
    expect((await src.available()).single.version, '0.3.0');
    final nlInfo = await src.install(PackBytes(nl));
    expect(nlInfo.id, 'nl');
    await expectLater(src.install(PackBytes(bad)), throwsA(isA<CourseFormatException>()));

    expect(await src.remove('it'), isTrue);
    final after = await src.available();
    expect(after.map((p) => '${p.id} ${p.version} ${p.origin.name}'),
        ['it 0.1.0 bundled', 'nl 1.0.0 local']);
    expect(await src.remove('it'), isFalse); // bundled packs stay
  });

  test('pack files copied into courses/ by hand are listed, refreshed and forgotten', () async {
    // E.g. the locally built Sarnami pack, which must never be bundled (docs/private-importers.md).
    final dir = Directory('${tmp.path}/courses')..createSync(recursive: true);
    Map<String, String> hnsMeta(String version) => {
          'course_id': 'hns',
          'target': 'hns',
          'title': '{"nl":"Sarnami"}',
          'translations': '["nl"]',
          'unverified': '1',
          'version': version,
        };
    writeFixtureCourseFile('${dir.path}/hns.sqlite', overrideMeta: hnsMeta('0.1.0'));
    writeFixtureCourseFile('${dir.path}/Sarnami.sqlite', overrideMeta: hnsMeta('0.1.0'));
    File('${dir.path}/junk.sqlite').writeAsStringSync('not a database');
    final warnings = <String>[];
    final bundled = FakeBundled({'a/it.sqlite': v1});

    final packs = await source(bundled, NativePackFileStore(dir), warnings).available();
    expect(packs.map((p) => '${p.id} ${p.version} ${p.origin.name} ${p.unverified}'),
        ['hns 0.1.0 local true', 'it 0.1.0 bundled false']);
    expect(warnings, hasLength(2));
    expect(warnings.where((w) => w.contains('Sarnami.sqlite') && w.contains('must be its course id')), hasLength(1));
    expect(warnings.where((w) => w.contains('junk.sqlite')), hasLength(1));
    final src = source(bundled, NativePackFileStore(dir));
    final course = await platform.loadCoursePack((await src.open('hns')).data);
    expect(course.meta.translations, ['nl']);

    // A rebuilt pack copied over the old file is picked up on the next start.
    writeFixtureCourseFile('${dir.path}/hns.sqlite', overrideMeta: hnsMeta('0.2.0'));
    expect((await source(bundled, NativePackFileStore(dir)).available()).first.version, '0.2.0');

    // Deleting the file removes it from the list.
    File('${dir.path}/hns.sqlite').deleteSync();
    expect((await source(bundled, NativePackFileStore(dir)).available()).map((p) => p.id), ['it']);
  });

  test('memory store (web path) works with bytes only', () async {
    final src = source(FakeBundled({'assets/courses/it.sqlite': v1}), MemoryPackFileStore());
    final h = await src.open('it');
    expect(h.data, isA<PackBytes>());
    expect((await platform.loadCoursePack(h.data)).itemCount, 21);
  });

  test('semver comparison', () {
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('1.2.0', '1.10.0'), lessThan(0));
    expect(compareVersions('2.0', '1.9.9'), greaterThan(0));
    expect(compareVersions('1.0.0-beta', '1.0.0'), lessThan(0));
    expect(compareVersions('1.0.0-beta.2', '1.0.0-beta.10'), lessThan(0));
    expect(compareVersions('1.0.0-alpha', '1.0.0-alpha.1'), lessThan(0));
    expect(compareVersions('1.0.0+build5', '1.0.0'), 0);
  });

  test('AppData opens and caches courses', () async {
    final progress = ProgressRepo(ProgressDb(NativeDatabase.memory()));
    final app = AppData(
      progress: progress,
      packs: source(FakeBundled({'a/it.sqlite': v1}), MemoryPackFileStore()),
      loadPack: platform.loadCoursePack,
    );
    addTearDown(app.close);
    expect((await app.availableCourses()).single.id, 'it');
    final c1 = await app.openCourse('it');
    expect(identical(await app.openCourse('it'), c1), isTrue);
    await expectLater(app.openCourse('nope'), throwsStateError);
    final info = await app.installPack(PackBytes(v2));
    expect(info.version, '0.2.0');
    expect((await app.openCourse('it')).version, '0.2.0');
    final stats = await app.stats.forCourse(c1);
    expect(stats.length, 5);
  });
}
