import 'dart:io';
import 'dart:typed_data';

import 'package:tosk/audio/sound_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_audio.dart';

class _Throwing implements AudioBackend {
  @override
  Future<void> preload(Iterable<Sfx> sounds) => throw StateError('no audio');
  @override
  Future<void> play(Sfx sfx) => throw StateError('no audio');
  @override
  Future<void> dispose() async {}
}

void main() {
  test('plays through the backend when enabled', () async {
    final backend = FakeAudioBackend();
    final s = SoundService(backend)
      ..warmUp()
      ..correct()
      ..wrong()
      ..complete()
      ..levelUp()
      ..bonus()
      ..select();
    await pumpEventQueue();
    expect(s.enabled, isTrue);
    expect(backend.preloaded, Sfx.values.toSet());
    expect(backend.played, [Sfx.correct, Sfx.wrong, Sfx.complete, Sfx.levelUp, Sfx.bonus, Sfx.select]);
  });

  test('silent when the "Sound effects" setting is off', () async {
    final backend = FakeAudioBackend();
    SoundService(backend, enabled: false)
      ..warmUp()
      ..correct()
      ..select();
    await pumpEventQueue();
    expect(backend.played, isEmpty);
    expect(backend.preloaded, isEmpty);
  });

  test('a backend that throws fails silently', () async {
    SoundService(_Throwing())
      ..warmUp()
      ..correct();
    await pumpEventQueue();
  });

  group('sound assets (tool/make_sounds.py)', () {
    for (final sfx in Sfx.values) {
      test('${sfx.name}: a small, normalized 16-bit mono WAV', () {
        final file = File('assets/${sfx.asset}');
        expect(file.existsSync(), isTrue, reason: '${file.path} missing: run python tool/make_sounds.py');
        final bytes = file.readAsBytesSync();
        expect(bytes.length, lessThan(50 * 1024));
        final d = ByteData.sublistView(bytes);
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
        expect(d.getUint16(20, Endian.little), 1, reason: 'PCM');
        expect(d.getUint16(22, Endian.little), 1, reason: 'mono');
        expect(d.getUint16(34, Endian.little), 16, reason: '16-bit');
        var peak = 0;
        for (var i = 44; i + 1 < bytes.length; i += 2) {
          final v = d.getInt16(i, Endian.little).abs();
          if (v > peak) peak = v;
        }
        expect(peak, lessThan(32767), reason: 'no clipping');
        expect(peak, greaterThan(sfx == Sfx.select ? 1500 : 10000), reason: 'normalized');
        if (sfx == Sfx.select) expect(peak, lessThan(6000), reason: 'the tick is quiet');
      });
    }
  });
}
