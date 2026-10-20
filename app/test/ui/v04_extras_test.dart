// v0.4 extras in the app: bookmarks (stars on the word page, the word
// popover and the feedback panel's Star sheet; Progress → Starred with
// filters, unstar + undo and "Practice starred"), the stats card and the
// stats page (forecast 14/30 days, accuracy), and AI conversation practice
// (Practice → Chat only with AI configured; streamed replies with a
// correction, tap-for-gloss and a translation; offline and key errors).
// HTTP is a MockClient; no real API is called and no real key is used.
import 'dart:convert';

import 'package:tosk/ai/ai_config.dart';
import 'package:tosk/ai/secret_store.dart';
import 'package:tosk/ai/tutor.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/bookmarks.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/bookmarks/starred_screen.dart';
import 'package:tosk/ui/chat/chat_screen.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/lesson/player_screen.dart';
import 'package:tosk/ui/progress/stats_view.dart';
import 'package:tosk/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../ai/ai_fixtures.dart' show anthropicStream, fakeKey;
import 'helpers.dart';

const _ai = {AiSettingKeys.provider: 'anthropic'};

const tutorReplyText =
    'CORRECTION: Io mangio il pane — with io the ending is -o.\n'
    'Mangiamo il pane! Ti piace?\n'
    'TRANSLATION: We eat bread! Do you like it?';

/// A fake Anthropic API for the tutor.
class FakeTutorAi {
  int status = 200;
  bool offline = false;
  final List<Map<String, Object?>> bodies = [];

  late final MockClient client = MockClient((req) async {
    if (offline) throw http.ClientException('Failed host lookup');
    final body = jsonDecode(req.body) as Map<String, Object?>;
    bodies.add(body);
    if (status != 200) {
      return http.Response('{"type":"error","error":{"type":"authentication_error","message":"invalid"}}', status);
    }
    return http.Response.bytes(
      utf8.encode(anthropicStream(['CORRECTION: Io mangio il pane — with io ', 'the ending is -o.\nMangiamo il pane! ', 'Ti piace?\nTRANSLATION: We eat bread! Do you like it?'])),
      200,
    );
  });
}

List<Override> tutorOverrides(FakeTutorAi ai) => [
  secretStoreProvider.overrideWithValue(MemorySecretStore({AiSettingKeys.apiKeySecret: fakeKey})),
  httpClientProvider.overrideWithValue(ai.client),
];

