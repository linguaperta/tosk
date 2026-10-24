// Reports to the developer in the app: a submitted flag is uploaded when
// signed in (and the sheet says where flags go), Settings → Send feedback
// (send when signed in; otherwise copy or an email draft), Settings → About
// (privacy policy, source, licences, the hidden developer options), the
// Unverified badge's explanation, and the sync section's privacy link.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/sync/fake_sync_backend.dart';
import 'package:tosk/sync/report_outbox.dart';
import 'package:tosk/sync/sync_providers.dart';
import 'package:tosk/sync/sync_service.dart';
import 'package:tosk/ui/common/external_link.dart';
import 'package:tosk/ui/common/links.dart';
import 'package:tosk/ui/feedback/send_feedback_screen.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/shell/course_switcher.dart';

import '../sync/report_outbox_test.dart' show reportingService;
import 'ai_flags_sounds_test.dart' show answerConjPick, scrollSettingsTo;
import 'bw_helpers.dart';
import 'helpers.dart';

const _lab = '/play/lab?skills=present-are&types=conj_pick&length=1';

class Reporting {
  Reporting(this.service, this.server, this.outbox);
  final SyncService service;
  final FakeSyncServer server;
  final InMemoryOutboxStore outbox;
}

/// A sync service (signed in unless [signIn] is false) made outside the fake
/// clock, disposed after the test.
Future<Reporting> reporting(WidgetTester tester, {bool signIn = true}) async {
  late Reporting r;
  await tester.runAsync(() async {
    final (s, server, store) = await reportingService(signIn: signIn);
    r = Reporting(s, server, store);
  });
  addTearDown(r.service.dispose);
  return r;
}

List<Override> withSync(Reporting r, {List<Uri>? opened}) => [
  syncServiceProvider.overrideWithValue(r.service),
  if (opened != null) externalLinkOpenerProvider.overrideWithValue((u) async => (opened..add(u)).isNotEmpty),
];

