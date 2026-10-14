import 'dart:convert';

import 'package:tosk/ai/sse.dart';
import 'package:flutter_test/flutter_test.dart';

Stream<List<int>> _split(String s, int size) {
  final b = utf8.encode(s);
  return Stream.fromIterable([
    for (var i = 0; i < b.length; i += size) b.sublist(i, i + size > b.length ? b.length : i + size),
  ]);
}

void main() {
  test('events with names, multi-line data, comments and CRLF', () async {
    const text = ': keep-alive\r\nevent: a\r\ndata: one\r\ndata: two\r\n\r\ndata:{"x":1}\n\nevent: b\ndata: last';
    final events = await parseSse(_split(text, 3)).toList();
    expect(events.map((e) => e.event), ['a', null, 'b']);
    expect(events.map((e) => e.data), ['one\ntwo', '{"x":1}', 'last']);
  });

  test('multi-byte characters split across chunks survive', () async {
    final events = await parseSse(_split('data: è già ✓\n\n', 1)).toList();
    expect(events.single.data, 'è già ✓');
  });
}
