/// Standalone preview of the progression widgets with fake data:
/// `flutter run -t lib/main_progression_preview.dart`.
library;

import 'package:flutter/material.dart';

import 'core/core.dart';
import 'progression/prng.dart';
import 'progression/progression.dart';
import 'ui/progression/progression_widgets.dart';

void main() => runApp(const ProgressionPreviewApp());

class ProgressionPreviewApp extends StatefulWidget {
  const ProgressionPreviewApp({super.key});

  @override
  State<ProgressionPreviewApp> createState() => _ProgressionPreviewAppState();
}

class _ProgressionPreviewAppState extends State<ProgressionPreviewApp> {
  bool _dark = false;
  bool _reduceMotion = false;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) =>
        ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: b));
    return MaterialApp(
      title: 'Progression preview',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: _PreviewHome(
        reduceMotion: _reduceMotion,
        dark: _dark,
        onDark: (v) => setState(() => _dark = v),
        onReduceMotion: (v) => setState(() => _reduceMotion = v),
      ),
    );
  }
}

class _PreviewData {
  _PreviewData() {
    final rng = XorShift32.fromString('preview');
    final counts = <LocalDate, int>{};
    for (var i = 0; i < 26 * 7; i++) {
      final d = today.addDays(-i);
      final r = rng.nextInt(100);
      if (i > 0 && i < 4) continue; // a recent gap, partly frozen
      if (r < 70) counts[d] = r < 10 ? 60 : rng.nextInt(40) + 1;
    }
    streak = computeStreak(counts, today: today);
    heatmap = HeatmapData.fromCounts(counts,
        from: today.startOfWeek.addDays(-7 * 25), to: today, frozen: streak.frozenDays, today: today);

    final week = Period.weekOf(today), month = Period.monthOf(today);
    final weekly = [
      for (final t in selectChallenges(week)) Challenge(template: t, period: week, progress: rng.nextInt(t.target + 20)),
    ];
    final monthly = [
      for (final t in selectChallenges(month)) Challenge(template: t, period: month, progress: rng.nextInt(t.target)),
    ];
    board = ChallengeBoard(week: week, month: month, weekly: weekly, monthly: monthly, badges: [
      EarnedBadge(
          id: 'streak:7', kind: BadgeKind.streak, title: '7-day streak', description: 'Practiced 7 days in a row',
          earnedOn: today.addDays(-30)),
      EarnedBadge(
          id: 'level:5', kind: BadgeKind.level, title: 'Level 5', description: 'Reached level 5',
          earnedOn: today.addDays(-20)),
      EarnedBadge(
          id: 'W:conj50', kind: BadgeKind.challenge, title: 'Conjugator', description: 'Get 50 conjugations right',
          earnedOn: today.addDays(-9), metric: ChallengeMetric.conjugations),
    ]);

    const verbs = [
      ('essere', 'to be'), ('avere', 'to have'), ('fare', 'to do'), ('andare', 'to go'),
      ('mangiare', 'to eat'), ('parlare', 'to speak'), ('dormire', 'to sleep'), ('vedere', 'to see'),
    ];
    const tenses = ['presente', 'passato_prossimo', 'imperfetto', 'futuro'];
    collection = VerbCollection(tenses: tenses, verbs: [
      for (final (lemma, gloss) in verbs)
        VerbCard(
          item: Item(id: 'it:$lemma', pos: 'verb', lemma: lemma, tr: {'en': [gloss]}),
          cells: [
            for (final t in tenses)
              VerbTenseCell(
                tense: t,
                facetId: 'it:$lemma#form:$t',
                mastery: VerbMastery.values[(rng.nextInt(4) + (lemma == 'essere' ? 3 : 0)).clamp(0, 3)],
                retrievability: 0.9,
              ),
          ],
        ),
    ]);

    FacetState st(String id, double s) => FacetState(
        facetId: id, stability: s, difficulty: 5, due: DateTime.utc(2026, 11), lastReview: DateTime.utc(2026, 10),
        reps: 3, lapses: 0, phase: CardPhase.review);
    summary = SessionProgressSummary(
      sessionId: 'preview',
      mode: 'lesson',
      startedAt: DateTime.utc(2026, 10, 13, 9),
      endedAt: DateTime.utc(2026, 10, 13, 9, 4),
      reviews: 12,
      correct: 11,
      xpEarned: 146,
      levelBefore: curve.levelFor(2340),
      levelAfter: curve.levelFor(2486),
      facetChanges: [
        for (final w in ['mangiare', 'parlare', 'ciao', 'grazie'])
          FacetChange(
              facetId: 'it:$w#rec', before: st('it:$w#rec', 2), after: st('it:$w#rec', 6), recallBefore: 0.7,
              recallAfter: 1, reviews: 2, mistakes: 0),
      ],
      tierChanges: const [
        TierChange(skillId: 'Greetings', from: SkillTier.silver, to: SkillTier.gold),
        TierChange(skillId: 'Present -are', from: SkillTier.started, to: SkillTier.bronze),
      ],
    );
  }

  static const curve = LevelCurve();
  final LocalDate today = LocalDate.fromDateTime(DateTime.now());
  late final StreakInfo streak;
  late final HeatmapData heatmap;
  late final ChallengeBoard board;
  late final VerbCollection collection;
  late final SessionProgressSummary summary;
  final LevelInfo level = curve.levelFor(4321);
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome({
    required this.reduceMotion,
    required this.dark,
    required this.onDark,
    required this.onReduceMotion,
  });

  final bool reduceMotion;
  final bool dark;
  final ValueChanged<bool> onDark;
  final ValueChanged<bool> onReduceMotion;

  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  final _data = _PreviewData();
  var _run = const NonStopRun();

  void _answer(bool ok) => setState(() => _run = _run.answer(correct: ok, at: DateTime.now()));

  @override
  Widget build(BuildContext context) {
    final rm = widget.reduceMotion;
    final theme = Theme.of(context);
    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            child,
          ]),
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progression preview'),
        actions: [
          const Icon(Icons.dark_mode_outlined),
          Switch(value: widget.dark, onChanged: widget.onDark),
          const Icon(Icons.motion_photos_off_outlined),
          Switch(value: rm, onChanged: widget.onReduceMotion),
        ],
      ),
      body: ListView(
        children: [
          section(
            'Profile',
            Row(children: [
              LevelBadge(level: _data.level, reduceMotion: rm),
              const SizedBox(width: 24),
              StreakCounter(streak: _data.streak, reduceMotion: rm, showLongest: true),
            ]),
          ),
          section('Heatmap', StreakHeatmap(data: _data.heatmap, reduceMotion: rm)),
          section(
            'Tiers',
            Wrap(spacing: 16, children: [
              for (final t in SkillTier.values) TierBadge(tier: t, size: 40, reduceMotion: rm, showLabel: true),
            ]),
          ),
          section('Challenges', ChallengesList(board: _data.board, today: _data.today, reduceMotion: rm)),
          section('Session summary', SessionSummaryCard(summary: _data.summary, reduceMotion: rm, onContinue: () {})),
          section(
            'Non-stop HUD',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              NonStopHud(run: _run, reduceMotion: rm),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(onPressed: () => _answer(true), child: const Text('Correct')),
                OutlinedButton(onPressed: () => _answer(false), child: const Text('Wrong')),
                TextButton(onPressed: () => setState(() => _run = const NonStopRun()), child: const Text('Reset')),
              ]),
            ]),
          ),
          section(
            'Verb collection',
            SizedBox(height: 640, child: VerbCollectionView(collection: _data.collection, reduceMotion: rm)),
          ),
        ],
      ),
    );
  }
}
