// The web update path with a fake browser: a new service worker plus a
// different deployed build offers a reload; the same build (a fresh load
// right after a deploy), offline or no file stays quiet; the one-time
// "What's new in X.Y.Z" after the version changed.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/updates/app_release.dart';
import 'package:tosk/updates/update_check.dart';
import 'package:tosk/updates/web_update.dart';

import '../ui/helpers.dart' show TestProgressStore;

/// The browser: [deployed] is what `whats_new.json` says (null: offline).
class FakeWebUpdateSource implements WebUpdateSource {
  FakeWebUpdateSource({this.deployed, this.updatedBefore = false});

  WhatsNew? deployed;
  bool updatedBefore;
  int fetches = 0;
  int reloads = 0;
  final _ctl = StreamController<void>.broadcast();

  /// The new deploy's worker takes over.
  void workerTakesOver() => _ctl.add(null);

  @override
  Stream<void> get workerUpdated => _ctl.stream;

  @override
  bool get workerUpdatedBefore => updatedBefore;

  @override
  Future<WhatsNew?> fetchWhatsNew() async {
    fetches++;
    return deployed;
  }

  @override
  void reload() => reloads++;
}

WhatsNew whatsNew(String version, {String build = '', String notes = '- Better things'}) =>
    WhatsNew(version: AppVersion.parse(version)!, build: build, title: 'Preview $version', notes: notes);

