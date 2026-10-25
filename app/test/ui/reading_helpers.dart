// Shared by the reader's widget tests and its review screenshots.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/speech/speaker.dart';

/// The centre of [word] (its first occurrence) in the reader's paragraph [p], in global coordinates.
Offset readingWordCenter(WidgetTester tester, int p, String word) {
  final para = find.descendant(of: find.byKey(ValueKey('reading-p-$p')), matching: find.byType(RichText));
  final r = tester.renderObject<RenderParagraph>(para.first);
  final text = r.text.toPlainText();
  final i = text.indexOf(word);
  if (i < 0) throw StateError('"$word" is not in paragraph $p: $text');
  final boxes = r.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + word.length));
  return r.localToGlobal(boxes.first.toRect().center);
}

/// Taps [word] in the reader's paragraph [p] and settles.
Future<void> tapReadingWord(WidgetTester tester, int p, String word) async {
  await tester.tapAt(readingWordCenter(tester, p, word));
  await tester.pumpAndSettle();
}

/// A speaker whose sentences last until [finish] (or [stop]) is called, so a
/// test can look at the reader while it reads.
class HoldingSpeaker implements Speaker {
  HoldingSpeaker({this.languages = const {'it', 'nl', 'es'}});
  final Set<String> languages;
  final List<(String, String, bool)> spoken = [];
  Completer<void>? _current;
  int stops = 0;

  @override
  Future<VoiceStatus> voiceStatus(String languageCode) async =>
      languages.contains(languageCode) ? VoiceStatus.ready : VoiceStatus.missing;

  @override
  Future<void> speak(String text, String languageCode, {bool slow = false}) {
    spoken.add((text, languageCode, slow));
    final c = Completer<void>();
    _current = c;
    return c.future;
  }

  /// Ends the sentence being spoken.
  void finish() {
    final c = _current;
    _current = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  bool get speaking => _current != null && !_current!.isCompleted;

  @override
  Future<void> stop() async {
    stops++;
    finish();
  }
}
