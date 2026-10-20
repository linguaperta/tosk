// Web packs (v0.7): the same-origin mirror on GitHub Pages with gzipped packs
// (`web_url`, `gz_sha256`, `gz_size`), relative URLs, and the persistent
// blob pack store (IndexedDB in the browser, memory here).
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:tosk/core/core.dart';
import 'package:tosk/data/packs/blob_pack_file_store.dart';
import 'package:tosk/data/packs/github_pack_source.dart';
import 'package:tosk/data/packs/local_pack_source.dart';
import 'package:tosk/data/platform/platform.dart' as platform;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/course_fixture.dart';
import 'local_pack_source_test.dart' show FakeBundled;

const _site = 'https://owner.github.io/tosk/';
String _sha(List<int> b) => crypto.sha256.convert(b).toString();

void main() {
  final v1 = fixtureCourseBytes(); // it 0.1.0
  final v2 = fixtureCourseBytes(overrideMeta: {'version': '0.2.0'});
  final v2gz = Uint8List.fromList(gzip.encode(v2));

  Map<String, Object?> entry({String? gzSha, int? gzSize, String? sha, bool web = true}) => {
    'id': 'it',
    'version': '0.2.0',
    'title': {'en': 'Italian'},
    'schema_version': '1',
    'min_app_version': '0.3.0',
    'sha256': sha ?? _sha(v2),
    'size': v2.length,
    'url': 'https://github.com/linguaperta/tosk-data/releases/download/packs-1/it.sqlite',
    if (web) ...{'web_url': 'it.sqlite.gz', 'gz_sha256': gzSha ?? _sha(v2gz), 'gz_size': gzSize ?? v2gz.length},
  };

  String index(Map<String, Object?> e) => jsonEncode({'index_version': 1, 'tag': 'packs-1', 'courses': [e]});

  ({GitHubPackSource src, List<Uri> requests, BlobPackFileStore store, MemoryBlobStore blobs}) setup(
    String indexJson, {
    bool preferWeb = true,
    List<int>? gzBody,
  }) {
    final requests = <Uri>[];
    final client = MockClient((req) async {
      requests.add(req.url);
      final u = req.url.toString();
      if (u == '${_site}packs/index.json') return http.Response(indexJson, 200);
      if (u == '${_site}packs/it.sqlite.gz') return http.Response.bytes(gzBody ?? v2gz, 200);
      if (u.endsWith('/it.sqlite')) return http.Response.bytes(v2, 200);
      return http.Response('Not Found', 404);
    });
    final blobs = MemoryBlobStore();
    final store = BlobPackFileStore(blobs);
    final src = GitHubPackSource(
      local: LocalPackSource(
        bundled: FakeBundled({'assets/courses/it.sqlite': v1}),
        store: store,
        readMeta: platform.readPackMeta,
      ),
      client: client,
      appVersion: '0.7.0',
      indexUrl: Uri.parse('${_site}packs/index.json'),
      verify: (d) async => platform.loadCoursePack(d),
      preferWebPacks: preferWeb,
    );
    return (src: src, requests: requests, store: store, blobs: blobs);
  }

  test('index fields: web pack fields parse, round-trip, and older entries lack them', () {
    final idx = RemoteIndex.parse(index(entry()));
    final p = idx['it']!;
    expect(p.hasWebPack, isTrue);
    expect(p.gzSize, v2gz.length);
    final back = RemoteIndex.parse(idx.toJsonString())['it']!;
    expect(back.webUrl, 'it.sqlite.gz');
    expect(back.gzSha256, p.gzSha256);
    final old = RemoteIndex.parse(index(entry(web: false)))['it']!;
    expect(old.hasWebPack, isFalse);
    expect(old.toJson().containsKey('web_url'), isFalse);
  });

  test('relative URLs resolve against the index URL', () async {
    final s = setup(index({...entry(), 'url': 'it.sqlite'}));
    final idx = await s.src.fetchIndex();
    expect(idx['it']!.webUrl, '${_site}packs/it.sqlite.gz');
    expect(idx['it']!.url, '${_site}packs/it.sqlite');
  });

  test('the web downloads the gzipped copy, checks both checksums and persists it', () async {
    final s = setup(index(entry()));
    final idx = await s.src.fetchIndex();
    final progress = <int>[];
    final info = await s.src.download(idx['it']!, onProgress: (got, total) => progress.add(total));
    expect(info.version, '0.2.0');
    expect(s.requests.map((u) => u.path).toList(), ['/tosk/packs/index.json', '/tosk/packs/it.sqlite.gz']);
    expect(progress.toSet(), {v2gz.length});
    expect(s.blobs.blobs['it'], v2); // stored decompressed
    expect(jsonDecode(s.blobs.texts['packs.json']!)['packs']['it']['origin'], 'remote');

    // A "reload": a new source over the same blobs sees the downloaded pack.
    final again = LocalPackSource(
      bundled: FakeBundled({'assets/courses/it.sqlite': v1}),
      store: BlobPackFileStore(s.blobs),
      readMeta: platform.readPackMeta,
    );
    expect((await again.available()).single.version, '0.2.0');
    expect((await platform.loadCoursePack((await again.open('it')).data)).version, '0.2.0');
  });

  test('a corrupt .gz or a wrong pack checksum is refused and the installed pack kept', () async {
    for (final s in [
      setup(index(entry(gzSha: 'ab' * 32))),
      setup(index(entry(sha: 'cd' * 32))),
      setup(index(entry()), gzBody: [...v2gz.sublist(0, 100), ...List.filled(v2gz.length - 100, 0)]),
    ]) {
      final idx = await s.src.fetchIndex();
      await expectLater(
        s.src.download(idx['it']!),
        throwsA(isA<PackDownloadException>().having((e) => e.kind, 'kind', PackDownloadError.corrupt)),
      );
      expect((await s.src.available()).single.version, '0.1.0');
    }
  });

  test('native builds ignore the web copy and download the pack itself', () async {
    final s = setup(index(entry()), preferWeb: false);
    final idx = await s.src.fetchIndex();
    await s.src.download(idx['it']!);
    expect(s.requests.last.path, endsWith('/it.sqlite'));
  });

  test('a failing blob store falls back to memory for the session', () async {
    Object? reported;
    final store = FallbackBlobStore(_Broken(), onFallback: (e) => reported = e);
    await store.put('it', Uint8List.fromList([1, 2, 3]));
    expect(store.usingFallback, isTrue);
    expect(reported, isA<StateError>());
    expect(await store.get('it'), [1, 2, 3]);
    expect(await store.keys(), ['it']);
  });
}

class _Broken implements BlobStore {
  Never _fail() => throw StateError('IndexedDB is not available');
  @override
  Future<Uint8List?> get(String key) async => _fail();
  @override
  Future<void> put(String key, Uint8List bytes) async => _fail();
  @override
  Future<void> delete(String key) async => _fail();
  @override
  Future<List<String>> keys() async => _fail();
  @override
  Future<String?> getText(String key) async => _fail();
  @override
  Future<void> putText(String key, String value) async => _fail();
}
