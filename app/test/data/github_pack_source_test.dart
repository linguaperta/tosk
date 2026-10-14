// GitHubPackSource against a fake GitHub (MockClient with the release URLs and
// their redirects to object storage), and once against a real local HTTP
// server: index, offers, downloads with progress, 404, corrupted checksum,
// truncated download, newer schema / app, network loss, cancel, the atomic
// swap with rollback on an on-disk store, and crash recovery.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/app_data.dart';
import 'package:tosk/data/packs/github_pack_source.dart';
import 'package:tosk/data/packs/local_pack_source.dart';
import 'package:tosk/data/packs/pack_file_store.dart';
import 'package:tosk/data/platform/platform.dart' as platform;
import 'package:tosk/data/platform/platform_native.dart' show NativePackFileStore;
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/course_fixture.dart';
import 'local_pack_source_test.dart' show FakeBundled;

const _repo = 'https://github.com/timoverlaan/tosk-data';
const _tag = 'packs-20261014';
String _asset(String name) => '$_repo/releases/download/$_tag/$name';
String _storage(String name) => 'https://objects.githubusercontent.com/github-production-release-asset/$_tag/$name';

String _sha(List<int> b) => crypto.sha256.convert(b).toString();

Map<String, Object?> _entry(
  String id,
  Uint8List bytes, {
  String version = '0.2.0',
  String schema = '1',
  String minApp = '0.3.0',
  String? sha,
  int? size,
}) => {
  'id': id,
  'version': version,
  'title': {'en': id.toUpperCase()},
  'description': {'en': 'About $id'},
  'target': id,
  'sources': ['en', 'nl'],
  'unverified': false,
  'schema_version': schema,
  'min_app_version': minApp,
  'sha256': sha ?? _sha(bytes),
  'size': size ?? bytes.length,
  'url': _asset('$id.sqlite'),
};

/// A fake GitHub: `releases/latest/download/x` → 302 → `releases/download/<tag>/x`
/// → 302 → object storage, which serves [files] (in 3 chunks, or via [stream]).
class FakeGitHub {
  FakeGitHub(this.files);
  final Map<String, List<int>> files;
  final requests = <Uri>[];
  Stream<List<int>> Function(String name, List<int> bytes)? stream;
  int? status;

  http.Client get client => MockClient.streaming((req, _) async {
    requests.add(req.url);
    final u = req.url.toString();
    final name = req.url.pathSegments.last;
    expect(req.followRedirects, isFalse, reason: 'redirects are followed by hand');
    if (u == '$_repo/releases/latest/download/$name') return _redirect(_asset(name));
    if (u == _asset(name)) return _redirect(_storage(name));
    final body = files[name];
    if (u != _storage(name) || body == null || status != null) {
      return http.StreamedResponse(Stream.value(utf8.encode('Not Found')), status ?? 404);
    }
    final s = stream?.call(name, body) ??
        Stream.fromIterable([
          for (var i = 0; i < body.length; i += (body.length / 3).ceil())
            body.sublist(i, (i + (body.length / 3).ceil()).clamp(0, body.length)),
        ]);
    return http.StreamedResponse(s, 200, contentLength: body.length);
  });

  http.StreamedResponse _redirect(String to) =>
      http.StreamedResponse(const Stream.empty(), 302, headers: {'location': to});
}

