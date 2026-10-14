// v0.3 feature batch B: typing ("challenge") mode and the accent bar,
// "I was right", the daily goal and reminder, progress backup, jump to the
// current unit, and the instruction kept in view after Check.
import 'dart:convert';
import 'dart:typed_data';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/sync/progress_backup.dart';
import 'package:tosk/engine/engine.dart' show FocusPresets, openMistakes;
import 'package:tosk/progression/progression.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/reminders/reminder_backend.dart';
import 'package:tosk/ui/goal/daily_goal_providers.dart';
import 'package:tosk/ui/lesson/answer_override.dart';
import 'package:tosk/ui/lesson/typing.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/backup_section.dart';
import 'package:tosk/ui/settings/learner_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/big_map_course.dart';
import 'helpers.dart';

/// Records reminder calls; permission as configured.
class FakeReminderBackend implements ReminderBackend {
  FakeReminderBackend({this.grant = true, this.supported = true});
  final bool grant;
  @override
  final bool supported;
  int permissionRequests = 0;
  final List<List<ReminderSlot>> scheduled = [];

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> replaceAll(List<ReminderSlot> slots, {required String title, required String body}) async =>
      scheduled.add(slots);
}

/// In-memory backup files.
class FakeBackupFiles implements BackupFiles {
  final Map<String, Uint8List> saved = {};
  ({String name, Uint8List bytes})? next;

  @override
  Future<String?> save(String fileName, Uint8List bytes) async {
    saved[fileName] = bytes;
    return 'Downloads/$fileName';
  }

  @override
  Future<({String name, Uint8List bytes})?> pick() async => next;
}

/// [xp] worth of right first answers today (new facets earn 8 XP each).
Future<void> seedXpToday(TestProgressStore store, int xp) async {
  for (var i = 0; i * 8 < xp; i++) {
    await store.record(
      ReviewEvent(
        id: 'xp-$i',
        facetId: 'it:seed$i#rec',
        at: testNow.subtract(Duration(minutes: 30 - i)),
        rating: Rating.good,
        exerciseType: 'multiple_choice',
        inputMode: InputMode.tap,
        responseMs: 4000,
        correct: true,
        mode: 'lesson',
      ),
    );
  }
}

TestProgressStore typingStore([Map<String, String> extra = const {}]) =>
    TestProgressStore(settings: {LearnerSettingKeys.answerInput: 'type', ...extra});

