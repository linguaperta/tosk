/// Errors from AI providers, sorted into what the UI tells the learner.
library;

enum AiErrorKind {
  /// No connection, DNS failure, timeout: show the bundled grammar note instead.
  network,

  /// 401/403: the API key is wrong or lacks access ("check your API key").
  auth,

  /// 404 or an unknown model.
  model,

  /// 429 or "overloaded": try again later.
  rateLimit,

  /// 5xx and other server-side failures.
  server,

  /// Anything else (bad request, unreadable response).
  other,
}

class AiException implements Exception {
  const AiException(this.kind, this.message, {this.status});
  final AiErrorKind kind;
  final String message;
  final int? status;

  /// One sentence for the learner (English, like the rest of the UI).
  String get userMessage => switch (kind) {
    AiErrorKind.network => "Couldn't reach the AI service. Check your connection.",
    AiErrorKind.auth => 'The AI provider rejected the request: check your API key in Settings.',
    AiErrorKind.model => 'The model was not found: check the model name in Settings.',
    AiErrorKind.rateLimit => 'The AI service is busy or rate-limited. Try again in a moment.',
    AiErrorKind.server => 'The AI service had a problem. Try again later.',
    AiErrorKind.other => 'The AI request failed: $message',
  };

  /// Maps an HTTP status (and the provider's error type, if any) to a kind.
  static AiErrorKind kindFor(int status, {String? type}) {
    if (status == 401 || status == 403 || type == 'authentication_error' || type == 'permission_error') {
      return AiErrorKind.auth;
    }
    if (status == 404 || type == 'not_found_error' || type == 'model_not_found') return AiErrorKind.model;
    if (status == 429 || status == 529 || type == 'rate_limit_error' || type == 'overloaded_error') {
      return AiErrorKind.rateLimit;
    }
    if (status >= 500) return AiErrorKind.server;
    return AiErrorKind.other;
  }

  @override
  String toString() => 'AiException(${kind.name}${status == null ? '' : ', $status'}): $message';
}