void main() {
  final v1 = fixtureCourseBytes(); // it 0.1.0
  final v2 = fixtureCourseBytes(overrideMeta: {'version': '0.2.0'});
  final nl = fixtureCourseBytes(
    overrideMeta: {'course_id': 'nl', 'title': '{"en":"Dutch","nl":"Nederlands"}', 'version': '1.0.0'},
  );
  final schema9 = fixtureCourseBytes(overrideMeta: {'schema_version': '9', 'version': '0.2.0'});

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('tosk_gh_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may hold a file briefly.
    }
  });

  String indexJson(List<Map<String, Object?>> courses, {int version = 1}) => jsonEncode({
    'index_version': version,
    'generated_at': '2026-10-14T10:00:00Z',
    'tag': _tag,
    'courses': courses,
  });

  LocalPackSource local(PackFileStore store) => LocalPackSource(
    bundled: FakeBundled({'assets/courses/it.sqlite': v1}),
    store: store,
    readMeta: platform.readPackMeta,
  );

  GitHubPackSource source(
    FakeGitHub gh,
    PackFileStore store, {
    String appVersion = '0.4.0',
    Future<void> Function(PackData)? verify,
  }) => GitHubPackSource(
    local: local(store),
    client: gh.client,
    appVersion: appVersion,
    verify: verify ?? (d) async => platform.loadCoursePack(d),
  );

  Directory courses() => Directory('${tmp.path}/courses');
  NativePackFileStore nativeStore() => NativePackFileStore(courses());
  List<String> leftovers() => [
    for (final f in courses().listSync())
      if (f.path.endsWith('.download') || f.path.endsWith('.bak') || f.path.endsWith('.tmp')) f.path,
  ];
  Map<String, dynamic> manifest() =>
      (jsonDecode(File('${courses().path}/packs.json').readAsStringSync()) as Map<String, dynamic>)['packs']
          as Map<String, dynamic>;

  group('index and offers', () {
    test('the stable URL redirects to the release asset; offers combine installed and online', () async {
      final gh = FakeGitHub({
        'index.json': utf8.encode(
          indexJson([
            _entry('it', v2),
            _entry('nl', nl, version: '1.0.0'),
            _entry('es', v2, schema: '2'),
            _entry('fr', v2, minApp: '9.0.0'),
          ]),
        ),
      });
      final src = source(gh, MemoryPackFileStore());
      expect(src.indexUrl.toString(), kDefaultPackIndexUrl);
      final index = await src.fetchIndex();
      expect(gh.requests.map((u) => u.host), ['github.com', 'github.com', 'objects.githubusercontent.com']);
      expect(index.tag, _tag);
      expect(index.generatedAt, DateTime.utc(2026, 10, 14, 10));
      expect(index['it']!.url, _asset('it.sqlite'));
      expect(index['nl']!.description['en'], 'About nl');

      final offers = {for (final o in await src.offers(index)) o.id: o};
      expect(offers.keys, ['it', 'nl', 'es', 'fr']);
      expect(offers['it']!.status, OfferStatus.updateAvailable);
      expect(offers['it']!.installedVersion, '0.1.0');
      expect(offers['nl']!.status, OfferStatus.downloadable);
      expect(offers['es']!.status, OfferStatus.needsAppUpdate);
      expect(offers['fr']!.status, OfferStatus.needsAppUpdate);
      expect((await src.offers(null)).single.status, OfferStatus.installed);
    });

    test('combineOffers: same or older online version, incompatible update', () {
      RemoteIndex idx(String v, {String schema = '1'}) => RemoteIndex(
        courses: [
          RemotePack(id: 'it', version: v, title: const {}, url: 'u', sha256: 's', size: 1, schemaVersion: schema),
        ],
      );
      List<OfferStatus> st(RemoteIndex i) => [
        for (final o in combineOffers(installed: {'it': '1.1.0'}, index: i, appVersion: '0.4.0', schemaMajor: 1))
          o.status,
      ];
      expect(st(idx('1.1.0')), [OfferStatus.installed]);
      expect(st(idx('1.0.9')), [OfferStatus.installed]);
      expect(st(idx('1.2.0')), [OfferStatus.updateAvailable]);
      expect(st(idx('1.2.0', schema: '1.3')), [OfferStatus.updateAvailable]); // minor bump: additive
      expect(st(idx('2.0.0', schema: '2')), [OfferStatus.installed]); // not usable: no badge
    });

    test('bad indexes and no network are polite errors', () async {
      Future<PackDownloadException> failIndex(String body, {int? status}) async {
        final gh = FakeGitHub({'index.json': utf8.encode(body)})..status = status;
        try {
          await source(gh, MemoryPackFileStore()).fetchIndex();
        } on PackDownloadException catch (e) {
          return e;
        }
        fail('no error');
      }

      expect((await failIndex('{nope')).kind, PackDownloadError.corrupt);
      expect((await failIndex(indexJson([], version: 2))).detail, contains('newer app'));
      expect((await failIndex('{}', status: 404)).kind, PackDownloadError.http);
      expect((await failIndex('{}', status: 500)).message, contains('500'));
      final offline = GitHubPackSource(
        local: local(MemoryPackFileStore()),
        client: MockClient((_) => throw http.ClientException('Failed host lookup')),
        appVersion: '0.4.0',
      );
      final e = await offline.fetchIndex().then<Object?>((_) => null, onError: (Object e) => e);
      expect(e, isA<PackDownloadException>().having((e) => e.kind, 'kind', PackDownloadError.network));
      expect((e! as PackDownloadException).message, contains('offline'));
    });
  });

  group('download (on-disk store)', () {
    test('an update downloads with progress, swaps in and is recorded as remote', () async {
      final gh = FakeGitHub({'it.sqlite': v2});
      final src = source(gh, nativeStore());
      expect((await src.available()).single.version, '0.1.0');
      final progress = <int>[];
      final info = await src.download(
        RemotePack.fromJson(_entry('it', v2)),
        onProgress: (got, total) {
          expect(total, v2.length);
          progress.add(got);
        },
      );
      expect(info.version, '0.2.0');
      expect(info.origin, PackOrigin.remote);
      expect(progress.first, 0);
      expect(progress.last, v2.length);
      expect(progress, orderedEquals([...progress]..sort()));
      expect(File('${courses().path}/it.sqlite').readAsBytesSync(), v2);
      expect(manifest()['it']['origin'], 'remote');
      expect(manifest()['it']['version'], '0.2.0');
      expect(leftovers(), isEmpty);
      // A new start keeps the downloaded version (the bundled 0.1.0 is older).
      final again = local(nativeStore());
      expect((await again.available()).single.version, '0.2.0');
    });

    Future<void> expectUnchanged() async {
      expect(File('${courses().path}/it.sqlite').readAsBytesSync(), v1);
      expect(manifest()['it']['version'], '0.1.0');
      expect(manifest()['it']['origin'], 'bundled');
      expect(leftovers(), isEmpty);
    }

    Future<PackDownloadException> failing(
      FakeGitHub gh,
      Map<String, Object?> entry, {
      Future<void> Function(PackData)? verify,
      DownloadCancel? cancel,
      DownloadProgress? onProgress,
    }) async {
      final src = source(gh, nativeStore(), verify: verify);
      await src.available();
      try {
        await src.download(RemotePack.fromJson(entry), cancel: cancel, onProgress: onProgress);
      } on PackDownloadException catch (e) {
        return e;
      }
      fail('the download should fail');
    }

    test('404', () async {
      final e = await failing(FakeGitHub({}), _entry('it', v2));
      expect(e.kind, PackDownloadError.http);
      expect(e.detail, contains('404'));
      await expectUnchanged();
    });

    test('corrupted checksum', () async {
      final e = await failing(FakeGitHub({'it.sqlite': v2}), _entry('it', v2, sha: _sha(v1)));
      expect(e.kind, PackDownloadError.corrupt);
      expect(e.message, contains('checksum'));
      await expectUnchanged();
    });

    test('truncated download', () async {
      final gh = FakeGitHub({'it.sqlite': v2})..stream = (_, b) => Stream.value(b.sublist(0, b.length ~/ 2));
      final e = await failing(gh, _entry('it', v2));
      expect(e.message, contains('incomplete'));
      await expectUnchanged();
    });

    test('larger than announced', () async {
      final e = await failing(FakeGitHub({'it.sqlite': v2}), _entry('it', v2, size: 100));
      expect(e.kind, PackDownloadError.corrupt);
      await expectUnchanged();
    });

    test('newer schema or app: refused before downloading', () async {
      final gh = FakeGitHub({'it.sqlite': v2});
      expect((await failing(gh, _entry('it', v2, schema: '2'))).kind, PackDownloadError.incompatible);
      expect((await failing(gh, _entry('it', v2, minApp: '0.9.0'))).message, contains('0.9.0'));
      expect(gh.requests, isEmpty);
      await expectUnchanged();
    });

    test('a file whose own schema is newer than the index says is refused', () async {
      final e = await failing(FakeGitHub({'it.sqlite': schema9}), _entry('it', schema9));
      expect(e.kind, PackDownloadError.corrupt);
      expect(e.message, contains('current version is kept'));
      await expectUnchanged();
    });

    test('the wrong course or version in the file is refused', () async {
      expect((await failing(FakeGitHub({'it.sqlite': nl}), _entry('it', nl))).kind, PackDownloadError.corrupt);
      expect(
        (await failing(FakeGitHub({'it.sqlite': v2}), _entry('it', v2, version: '0.3.0'))).detail,
        contains('0.2.0'),
      );
      await expectUnchanged();
    });

    test('network loss mid-download', () async {
      final gh = FakeGitHub({'it.sqlite': v2})
        ..stream = (_, b) async* {
          yield b.sublist(0, 1000);
          throw http.ClientException('Connection reset by peer');
        };
      final e = await failing(gh, _entry('it', v2));
      expect(e.kind, PackDownloadError.network);
      await expectUnchanged();
    });

    test('cancel', () async {
      final cancel = DownloadCancel();
      final e = await failing(
        FakeGitHub({'it.sqlite': v2}),
        _entry('it', v2),
        cancel: cancel,
        onProgress: (got, _) {
          if (got > 0) cancel.cancel();
        },
      );
      expect(e.kind, PackDownloadError.cancelled);
      await expectUnchanged();
    });

    test('a new version that fails to open is rolled back to the previous one', () async {
      var opened = 0;
      final e = await failing(
        FakeGitHub({'it.sqlite': v2}),
        _entry('it', v2),
        verify: (d) async {
          opened++;
          // The new file is in place while it is opened.
          expect(File((d as PackFile).path).readAsBytesSync(), v2);
          throw StateError('disk full');
        },
      );
      expect(opened, 1);
      expect(e.kind, PackDownloadError.corrupt);
      expect(e.detail, contains('disk full'));
      await expectUnchanged();
    });

    test('a crash mid-swap is repaired on the next start', () async {
      await local(nativeStore()).available();
      final dir = courses().path;
      File('$dir/it.sqlite').renameSync('$dir/it.sqlite.bak'); // previous version kept
      File('$dir/it.sqlite').writeAsBytesSync(v2); // new one swapped in, not yet opened
      File('$dir/nl.sqlite.download').writeAsBytesSync([1, 2, 3]); // interrupted download
      final again = local(nativeStore());
      expect((await again.available()).map((p) => '${p.id} ${p.version}'), ['it 0.1.0']);
      await expectUnchanged();
    });
  });

  test('web/in-memory store: a new course is downloaded and listed', () async {
    final gh = FakeGitHub({'nl.sqlite': nl});
    final src = source(gh, MemoryPackFileStore());
    await src.download(RemotePack.fromJson(_entry('nl', nl, version: '1.0.0')));
    final packs = {for (final p in await src.available()) p.id: p};
    expect(packs.keys, ['it', 'nl']);
    expect(packs['nl']!.origin, PackOrigin.remote);
    // Removing a downloaded course works like removing a file-added one.
    expect(await src.remove('nl'), isTrue);
    expect((await src.available()).map((p) => p.id), ['it']);
  });

  test('AppData.downloadPack evicts the cached course and keeps the review log', () async {
    final gh = FakeGitHub({'it.sqlite': v2});
    final app = AppData(
      progress: ProgressRepo(ProgressDb(NativeDatabase.memory())),
      packs: source(gh, MemoryPackFileStore()),
      loadPack: platform.loadCoursePack,
    );
    addTearDown(app.close);
    expect((await app.openCourse('it')).meta.version, '0.1.0');
    await app.progress.record(
      ReviewEvent(
        id: 'r1',
        facetId: 'it:ciao#rec',
        at: DateTime.utc(2026, 10, 14),
        rating: Rating.good,
        exerciseType: 'flashcard',
        inputMode: InputMode.self,
        responseMs: 500,
        correct: true,
      ),
    );
    expect(app.remote, isNotNull);
    await app.downloadPack(RemotePack.fromJson(_entry('it', v2)));
    expect((await app.openCourse('it')).meta.version, '0.2.0');
    expect((await app.progress.log()).single.id, 'r1');
    expect((await app.progress.state('it:ciao#rec'))?.reps, 1);
  });

  test('a real HTTP server: redirects, download, and a dropped connection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final p = req.uri.path;
      if (p == '/latest/index.json') {
        req.response
          ..statusCode = 302
          ..headers.set('location', '/assets/index.json');
      } else if (p == '/assets/index.json') {
        req.response.write(
          indexJson([
            {..._entry('it', v2), 'url': '$base/dl/it.sqlite'},
            {..._entry('nl', nl, version: '1.0.0'), 'url': '$base/drop/nl.sqlite'},
          ]),
        );
      } else if (p == '/dl/it.sqlite') {
        req.response
          ..statusCode = 307
          ..headers.set('location', '/files/it.sqlite');
      } else if (p == '/files/it.sqlite') {
        req.response
          ..headers.contentLength = v2.length
          ..add(v2);
      } else if (p == '/drop/nl.sqlite') {
        // Announce the whole file, send a third, then drop the connection.
        req.response.headers.contentLength = nl.length;
        final socket = await req.response.detachSocket();
        socket.add(nl.sublist(0, nl.length ~/ 3));
        await socket.flush();
        socket.destroy();
        return;
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    final client = http.Client();
    addTearDown(client.close);
    final src = GitHubPackSource(
      local: local(nativeStore()),
      client: client,
      appVersion: '0.4.0',
      indexUrl: Uri.parse('$base/latest/index.json'),
      timeout: const Duration(seconds: 5),
    );
    final index = await src.fetchIndex();
    expect((await src.download(index['it']!)).version, '0.2.0');
    final e = await src.download(index['nl']!).then<Object?>((_) => null, onError: (Object e) => e);
    expect(e, isA<PackDownloadException>());
    expect((e! as PackDownloadException).kind, anyOf(PackDownloadError.network, PackDownloadError.corrupt));
    expect((await src.available()).map((p) => '${p.id} ${p.version}'), ['it 0.2.0']);
    expect(leftovers(), isEmpty);
  });
}
