// AI conversation practice (ai/tutor.dart): the system prompt carries the
// learner's words and grammar, multi-turn requests for both providers, the
// reply format (correction, reply, translation; also while streaming), the
// conversation store, and glossing free text (engine/word_lookup.dart).
// HTTP is a MockClient; no real API is called and no real key is used.
import 'dart:convert';

import 'package:tosk/ai/ai_config.dart';
import 'package:tosk/ai/ai_errors.dart';
import 'package:tosk/ai/llm_explainer.dart';
import 'package:tosk/ai/tutor.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/ui/chat/chat_providers.dart' show tutorContextFor;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../engine/fixtures/italian_course.dart';
import 'ai_fixtures.dart';

const _ctx = TutorContext(
  courseTitle: 'Italian',
  targetLang: 'it',
  sourceLang: 'en',
  words: ['il pane (bread)', 'mangiare (to eat)'],
  grammar: ['present (presente)'],
);

final _t0 = DateTime.utc(2026, 10, 20, 9);

Conversation _conv(List<(bool, String)> lines) => Conversation(
  id: 'c1',
  topic: 'food',
  startedAt: _t0,
  messages: [
    for (final (i, (tutor, text)) in lines.indexed)
      ChatMessage(fromTutor: tutor, text: text, at: _t0.add(Duration(minutes: i))),
  ],
);

