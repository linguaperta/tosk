// Golden images of the first-run welcome: every page in black & white and the
// first page in colour. Test font (Ahem), like bw_golden_test.dart. Update with:
//   flutter test --update-goldens test/ui/welcome_golden_test.dart
// Rendered on Windows; CI (Linux) skips them with --exclude-tags golden.
@Tags(['golden'])
library;

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/sync/sync_providers.dart';
import 'package:tosk/ui/settings/setting_keys.dart';

import 'helpers.dart';
import 'welcome_test.dart' show fakeSync, freshStore, key;

Future<void> _golden(WidgetTester tester, String name) async {
  // Tosk's PNGs load on real futures.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
  await expectLater(key('app-root'), matchesGoldenFile('goldens/welcome_$name.png'));
}

void main() {
  testWidgets('black & white pages', (tester) async {
    final service = await fakeSync(tester);
    await pumpApp(
      tester,
      size: const Size(390, 844),
      store: freshStore({SettingKeys.display: 'bw'}),
      overrides: [syncServiceProvider.overrideWithValue(service)],
    );
    await _golden(tester, 'bw_tosk');
    await tapKey(tester, 'welcome-next');
    await _golden(tester, 'bw_how');
    await tapKey(tester, 'welcome-next');
    await _golden(tester, 'bw_sign_in');
    await tapKey(tester, 'welcome-sync-skip');
    await _golden(tester, 'bw_key');
  });

  testWidgets('colour first page', (tester) async {
    await pumpApp(tester, size: const Size(390, 844), store: freshStore());
    await _golden(tester, 'tosk');
  });
}