void main() {
  group('typing mode', () {
    testWidgets('Settings: Answer input Tap / Type persists and switches the engine to keyboard', (tester) async {
      final store = await pumpApp(tester, size: const Size(400, 900));
      await goTab(tester, 'Settings');
      await tapKey(tester, 'setting-answer-input-Type');
      expect(store.settings[LearnerSettingKeys.answerInput], 'type');
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      expect(container.read(sessionOptionsProvider).preferredInput, InputMode.keyboard);
      await tapKey(tester, 'setting-answer-input-Tap');
      expect(store.settings[LearnerSettingKeys.answerInput], 'tap');
      expect(container.read(sessionOptionsProvider).preferredInput, InputMode.tap);
    });

    testWidgets('conjugation pick: type the ending after the stem; accent bar; graded right', (tester) async {
      await pumpApp(
        tester,
        store: typingStore(),
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.conjPick], length: 1),
      );
      expect(find.byKey(const ValueKey('conj-pick-typed')), findsOneWidget);
      expect(find.byKey(const ValueKey('ending-0')), findsNothing, reason: 'no options in typing mode');
      expect(find.text('mang'), findsWidgets); // the stem as the field prefix
      await typeInto(tester, find.byKey(const ValueKey('conj-pick-typed')), 'iamo');
      expect(find.byKey(const ValueKey('check-button')), findsOneWidget);
      await tapKey(tester, 'check-button');
      expect(find.text('Correct!'), findsOneWidget);
    });

    testWidgets('grid: one text field per asked cell, Enter moves on, no tile bank', (tester) async {
      await pumpApp(
        tester,
        store: typingStore(),
        size: const Size(400, 900),
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.conjGrid], length: 1),
      );
      expect(find.byKey(const ValueKey('grid-tile-0')), findsNothing);
      expect(find.byKey(const ValueKey('grid-input-0')), findsNothing, reason: 'prefilled');
      expect(find.byKey(const ValueKey('grid-input-1')), findsOneWidget);
      await answerCurrentNoContinue(tester);
      expect(find.text('Correct!'), findsOneWidget);
    });

    testWidgets('sentence builder and transform: typed sentences', (tester) async {
      await pumpApp(
        tester,
        store: typingStore(),
        initialLocation: Routes.labPlay(skills: ['greetings'], types: [ExerciseType.sentenceBuilder], length: 1),
      );
      expect(find.byKey(const ValueKey('tile-0')), findsNothing);
      await typeInto(tester, find.byKey(const ValueKey('answer-input')), 'buongiorno, grazie!');
      await tapKey(tester, 'check-button');
      expect(find.text('Correct!'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await pumpApp(
        tester,
        store: typingStore(),
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.transform], length: 1),
      );
      await typeInto(tester, find.byKey(const ValueKey('answer-input')), 'Noi mangiamo la mela');
      await tapKey(tester, 'check-button');
      expect(find.text('Correct!'), findsOneWidget);
    });

    testWidgets('cloze: a text field even when the exercise has options; recognition stays tap', (tester) async {
      await pumpApp(
        tester,
        store: typingStore(),
        initialLocation: Routes.labPlay(skills: ['essere-avere'], types: [ExerciseType.cloze], length: 1),
      );
      expect(find.byKey(const ValueKey('cloze-option-0')), findsNothing);
      await typeInto(tester, find.byKey(const ValueKey('answer-input')), 'sono');
      await tapKey(tester, 'check-button');
      expect(find.text('Correct!'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await pumpApp(
        tester,
        store: typingStore(),
        initialLocation: Routes.labPlay(skills: ['family'], types: [ExerciseType.multipleChoice], length: 1),
      );
      expect(find.byKey(const ValueKey('option-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('answer-input')), findsNothing);
    });

    testWidgets('real engine: cloze is free text, graded with the accent setting', (tester) async {
      await pumpApp(
        tester,
        engine: true,
        overrides: [focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults)],
        store: typingStore(),
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.cloze], length: 1),
      );
      final e = currentExercise(tester) as ClozeExercise;
      expect(e.options, isNull);
      await typeInto(tester, find.byKey(const ValueKey('answer-input')), e.expected);
      await tapKey(tester, 'check-button');
      expect(find.text('Correct!'), findsOneWidget);
    });
  });

  group('accent bar', () {
    testWidgets('letters come from the course; a tap inserts at the cursor, a long press the capital', (tester) async {
      final reported = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccentLetters(
              letters: const ['è', 'à'],
              child: TypedAnswerField(onChanged: reported.add),
            ),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('answer-input'));
      await tester.enterText(field, 'cia');
      await tester.pump();
      final editable = tester.state<EditableTextState>(find.byType(EditableText));
      editable.userUpdateTextEditingValue(
        editable.textEditingValue.copyWith(selection: const TextSelection.collapsed(offset: 2)),
        SelectionChangedCause.tap,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('accent-à')));
      await tester.pump();
      expect(editable.textEditingValue.text, 'ciàa');
      expect(editable.textEditingValue.selection.baseOffset, 3);
      expect(reported.last, 'ciàa');
      await tester.longPress(find.byKey(const ValueKey('accent-è')));
      await tester.pump();
      expect(reported.last, 'ciàÈa');
      // The field keeps the focus (the keyboard stays up).
      expect(editable.widget.focusNode.hasFocus, isTrue);
      final size = tester.getSize(find.byKey(const ValueKey('accent-è')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('in a typed exercise the bar shows the active course letters', (tester) async {
      await pumpApp(
        tester,
        store: typingStore(),
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.conjPick], length: 1),
      );
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      final letters = container.read(accentLettersProvider);
      // The small demo course may have too few accented letters for a bar.
      if (letters.isNotEmpty) expect(find.byKey(ValueKey('accent-${letters.first}')), findsOneWidget);
    });
  });

  group('"I was right"', () {
    testWidgets('fake session: confirm → counted correct, event re-rated, flag stored', (tester) async {
      final store = await pumpApp(
        tester,
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.conjPick], length: 1),
      );
      await answerCurrentNoContinue(tester, wrong: true);
      expect(find.text('Not quite'), findsOneWidget);
      await tapKey(tester, 'override-button');
      expect(find.text('Count my answer as correct?'), findsOneWidget);
      await tapKey(tester, 'override-cancel');
      expect(find.text('Not quite'), findsOneWidget);
      await tapKey(tester, 'override-button');
      await tapKey(tester, 'override-confirm');
      expect(find.text('Correct!'), findsOneWidget);
      expect(find.byKey(const ValueKey('override-button')), findsNothing);

      final log = await store.log();
      final o = log.singleWhere((e) => e.isOverride);
      expect(o.overriddenId, log.firstWhere((e) => !e.isOverride && !e.correct).id);
      final flags = await overrideFlags(store);
      expect(flags.single['facet_id'], 'it:mangiare#form:presente');
      expect(flags.single['given'], 'mangiate');
      expect(flags.single['overridden_events'], [o.overriddenId]);
      // The state equals a right answer's.
      expect((await store.state('it:mangiare#form:presente'))!.lapses, 0);
    });

    testWidgets('real engine: no re-ask, the mistake leaves the list, the summary counts it right', (tester) async {
      final store = await pumpApp(
        tester,
        engine: true,
        overrides: [focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults)],
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.conjPick], length: 2),
      );
      final first = currentExercise(tester);
      await answerCurrentNoContinue(tester, wrong: true);
      await tapKey(tester, 'override-button');
      await tapKey(tester, 'override-confirm');
      await tapKey(tester, 'continue-button');
      expect(first.type, ExerciseType.conjPick);
      await playToSummary(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      final course = await container.read(courseDataProvider.future);
      expect(
        await openMistakes(store: store, course: course, scheduler: container.read(schedulerProvider), now: testNow),
        isEmpty,
      );
    });

    testWidgets('a right answer has no "I was right"', (tester) async {
      await pumpApp(
        tester,
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.conjPick], length: 1),
      );
      await answerCurrentNoContinue(tester);
      expect(find.byKey(const ValueKey('override-button')), findsNothing);
    });
  });

  group('daily goal', () {
    testWidgets('map header: progress, then "Goal met"; Off hides it', (tester) async {
      await pumpApp(tester, size: const Size(320, 640));
      expect(find.byKey(const ValueKey('daily-goal')), findsOneWidget);
      expect(find.text('0 / 50 XP'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-goal-open')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      final store = TestProgressStore();
      await seedXpToday(store, 56);
      await pumpApp(tester, size: const Size(320, 640), store: store);
      expect(find.text('Goal met'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-goal-met')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      await pumpApp(tester, store: TestProgressStore(settings: {LearnerSettingKeys.dailyGoalXp: '0'}));
      expect(find.byKey(const ValueKey('daily-goal')), findsNothing);
    });

    testWidgets('heatmap marks the days the goal was met, with a legend', (tester) async {
      final store = TestProgressStore(settings: {LearnerSettingKeys.dailyGoalXp: '20'});
      await seedXpToday(store, 24);
      await pumpApp(tester, store: store, size: const Size(400, 1000), initialLocation: Routes.progress);
      final today = LocalCalendar.utc.dateOf(testNow);
      expect(find.byKey(ValueKey('goal-$today')), findsOneWidget);
      expect(find.byKey(ValueKey('goal-${today.addDays(-1)}')), findsNothing);
      expect(find.byKey(const ValueKey('heatmap-goal-legend')), findsOneWidget);
    });

    test('goalMetDays and DailyGoalStatus', () {
      final d = LocalDate(2026, 10, 14);
      expect(goalMetDays({d: 50, d.addDays(-1): 49}, 50), {d});
      expect(goalMetDays({d: 500}, 0), isEmpty);
      const s = DailyGoalStatus(goalXp: 50, todayXp: 30);
      expect(s.met, isFalse);
      expect(s.remaining, 20);
      expect(s.progress, closeTo(0.6, 1e-9));
      expect(const DailyGoalStatus(goalXp: 0, todayXp: 30).enabled, isFalse);
    });
  });

  group('reminder', () {
    final now = DateTime.utc(2026, 10, 14, 12);
    final today = LocalDate(2026, 10, 14);
    DateTime utcWall(LocalDate d, int h, int m) => DateTime.utc(d.year, d.month, d.day, h, m);

    test('plan: the next 7 days at the time; not today once the goal is met or the time has passed', () {
      List<ReminderSlot> plan({int todayXp = 0, int hour = 19, bool enabled = true, int goal = 50}) => planReminders(
        enabled: enabled,
        goalXp: goal,
        todayXp: todayXp,
        today: today,
        now: now,
        hour: hour,
        minute: 30,
        wallClock: utcWall,
      );
      final open = plan();
      expect(open, hasLength(7));
      expect(open.first, ReminderSlot(today, DateTime.utc(2026, 10, 14, 19, 30)));
      expect(open.last.date, today.addDays(6));
      final met = plan(todayXp: 50);
      expect(met, hasLength(6));
      expect(met.first.date, today.addDays(1));
      expect(plan(hour: 9).first.date, today.addDays(1), reason: '9:30 has passed');
      expect(plan(enabled: false), isEmpty);
      expect(plan(goal: 0), isEmpty);
    });

    test('plan follows the device clock across a DST switch (wall time stays 19:30)', () {
      // Europe/Amsterdam-like: +2 before 2026-10-25, +1 after.
      DateTime wall(LocalDate d, int h, int m) {
        final offset = d.isBefore(LocalDate(2026, 10, 25)) ? 2 : 1;
        return DateTime.utc(d.year, d.month, d.day, h, m).subtract(Duration(hours: offset));
      }

      final slots = planReminders(
        enabled: true,
        goalXp: 20,
        todayXp: 0,
        today: LocalDate(2026, 10, 23),
        now: DateTime.utc(2026, 10, 23, 8),
        hour: 19,
        minute: 30,
        wallClock: wall,
      );
      expect(slots[1].at, DateTime.utc(2026, 10, 24, 17, 30));
      expect(slots[2].at, DateTime.utc(2026, 10, 25, 18, 30));
    });

    testWidgets('switching it on asks for permission and schedules; reaching the goal drops today', (tester) async {
      final backend = FakeReminderBackend();
      final store = await pumpApp(
        tester,
        size: const Size(400, 1000),
        overrides: [reminderBackendProvider.overrideWithValue(backend)],
      );
      await goTab(tester, 'Settings');
      await tapKey(tester, 'reminder-switch');
      expect(backend.permissionRequests, 1);
      expect(store.settings[LearnerSettingKeys.reminderEnabled], 'true');
      expect(find.byKey(const ValueKey('reminder-time')), findsOneWidget);
      // testNow is 12:00 UTC; the default 19:00 is still ahead today.
      expect(backend.scheduled.last, hasLength(7));

      // A session that reaches the goal: today's reminder goes.
      await seedXpToday(store, 56);
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      container.read(progressRevisionProvider.notifier).bump();
      await tester.pumpAndSettle();
      expect(backend.scheduled.last, hasLength(6));

      await tapKey(tester, 'reminder-switch');
      expect(store.settings[LearnerSettingKeys.reminderEnabled], 'false');
      expect(backend.scheduled.last, isEmpty, reason: 'cancelled');
    });

    testWidgets('permission denied: stays off with a message; unsupported: no reminder option', (tester) async {
      final denied = FakeReminderBackend(grant: false);
      final store = await pumpApp(
        tester,
        size: const Size(400, 1000),
        overrides: [reminderBackendProvider.overrideWithValue(denied)],
      );
      await goTab(tester, 'Settings');
      await tapKey(tester, 'reminder-switch');
      expect(store.settings[LearnerSettingKeys.reminderEnabled], isNot('true'));
      expect(find.byKey(const ValueKey('reminder-denied')), findsOneWidget);
      expect(denied.scheduled, isEmpty);
      await tester.pumpWidget(const SizedBox());

      await pumpApp(
        tester,
        size: const Size(400, 1000),
        overrides: [reminderBackendProvider.overrideWithValue(FakeReminderBackend(supported: false))],
      );
      await goTab(tester, 'Settings');
      await scrollToFind(tester, find.byKey(const ValueKey('setting-daily-goal')));
      expect(find.byKey(const ValueKey('setting-daily-goal')), findsOneWidget);
      expect(find.byKey(const ValueKey('reminder-switch')), findsNothing);
    });
  });

  group('backup', () {
    testWidgets('export writes every answer; import asks first, merges, and a second import adds nothing', (
      tester,
    ) async {
      final files = FakeBackupFiles();
      final source = TestProgressStore();
      await seedXpToday(source, 40);
      await pumpApp(tester, store: source, overrides: [backupFilesProvider.overrideWithValue(files)]);
      await goTab(tester, 'Settings');
      await tapKey(tester, 'backup-export');
      expect(files.saved.keys.single, 'tosk-backup-20261013.jsonl');
      expect(find.byKey(const ValueKey('backup-saved')), findsOneWidget);
      final text = utf8.decode(files.saved.values.single);
      expect(decodeBackup(text).events, hasLength(5));
      await tester.pumpWidget(const SizedBox());

      // Another device.
      final target = TestProgressStore();
      await pumpApp(tester, store: target, overrides: [backupFilesProvider.overrideWithValue(files)]);
      await goTab(tester, 'Settings');
      files.next = (name: 'tosk-backup-20261013.jsonl', bytes: files.saved.values.single);
      await tapKey(tester, 'backup-import');
      expect(find.byKey(const ValueKey('backup-confirm')), findsOneWidget);
      expect(find.textContaining('5 answers'), findsOneWidget);
      await tapKey(tester, 'backup-import-cancel');
      expect(await target.log(), isEmpty, reason: 'cancelled');

      await tapKey(tester, 'backup-import');
      await tapKey(tester, 'backup-import-confirm');
      expect(find.byKey(const ValueKey('backup-import-result')), findsOneWidget);
      expect(find.textContaining('5 new answers (0 already here)'), findsOneWidget);
      await tapKey(tester, 'backup-result-ok');
      expect((await target.log()).length, 5);
      expect(await target.allStates(), hasLength(5));

      await tapKey(tester, 'backup-import');
      await tapKey(tester, 'backup-import-confirm');
      expect(find.textContaining('0 new answers (5 already here)'), findsOneWidget);
      await tapKey(tester, 'backup-result-ok');
      expect((await target.log()).length, 5);
    });

    testWidgets('a file that is no backup is refused', (tester) async {
      final files = FakeBackupFiles()..next = (name: 'notes.txt', bytes: Uint8List.fromList(utf8.encode('hello')));
      final store = await pumpApp(tester, overrides: [backupFilesProvider.overrideWithValue(files)]);
      await goTab(tester, 'Settings');
      await tapKey(tester, 'backup-import');
      expect(find.byKey(const ValueKey('backup-invalid')), findsOneWidget);
      expect(await store.log(), isEmpty);
    });
  });

  group('map and player', () {
    testWidgets('long map: "Jump to current unit" scrolls to the first unfinished unit', (tester) async {
      final course = bigMapCourse();
      final store = TestProgressStore(settings: {'course.active': course.meta.id, 'courses.added': course.meta.id});
      // Units 1-5 finished (bronze), the rest available.
      final done = course.units.take(5).map((u) => u.id).toSet();
      final stats = {
        for (final s in course.skills)
          s.id: SkillStats(tier: done.contains(s.unitId) ? MapTier.bronze : MapTier.available),
      };
      await pumpApp(
        tester,
        size: const Size(360, 640),
        store: store,
        overrides: [
          courseCatalogProvider.overrideWithValue(BigCourseCatalog()),
          skillStatsProvider.overrideWith((ref) async => stats),
        ],
      );
      final jump = find.byKey(const ValueKey('jump-current-unit'));
      expect(jump, findsOneWidget);
      final unitId = currentUnitId([for (final s in course.skills) (unitId: s.unitId, skillId: s.id)], stats)!;
      expect(unitId, isNot(course.units.first.id));
      final title = find.text(course.units.firstWhere((u) => u.id == unitId).title['en']!, skipOffstage: false);
      expect(tester.getTopLeft(title).dy, greaterThan(640), reason: 'below the fold before');
      await tester.tap(jump);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title).dy, inInclusiveRange(40, 400), reason: 'the unit near the top after the jump');
    });

    testWidgets('short maps have no jump button', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const ValueKey('jump-current-unit')), findsNothing);
    });

    testWidgets('after Check on a tall grid the instruction is back in view; the next exercise starts at the top', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(320, 480),
        initialLocation: Routes.labPlay(skills: ['present-are'], types: [ExerciseType.conjGrid], length: 2),
      );
      final scroll = find.descendant(
        of: find.byKey(const ValueKey('exercise-scroll')),
        matching: find.byType(Scrollable),
      );
      // Filling the grid scrolls down to the tiles (ensureVisible).
      await answerCurrentNoContinue(tester, wrong: true);
      final instruction = find.text('Fill in the table');
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(tester.getTopLeft(instruction).dy, greaterThanOrEqualTo(appBarBottom));
      await tapKey(tester, 'continue-button');
      expect(tester.state<ScrollableState>(scroll.first).position.pixels, 0);
    });
  });
}
