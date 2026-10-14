import 'package:tosk/ai/caching_explainer.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/feedback_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ai_fixtures.dart';

class _Counting implements Explainer {
  int calls = 0;
  Object? fail;
  @override
  bool get isAvailable => true;
  @override
  Stream<String> explain(ExplainContext ctx) async* {
    calls++;
    yield 'Because ';
    if (fail != null) throw fail!;
    yield '${ctx.expected}.';
  }
}

void main() {
  test('fetches once per (fingerprint, given, language), then serves the cache', () async {
    final inner = _Counting();
    final store = InMemoryFeedbackStore();
    final x = CachingExplainer(
      inner,
      store,
      clock: () => DateTime.utc(2026, 10, 14),
      provider: 'anthropic',
      model: 'm',
    );
    expect(await x.explain(wrongCtx).join(), 'Because mangiamo.');
    expect(await x.explain(wrongCtx).join(), 'Because mangiamo.');
    expect(inner.calls, 1);
    final saved = await store.explanation(wrongCtx.fingerprint, 'mangiate', 'en');
    expect(saved?.text, 'Because mangiamo.');
    expect(saved?.provider, 'anthropic');
    expect(saved?.facetId, wrongCtx.facetId);

    // Another reply language is another entry.
    await x.explain(wrongCtx.copyWith(explainLang: 'nl')).drain<void>();
    expect(inner.calls, 2);
    expect(await x.cached(wrongCtx), 'Because mangiamo.');
  });

  test('failed replies are not cached', () async {
    final inner = _Counting()..fail = StateError('offline');
    final x = CachingExplainer(inner, InMemoryFeedbackStore());
    await expectLater(x.explain(wrongCtx).toList(), throwsStateError);
    expect(await x.cached(wrongCtx), isNull);
  });

  test('fingerprints ignore the given answer and the session, and are stable', () {
    expect(wrongCtx.fingerprint, rightCtx.fingerprint);
    expect(wrongCtx.fingerprint, hasLength(16));
    expect(stableHash(''), '811c9dc5050c5d1f');
    expect(stableHash('abc'), stableHash('abc'));
    expect(stableHash('abc'), isNot(stableHash('abd')));
  });
}
