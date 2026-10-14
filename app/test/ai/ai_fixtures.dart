import 'dart:convert';

import 'package:tosk/core/core.dart';

/// A wrong conj_pick answer with a grammar note.
const wrongCtx = MistakeContext(
  courseId: 'it',
  facetId: 'it:mangiare#form:presente',
  exerciseType: ExerciseType.conjPick,
  prompt: 'Pick the right ending: mangiare (noi, presente): mang___ — iamo / iate / ano',
  expected: 'mangiamo',
  given: 'mangiate',
  sourceLang: 'en',
  targetLang: 'it',
  skillId: 'present_are',
  note: '# Present of -are verbs\n\n- noi → **-iamo**',
  options: ['iamo', 'iate', 'ano'],
  instruction: 'Pick the right ending',
);

/// The same exercise answered correctly.
const rightCtx = ExplainContext(
  courseId: 'it',
  facetId: 'it:mangiare#form:presente',
  exerciseType: ExerciseType.conjPick,
  prompt: 'Pick the right ending: mangiare (noi, presente): mang___ — iamo / iate / ano',
  expected: 'mangiamo',
  given: 'mangiamo',
  sourceLang: 'nl',
  targetLang: 'it',
  correct: true,
);

/// An Anthropic Messages SSE stream with [chunks] as text deltas.
String anthropicStream(List<String> chunks) {
  final b = StringBuffer()
    ..write('event: message_start\ndata: {"type":"message_start","message":{"id":"m","content":[]}}\n\n')
    ..write('event: content_block_start\ndata: {"type":"content_block_start","index":0,'
        '"content_block":{"type":"text","text":""}}\n\n')
    ..write('event: ping\ndata: {"type": "ping"}\n\n');
  for (final c in chunks) {
    b.write('event: content_block_delta\ndata: ${jsonEncode({
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': c},
    })}\n\n');
  }
  b
    ..write('event: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\n')
    ..write('event: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n')
    ..write('event: message_stop\ndata: {"type":"message_stop"}\n\n');
  return b.toString();
}

/// An OpenAI Chat Completions SSE stream with [chunks] as content deltas.
String openAiStream(List<String> chunks) {
  final b = StringBuffer()
    ..write('data: {"choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}\n\n');
  for (final c in chunks) {
    b.write('data: ${jsonEncode({
      'choices': [
        {'index': 0, 'delta': {'content': c}},
      ],
    })}\n\n');
  }
  b
    ..write('data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\n')
    ..write('data: [DONE]\n\n');
  return b.toString();
}

/// A fake key: never a real one.
const fakeKey = 'test-key-not-real';
