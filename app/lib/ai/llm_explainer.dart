/// AI explainers over the providers' streaming HTTP APIs: [ClaudeExplainer]
/// (Anthropic Messages API) and [OpenAiExplainer] (OpenAI Chat Completions,
/// also any OpenAI-compatible server). Both implement the core [Explainer]
/// and expose [LlmExplainer.complete] for other prompts (flag review).
///
/// The `http.Client` is injected, so tests use `MockClient` and never call a
/// real API. The API key is sent only in the auth header and never logged.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/core.dart';
import 'ai_config.dart';
import 'ai_errors.dart';
import 'prompts.dart';
import 'sse.dart';

/// How long to wait for the response headers (the stream itself may take longer).
const Duration kAiConnectTimeout = Duration(seconds: 25);

/// Silence allowed between two streamed chunks.
const Duration kAiIdleTimeout = Duration(seconds: 30);

abstract class LlmExplainer implements Explainer {
  LlmExplainer({
    required this.config,
    required this.client,
    this.connectTimeout = kAiConnectTimeout,
    this.idleTimeout = kAiIdleTimeout,
  });

  final AiConfig config;
  final http.Client client;
  final Duration connectTimeout;
  final Duration idleTimeout;

  /// `anthropic`, `openai`, `openai_compatible`.
  String get providerId => config.provider.id;
  String get model => config.effectiveModel;

  @override
  bool get isAvailable => config.isConfigured;

  /// Streams the reply to [prompt] as text chunks. Errors are [AiException]s.
  Stream<String> complete(ChatPrompt prompt);

  @override
  Stream<String> explain(ExplainContext ctx) => complete(explainPrompt(ctx));

  /// A tiny request that checks the key, model and URL ("Test connection").
  Future<void> testConnection() async {
    await complete(
      const ChatPrompt(system: 'You are a connection test.', user: 'Reply with the single word OK.', maxTokens: 8),
    ).drain<void>();
  }

  /// Sends [request] and returns the streamed response, mapping HTTP errors.
  Future<http.StreamedResponse> send(http.Request request) async {
    final http.StreamedResponse res;
    try {
      res = await client.send(request).timeout(connectTimeout);
    } on TimeoutException {
      throw const AiException(AiErrorKind.network, 'Timed out connecting');
    } on http.ClientException catch (e) {
      throw AiException(AiErrorKind.network, e.message);
    } on AiException {
      rethrow;
    } catch (e) {
      // dart:io SocketException/HandshakeException and browser fetch errors.
      throw AiException(AiErrorKind.network, e.runtimeType.toString());
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    String body = '';
    try {
      body = await res.stream.bytesToString().timeout(connectTimeout);
    } catch (_) {}
    final (type, message) = errorDetails(body);
    throw AiException(
      AiException.kindFor(res.statusCode, type: type),
      message ?? 'HTTP ${res.statusCode}',
      status: res.statusCode,
    );
  }

  /// SSE events of [res], failing when the stream stalls.
  Stream<SseEvent> events(http.StreamedResponse res) => parseSse(
    res.stream.timeout(
      idleTimeout,
      onTimeout: (sink) {
        sink.addError(const AiException(AiErrorKind.network, 'The response stalled'));
        sink.close();
      },
    ),
  ).handleError(
    (Object e) => throw (e is AiException ? e : AiException(AiErrorKind.network, e.runtimeType.toString())),
  );

  /// `(type, message)` from a provider's JSON error body (both providers use `{"error": {...}}`).
  static (String?, String?) errorDetails(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) {
        final e = j['error'] as Map;
        return ((e['type'] ?? e['code'])?.toString(), e['message']?.toString());
      }
    } catch (_) {}
    return (null, body.isEmpty ? null : (body.length > 200 ? body.substring(0, 200) : body));
  }
}

/// Anthropic Messages API with `stream: true`.
class ClaudeExplainer extends LlmExplainer {
  ClaudeExplainer({
    required super.config,
    required super.client,
    super.connectTimeout,
    super.idleTimeout,
    this.browser = false,
  });

