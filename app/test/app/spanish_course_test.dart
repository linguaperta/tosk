// The Spanish course (v0.6 pilot) end to end: the bundled pack is listed with
// its description, opens as the active course, and full lessons play through
// the engine (unit 1 and a past-tense skill), answered correctly.
import 'dart:io';

import 'package:tosk/app_bootstrap.dart';
import 'package:tosk/core/core.dart' show CourseTrees;
import 'package:tosk/data/bootstrap.dart';
import 'package:tosk/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/helpers.dart';
import '../ui/helpers.dart';
import 'app_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final tmp = Directory.systemTemp.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
  });

  test('the Spanish pack is bundled, described, and plays full lessons', () async {
    final dir = tempDir('tosk_spanish');
    final boot = await bootApp(options: AppDataOptions(dataDirectory: dir.path));
    addTearDown(boot.close);
    final packs = await boot.app.availableCourses();
    expect(packs.map((p) => p.id), contains('es'));

    final container = ProviderContainer.test(overrides: [...boot.overrides, clockProvider.overrideWithValue(() => testNow)]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await container.read(settingsProvider.notifier).change((s) => s.copyWith(courseId: 'es'));
    final course = await container.read(courseDataProvider.future);
    expect(course.meta.id, 'es');
    expect(course.meta.title['en'], 'Spanish');
    expect(course.meta.description['en'], isNotEmpty);
    expect(course.meta.description['nl'], isNotEmpty);
    expect(course.meta.persons, contains('vosotros'));
    // the main tree, plus its themed topics (docs/topic-split.md)
    final trees = CourseTrees.of(course);
    expect(trees.mainUnits.length, inInclusiveRange(8, 10));
    expect(trees.mainSkills.length, inInclusiveRange(30, 50));
    expect(trees.topics, isNotEmpty);

    final factory = await container.read(sessionFactoryProvider.future);
    for (final skillId in ['greetings', 'ser', 'present-ar', 'indefinido']) {
      final session = await factory.lesson(skillId);
      var served = 0;
      for (var e = await session.next(); e != null; e = await session.next()) {
        served++;
        final r = await session.submit(e, correctAnswer(e), elapsed: const Duration(seconds: 4));
        expect(r.correct, isTrue, reason: '$skillId ${e.type}');
      }
      expect(served, greaterThanOrEqualTo(8), reason: skillId);
      expect(session.correctCount, session.answered, reason: skillId);
    }
  });
}