/// Lets the service's "sync soon" timer fire and the upload finish.
Future<void> letSync(WidgetTester tester) async {
  await tester.pump(SyncService.localChangeDelay + const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  group('flags', () {
    testWidgets('signed in: a submitted flag goes to the developer, and the sheet says so', (tester) async {
      final r = await reporting(tester);
      await pumpApp(tester, initialLocation: _lab, overrides: withSync(r));
      await answerConjPick(tester, wrong: true);
      await tapKey(tester, 'flag-button');
      expect(
        find.text('Submitted flags are sent to the developer and kept on this device.'),
        findsOneWidget,
      );
      await tapKey(tester, 'flag-reason-answer_wrong');
      await tapKey(tester, 'flag-submit');
      expect(find.text('Reported'), findsOneWidget);
      await letSync(tester);
      final sent = r.server.reports.entries.single;
      expect(sent.key, startsWith('feedback/'));
      expect(sent.value['kind'], 'flag');
      expect(sent.value['uid'], 'uid1');
      expect(sent.value['flag'], contains('"reasons":["answer_wrong"]'));
      expect(r.outbox.items, isEmpty);
    });

    testWidgets('signed out: the sheet asks to sign in, and nothing is queued', (tester) async {
      final r = await reporting(tester, signIn: false);
      await pumpApp(tester, initialLocation: _lab, overrides: withSync(r));
      await answerConjPick(tester, wrong: true);
      await tapKey(tester, 'flag-button');
      expect(find.textContaining('Sign in to send flags to the developer automatically'), findsOneWidget);
      await tapKey(tester, 'flag-reason-unclear');
      await tapKey(tester, 'flag-submit');
      expect(r.outbox.items, isEmpty);
      expect(r.server.reports, isEmpty);
    });

    testWidgets('a build without sync keeps the old wording', (tester) async {
      await pumpApp(tester, initialLocation: _lab);
      await answerConjPick(tester, wrong: true);
      await tapKey(tester, 'flag-button');
      expect(find.text('Flags stay on this device. Export them from Settings → Feedback & flags.'), findsOneWidget);
    });
  });

  group('Send feedback', () {
    testWidgets('Settings → Send feedback; signed in: Send with an optional email', (tester) async {
      final r = await reporting(tester);
      await pumpApp(tester, initialLocation: Routes.settings, overrides: withSync(r));
      await scrollSettingsTo(tester, 'open-feedback');
      expect(find.text('Ideas, problems, questions: straight to the developer'), findsOneWidget);
      await tapKey(tester, 'open-feedback');
      expect(find.text('Send feedback'), findsWidgets);
      final send = find.byKey(const ValueKey('feedback-send'));
      expect(tester.widget<ButtonStyleButton>(send).onPressed, isNull, reason: 'nothing written yet');
      await tester.enterText(find.byKey(const ValueKey('feedback-text')), 'The map is lovely.');
      await tester.enterText(find.byKey(const ValueKey('feedback-email')), 'not an address');
      await tester.pumpAndSettle();
      await tapIt(tester, send);
      expect(find.byKey(const ValueKey('feedback-error')), findsOneWidget);
      expect(r.outbox.items, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('feedback-email')), 'me@example.com');
      await tester.pumpAndSettle();
      await tapIt(tester, send);
      expect(find.byKey(const ValueKey('feedback-text')), findsNothing, reason: 'back in Settings');
      expect(find.textContaining('Thank you!'), findsOneWidget);
      await letSync(tester);
      final sent = r.server.reports.values.single;
      expect(sent['kind'], 'general');
      expect(sent['text'], 'The map is lovely.');
      expect(sent['email'], 'me@example.com');
      expect(sent['uid'], 'uid1');
    });

    testWidgets('not signed in: copy the text or open an email draft; sign-in hint with sync', (tester) async {
      final r = await reporting(tester, signIn: false);
      final opened = <Uri>[];
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      await pumpApp(
        tester,
        initialLocation: Routes.feedback,
        overrides: [...withSync(r, opened: opened), feedbackEmailProvider.overrideWithValue('dev@example.org')],
      );
      expect(find.byKey(const ValueKey('feedback-send')), findsNothing);
      expect(find.byKey(const ValueKey('feedback-email')), findsNothing);
      expect(find.byKey(const ValueKey('feedback-sign-in-hint')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('feedback-text')), 'Dark mode please');
      await tester.pumpAndSettle();
      await tapKey(tester, 'feedback-copy');
      expect(copied, startsWith('Dark mode please\n\n— tosk '));
      await tapKey(tester, 'feedback-email-draft');
      expect(opened.single.scheme, 'mailto');
      expect(opened.single.path, 'dev@example.org');
      expect(opened.single.query, contains('body=Dark%20mode%20please'));
      await tapKey(tester, 'feedback-issues');
      expect(opened.last.toString(), kIssuesUrl);
      expect(r.outbox.items, isEmpty);
    });

    testWidgets('no sync and no address: copy only, no hint', (tester) async {
      await pumpApp(tester, initialLocation: Routes.feedback);
      expect(find.byKey(const ValueKey('feedback-email-draft')), findsNothing);
      expect(find.byKey(const ValueKey('feedback-sign-in-hint')), findsNothing);
      expect(find.byKey(const ValueKey('feedback-copy')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final bw in [false, true]) {
      testWidgets('the screen fits a small phone (${bw ? 'black & white' : 'colour'})', (tester) async {
        final r = await reporting(tester);
        await pumpApp(
          tester,
          size: const Size(320, 568),
          initialLocation: Routes.feedback,
          store: bw ? TestProgressStore(settings: const {'ui.display': 'bw'}) : null,
          overrides: withSync(r),
        );
        expect(tester.takeException(), isNull);
        if (bw) await expectGrayscale(tester, 'send feedback');
      });
    }
  });

  group('About', () {
    testWidgets('privacy policy, source, licences; seven taps show the developer options', (tester) async {
      final opened = <Uri>[];
      await pumpApp(
        tester,
        initialLocation: Routes.settings,
        overrides: [externalLinkOpenerProvider.overrideWithValue((u) async => (opened..add(u)).isNotEmpty)],
      );
      await scrollSettingsTo(tester, 'about-privacy');
      expect(find.byKey(const ValueKey('open-debug')), findsNothing, reason: 'hidden from learners');
      await tapKey(tester, 'about-privacy');
      expect(opened.last.toString(), kPrivacyPolicyUrl);
      await scrollSettingsTo(tester, 'about-source');
      await tapKey(tester, 'about-source');
      expect(opened.last.toString(), kSourceUrl);

      await enableDeveloperOptions(tester);
      await scrollSettingsTo(tester, 'open-debug');
      expect(find.byKey(const ValueKey('open-debug')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // the snack bar leaves
      await tester.pumpAndSettle();
      await scrollSettingsTo(tester, 'developer-options');
      await tapKey(tester, 'developer-options');
      expect(find.byKey(const ValueKey('open-debug')), findsNothing);

      await scrollSettingsTo(tester, 'about-licences');
      await tapKey(tester, 'about-licences');
      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text('tosk'), findsWidgets);
    });

    testWidgets('the sync section links the privacy policy', (tester) async {
      final r = await reporting(tester, signIn: false);
      final opened = <Uri>[];
      await pumpApp(tester, initialLocation: Routes.settings, overrides: withSync(r, opened: opened));
      await scrollSettingsTo(tester, 'sync-privacy');
      await tapKey(tester, 'sync-privacy');
      expect(opened.single.toString(), kPrivacyPolicyUrl);
    });
  });

  testWidgets('the Unverified badge explains itself on a tap', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: UnverifiedBadge()))));
    expect(find.text('Unverified'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unverified-badge')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unverified-info')), findsOneWidget);
    expect(find.textContaining('No native speaker has checked this course yet'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unverified-info')), findsNothing);
    expect(find.bySemanticsLabel('Unverified course. What does this mean?'), findsOneWidget);
  });

  testWidgets('signed in, the sync summary counts reports waiting to send', (tester) async {
    final r = await reporting(tester);
    r.server.offline = true;
    await tester.runAsync(() => r.service.sendReport(report('abcdefgh')));
    await pumpApp(tester, initialLocation: Routes.settings, overrides: withSync(r));
    await scrollSettingsTo(tester, 'sync-summary');
    expect(find.textContaining('1 report for the developer waiting to send'), findsOneWidget);
    r.server.offline = false;
    await letSync(tester);
  });
}

OutgoingReport report(String id) => OutgoingReport(
  id: id,
  collection: ReportCollections.feedback,
  createdAtMs: 1,
  fields: const {'v': 1, 'kind': 'general', 'app': 'x', 'platform': 'web', 'at': 1, 'text': 'hi'},
);
