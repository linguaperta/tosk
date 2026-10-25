/// Settings → About: Tosk and the version, the course's content credits, the
/// privacy policy, the source code, the open-source licences, "Show welcome
/// again", and the hidden developer options (seven taps on the version, as
/// on Android: the debug screen).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_version.dart';
import '../../providers.dart';
import '../brand/tosk.dart';
import '../common/external_link.dart';
import '../common/links.dart';
import '../routes.dart';
import '../updates/update_notice.dart';
import 'setting_keys.dart';
import 'settings_parts.dart';

/// Whether the developer options show (device-only [SettingKeys.developerOptions]).
final developerOptionsProvider = AsyncNotifierProvider<DeveloperOptions, bool>(DeveloperOptions.new);

class DeveloperOptions extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      (await ref.watch(progressStoreProvider).getSetting(SettingKeys.developerOptions)) == 'true';

  Future<void> set(bool on) async {
    state = AsyncData(on);
    await ref.read(progressStoreProvider).setSetting(SettingKeys.developerOptions, on ? 'true' : null);
  }
}

/// Taps on the version that turn the developer options on.
const kDeveloperTaps = 7;

bool _licencesAdded = false;

/// Adds the licences that aren't a Dart package's (the app itself, the
/// Gelasio font, the course content) to the licence page. Idempotent.
void registerAppLicences() {
  if (_licencesAdded) return;
  _licencesAdded = true;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['tosk'], '''
tosk is free software under the Apache License, Version 2.0. The source code is at $kSourceUrl.

The name "tosk" and the Tosk art are not covered by that licence: the art is licensed CC BY-NC-ND 4.0 (see TRADEMARKS.md in the source code).

Course content is licensed by its authors, shown with each course (the official courses: CC BY-SA 4.0, with data from Wiktionary, FrequencyWords and Tatoeba).''');
    try {
      yield LicenseEntryWithLineBreaks(['Gelasio'], await rootBundle.loadString('assets/brand/fonts/OFL.txt'));
    } on Object {
      // Not bundled (tests).
    }
  });
}

class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key, this.attribution});

  /// The open course's content credits.
  final String? attribution;

  @override
  ConsumerState<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<AboutSection> {
  int _taps = 0;

  Future<void> _open(String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await ref.read(externalLinkOpenerProvider)(Uri.parse(url));
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text("Couldn't open the browser. The address is $url")));
  }

  void _versionTapped(bool on) {
    if (on) return;
    _taps++;
    final left = kDeveloperTaps - _taps;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (left <= 0) {
      _taps = 0;
      unawaited(ref.read(developerOptionsProvider.notifier).set(true));
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Developer options are on (at the end of Settings)')));
    } else if (left <= 3) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        content: Text('$left more tap${left == 1 ? '' : 's'} for the developer options'),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final developer = ref.watch(developerOptionsProvider).value ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: const ValueKey('about-brand'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              key: const ValueKey('about-version'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _versionTapped(developer),
              child: const BrandLockup(caption: 'Version $kAppVersion · free and offline-first'),
            ),
          ),
        ),
        // Sideloaded builds: GitHub Releases (the web updates itself).
        const UpdateCheckTile(),
        if (widget.attribution case final a? when a.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Course content'),
            subtitle: Text(a),
          ),
        ListTile(
          key: const ValueKey('about-privacy'),
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy policy'),
          subtitle: const Text('What is stored where. No ads, no tracking'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => unawaited(_open(kPrivacyPolicyUrl)),
        ),
        ListTile(
          key: const ValueKey('about-source'),
          leading: const Icon(Icons.code),
          title: const Text('Source code'),
          subtitle: Text('${kSourceUrl.replaceFirst('https://', '')} · Apache-2.0'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => unawaited(_open(kSourceUrl)),
        ),
        ListTile(
          key: const ValueKey('about-licences'),
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-source licences'),
          subtitle: const Text('The software and fonts tosk is built with'),
          onTap: () {
            registerAppLicences();
            showLicensePage(
              context: context,
              applicationName: 'tosk',
              applicationVersion: kAppVersion,
              applicationLegalese: 'Apache-2.0. The name and the Tosk art are not part of the licence.',
            );
          },
        ),
        ListTile(
          key: const ValueKey('show-welcome'),
          leading: const Icon(Icons.waving_hand_outlined),
          title: const Text('Show welcome again'),
          subtitle: const Text('Who Tosk is, how tosk works, sign-in and the Claude key'),
          onTap: () => context.push(Routes.welcome()),
        ),
        if (developer) ...[
          const SettingsHeader('Developer options'),
          ListTile(
            key: const ValueKey('open-debug'),
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Debug'),
            subtitle: const Text('Courses, skills and strength'),
            onTap: () => context.push(Routes.debug),
          ),
          SwitchListTile(
            key: const ValueKey('developer-options'),
            secondary: const Icon(Icons.developer_mode_outlined),
            title: const Text('Show developer options'),
            value: true,
            onChanged: (v) => unawaited(ref.read(developerOptionsProvider.notifier).set(v)),
          ),
        ],
      ],
    );
  }
}