void main() {
  group('prompt', () {
    test('lists the known words and the unlocked grammar, in the target language', () {
      final p = tutorSystemPrompt(_ctx, topic: 'Food and drink');
      expect(p, contains('Italian'));
      expect(p, contains('il pane (bread)'));
      expect(p, contains('present (presente)'));
      expect(p, contains('CORRECTION:'));
      expect(p, contains('TRANSLATION:'));
      expect(p, contains('Topic: Food and drink.'));
      expect(p, isNot(contains('beginner')));
      expect(
        tutorSystemPrompt(
          const TutorContext(courseTitle: 'x', targetLang: 'nl', sourceLang: 'en', words: [], grammar: [], beginner: true),
          topic: 't',
        ),
        allOf(contains('Dutch'), contains('beginner'), contains('present tense of the most common verbs')),
      );
    });

    test('the conversation becomes alternating turns starting with the kickoff', () {
      final p = tutorPrompt(_ctx, _conv([(true, 'Ciao!'), (false, 'Ciao'), (false, 'Mangio il pane')]));
      final m = p.messages();
      expect(m.map((x) => x['role']), ['user', 'assistant', 'user']);
      expect(m.first['content'], contains('Food and drink'));
      expect(m.last['content'], 'Ciao\nMangio il pane', reason: 'two learner messages in a row are joined');
      expect(p.maxTokens, kTutorMaxTokens);
    });

    test('only the latest messages are sent', () {
      final long = _conv([for (var i = 0; i < 60; i++) (i.isEven, 'm$i')]);
      final m = tutorPrompt(_ctx, long).messages();
      expect(m.length, kTutorHistory + 1);
      expect(m.last['content'], 'm59');
    });
  });

  group('clients send the turns', () {
    final conv = _conv([(true, 'Ciao! Cosa mangi?'), (false, 'Io mangia il pane')]);

    test('Claude: messages with roles, the system prompt, streamed text', () async {
      late Map<String, Object?> body;
      final client = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return http.Response.bytes(
          utf8.encode(
            anthropicStream(['CORRECTION: Io mangio il pane — with io the ending is -o.\n', 'Bene! ', 'TRANSLATION: Good!']),
          ),
          200,
        );
      });
      final llm = ClaudeExplainer(config: const AiConfig(provider: AiProvider.anthropic, apiKey: fakeKey), client: client);
      final text = (await tutorReply(llm, _ctx, conv).toList()).join();
      final messages = (body['messages']! as List).cast<Map>();
      expect(messages.map((m) => m['role']), ['user', 'assistant', 'user']);
      expect(messages.last['content'], 'Io mangia il pane');
      expect(body['system'], contains('mangiare (to eat)'));
      expect(body['model'], 'claude-haiku-5-5');
      final r = TutorReply.parse(text);
      expect(r.correction, 'Io mangio il pane — with io the ending is -o.');
      expect(r.reply, 'Bene!');
      expect(r.translation, 'Good!');
    });

    test('OpenAI: the system message first, then the turns', () async {
      late Map<String, Object?> body;
      final client = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return http.Response(openAiStream(['Bene!\n', 'TRANSLATION: Good!']), 200);
      });
      final llm = OpenAiExplainer(config: const AiConfig(provider: AiProvider.openai, apiKey: fakeKey), client: client);
      expect((await tutorReply(llm, _ctx, conv).toList()).join(), 'Bene!\nTRANSLATION: Good!');
      final roles = [for (final m in (body['messages']! as List).cast<Map>()) m['role']];
      expect(roles, ['system', 'user', 'assistant', 'user']);
    });

    test('a refusal ends the stream with an error', () async {
      final client = MockClient(
        (_) async => http.Response(
          'event: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"refusal"}}\n\n',
          200,
        ),
      );
      final llm = ClaudeExplainer(config: const AiConfig(provider: AiProvider.anthropic, apiKey: fakeKey), client: client);
      await expectLater(tutorReply(llm, _ctx, conv).toList(), throwsA(isA<AiException>()));
    });

    test('offline is a network error', () async {
      final client = MockClient((_) async => throw http.ClientException('Failed host lookup'));
      final llm = ClaudeExplainer(config: const AiConfig(provider: AiProvider.anthropic, apiKey: fakeKey), client: client);
      await expectLater(
        tutorReply(llm, _ctx, conv).toList(),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.network)),
      );
    });
  });

  group('reply parsing', () {
    test('lenient markers: bold, case, multi-line translation, no correction', () {
      final r = TutorReply.parse('Ciao! Come stai?\n\n**Translation:** Hi! How\nare you?');
      expect(r.correction, isNull);
      expect(r.reply, 'Ciao! Come stai?');
      expect(r.translation, 'Hi! How are you?');
      final plain = TutorReply.parse('Solo testo.');
      expect(plain.reply, 'Solo testo.');
      expect(plain.translation, isNull);
    });

    test('while streaming, a half-written marker line is held back', () {
      expect(TutorReply.parse('CORREC', streaming: true).reply, '');
      expect(TutorReply.parse('Bene!\nTRANS', streaming: true).reply, 'Bene!');
      expect(TutorReply.parse('Bene!\nTranquillo', streaming: true).reply, 'Bene!\nTranquillo');
      expect(TutorReply.parse('Bene!\nTRANS').reply, 'Bene!\nTRANS', reason: 'complete text keeps everything');
    });
  });

  group('conversation store', () {
    test('saves, lists newest first, caps, deletes; JSON round trip', () async {
      final store = ConversationStore(InMemoryProgressStore(scheduler: FsrsScheduler()));
      for (var i = 0; i < kMaxConversations + 2; i++) {
        await store.save('it', Conversation(id: 'c$i', topic: 'free', startedAt: _t0.add(Duration(hours: i))));
      }
      var all = await store.list('it');
      expect(all.length, kMaxConversations);
      expect(all.first.id, 'c${kMaxConversations + 1}');
      final c = (await store.get('it', 'c5'))!.withMessage(ChatMessage(fromTutor: false, text: 'Ciao', at: _t0.add(const Duration(days: 1))));
      await store.save('it', c);
      all = await store.list('it');
      expect(all.first.id, 'c5');
      expect(all.first.messages.single.text, 'Ciao');
      expect((await store.list('nl')), isEmpty);
      await store.delete('it', 'c5');
      expect(await store.get('it', 'c5'), isNull);
      expect(conversationsKey('it'), startsWith('chat.'), reason: 'chat.* settings are never in a backup');
    });

    test('a conversation keeps its latest messages only', () {
      var c = Conversation(id: 'x', topic: 'free', startedAt: _t0);
      for (var i = 0; i < kMaxConversationMessages + 5; i++) {
        c = c.withMessage(ChatMessage(fromTutor: i.isOdd, text: '$i', at: _t0));
      }
      expect(c.messages.length, kMaxConversationMessages);
      expect(c.messages.last.text, '${kMaxConversationMessages + 4}');
    });
  });

  group('tutor context and glossing', () {
    final it = italianCourse();

    test('a beginner gets the first skill\'s words; a learner the words and grammar of started skills', () {
      final beginner = tutorContextFor(it, const [], lang: 'en');
      expect(beginner.beginner, isTrue);
      expect(beginner.words, isNotEmpty);
      final first = it.skills.first.id;
      expect(beginner.words.length, it.skillItems(first).length);

      final presentFacet = it.skills
          .expand((s) => it.skillFacets(s.id))
          .firstWhere((f) => f.facetId.endsWith('#form:presente'))
          .facetId;
      final learner = tutorContextFor(it, [presentFacet, '${it.skillItems(first).first.id}#rec'], lang: 'en');
      expect(learner.beginner, isFalse);
      expect(learner.grammar.join(' '), contains('presente'));
      expect(learner.words.any((w) => w.contains('(')), isTrue, reason: 'words come with their gloss');
    });

    test('free text becomes tokens with course words aligned; rendering gives the text back', () {
      final lookup = WordLookup.of(it);
      const text = "Il ragazzo mangia una mela, e l'acqua? Sì!";
      final tokens = lookup.tokenize(text);
      expect(renderTokenRefs(tokens), text);
      TokenRef word(String w) => tokens.firstWhere((t) => t.text == w);
      expect(word('ragazzo').itemId, 'it:ragazzo');
      expect(word('Il').isWord, isTrue);
      expect(word('mangia').itemId, 'it:mangiare');
      expect(word('mangia').form, startsWith('presente.'));
      expect(tokens.where((t) => !t.isWord).map((t) => t.text), containsAll([',', '?', '!']));
      expect(lookup.tokenize(''), isEmpty);
      expect(renderTokenRefs(lookup.tokenize('  Ciao  ')), '  Ciao  ');
    });
  });
}
