import 'package:tosk/speech/speech_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("can't listen now: snoozes listening exercises for an hour", () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(listenSnoozeProvider.notifier);
    expect(n.active, isFalse);
    n.snooze();
    expect(n.active, isTrue);
    final until = c.read(listenSnoozeProvider)!;
    expect(until.difference(DateTime.now()).inMinutes, inInclusiveRange(58, 60));
    n.snooze(const Duration(milliseconds: -1));
    expect(n.active, isFalse);
  });
}
