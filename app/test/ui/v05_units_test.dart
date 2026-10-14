// v0.5 pure pieces: voice locale choice, ONYX detection, the pen channel's
// point decoding, the new learner settings and their backup rules.
import 'dart:typed_data';

import 'package:tosk/data/sync/progress_backup.dart';
import 'package:tosk/device/device_info.dart';
import 'package:tosk/device/onyx.dart';
import 'package:tosk/speech/speaker.dart';
import 'package:tosk/ui/settings/learner_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('voice locale: exact, preferred region, any region, none', () {
    expect(pickVoiceLocale('it', ['en-US', 'it-IT', 'it-CH']), 'it-IT');
    expect(pickVoiceLocale('it', ['it_CH', 'it_IT']), 'it_IT');
    expect(pickVoiceLocale('nl', ['nl-BE', 'nl-NL']), 'nl-NL');
    expect(pickVoiceLocale('nl', ['nl-BE']), 'nl-BE');
    expect(pickVoiceLocale('pt', ['pt-BR', 'pt-PT']), 'pt-PT');
    expect(pickVoiceLocale('es', ['es']), 'es');
    expect(pickVoiceLocale('hns', ['nl-NL', 'hi-IN']), isNull, reason: 'Sarnami has no voice');
    expect(pickVoiceLocale('it', const []), isNull);
  });

  test('ONYX detection by manufacturer or brand', () {
    expect(const DeviceInfo(manufacturer: 'ONYX', brand: 'Onyx').isOnyx, isTrue);
    expect(const DeviceInfo(manufacturer: 'Qualcomm', brand: 'onyx').isOnyx, isTrue);
    expect(const DeviceInfo(manufacturer: 'Google', brand: 'google').isOnyx, isFalse);
    expect(DeviceInfo.unknown.isOnyx, isFalse);
  });

  test('pen points decode from the channel', () {
    expect(decodePenPoints(Float64List.fromList([1, 2, 3, 4.5, 5, 6])), [(1.0, 2.0, 3), (4.5, 5.0, 6)]);
    expect(decodePenPoints([1, 2, 3, 4]), [(1.0, 2.0, 3)], reason: 'a trailing partial point is dropped');
    expect(decodePenPoints(null), isEmpty);
  });

  test('learner settings: handwriting, listening and the e-reader switches persist', () async {
    final store = TestProgressStore();
    const d = LearnerSettings();
    expect(d.listening, isTrue);
    expect(d.einkFullRefresh, isNull);
    expect(d.onyxPen, isTrue);
    final s = d.copyWith(answerInput: AnswerInputPref.handwrite, listening: false, einkFullRefresh: false, onyxPen: false);
    await s.save(store);
    expect(store.settings[LearnerSettingKeys.answerInput], 'handwrite');
    final back = await LearnerSettings.load(store);
    expect(back, s);
    expect(back.handwriting, isTrue);
    // Never set: absent, so the default (on in black & white) applies.
    final fresh = TestProgressStore();
    await d.save(fresh);
    expect(fresh.settings.containsKey(LearnerSettingKeys.einkFullRefresh), isFalse);
  });

  test('e-reader switches are device-only in backups', () {
    expect(kDeviceOnlySettings, containsAll([LearnerSettingKeys.einkFullRefresh, LearnerSettingKeys.onyxPen]));
    expect(kDeviceOnlySettings.contains(LearnerSettingKeys.listening), isFalse);
  });
}
