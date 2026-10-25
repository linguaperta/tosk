// Course indexes and packs: https only (also after redirects), loopback and
// the page's own origin excepted; bounded index reads, pack sizes and gzip
// decompression (a gzip bomb is refused without expanding it).
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/packs/blob_pack_file_store.dart';
import 'package:tosk/data/packs/github_pack_source.dart';
import 'package:tosk/data/packs/local_pack_source.dart';
import 'package:tosk/data/platform/platform.dart' as platform;

import '../fixtures/course_fixture.dart';

String _sha(List<int> b) => crypto.sha256.convert(b).toString();

void main() {
  final v2 = fixtureCourseBytes(overrideMeta: {'version': '0.2.0'});

  Map<String, Object?> entry(String url, {Map<String, Object?> extra = const {}}) => {
    'id': 'it',
    'version': '0.2.0',
    'title': {'en': 'Italian'},
    'schema_version': '1',
    'min_app_version': '0.3.0',
    'sha256': _sha(v2),
    'size': v2.length,
    'url': url,
    ...extra,
  };
  String index(List<Map<String, Object?>> courses) => jsonEncode({'index_version': 1, 'courses': courses});

  ({GitHubPackSource src, List<Uri> requests}) setup(
    Future<http.Response> Function(Uri url) handler, {
    String indexUrl = 'https://example.org/index.json',
    Uri? sameOrigin,
    bool preferWeb = false,
  }) {
    final requests = <Uri>[];
    final src = GitHubPackSource(
      local: LocalPackSource(
        bundled: const NoBundledPacks(),
        store: BlobPackFileStore(MemoryBlobStore()),
        readMeta: platform.readPackMeta,
      ),
      client: MockClient((req) {
        requests.add(req.url);
        return handler(req.url);
      }),
      appVersion: '0.7.0',
      indexUrl: Uri.parse(indexUrl),
      sameOrigin: sameOrigin,
      preferWebPacks: preferWeb,
    );
    return (src: src, requests: requests);
  }

  Matcher refused(PackDownloadError kind) => throwsA(isA<PackDownloadException>().having((e) => e.kind, 'kind', kind));

  group('URL policy', () {
    test('pack URLs', () {
      for (final u in [
        'https://github.com/x',
        'http://localhost:8080/i.json',
        'http://127.0.0.1/i.json',
        'http://127.1.2.3/i.json',
        'http://[::1]:9/i.json',
        'http://app.localhost/i.json',
      ]) {
        expect(isAllowedPackUrl(Uri.parse(u)), isTrue, reason: u);
      }
      for (final u in [
        'http://example.org/i.json',
        'http://192.168.1.5/i.json', // the LAN is not trusted for packs
        'http://127.0.0.1.evil.example/i.json',
        'http://localhost.evil.example/i.json',
        'http://0x7f000001/i.json',
        'ftp://example.org/i.json',
        'file:///etc/passwd',
        'data:application/json,{}',
        'https://user:pw@example.org/i.json',
        '/relative/i.json',
      ]) {
        expect(isAllowedPackUrl(Uri.parse(u)), isFalse, reason: u);
      }
      final page = Uri.parse('http://192.168.1.5:8080/tosk/');
      expect(isAllowedPackUrl(Uri.parse('http://192.168.1.5:8080/tosk/packs/index.json'), sameOrigin: page), isTrue);
      expect(isAllowedPackUrl(Uri.parse('http://192.168.1.5:8081/x'), sameOrigin: page), isFalse);
    });

    test('AI URLs', () {
      for (final u in [
        'https://api.anthropic.com',
        'http://localhost:11434/v1',
        'http://127.0.0.1:1234/v1',
        'http://[::1]:1234',
        'http://192.168.1.10:8080/v1',
        'http://10.0.0.2/v1',
        'http://172.20.1.1/v1',
        'http://169.254.1.1/v1',
        'http://[fd00::1]/v1',
        'http://[fe80::1]/v1',
        'http://[::ffff:192.168.0.1]/v1',
        'http://gpu-box.local:8000/v1',
      ]) {
        expect(isAllowedAiUrl(Uri.parse(u)), isTrue, reason: u);
      }
      for (final u in [
        'http://api.example.com/v1',
        'http://8.8.8.8/v1',
        'http://172.32.0.1/v1',
        'http://192.168.1.10.nip.io/v1',
        'http://[2001:db8::1]/v1',
        'ftp://localhost/v1',
        'https://user:pw@api.example.com',
      ]) {
        expect(isAllowedAiUrl(Uri.parse(u)), isFalse, reason: u);
      }
    });
  });

  test('an http index on a remote host is refused without a request', () async {
    final s = setup((_) async => http.Response(index([]), 200), indexUrl: 'http://example.org/index.json');
    await expectLater(s.src.fetchIndex(), refused(PackDownloadError.http));
    expect(s.requests, isEmpty);
  });

  test('the page origin may be plain http on the web', () async {
    final s = setup(
      (_) async => http.Response(index([]), 200),
      indexUrl: 'http://192.168.1.5:8080/tosk/packs/index.json',
      sameOrigin: Uri.parse('http://192.168.1.5:8080/tosk/'),
    );
    expect((await s.src.fetchIndex()).courses, isEmpty);
  });

  test('a redirect to http is refused (index and pack)', () async {
    final s = setup((u) async {
      if (u.path == '/index.json') {
        return http.Response(index([entry('https://example.org/it.sqlite')]), 200);
      }
      if (u.path == '/latest.json') return http.Response('', 302, headers: {'location': 'http://example.org/index.json'});
      if (u.scheme == 'https' && u.path == '/it.sqlite') {
        return http.Response('', 302, headers: {'location': 'http://cdn.example.org/it.sqlite'});
      }
      return http.Response.bytes(v2, 200);
    });
    await expectLater(s.src.fetchIndex(url: Uri.parse('https://example.org/latest.json')), refused(PackDownloadError.http));
    final idx = await s.src.fetchIndex();
    await expectLater(s.src.download(idx['it']!), refused(PackDownloadError.http));
    expect(s.requests.where((u) => u.scheme == 'http'), isEmpty);
    expect(await s.src.available(), isEmpty);
  });

  test('an http pack URL in an https index is refused', () async {
    final s = setup((u) async {
      if (u.path == '/index.json') return http.Response(index([entry('http://example.org/it.sqlite')]), 200);
      return http.Response.bytes(v2, 200);
    });
    final idx = await s.src.fetchIndex();
    await expectLater(s.src.download(idx['it']!), refused(PackDownloadError.http));
    expect(s.requests.where((u) => u.scheme == 'http'), isEmpty);
  });

  test('an oversized index.json is refused', () async {
    final big = index([entry('https://example.org/it.sqlite', extra: {'pad': 'x' * (kMaxIndexBytes + 10)})]);
    final s = setup((_) async => http.Response(big, 200));
    await expectLater(s.src.fetchIndex(), refused(PackDownloadError.corrupt));
  });

  test('implausible pack sizes are refused when the index is read', () {
    for (final extra in [
      {'size': kMaxPackBytes + 1},
      {'size': 0},
      {'size': -5},
      {'gz_size': kMaxPackBytes + 1, 'gz_sha256': 'ab', 'web_url': 'it.sqlite.gz'},
    ]) {
      expect(
        () => RemoteIndex.parse(index([entry('https://example.org/it.sqlite', extra: extra)])),
        throwsFormatException,
        reason: '$extra',
      );
    }
  });

  test('a gzip bomb is refused without expanding past the pack size', () async {
    // 64 MB of zeros gzip to about 64 KB; the pack is announced at its real size.
    final bomb = Uint8List.fromList(gzip.encode(Uint8List(64 << 20)));
    expect(bomb.length, lessThan(1 << 20));
    final s = setup((u) async {
      if (u.path == '/index.json') {
        return http.Response(
          index([
            entry(
              'https://example.org/it.sqlite',
              extra: {'web_url': 'it.sqlite.gz', 'gz_sha256': _sha(bomb), 'gz_size': bomb.length},
            ),
          ]),
          200,
        );
      }
      if (u.path == '/it.sqlite.gz') return http.Response.bytes(bomb, 200);
      return http.Response('', 404);
    }, preferWeb: true);
    final idx = await s.src.fetchIndex();
    await expectLater(s.src.download(idx['it']!), refused(PackDownloadError.corrupt));
    expect(await s.src.available(), isEmpty);
  });
}
