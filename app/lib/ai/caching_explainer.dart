/// Caches explanations per (exercise fingerprint, given answer, reply
/// language) in the progress database, so a reply is fetched once and then
/// works offline and in mistake review.
library;

import '../core/core.dart';

class CachingExplainer implements Explainer {
  CachingExplainer(this.inner, this.cache, {this.clock = DateTime.now, this.provider, this.model});

  final Explainer inner;
  final ExplanationCache cache;
  final DateTime Function() clock;
  final String? provider;
  final String? model;

  @override
  bool get isAvailable => inner.isAvailable;

  /// The cached reply for [ctx], if any (no network).
  Future<String?> cached(ExplainContext ctx) async =>
      (await cache.explanation(ctx.fingerprint, ctx.given, ctx.replyLang))?.text;

  @override
  Stream<String> explain(ExplainContext ctx) async* {
    final hit = await cached(ctx);
    if (hit != null) {
      yield hit;
      return;
    }
    final buf = StringBuffer();
    await for (final chunk in inner.explain(ctx)) {
      buf.write(chunk);
      yield chunk;
    }
    final text = buf.toString().trim();
    // Only complete replies are cached: an error above skips this.
    if (text.isNotEmpty) {
      await cache.saveExplanation(
        CachedExplanation(
          fingerprint: ctx.fingerprint,
          given: ctx.given,
          lang: ctx.replyLang,
          text: text,
          createdAt: clock().toUtc(),
          facetId: ctx.facetId,
          provider: provider,
          model: model,
        ),
      );
    }
  }
}
