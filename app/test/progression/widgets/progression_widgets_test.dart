import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart';
import 'package:tosk/ui/progression/progression_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child, {Brightness brightness = Brightness.light, bool scroll = true}) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness)),
      home: Scaffold(body: scroll ? SingleChildScrollView(child: child) : child),
    );

FacetState st(String id, {double s = 30, CardPhase phase = CardPhase.review}) => FacetState(
    facetId: id, stability: s, difficulty: 5, due: DateTime.utc(2026, 11), lastReview: DateTime.utc(2026, 10),
    reps: 4, lapses: 0, phase: phase);

void main() {
  group('TierBadge', () {
    for (final brightness in Brightness.values) {
      testWidgets('renders every tier ($brightness)', (tester) async {
        await tester.pumpWidget(wrap(
          Wrap(children: [for (final t in SkillTier.values) TierBadge(tier: t, showLabel: true)]),
          brightness: brightness,
        ));
        await tester.pumpAndSettle();
        for (final t in SkillTier.values) {
          expect(find.bySemanticsLabel('${tierLabel(t)} tier'), findsOneWidget);
        }
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(find.byIcon(Icons.military_tech), findsNWidgets(3));
        expect(find.text('Gold'), findsOneWidget);
      });
    }

    testWidgets('reduceMotion disables the transition', (tester) async {
      await tester.pumpWidget(wrap(const TierBadge(tier: SkillTier.gold, reduceMotion: true)));
      expect(find.byType(AnimatedSwitcher), findsNothing);
      await tester.pumpWidget(wrap(const TierBadge(tier: SkillTier.gold)));
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
    });
  });

  group('LevelBadge', () {
    final info = const LevelCurve().levelFor(250); // level 2, 150 of 183

    testWidgets('shows level, XP and the ring at the right value', (tester) async {
      await tester.pumpWidget(wrap(LevelBadge(level: info, reduceMotion: true)));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('${info.xpIntoLevel} / ${info.xpForNext} XP'), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, closeTo(info.progress, 1e-9));
      expect(find.bySemanticsLabel(RegExp('Level 2')), findsOneWidget);
    });

    testWidgets('animates up to the value when motion is allowed', (tester) async {
      await tester.pumpWidget(wrap(LevelBadge(level: info), brightness: Brightness.dark));
      expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
      await tester.pumpAndSettle();
      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, closeTo(info.progress, 1e-9));
    });
  });

  group('StreakHeatmap', () {
    const today = LocalDate(2026, 10, 13);
    final data = HeatmapData(
      from: const LocalDate(2026, 9, 7),
      to: today,
      counts: {const LocalDate(2026, 9, 7): 3, const LocalDate(2026, 10, 1): 60, today: 12},
      frozen: {const LocalDate(2026, 10, 2)},
      today: today,
    );

    for (final reduce in [true, false]) {
      testWidgets('renders cells, frozen days and legend (reduceMotion: $reduce)', (tester) async {
        LocalDate? tapped;
        await tester.pumpWidget(wrap(StreakHeatmap(data: data, reduceMotion: reduce, onDayTap: (d) => tapped = d)));
        await tester.pumpAndSettle();
        for (final d in data.days) {
          expect(find.byKey(ValueKey('heat-$d')), findsOneWidget, reason: '$d');
        }
        expect(find.byKey(const ValueKey('heat-2026-10-14')), findsNothing); // after range
        expect(find.bySemanticsLabel('2026-10-01: 60 reviews'), findsOneWidget);
        expect(find.bySemanticsLabel('2026-10-02: 0 reviews (streak freeze)'), findsOneWidget);
        expect(find.text('Oct'), findsOneWidget);
        expect(find.text('Sep'), findsOneWidget);
        expect(find.text('Less'), findsOneWidget);
        expect(find.byType(AnimatedContainer), reduce ? findsNothing : findsWidgets);
        await tester.tap(find.byKey(const ValueKey('heat-2026-10-13')));
        expect(tapped, today);
      });
    }

    testWidgets('long ranges scroll horizontally and open at the latest week', (tester) async {
      final long = HeatmapData(from: today.addDays(-364), to: today, counts: {today: 5}, today: today);
      await tester.pumpWidget(wrap(StreakHeatmap(data: long, reduceMotion: true), brightness: Brightness.dark));
      final scroll = tester.widget<SingleChildScrollView>(
          find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal));
      expect(scroll.reverse, isTrue);
      // Today's cell is visible on screen without scrolling.
      final rect = tester.getRect(find.byKey(ValueKey('heat-$today')));
      expect(rect.right, lessThanOrEqualTo(800));
      expect(rect.left, greaterThanOrEqualTo(0));
    });
  });

  group('StreakCounter', () {
    testWidgets('shows the streak and freezes', (tester) async {
      final s = computeStreak({const LocalDate(2026, 10, 12): 120, const LocalDate(2026, 10, 13): 1},
          today: const LocalDate(2026, 10, 13));
      await tester.pumpWidget(wrap(StreakCounter(streak: s, reduceMotion: true, showLongest: true)));
      expect(find.text('2'), findsOneWidget);
      expect(find.byIcon(Icons.ac_unit), findsNWidgets(2));
      expect(find.text('best 2'), findsOneWidget);
      expect(find.bySemanticsLabel('2 day streak, 2 streak freezes'), findsOneWidget);
    });
  });

  group('ChallengesList', () {
    final week = Period.weekOf(const LocalDate(2026, 10, 13));
    final month = Period.monthOf(const LocalDate(2026, 10, 13));
    final board = ChallengeBoard(
      week: week,
      month: month,
      weekly: [
        Challenge(template: weeklyChallengePool[0], period: week, progress: 37),
        Challenge(
            template: weeklyChallengePool[2], period: week, progress: 55, completedAt: DateTime.utc(2026, 10, 12)),
      ],
      monthly: [Challenge(template: monthlyChallengePool[0], period: month, progress: 0)],
      badges: [
        EarnedBadge(
            id: 'streak:7', kind: BadgeKind.streak, title: '7-day streak', description: 'x',
            earnedOn: const LocalDate(2026, 10, 1)),
        EarnedBadge(
            id: 'W2026-41:conj50', kind: BadgeKind.challenge, title: 'Conjugator', description: 'y',
            earnedOn: const LocalDate(2026, 10, 9), metric: ChallengeMetric.conjugations),
      ],
    );

    testWidgets('shows progress, completion and badges', (tester) async {
      await tester.pumpWidget(wrap(ChallengesList(board: board, today: const LocalDate(2026, 10, 13), reduceMotion: true)));
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('6 days left'), findsOneWidget);
      expect(find.text('19 days left'), findsOneWidget);
      expect(find.text('37/150'), findsOneWidget);
      expect(find.text('0/1000'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('7-day streak'), findsOneWidget);
      expect(find.text('Conjugator'), findsNWidgets(2)); // challenge title + badge
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
      expect(bars.map((b) => b.value), [closeTo(37 / 150, 1e-9), 1.0, 0.0]);
    });

    testWidgets('animated bars settle at the same values; empty badge shelf', (tester) async {
      final empty = ChallengeBoard(week: week, month: month, weekly: board.weekly, monthly: board.monthly, badges: const []);
      await tester.pumpWidget(wrap(ChallengesList(board: empty), brightness: Brightness.dark));
      expect(find.byType(TweenAnimationBuilder<double>), findsNWidgets(3));
      await tester.pumpAndSettle();
      final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
      expect(bars.first.value, closeTo(37 / 150, 1e-9));
      expect(find.textContaining('first badge'), findsOneWidget);
      expect(find.textContaining('days left'), findsNothing); // no today given
    });
  });

  group('VerbCollectionView', () {
    const parlare = Item(id: 'it:parlare', pos: 'verb', lemma: 'parlare', tr: {'en': ['to speak'], 'nl': ['spreken']});
    const mangiare = Item(id: 'it:mangiare', pos: 'verb', lemma: 'mangiare', tr: {'en': ['to eat']});
    VerbTenseCell cell(String item, String tense, VerbMastery m) =>
        VerbTenseCell(tense: tense, facetId: '$item#form:$tense', mastery: m, retrievability: 0.9);
    final collection = VerbCollection(tenses: const [
      'presente',
      'passato_prossimo',
    ], verbs: [
      VerbCard(item: parlare, cells: [
        cell('it:parlare', 'presente', VerbMastery.mastered),
        cell('it:parlare', 'passato_prossimo', VerbMastery.mastered),
      ]),
      VerbCard(item: mangiare, cells: [
        cell('it:mangiare', 'presente', VerbMastery.known),
        cell('it:mangiare', 'passato_prossimo', VerbMastery.unseen),
      ]),
    ]);

    for (final reduce in [true, false]) {
      testWidgets('cards with tense pills lit by mastery (reduceMotion: $reduce)', (tester) async {
        VerbCard? tapped;
        await tester.pumpWidget(wrap(
          VerbCollectionView(
            collection: collection,
            lang: 'nl',
            tenseLabel: (t) => t == 'presente' ? 'Present' : 'Perfect',
            reduceMotion: reduce,
            onVerbTap: (v) => tapped = v,
          ),
          scroll: false,
        ));
        await tester.pumpAndSettle();
        expect(find.text('2 of 4 tables mastered'), findsOneWidget);
        expect(find.text('parlare'), findsOneWidget);
        expect(find.text('spreken'), findsOneWidget); // gloss in nl
        expect(find.text('to eat'), findsOneWidget); // falls back to en
        expect(find.bySemanticsLabel(RegExp('Present: Mastered')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Perfect: Unseen')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Present: Known')), findsOneWidget);
        expect(find.byIcon(Icons.star), findsOneWidget); // parlare complete
        expect(find.byType(AnimatedContainer), reduce ? findsNothing : findsNWidgets(4));
        await tester.tap(find.text('mangiare'));
        expect(tapped?.itemId, 'it:mangiare');
      });
    }

    testWidgets('no overflow on a narrow phone with large text', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 740), textScaler: TextScaler.linear(1.6)),
          child: Scaffold(body: VerbCollectionView(collection: collection, reduceMotion: true)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('parlare'), findsOneWidget);
    });

    testWidgets('empty collection and the full page', (tester) async {
      await tester.pumpWidget(wrap(const VerbCollectionView(collection: VerbCollection(tenses: [], verbs: []))));
      expect(find.text('No verbs in this course yet.'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(home: VerbCollectionPage(collection: collection, reduceMotion: true)));
      expect(find.text('Verb collection'), findsOneWidget);
      expect(find.text('passato prossimo'), findsNWidgets(2)); // default label
    });
  });

  group('SessionSummaryCard', () {
    SessionProgressSummary summary({bool levelUp = true}) => SessionProgressSummary(
          sessionId: 's1',
          mode: 'lesson',
          startedAt: DateTime.utc(2026, 10, 13, 9),
          endedAt: DateTime.utc(2026, 10, 13, 9, 4),
          reviews: 12,
          correct: 10,
          xpEarned: 123,
          levelBefore: const LevelCurve().levelFor(levelUp ? 50 : 120),
          levelAfter: const LevelCurve().levelFor(levelUp ? 173 : 243),
          facetChanges: [
            FacetChange(
                facetId: 'it:ciao#rec', before: null, after: st('it:ciao#rec'), recallBefore: 0, recallAfter: 1,
                reviews: 2, mistakes: 1),
            FacetChange(
                facetId: 'it:grazie#rec', before: st('it:grazie#rec', s: 3), after: st('it:grazie#rec', s: 8),
                recallBefore: 0.8, recallAfter: 1, reviews: 1, mistakes: 0),
            FacetChange(
                facetId: 'it:prego#rec', before: st('it:prego#rec', s: 8), after: st('it:prego#rec', s: 2),
                recallBefore: 0.8, recallAfter: 1, reviews: 1, mistakes: 1),
          ],
          tierChanges: const [
            TierChange(skillId: 'greetings', from: SkillTier.started, to: SkillTier.bronze),
            TierChange(skillId: 'food', from: SkillTier.gold, to: SkillTier.silver),
          ],
        );

    testWidgets('shows XP, accuracy, level-up, tiers and improved words', (tester) async {
      var continued = false;
      await tester.pumpWidget(wrap(SessionSummaryCard(
        summary: summary(),
        reduceMotion: true,
        itemLabel: (id) => id == 'it:ciao' ? 'ciao!' : null,
        skillLabel: (id) => id.toUpperCase(),
        onContinue: () => continued = true,
      )));
      expect(find.text('+123 XP'), findsOneWidget);
      expect(find.text('83% correct · 10/12 answers'), findsOneWidget);
      expect(find.text('Level up! 1 → 2'), findsOneWidget);
      expect(find.text('GREETINGS'), findsOneWidget);
      expect(find.text('Bronze'), findsOneWidget);
      expect(find.text('Silver'), findsOneWidget);
      expect(find.text('Stronger now (2)'), findsOneWidget);
      expect(find.text('ciao!'), findsOneWidget);
      expect(find.text('grazie'), findsOneWidget);
      expect(find.text('prego'), findsNothing); // got weaker
      await tester.tap(find.text('Continue'));
      expect(continued, isTrue);
    });

    testWidgets('XP counts up when motion is allowed; no level-up banner without one', (tester) async {
      await tester.pumpWidget(wrap(SessionSummaryCard(summary: summary(levelUp: false)), brightness: Brightness.dark));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('+123 XP'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('+123 XP'), findsOneWidget);
      expect(find.textContaining('Level up'), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });
  });

  group('NonStopHud', () {
    final t0 = DateTime.utc(2026, 10, 13, 18);

    NonStopRun play(int correct, {int wrongAtEnd = 0}) {
      var run = const NonStopRun();
      var at = t0;
      for (var i = 0; i < correct; i++) {
        at = at.add(const Duration(seconds: 2));
        run = run.answer(correct: true, at: at);
      }
      for (var i = 0; i < wrongAtEnd; i++) {
        at = at.add(const Duration(seconds: 2));
        run = run.answer(correct: false, at: at);
      }
      return run;
    }

    testWidgets('score, multiplier, combo and bonus progress', (tester) async {
      final run = play(7);
      await tester.pumpWidget(wrap(NonStopHud(
        run: run,
        clock: () => run.lastAnswerAt!,
        reduceMotion: true,
        best: NonStopRecord(
            sessionId: 'b', score: 999, answered: 1, correct: 1, bestCombo: 1, bonusRoundsCompleted: 0,
            startedAt: t0, endedAt: t0),
      )));
      expect(find.text('${run.score}'), findsOneWidget);
      expect(find.text('×1.5'), findsOneWidget);
      expect(find.text('Combo 7'), findsOneWidget);
      expect(find.text('Bonus in 18'), findsOneWidget);
      expect(find.text('Best 999'), findsOneWidget);
      expect(find.byKey(const ValueKey('bonus-banner')), findsNothing);
      expect(find.byType(AnimatedSwitcher), findsNothing);
    });

    testWidgets('bonus round countdown ticks and disappears at the deadline', (tester) async {
      final run = play(25);
      var now = run.lastAnswerAt!;
      await tester.pumpWidget(wrap(NonStopHud(run: run, clock: () => now)));
      expect(find.byKey(const ValueKey('bonus-banner')), findsOneWidget);
      expect(find.text('Conjugation blitz ×2'), findsOneWidget);
      expect(find.text('10 left'), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget);
      expect(find.text('×3'), findsOneWidget);
      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:55'), findsOneWidget);
      now = now.add(const Duration(seconds: 56));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bonus-banner')), findsNothing);
      // Disposing with the timer stopped leaves nothing pending.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('timer is cancelled when the round ends via a new run and on dispose', (tester) async {
      final run = play(25);
      await tester.pumpWidget(wrap(NonStopHud(run: run, clock: () => run.lastAnswerAt!, reduceMotion: true)));
      expect(find.byKey(const ValueKey('bonus-banner')), findsOneWidget);
      final after = play(25, wrongAtEnd: 0).tick(run.bonusRound!.deadline.add(const Duration(seconds: 1)));
      await tester.pumpWidget(wrap(NonStopHud(run: after, clock: () => run.lastAnswerAt!, reduceMotion: true)));
      expect(find.byKey(const ValueKey('bonus-banner')), findsNothing);
      await tester.pumpWidget(wrap(NonStopHud(run: run, clock: () => run.lastAnswerAt!)));
      await tester.pumpWidget(const SizedBox()); // dispose while active
    });

    testWidgets('a broken combo shows x1', (tester) async {
      final run = play(12, wrongAtEnd: 1);
      await tester.pumpWidget(wrap(NonStopHud(run: run, clock: () => run.lastAnswerAt!), brightness: Brightness.dark));
      await tester.pumpAndSettle();
      expect(find.text('×1'), findsOneWidget);
      expect(find.text('Combo 0'), findsOneWidget);
    });
  });
}