/// Lets a mock AI stream finish (its done event needs real event-loop turns).
Future<void> settleAi(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<TestProgressStore> seededStore([Map<String, String> settings = const {}]) async {
  final store = TestProgressStore(settings: settings);
  await seedDemoProgress(store, buildDemoItalian(), testNow);
  return store;
}

void main() {
  final allSkills = buildDemoItalian().skills.map((s) => s.id).toList();

  group('bookmarks', () {
    testWidgets('star a word on its page and an example sentence; Progress → Starred lists them', (tester) async {
      final repo = InMemoryBookmarkRepo();
      await pumpApp(
        tester,
        initialLocation: Routes.word('it:mangiare'),
        overrides: [bookmarkRepoProvider.overrideWithValue(repo)],
      );
      await tapKey(tester, 'word-star');
      expect(find.byTooltip('Unstar this word'), findsOneWidget);
      await tapKey(tester, 'word-example-star-s:demo1');
      final set = await repo.load('it');
      expect(set.contains(BookmarkKind.word, 'it:mangiare'), isTrue);
      expect(set.contains(BookmarkKind.sentence, 's:demo1'), isTrue);
      expect(set.of(BookmarkKind.word).single.detail, 'to eat');

      await tester.pumpWidget(const SizedBox());
      await pumpApp(
        tester,
        initialLocation: Routes.progress,
        overrides: [bookmarkRepoProvider.overrideWithValue(repo)],
      );
      await scrollToFind(tester, find.byKey(const ValueKey('open-starred')));
      expect(find.text('Starred (2)'), findsOneWidget);
      await tapKey(tester, 'open-starred');
      expect(find.byType(StarredScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('starred-word:it:mangiare')), findsOneWidget);
      expect(find.byKey(const ValueKey('starred-sentence:s:demo1')), findsOneWidget);
      expect(find.text('1 word · 1 sentence · 0 exercises'), findsOneWidget);

      // Filter by kind.
      await tapKey(tester, 'starred-filter-sentence');
      expect(find.byKey(const ValueKey('starred-word:it:mangiare')), findsNothing);
      await tapKey(tester, 'starred-filter-exercise');
      expect(find.text('Nothing starred of this kind.'), findsOneWidget);
      await tapKey(tester, 'starred-filter-all');

      // Unstar, then undo.
      await tapKey(tester, 'unstar-word:it:mangiare');
      expect(find.byKey(const ValueKey('starred-word:it:mangiare')), findsNothing);
      expect((await repo.load('it')).contains(BookmarkKind.word, 'it:mangiare'), isFalse);
      await tester.tap(find.byKey(const ValueKey('starred-undo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('starred-word:it:mangiare')), findsOneWidget);
      expect((await repo.load('it')).contains(BookmarkKind.word, 'it:mangiare'), isTrue);
    });

    testWidgets('the word popover has a star', (tester) async {
      final repo = InMemoryBookmarkRepo();
      await pumpApp(
        tester,
        initialLocation: Routes.word('it:mangiare'),
        overrides: [bookmarkRepoProvider.overrideWithValue(repo)],
      );
      await tapIt(tester, find.byKey(const ValueKey('word-s:demo1-0')));
      expect(find.byKey(const ValueKey('word-popover')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('word-popover-star')));
      await tester.pumpAndSettle();
      expect((await repo.load('it')).contains(BookmarkKind.word, 'it:mangiare'), isTrue);
    });

    testWidgets('the feedback panel stars the exercise and its word; Practice starred replays it', (tester) async {
      final repo = InMemoryBookmarkRepo();
      await pumpApp(
        tester,
        initialLocation: Routes.labPlay(skills: allSkills, types: [ExerciseType.multipleChoice], length: 1),
        overrides: [bookmarkRepoProvider.overrideWithValue(repo)],
      );
      final ex = currentExercise(tester);
      await answerCurrentNoContinue(tester, wrong: true);
      expect(find.text('Star'), findsOneWidget);
      await tapKey(tester, 'star-button');
      expect(find.byKey(const ValueKey('star-sheet')), findsOneWidget);
      await tapKey(tester, 'star-toggle-exercise');
      await tapKey(tester, 'star-toggle-word');
      expect(find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == 'starred'), findsNWidgets(2));
      final set = await repo.load('it');
      expect(set.of(BookmarkKind.exercise).single.facetId, ex.facetId);
      expect(set.of(BookmarkKind.exercise).single.exercise?['type'], ex.type.id);
      expect(set.contains(BookmarkKind.word, ex.facetId.split('#').first), isTrue);
      // Close the sheet: the panel's action now reads "Starred".
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Starred'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      // Practice starred: the starred exercise comes back as it was.
      await pumpApp(tester, initialLocation: Routes.starred, overrides: [bookmarkRepoProvider.overrideWithValue(repo)]);
      await tapKey(tester, 'starred-practice');
      expect(find.byType(PlayerScreen), findsOneWidget);
      final again = currentExercise(tester);
      expect(again.type, ex.type);
      expect(again.facetId, ex.facetId);
      expect(again.id, startsWith('starred:'));
    });

    testWidgets('nothing starred: the empty state, no practice button; the player says so', (tester) async {
      await pumpApp(tester, initialLocation: Routes.starred);
      expect(find.byKey(const ValueKey('starred-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('starred-practice')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, initialLocation: Routes.starredPlay);
      expect(find.byKey(const ValueKey('player-empty')), findsOneWidget);
    });
  });

  group('stats', () {
    testWidgets('the Progress card shows what is due and opens the stats page', (tester) async {
      await pumpApp(tester, store: await seededStore(), initialLocation: Routes.progress);
      await scrollToFind(tester, find.byKey(const ValueKey('stats-summary')));
      expect(find.byKey(const ValueKey('stats-due-today')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-forecast-chart-7')), findsOneWidget);
      await tapKey(tester, 'open-stats');
      expect(find.byType(StatsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-forecast-chart-14')), findsOneWidget);
      expect(find.textContaining('in the next 14 days'), findsOneWidget);
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stats-forecast-chart-30')), findsOneWidget);
      expect(find.textContaining('in the next 30 days'), findsOneWidget);
      // Accuracy from the seeded log.
      await scrollToFind(tester, find.byKey(const ValueKey('stats-by-type')));
      expect(find.descendant(of: find.byKey(const ValueKey('stats-by-type')), matching: find.byType(AccuracyRowView)), findsWidgets);
      await scrollToFind(tester, find.byKey(const ValueKey('stats-by-kind')));
      expect(find.descendant(of: find.byKey(const ValueKey('stats-by-kind')), matching: find.byType(AccuracyRowView)), findsWidgets);
    });

    testWidgets('a fresh learner: no answers yet', (tester) async {
      await pumpApp(tester, initialLocation: Routes.stats);
      expect(find.byKey(const ValueKey('stats-forecast-total')), findsOneWidget);
      await scrollToFind(tester, find.text('No answers in the last 30 days.'));
      expect(find.text('No answers in the last 30 days.'), findsWidgets);
    });
  });

  group('AI conversation', () {
    testWidgets('no Chat tab without a configured provider and key', (tester) async {
      await pumpApp(tester, store: TestProgressStore(settings: _ai), initialLocation: Routes.practice); // no key
      expect(find.byKey(const ValueKey('practice-tab-chat')), findsNothing);
      expect(find.byKey(const ValueKey('practice-tab-stories')), findsOneWidget);
    });

    testWidgets('start a conversation: the tutor streams a reply with a correction, glosses and a translation',
        (tester) async {
      final ai = FakeTutorAi();
      final store = TestProgressStore(settings: _ai);
      await pumpApp(tester, store: store, initialLocation: Routes.chats, overrides: tutorOverrides(ai));
      expect(find.byKey(const ValueKey('practice-tab-chat')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-home')), findsOneWidget);
      await tapKey(tester, 'chat-topic-food');
      expect(find.text('Start: Food and drink'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-start')));
      await settleAi(tester);
      expect(find.byType(ChatScreen), findsOneWidget);

      // The kickoff request: the topic, the learner's words, alternating turns.
      final first = ai.bodies.single;
      expect(first['system'], allOf(contains('Italian'), contains('Topic: Food and drink.'), contains('TRANSLATION:')));
      expect((first['messages']! as List).single, containsPair('role', 'user'));
      expect(first['stream'], isTrue);

      expect(find.byKey(const ValueKey('chat-tutor-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-correction-0')), findsOneWidget);
      expect(find.textContaining('Io mangio il pane'), findsOneWidget);
      // Tap a word of the reply for its gloss.
      await tester.tap(find.byKey(const ValueKey('word-chat0-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('word-popover')), findsOneWidget);
      expect(find.byKey(const ValueKey('word-popover-glosses')), findsOneWidget);
      await tester.tapAt(const Offset(5, 300));
      await tester.pumpAndSettle();
      // The translation, one tap away.
      expect(find.byKey(const ValueKey('chat-translation-0')), findsNothing);
      await tapKey(tester, 'chat-translate-0');
      expect(find.text('We eat bread! Do you like it?'), findsOneWidget);

      // Reply: the learner's message and the history go out.
      await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Sì, mi piace il pane');
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await settleAi(tester);
      expect(find.byKey(const ValueKey('chat-learner-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-tutor-2')), findsOneWidget);
      final roles = [for (final m in (ai.bodies.last['messages']! as List).cast<Map>()) m['role']];
      expect(roles, ['user', 'assistant', 'user']);
      expect((ai.bodies.last['messages']! as List).cast<Map>().last['content'], 'Sì, mi piace il pane');

      // Saved locally (a chat.* setting: never in a backup).
      final saved = store.settings[conversationsKey('it')]!;
      expect(saved, contains('mi piace il pane'));

      // Back on the Chat tab, the conversation is listed; delete it.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await scrollToFind(tester, find.text('Recent conversations'));
      expect(find.text('Recent conversations'), findsOneWidget);
      final id = (jsonDecode(saved) as List).first['id'] as String;
      await tapKey(tester, 'chat-delete-$id');
      await tapKey(tester, 'chat-delete-yes');
      expect(find.text('Recent conversations'), findsNothing);
      expect(store.settings[conversationsKey('it')], isNull);
    });

    testWidgets('offline: says so, keeps the messages, and Try again works once back online', (tester) async {
      final ai = FakeTutorAi()..offline = true;
      await pumpApp(tester, store: TestProgressStore(settings: _ai), initialLocation: Routes.chats, overrides: tutorOverrides(ai));
      await tester.tap(find.byKey(const ValueKey('chat-start')));
      await settleAi(tester);
      expect(find.byKey(const ValueKey('chat-error-network')), findsOneWidget);
      expect(find.textContaining('needs an internet connection'), findsOneWidget);
      ai.offline = false;
      await tester.tap(find.byKey(const ValueKey('chat-retry')));
      await settleAi(tester);
      expect(find.byKey(const ValueKey('chat-error-network')), findsNothing);
      expect(find.byKey(const ValueKey('chat-tutor-0')), findsOneWidget);
    });

    testWidgets('a rejected key points to Settings, without Try again', (tester) async {
      final ai = FakeTutorAi()..status = 401;
      await pumpApp(tester, store: TestProgressStore(settings: _ai), initialLocation: Routes.chats, overrides: tutorOverrides(ai));
      await tester.tap(find.byKey(const ValueKey('chat-start')));
      await settleAi(tester);
      expect(find.byKey(const ValueKey('chat-error-auth')), findsOneWidget);
      expect(find.textContaining('API key'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-retry')), findsNothing);
    });

    testWidgets('a conversation link without AI configured explains why', (tester) async {
      final store = TestProgressStore();
      await ConversationStore(store).save('it', Conversation(id: 'c1', topic: 'free', startedAt: testNow));
      await pumpApp(tester, store: store, initialLocation: Routes.chat('c1'));
      expect(find.byKey(const ValueKey('chat-unavailable')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-input')), findsNothing);
    });
  });
}