ProviderContainer containerFor(
  FakeWebUpdateSource source, {
  TestProgressStore? store,
  String version = '0.7.6',
  String build = 'aaa111',
}) {
  final c = ProviderContainer(
    overrides: [
      progressStoreProvider.overrideWithValue(store ?? TestProgressStore()),
      webUpdateSourceProvider.overrideWithValue(source),
      currentAppVersionProvider.overrideWithValue(AppVersion.parse(version)!),
      buildIdProvider.overrideWithValue(build),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('parses whats_new.json; junk is no info', () {
    final w = WhatsNew.parse(
      '{"version":"0.7.7","build":"b2","title":"Preview 7.7","notes":"Hi","url":"https://github.com/x"}',
    )!;
    expect('${w.version}', '0.7.7');
    expect(w.build, 'b2');
    expect(w.title, 'Preview 7.7');
    expect(w.url, Uri.parse('https://github.com/x'));
    expect(WhatsNew.parse('{"version":"x"}'), isNull);
    expect(WhatsNew.parse('<html>'), isNull);
    expect(WhatsNew.parse('[]'), isNull);
    expect(WhatsNew.parse('{"version":"0.7.7","url":"javascript:alert(1)"}')!.url, isNull);
  });

  test('a new worker with another build: reload offered; Later hides it; Reload reloads', () async {
    final source = FakeWebUpdateSource(deployed: whatsNew('0.7.7', build: 'bbb222'));
    final c = containerFor(source, store: TestProgressStore(settings: {kWhatsNewSeenKey: '0.7.6'}));
    await c.read(webUpdateProvider.notifier).startup();
    expect(c.read(webUpdateProvider).showReload, isFalse, reason: 'nothing happened yet');
    source.workerTakesOver();
    await settle();
    await settle();
    final s = c.read(webUpdateProvider);
    expect(s.showReload, isTrue);
    expect('${s.deployed?.version}', '0.7.7');
    c.read(webUpdateProvider.notifier).later();
    expect(c.read(webUpdateProvider).showReload, isFalse);
    // The next deploy offers it again.
    source.deployed = whatsNew('0.7.8', build: 'ccc333');
    source.workerTakesOver();
    await settle();
    await settle();
    expect(c.read(webUpdateProvider).showReload, isTrue);
    c.read(webUpdateProvider.notifier).reload();
    expect(source.reloads, 1);
  });

  test('the same build (a fresh load right after the deploy) stays quiet', () async {
    final source = FakeWebUpdateSource(deployed: whatsNew('0.7.6', build: 'aaa111'));
    final c = containerFor(source, store: TestProgressStore(settings: {kWhatsNewSeenKey: '0.7.6'}));
    await c.read(webUpdateProvider.notifier).startup();
    source.workerTakesOver();
    await settle();
    await settle();
    expect(c.read(webUpdateProvider).showReload, isFalse);
    expect(source.fetches, 1);
  });

  test('a same-version redeploy with another build still offers the reload', () async {
    final source = FakeWebUpdateSource(deployed: whatsNew('0.7.6', build: 'fff999'));
    final c = containerFor(source, store: TestProgressStore(settings: {kWhatsNewSeenKey: '0.7.6'}));
    await c.read(webUpdateProvider.notifier).startup();
    source.workerTakesOver();
    await settle();
    await settle();
    expect(c.read(webUpdateProvider).showReload, isTrue);
  });

  test('offline or no whats_new.json: no notice', () async {
    final source = FakeWebUpdateSource();
    final c = containerFor(source, store: TestProgressStore(settings: {kWhatsNewSeenKey: '0.7.6'}));
    await c.read(webUpdateProvider.notifier).startup();
    source.workerTakesOver();
    await settle();
    await settle();
    expect(c.read(webUpdateProvider).showReload, isFalse);
  });

  test('local builds (no build id) compare versions', () async {
    final source = FakeWebUpdateSource(deployed: whatsNew('0.7.7'), updatedBefore: true);
    final c = containerFor(
      source,
      build: '',
      store: TestProgressStore(settings: {kWhatsNewSeenKey: '0.7.6'}),
    );
    await c.read(webUpdateProvider.notifier).startup();
    await settle();
    await settle();
    expect(c.read(webUpdateProvider).showReload, isTrue, reason: 'the worker changed before the app listened');

    final same = FakeWebUpdateSource(deployed: whatsNew('0.7.6'), updatedBefore: true);
    final c2 = containerFor(
      same,
      build: '',
      store: TestProgressStore(settings: {kWhatsNewSeenKey: '0.7.6'}),
    );
    await c2.read(webUpdateProvider.notifier).startup();
    await settle();
    await settle();
    expect(c2.read(webUpdateProvider).showReload, isFalse);
  });

  group("what's new", () {
    test('first visit: nothing to show, the version is remembered', () async {
      final store = TestProgressStore();
      final source = FakeWebUpdateSource(deployed: whatsNew('0.7.6'));
      final c = containerFor(source, store: store);
      await c.read(webUpdateProvider.notifier).startup();
      expect(c.read(webUpdateProvider).whatsNew, isNull);
      expect(store.settings[kWhatsNewSeenKey], '0.7.6');
      expect(source.fetches, 0);
    });

    test('after an update (the reload): once, then never again', () async {
      final store = TestProgressStore(settings: {kWhatsNewSeenKey: '0.7.6'});
      final source = FakeWebUpdateSource(deployed: whatsNew('0.7.7', build: 'aaa111'));
      final c = containerFor(source, store: store, version: '0.7.7');
      await c.read(webUpdateProvider.notifier).startup();
      expect('${c.read(webUpdateProvider).whatsNew?.version}', '0.7.7');
      await c.read(webUpdateProvider.notifier).whatsNewShown();
      expect(c.read(webUpdateProvider).whatsNew, isNull);
      expect(store.settings[kWhatsNewSeenKey], '0.7.7');

      final again = containerFor(source, store: store, version: '0.7.7');
      await again.read(webUpdateProvider.notifier).startup();
      expect(again.read(webUpdateProvider).whatsNew, isNull);
    });

    test('no notes yet, another version deployed, or offline: nothing now, tried again next start', () async {
      for (final deployed in [whatsNew('0.7.7', notes: '  '), whatsNew('0.7.8'), null]) {
        final store = TestProgressStore(settings: {kWhatsNewSeenKey: '0.7.6'});
        final c = containerFor(
          FakeWebUpdateSource(deployed: deployed),
          store: store,
          version: '0.7.7',
        );
        await c.read(webUpdateProvider.notifier).startup();
        expect(c.read(webUpdateProvider).whatsNew, isNull, reason: '$deployed');
        expect(store.settings[kWhatsNewSeenKey], '0.7.6');
      }
    });
  });

  test('not the web: nothing listens', () async {
    final c = ProviderContainer(
      overrides: [
        progressStoreProvider.overrideWithValue(TestProgressStore()),
        webUpdateSourceProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    await c.read(webUpdateProvider.notifier).startup();
    expect(c.read(webUpdateProvider).showReload, isFalse);
    expect(c.read(updateModeProvider), UpdateMode.none, reason: 'flutter test');
  });
}
