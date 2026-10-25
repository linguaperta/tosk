/// The web app's update path (GitHub Pages): no GitHub check. A new deploy
/// changes `sw.js` (the Pages workflow stamps the commit into it), the
/// browser installs the new service worker, and `index.html` tells the app
/// (`tosk-update` event). The app then reads `whats_new.json` next to the
/// page: when its build differs from the running one, the notice says "tosk
/// was updated" with a Reload button. After the reload, a one-time "What's
/// new in X.Y.Z" sheet shows that file's notes.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import '../providers.dart';
import 'app_release.dart';
import 'update_check.dart';
import 'web_update_platform.dart';

/// The commit this build was made from (`--dart-define=TOSK_BUILD=...`, set by
/// the Pages workflow); empty for local builds.
const String kBuildId = String.fromEnvironment('TOSK_BUILD');

/// `whats_new.json`, written by the Pages workflow next to `index.html`.
@immutable
class WhatsNew {
  const WhatsNew({required this.version, this.build = '', this.title = '', this.notes = '', this.url});

  final AppVersion version;

  /// The deployed commit (empty when unknown).
  final String build;
  final String title;

  /// Release notes (markdown); empty when the release has none yet.
  final String notes;
  final Uri? url;

  static WhatsNew? parse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final version = AppVersion.parse('${json['version'] ?? ''}');
      if (version == null) return null;
      final url = Uri.tryParse('${json['url'] ?? ''}');
      return WhatsNew(
        version: version,
        build: '${json['build'] ?? ''}',
        title: '${json['title'] ?? ''}',
        notes: '${json['notes'] ?? ''}',
        url: url != null && url.scheme == 'https' ? url : null,
      );
    } on FormatException {
      return null;
    }
  }
}

/// The browser side: the service worker's signal, the deployed file, reload.
abstract interface class WebUpdateSource {
  /// Fires when a new service worker took over (a new deploy is live).
  Stream<void> get workerUpdated;

  /// Whether that already happened before the app started listening.
  bool get workerUpdatedBefore;

  /// The deployed `whats_new.json` (revalidated, not from the HTTP cache);
  /// null when it is missing or offline.
  Future<WhatsNew?> fetchWhatsNew();

  /// Reloads the page (the new build).
  void reload();
}

/// The browser on the web, null elsewhere (tests inject fakes).
final webUpdateSourceProvider = Provider<WebUpdateSource?>(
  (ref) => ref.watch(updateModeProvider) == UpdateMode.web ? createWebUpdateSource() : null,
);

/// This build's commit (tests override it).
final buildIdProvider = Provider<String>((ref) => kBuildId);

/// Device-only setting: the version whose "What's new" was shown (or that
/// the first visit started on).
const String kWhatsNewSeenKey = 'web.whats_new_seen';

@immutable
class WebUpdateState {
  const WebUpdateState({this.reloadReady = false, this.deployed, this.dismissed = false, this.whatsNew});

  /// A newer build is live: reload to get it.
  final bool reloadReady;
  final WhatsNew? deployed;

  /// "Later" on the reload notice (until the next new build).
  final bool dismissed;

  /// Notes to show once ("What's new in X.Y.Z"), until [WebUpdate.whatsNewShown].
  final WhatsNew? whatsNew;

  bool get showReload => reloadReady && !dismissed;

  WebUpdateState copyWith({bool? reloadReady, WhatsNew? deployed, bool? dismissed, WhatsNew? Function()? whatsNew}) =>
      WebUpdateState(
        reloadReady: reloadReady ?? this.reloadReady,
        deployed: deployed ?? this.deployed,
        dismissed: dismissed ?? this.dismissed,
        whatsNew: whatsNew == null ? this.whatsNew : whatsNew(),
      );
}

final webUpdateProvider = NotifierProvider<WebUpdate, WebUpdateState>(WebUpdate.new);

class WebUpdate extends Notifier<WebUpdateState> {
  StreamSubscription<void>? _sub;
  bool _started = false;

  @override
  WebUpdateState build() {
    ref.onDispose(() => _sub?.cancel());
    return const WebUpdateState();
  }

  ProgressStore get _store => ref.read(progressStoreProvider);

  /// On app start: listen for new deploys, and show this version's notes
  /// once if it is new on this browser.
  Future<void> startup() async {
    final source = ref.read(webUpdateSourceProvider);
    if (_started || source == null) return;
    _started = true;
    _sub = source.workerUpdated.listen((_) => unawaited(_onWorkerUpdated()));
    if (source.workerUpdatedBefore) unawaited(_onWorkerUpdated());
    await _whatsNewOnStart(source);
  }

  Future<void> _onWorkerUpdated() async {
    final source = ref.read(webUpdateSourceProvider);
    if (source == null) return;
    final deployed = await source.fetchWhatsNew();
    // Unknown (offline, no file): stay quiet. A worker that came with this
    // very page (a fresh load right after a deploy) is the same build.
    if (deployed == null || !_isNewer(deployed)) {
      debugPrint('[update] new service worker, same build (${deployed?.build ?? 'unknown'})');
      return;
    }
    debugPrint('[update] build ${deployed.build} (${deployed.version}) is live: offering a reload');
    state = state.copyWith(reloadReady: true, deployed: deployed, dismissed: false);
  }

  bool _isNewer(WhatsNew deployed) {
    final build = ref.read(buildIdProvider);
    if (build.isNotEmpty && deployed.build.isNotEmpty) return deployed.build != build;
    return deployed.version > ref.read(currentAppVersionProvider);
  }

  Future<void> _whatsNewOnStart(WebUpdateSource source) async {
    final current = ref.read(currentAppVersionProvider);
    try {
      final seen = await _store.getSetting(kWhatsNewSeenKey);
      if (seen == null) {
        // A first visit: nothing is "new" yet.
        await _store.setSetting(kWhatsNewSeenKey, '$current');
        return;
      }
      if (seen == '$current') return;
      final info = await source.fetchWhatsNew();
      // Another version's notes (a stale page) or none yet: try next start.
      if (info == null || info.version != current || info.notes.trim().isEmpty) return;
      state = state.copyWith(whatsNew: () => info);
    } on Object catch (e) {
      debugPrint('[update] what\'s new unavailable: $e');
    }
  }

  /// The "What's new" sheet was shown: never again for this version.
  Future<void> whatsNewShown() async {
    final info = state.whatsNew;
    state = state.copyWith(whatsNew: () => null);
    if (info != null) await _store.setSetting(kWhatsNewSeenKey, '${info.version}');
  }

  void reload() => ref.read(webUpdateSourceProvider)?.reload();

  void later() => state = state.copyWith(dismissed: true);
}
