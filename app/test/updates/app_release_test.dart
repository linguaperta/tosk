// App releases (the update notice of sideloaded builds): versions from tags,
// comparison including pre-releases, the newest newer release, the APK that
// fits the device, and the notes excerpt.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/app_version.dart';
import 'package:tosk/updates/app_release.dart';

AppVersion v(String s) => AppVersion.parse(s)!;

Map<String, Object?> releaseJson(
  String tag, {
  bool prerelease = true,
  bool draft = false,
  String? name,
  String body = '',
  List<String> assets = const [],
  String? published,
}) => {
  'tag_name': tag,
  'name': name ?? 'Release $tag',
  'body': body,
  'html_url': 'https://github.com/linguaperta/tosk/releases/tag/$tag',
  'prerelease': prerelease,
  'draft': draft,
  'published_at': ?published,
  'assets': [
    for (final a in assets)
      {'name': a, 'browser_download_url': 'https://github.com/linguaperta/tosk/releases/download/$tag/$a', 'size': 1},
  ],
};

AppRelease release(String tag, {List<String> assets = const [], String body = '', bool draft = false}) =>
    AppRelease.fromJson(
      releaseJson(tag, assets: assets, body: body, draft: draft),
      repo: 'linguaperta/tosk',
    )!;

void main() {
  group('AppVersion', () {
    test('parses versions, build numbers and pre-releases', () {
      expect(v('0.7.6'), const AppVersion(0, 7, 6));
      expect(v('0.7.6+19'), const AppVersion(0, 7, 6), reason: 'build metadata is ignored');
      expect(v('0.8'), const AppVersion(0, 8, 0));
      expect(v('1.0.0-rc.1').pre, ['rc', '1']);
      expect('${v('1.0.0-rc.1+3')}', '1.0.0-rc.1');
      for (final bad in ['', 'x', '1', '1.2.3.4', 'v1.2.3', '1.2.x', '1.2.3-']) {
        expect(AppVersion.parse(bad), isNull, reason: bad);
      }
      // This build's version parses (the notice compares against it).
      expect(AppVersion.parse(kAppVersion), isNotNull);
    });

    test('tags: preview-X.Y.Z and vX.Y.Z; other tags are not app releases', () {
      expect(AppVersion.fromTag('preview-0.7.6'), v('0.7.6'));
      expect(AppVersion.fromTag('v0.7.6'), v('0.7.6'));
      expect(AppVersion.fromTag('V1.2.3'), v('1.2.3'));
      expect(AppVersion.fromTag('preview0.7.7'), v('0.7.7'));
      expect(AppVersion.fromTag('0.7.6'), v('0.7.6'));
      expect(AppVersion.fromTag('preview-0.8.0-beta.2'), v('0.8.0-beta.2'));
      expect(AppVersion.fromTag('v0.8.0-rc.1'), v('0.8.0-rc.1'));
      expect(AppVersion.fromTag('packs-20261024'), isNull);
      expect(AppVersion.fromTag('nightly'), isNull);
    });

    test('compares numerically, with pre-releases before their release', () {
      final sorted = [
        '0.7.10',
        '0.7.6',
        '1.0.0',
        '0.7.9',
        '1.0.0-rc.2',
        '1.0.0-alpha',
        '1.0.0-rc.10',
        '1.0.0-alpha.1',
        '1.0.0-beta',
        '0.10.0',
      ].map(v).toList()..sort();
      expect(sorted.map((e) => '$e'), [
        '0.7.6',
        '0.7.9',
        '0.7.10',
        '0.10.0',
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-beta',
        '1.0.0-rc.2',
        '1.0.0-rc.10',
        '1.0.0',
      ]);
      expect(v('0.7.7') > v('0.7.6+19'), isTrue);
      expect(v('0.7.6') > v('0.7.6+19'), isFalse);
      expect(v('0.8.0-rc.1') > v('0.7.6'), isTrue);
      expect(v('0.8.0-rc.1') < v('0.8.0'), isTrue);
      expect(v('0.8.0-rc.1').isPreRelease, isTrue);
    });
  });

  group('releases from the API', () {
    test('reads the fields, skips non-app tags and keeps only GitHub https links', () {
      final body = jsonEncode([
        releaseJson(
          'preview-0.7.6',
          body: 'Notes',
          assets: ['tosk-preview-7.6-arm64.apk'],
          published: '2026-10-24T21:16:08Z',
        ),
        releaseJson('packs-20261024'),
        {'tag_name': 3},
        'junk',
        {
          ...releaseJson('preview-0.7.7', assets: ['evil.apk']),
          'html_url': 'http://example.com/x',
          'assets': [
            {'name': 'evil.apk', 'browser_download_url': 'https://example.com/evil.apk'},
            {'name': 'plain.apk', 'browser_download_url': 'http://github.com/plain.apk'},
          ],
        },
      ]);
      final list = AppRelease.listFromJson(body, repo: 'linguaperta/tosk');
      expect(list.map((r) => r.tag), ['preview-0.7.6', 'preview-0.7.7']);
      final r = list.first;
      expect(r.version, v('0.7.6'));
      expect(r.title, 'Release preview-0.7.6');
      expect(r.notes, 'Notes');
      expect(r.prerelease, isTrue);
      expect(r.publishedAt, DateTime.utc(2026, 10, 24, 21, 16, 8));
      expect(r.assets.single.url.host, 'github.com');
      final bad = list.last;
      expect(bad.page, Uri.parse('https://github.com/linguaperta/tosk/releases/tag/preview-0.7.7'));
      expect(bad.assets, isEmpty, reason: 'only https links on GitHub');
      expect(() => AppRelease.listFromJson('{}', repo: 'x/y'), throwsFormatException);
    });

    test('round-trips through the cache JSON', () {
      final r = release('preview-0.7.7', assets: ['tosk-preview-7.7-arm64.apk'], body: 'Hello');
      final back = AppRelease.fromJson(jsonDecode(jsonEncode(r.toJson())), repo: 'linguaperta/tosk')!;
      expect(back.version, r.version);
      expect(back.title, r.title);
      expect(back.notes, 'Hello');
      expect(back.page, r.page);
      expect(back.assets.single.url, r.assets.single.url);
    });

    test('a release without a title shows its tag', () {
      final r = AppRelease.fromJson({...releaseJson('v0.9.0'), 'name': ''}, repo: 'linguaperta/tosk')!;
      expect(r.title, 'v0.9.0');
    });
  });

  group('pickUpdate', () {
    final current = v('0.7.6+19');

    test('the newest newer release; previews (pre-releases) count; drafts do not', () {
      final releases = [
        release('preview-0.7.6'),
        release('preview-0.7.4'),
        release('preview-0.7.8', draft: true),
        release('preview-0.7.7'),
        release('v0.7.5'),
      ];
      expect(pickUpdate(releases, current)?.tag, 'preview-0.7.7');
      expect(pickUpdate(releases.take(2), current), isNull, reason: 'up to date');
      expect(pickUpdate(const [], current), isNull);
    });

    test('a release beats its own pre-release; v and preview tags mix', () {
      expect(pickUpdate([release('v0.8.0-rc.1'), release('preview-0.8.0')], current)?.tag, 'preview-0.8.0');
      expect(pickUpdate([release('v0.8.0-rc.1')], current)?.tag, 'v0.8.0-rc.1');
      expect(pickUpdate([release('v0.8.0-rc.1')], v('0.8.0')), isNull);
    });
  });

  group('pickAsset', () {
    final perAbi = release(
      'v0.8.0',
      assets: [
        'app-armeabi-v7a-release.apk',
        'app-arm64-v8a-release.apk',
        'app-x86_64-release.apk',
        'tosk-windows-x64.zip',
        'tosk-ios-unsigned.ipa',
      ],
    );

    test('the APK for the device ABI, in the device order', () {
      expect(
        pickAsset(perAbi, UpdatePlatform.android, abis: ['arm64-v8a', 'armeabi-v7a'])?.name,
        'app-arm64-v8a-release.apk',
      );
      expect(
        pickAsset(perAbi, UpdatePlatform.android, abis: ['armeabi-v7a', 'armeabi'])?.name,
        'app-armeabi-v7a-release.apk',
      );
      expect(pickAsset(perAbi, UpdatePlatform.android, abis: ['x86_64', 'arm64-v8a'])?.name, 'app-x86_64-release.apk');
    });

    test('the preview naming (arm64 only): other devices get the release page', () {
      final preview = release('preview-0.7.7', assets: ['tosk-preview-7.7-arm64.apk']);
      expect(pickAsset(preview, UpdatePlatform.android, abis: ['arm64-v8a'])?.name, 'tosk-preview-7.7-arm64.apk');
      expect(pickAsset(preview, UpdatePlatform.android, abis: ['armeabi-v7a']), isNull);
      expect(downloadUrl(preview, UpdatePlatform.android, abis: ['armeabi-v7a']), preview.page);
      expect(downloadUrl(preview, UpdatePlatform.android), preview.page, reason: 'ABI unknown');
    });

    test('a universal APK when no ABI matches', () {
      final r = release('v0.8.0', assets: ['tosk-0.8.0.apk', 'tosk-0.8.0-arm64.apk']);
      expect(pickAsset(r, UpdatePlatform.android, abis: ['armeabi-v7a'])?.name, 'tosk-0.8.0.apk');
      expect(pickAsset(r, UpdatePlatform.android, abis: ['arm64-v8a'])?.name, 'tosk-0.8.0-arm64.apk');
    });

    test('desktop archives; nothing for other platforms', () {
      expect(pickAsset(perAbi, UpdatePlatform.windows)?.name, 'tosk-windows-x64.zip');
      expect(pickAsset(perAbi, UpdatePlatform.macos), isNull);
      expect(pickAsset(perAbi, UpdatePlatform.linux), isNull);
      expect(pickAsset(perAbi, UpdatePlatform.other), isNull);
      expect(downloadUrl(perAbi, UpdatePlatform.macos), perAbi.page);
      expect(
        pickAsset(release('v1.0.0', assets: ['tosk-macos.dmg', 'tosk-linux.tar.gz']), UpdatePlatform.linux)?.name,
        'tosk-linux.tar.gz',
      );
    });
  });

  test('notes excerpt: the first lines as plain text, capped', () {
    final r = release(
      'v1.0.0',
      body: '## Highlights\n\n- **Topic trees** with `carved` names\n- [Web app](https://x) fixes\n\n<!-- hidden -->\n* Third\n* Fourth',
    );
    expect(r.notesExcerpt(), 'Highlights\n• Topic trees with carved names\n• Web app fixes');
    expect(r.notesExcerpt(maxLines: 5), contains('• Fourth'));
    final long = release('v1.0.0', body: 'a' * 500);
    expect(long.notesExcerpt(), hasLength(280));
    expect(long.notesExcerpt(), endsWith('…'));
    expect(release('v1.0.0').notesExcerpt(), isEmpty);
  });
}
