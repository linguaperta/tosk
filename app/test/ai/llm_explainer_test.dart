// ClaudeExplainer and OpenAiExplainer over a mock HTTP client: request shape
// (endpoint, headers, body), streamed parsing, and error mapping. No real API
// is ever called.
import 'dart:async';
import 'dart:convert';

import 'package:tosk/ai/ai_config.dart';
import 'package:tosk/ai/ai_errors.dart';
import 'package:tosk/ai/llm_explainer.dart';
import 'package:tosk/ai/prompts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'ai_fixtures.dart';

const claude = AiConfig(provider: AiProvider.anthropic, apiKey: fakeKey);
const openai = AiConfig(provider: AiProvider.openai, apiKey: fakeKey);

/// Streams [body] in small chunks (splitting multi-byte characters too).
http.StreamedResponse chunked(String body, {int status = 200, int size = 7}) {
  final bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream.fromIterable([
      for (var i = 0; i < bytes.length; i += size) bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size),
    ]),
    status,
  );
}

void main() {
  group('ClaudeExplainer', () {
    test('posts a streaming Messages request and yields the text deltas', () async {
      late http.BaseRequest seen;
      late Map<String, Object?> body;
      final client = MockClient.streaming((req, bodyStream) async {
        seen = req;
        body = jsonDecode(await bodyStream.bytesToString()) as Map<String, Object?>;
        return chunked(anthropicStream(['Use **-iamo** ', 'for *noi*: ', 'mangiamo — è giusto.']));
      });
      final x = ClaudeExplainer(config: claude, client: client);
      expect(x.isAvailable, isTrue);
      final chunks = await x.explain(wrongCtx).toList();
      expect(chunks.join(), 'Use **-iamo** for *noi*: mangiamo — è giusto.');

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(seen.headers['x-api-key'], fakeKey);
      expect(seen.headers['anthropic-version'], '2023-06-01');
      expect(seen.headers.containsKey('anthropic-dangerous-direct-browser-access'), isFalse);
      expect(body['model'], 'claude-haiku-5-5');
      expect(body['stream'], isTrue);
      expect(body['max_tokens'], isA<int>());
      expect(body['system'], contains('150 words'));
      final messages = body['messages']! as List;
      expect(messages.single, containsPair('role', 'user'));
      expect((messages.single as Map)['content'], contains('mangiate'));
    });

    test('opts in to direct browser access on the web', () async {
      late http.BaseRequest seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(anthropicStream(['ok']), 200);
      });
      await ClaudeExplainer(config: claude, client: client, browser: true).explain(wrongCtx).drain<void>();
      expect(seen.headers['anthropic-dangerous-direct-browser-access'], 'true');
    });

    test('uses the configured model and base URL', () async {
      late http.BaseRequest seen;
      String? model;
      final client = MockClient((req) async {
        seen = req;
        model = (jsonDecode(req.body) as Map)['model'] as String;
        return http.Response(anthropicStream(['ok']), 200);
      });
      final cfg = claude.copyWith(model: 'claude-sonnet-5-5', baseUrl: 'https://proxy.example/');
      await ClaudeExplainer(config: cfg, client: client).explain(wrongCtx).drain<void>();
      expect(seen.url.toString(), 'https://proxy.example/v1/messages');
      expect(model, 'claude-sonnet-5-5');
    });

    test('401 is an auth error', () async {
      final client = MockClient(
        (_) async => http.Response(
          '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}',
          401,
        ),
      );
      await expectLater(
        ClaudeExplainer(config: claude, client: client).explain(wrongCtx).toList(),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.auth)),
      );
    });

    test('a connection failure is a network error', () async {
      final client = MockClient((_) async => throw http.ClientException('Failed host lookup'));
      await expectLater(
        ClaudeExplainer(config: claude, client: client).explain(wrongCtx).toList(),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.network)),
      );
    });

    test('an error event mid-stream fails the stream after the text so far', () async {
      final body = '${anthropicStream(['partial']).split('event: content_block_stop').first}'
          'event: error\ndata: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}\n\n';
      final client = MockClient((_) async => http.Response(body, 200));
      final got = <String>[];
      Object? error;
      try {
        await for (final c in ClaudeExplainer(config: claude, client: client).explain(wrongCtx)) {
          got.add(c);
        }
      } catch (e) {
        error = e;
      }
      expect(got, ['partial']);
      expect(error, isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.rateLimit));
    });

    test('404 (unknown model), 429 and 500 map to their kinds', () async {
      for (final (status, kind) in [
        (404, AiErrorKind.model),
        (429, AiErrorKind.rateLimit),
        (500, AiErrorKind.server),
        (400, AiErrorKind.other),
      ]) {
        final client = MockClient((_) async => http.Response('{"error":{"message":"nope"}}', status));
        await expectLater(
          ClaudeExplainer(config: claude, client: client).complete(const ChatPrompt(system: 's', user: 'u')).toList(),
          throwsA(isA<AiException>().having((e) => e.kind, 'kind', kind)),
          reason: '$status',
        );
      }
    });

    test('testConnection succeeds on a reply and throws on a bad key', () async {
      final ok = MockClient((_) async => http.Response(anthropicStream(['OK']), 200));
      await ClaudeExplainer(config: claude, client: ok).testConnection();
      final bad = MockClient((_) async => http.Response('{"error":{"type":"authentication_error"}}', 401));
      await expectLater(ClaudeExplainer(config: claude, client: bad).testConnection(), throwsA(isA<AiException>()));
    });
  });

  group('OpenAiExplainer', () {
    test('posts a streaming chat completion and yields the content deltas', () async {
      late http.BaseRequest seen;
      late Map<String, Object?> body;
      final client = MockClient.streaming((req, s) async {
        seen = req;
        body = jsonDecode(await s.bytesToString()) as Map<String, Object?>;
        return chunked(openAiStream(['Il verbo ', 'è ', 'giusto.']), size: 5);
      });
      final x = OpenAiExplainer(config: openai, client: client);
      expect((await x.explain(rightCtx).toList()).join(), 'Il verbo è giusto.');
      expect(seen.url.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(seen.headers['authorization'], 'Bearer $fakeKey');
      expect(body['model'], AiProvider.openai.defaultModel);
      expect(body['stream'], isTrue);
      expect(body.containsKey('max_completion_tokens'), isTrue);
      final messages = (body['messages']! as List).cast<Map>();
      expect(messages.map((m) => m['role']), ['system', 'user']);
      // Right answers are explained too, in the reply language (Dutch here).
      expect(messages.first['content'], contains('Dutch'));
      expect(messages.last['content'], contains('accepted as correct'));
    });

    test('an OpenAI-compatible server: own base URL, max_tokens, no key needed', () async {
      late http.BaseRequest seen;
      late Map body;
      final client = MockClient((req) async {
        seen = req;
        body = jsonDecode(req.body) as Map;
        return http.Response(openAiStream(['ok']), 200);
      });
      const cfg = AiConfig(
        provider: AiProvider.openaiCompatible,
        baseUrl: 'http://localhost:11434/v1',
        model: 'llama3.2',
      );
      expect(cfg.isConfigured, isTrue);
      final x = llmExplainerFor(cfg, client)!;
      expect(x, isA<OpenAiExplainer>());
      expect((await x.explain(wrongCtx).toList()).join(), 'ok');
      expect(seen.url.toString(), 'http://localhost:11434/v1/chat/completions');
      expect(seen.headers.containsKey('authorization'), isFalse);
      expect(body['max_tokens'], isA<int>());
      expect(body.containsKey('max_completion_tokens'), isFalse);
    });

    test('401 is an auth error', () async {
      final client = MockClient(
        (_) async => http.Response('{"error":{"message":"Incorrect API key","code":"invalid_api_key"}}', 401),
      );
      await expectLater(
        OpenAiExplainer(config: openai, client: client).explain(wrongCtx).toList(),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.auth)),
      );
    });

    test('a connection that never answers times out as a network error', () async {
      final never = MockClient.streaming((_, _) => Completer<http.StreamedResponse>().future);
      final x = OpenAiExplainer(config: openai, client: never, connectTimeout: const Duration(milliseconds: 50));
      await expectLater(
        x.explain(wrongCtx).toList(),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.network)),
      );
    });

    test('a stream that stalls times out as a network error', () async {
      final stalled = MockClient.streaming(
        (_, _) async => http.StreamedResponse(StreamController<List<int>>().stream, 200),
      );
      final x = OpenAiExplainer(config: openai, client: stalled, idleTimeout: const Duration(milliseconds: 50));
      await expectLater(
        x.explain(wrongCtx).toList(),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.network)),
      );
    });
  });

  test('llmExplainerFor needs a configured provider', () {
    final client = MockClient((_) async => http.Response('', 200));
    expect(llmExplainerFor(const AiConfig(), client), isNull);
    expect(llmExplainerFor(const AiConfig(provider: AiProvider.anthropic), client), isNull, reason: 'no key');
    expect(llmExplainerFor(claude, client), isA<ClaudeExplainer>());
    expect(llmExplainerFor(openai, client), isA<OpenAiExplainer>());
  });
}
