/// Server-sent events (text/event-stream) parsing, enough for the Anthropic
/// Messages and OpenAI Chat Completions streams.
library;

import 'dart:async';
import 'dart:convert';

class SseEvent {
  const SseEvent({this.event, required this.data});

  /// The `event:` field (Anthropic sends one per event; OpenAI none).
  final String? event;

  /// The `data:` lines joined with newlines.
  final String data;

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Decodes a byte stream into events. Handles CRLF, multi-line data, comments
/// (`: ping`) and chunks split anywhere (even inside a UTF-8 sequence).
Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  String? event;
  final data = <String>[];
  await for (final raw in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (raw.isEmpty) {
      if (data.isNotEmpty) yield SseEvent(event: event, data: data.join('\n'));
      event = null;
      data.clear();
      continue;
    }
    if (raw.startsWith(':')) continue;
    final colon = raw.indexOf(':');
    final field = colon < 0 ? raw : raw.substring(0, colon);
    var value = colon < 0 ? '' : raw.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        data.add(value);
    }
  }
  if (data.isNotEmpty) yield SseEvent(event: event, data: data.join('\n'));
}