  /// Running in a browser: Anthropic requires an explicit opt-in header for
  /// direct browser calls (the key is the user's own, entered on this device).
  final bool browser;

  Uri get endpoint => Uri.parse('${config.effectiveBaseUrl}/v1/messages');

  @override
  Stream<String> complete(ChatPrompt prompt) async* {
    final req = http.Request('POST', endpoint)
      ..headers.addAll({
        'content-type': 'application/json',
        'accept': 'text/event-stream',
        'x-api-key': config.apiKey,
        'anthropic-version': '2023-06-01',
        if (browser) 'anthropic-dangerous-direct-browser-access': 'true',
      })
      ..body = jsonEncode({
        'model': model,
        'max_tokens': prompt.maxTokens,
        'system': prompt.system,
        'messages': [
          {'role': 'user', 'content': prompt.user},
        ],
        'stream': true,
      });
    final res = await send(req);
    await for (final e in events(res)) {
      final Object? j;
      try {
        j = jsonDecode(e.data);
      } catch (_) {
        continue;
      }
      if (j is! Map) continue;
      switch (j['type']) {
        case 'content_block_delta':
          final delta = j['delta'];
          if (delta is Map && delta['type'] == 'text_delta' && delta['text'] is String) {
            yield delta['text'] as String;
          }
        case 'error':
          final err = j['error'] is Map ? j['error'] as Map : const {};
          final type = err['type']?.toString();
          throw AiException(
            AiException.kindFor(type == 'overloaded_error' ? 529 : 500, type: type),
            err['message']?.toString() ?? 'Stream error',
          );
        case 'message_stop':
          return;
      }
    }
  }
}

/// OpenAI Chat Completions with `stream: true` (OpenAI itself, or a
/// compatible server such as a local one, with its own base URL).
class OpenAiExplainer extends LlmExplainer {
  OpenAiExplainer({required super.config, required super.client, super.connectTimeout, super.idleTimeout});

  Uri get endpoint => Uri.parse('${config.effectiveBaseUrl}/chat/completions');

  @override
  Stream<String> complete(ChatPrompt prompt) async* {
    final official = config.provider == AiProvider.openai;
    final req = http.Request('POST', endpoint)
      ..headers.addAll({
        'content-type': 'application/json',
        'accept': 'text/event-stream',
        if (config.apiKey.isNotEmpty) 'authorization': 'Bearer ${config.apiKey}',
      })
      ..body = jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': prompt.system},
          {'role': 'user', 'content': prompt.user},
        ],
        'stream': true,
        // OpenAI's current models take max_completion_tokens; compatible
        // servers generally still expect max_tokens. Reasoning models spend
        // part of the budget thinking, so OpenAI gets more room.
        if (official) 'max_completion_tokens': prompt.maxTokens * 4 else 'max_tokens': prompt.maxTokens,
      });
    final res = await send(req);
    await for (final e in events(res)) {
      if (e.data.trim() == '[DONE]') return;
      final Object? j;
      try {
        j = jsonDecode(e.data);
      } catch (_) {
        continue;
      }
      if (j is! Map) continue;
      if (j['error'] is Map) {
        final err = j['error'] as Map;
        throw AiException(AiErrorKind.server, err['message']?.toString() ?? 'Stream error');
      }
      final choices = j['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final delta = (choices.first as Map)['delta'];
      if (delta is Map && delta['content'] is String && (delta['content'] as String).isNotEmpty) {
        yield delta['content'] as String;
      }
    }
  }
}

/// The explainer for [config], or null when it isn't configured.
LlmExplainer? llmExplainerFor(AiConfig config, http.Client client, {bool browser = false}) {
  if (!config.isConfigured) return null;
  return switch (config.provider) {
    AiProvider.anthropic => ClaudeExplainer(config: config, client: client, browser: browser),
    AiProvider.openai || AiProvider.openaiCompatible => OpenAiExplainer(config: config, client: client),
    AiProvider.none => null,
  };
}
