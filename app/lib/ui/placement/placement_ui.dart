/// Placement in the app (docs/ui.md, "Placement"): the choice when a course
/// is added ("New to Italian?"), the result card ("You placed into Unit 7:
/// …"), and "Skip ahead without a test" ([SkipAheadScreen]).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../brand/tosk.dart';
import '../map/skill_stats.dart' show MapTier;
import '../routes.dart';
import '../theme/bw_skin.dart';
import '../theme/tosk_palette.dart';

/// What the learner wants when a course is added (or from Settings).
enum PlacementChoice {
  /// Start at unit 1.
  beginning,

  /// The placement test.
  findLevel,

  /// Mark units as known without a test.
  skipAhead,
}

/// Asks where to start with a course: "New to Italian?". With [rerun]
/// (Settings → "Find my level again") the first choice is Cancel instead.
Future<PlacementChoice?> showPlacementChoice(BuildContext context, {required String language, bool rerun = false}) =>
    showDialog<PlacementChoice>(
      context: context,
      builder: (context) => PlacementChoiceDialog(language: language, rerun: rerun),
    );

/// The dialog behind [showPlacementChoice]. Three full-width choices with an
/// icon, a title and a line each (never colour alone); the test is the filled
/// one.
class PlacementChoiceDialog extends StatelessWidget {
  const PlacementChoiceDialog({super.key, required this.language, this.rerun = false});
  final String language;
  final bool rerun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void pick(PlacementChoice c) => Navigator.of(context).pop(c);
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(rerun ? 'Find your level again' : 'New to $language?', key: const ValueKey('placement-question')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rerun)
              Text(
                'A short test from where you are now, or mark units as known yourself. '
                'Nothing you have learned is taken away.',
                style: theme.textTheme.bodyMedium,
              ),
            if (rerun) const SizedBox(height: 16),
            if (!rerun) ...[
              _ChoiceButton(
                key: const ValueKey('placement-scratch'),
                icon: Icons.flag_outlined,
                title: 'Yes, start at the beginning',
                line: 'Unit 1, one small step at a time.',
                onPressed: () => pick(PlacementChoice.beginning),
              ),
              const SizedBox(height: 10),
            ],
            _ChoiceButton(
              key: const ValueKey('placement-find'),
              icon: Icons.route_outlined,
              title: rerun ? 'Take the placement test' : 'I already know some — find my level',
              line: 'Up to 40 questions, unit by unit; stop any time.',
              filled: true,
              onPressed: () => pick(PlacementChoice.findLevel),
            ),
            const SizedBox(height: 10),
            _ChoiceButton(
              key: const ValueKey('placement-skip'),
              icon: Icons.fast_forward_outlined,
              title: 'Skip ahead without a test',
              line: 'Tick the units you know. They come back for review soon.',
              onPressed: () => pick(PlacementChoice.skipAhead),
            ),
          ],
        ),
      ),
      actions: [
        if (rerun)
          TextButton(
            key: const ValueKey('placement-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    super.key,
    required this.icon,
    required this.title,
    required this.line,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String title;
  final String line;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = filled ? scheme.onPrimary : scheme.onSurface;
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(line, style: theme.textTheme.bodySmall?.copyWith(color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 56)),
      alignment: AlignmentDirectional.centerStart,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    );
    return filled
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(
            onPressed: onPressed,
            style: style.copyWith(
              side: WidgetStatePropertyAll(BorderSide(color: scheme.outline, width: isBw(context) ? 2 : 1)),
            ),
            child: child,
          );
  }
}

/// Starts what [choice] asks for, for the active course: the test
/// ([Routes.placement]) or "Skip ahead" ([Routes.skipAhead]).
void startPlacement(GoRouter? router, PlacementChoice? choice) {
  switch (choice) {
    case PlacementChoice.findLevel:
      router?.push(Routes.placement);
    case PlacementChoice.skipAhead:
      router?.push(Routes.skipAhead);
    case PlacementChoice.beginning || null:
      break;
  }
}

// ---------------------------------------------------------------- labels

/// "Unit 3: Past tense" (the number counts main-tree units).
String placementUnitLabel(CourseData course, String unitId, String lang) {
  final main = CourseTrees.of(course).mainUnits;
  final i = main.indexWhere((u) => u.id == unitId);
  final unit = i < 0 ? course.units.where((u) => u.id == unitId).firstOrNull : main[i];
  final title = unit == null ? unitId : pickLang(unit.title, lang);
  return i < 0 ? title : 'Unit ${i + 1}: $title';
}

/// "Units 1–4, 6" from main-tree unit ids.
String unitRanges(CourseData course, Iterable<String> unitIds) {
  final main = CourseTrees.of(course).mainUnits;
  final nums = [
    for (final id in unitIds)
      if (main.indexWhere((u) => u.id == id) case final i when i >= 0) i + 1,
  ]..sort();
  if (nums.isEmpty) return '';
  final parts = <String>[];
  var start = nums.first, prev = nums.first;
  void flush() => parts.add(start == prev ? '$start' : (prev == start + 1 ? '$start, $prev' : '$start–$prev'));
  for (final n in nums.skip(1)) {
    if (n == prev + 1) {
      prev = n;
      continue;
    }
    flush();
    start = prev = n;
  }
  flush();
  return '${nums.length == 1 ? 'Unit' : 'Units'} ${parts.join(', ')}';
}

// ---------------------------------------------------------------- result

/// The result of a placement (test or self-declared) on the session summary
/// and the skip-ahead screen: where the learner continues, what is now
/// learned and open, what wasn't asked or has gaps, and when the words come
/// back. Icons and words, never colour alone. Brings the placed unit into
/// view on the map ([mapFocusProvider]).
class PlacementResultCard extends ConsumerStatefulWidget {
  const PlacementResultCard({super.key, required this.outcome, this.showTosk = true});
  final AssessmentOutcome outcome;

  /// Tosk beside the headline (off on the session summary, which has its own).
  final bool showTosk;

  @override
  ConsumerState<PlacementResultCard> createState() => _PlacementResultCardState();
}

class _PlacementResultCardState extends ConsumerState<PlacementResultCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final course = ref.read(courseDataProvider).value;
      final placed = widget.outcome.placedUnit;
      if (course == null || placed == null) return;
      final first = course.skills.where((s) => s.unitId == placed).firstOrNull;
      if (first != null) ref.read(mapFocusProvider.notifier).focus(first.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.outcome;
    final theme = Theme.of(context);
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final mono = isBw(context);
    if (course == null) return const SizedBox.shrink();
    final placed = o.placedUnit;
    final String headline;
    if (placed == null && o.passed) {
      headline = 'You know the whole main tree';
    } else if (!o.passed) {
      headline = 'Start at the beginning: ${placementUnitLabel(course, placed ?? CourseTrees.of(course).mainUnits.first.id, lang)}';
    } else {
      headline = '${o.selfDeclared ? 'You skipped ahead to' : 'You placed into'} ${placementUnitLabel(course, placed!, lang)}';
    }
    final trees = CourseTrees.of(course);
    final credited = o.creditedSkills.toSet();
    final topics = [
      for (final t in trees.topics)
        if (credited.contains(t.anchor)) t.titleIn(lang),
    ];
    final skillCount = credited.length;
    final lines = <(IconData, String, String)>[
      if (o.passedUnits.isNotEmpty)
        (
          Icons.check_circle_outline,
          'placement-learned',
          'Marked as learned: ${unitRanges(course, o.passedUnits)} ($skillCount skill${skillCount == 1 ? '' : 's'}).',
        ),
      if (placed != null && o.passed)
        (Icons.lock_open, 'placement-unlocked', 'Open now: ${placementUnitLabel(course, placed, lang)}.'),
      if (placed == null && o.passed) (Icons.lock_open, 'placement-unlocked', 'Every unit of the main tree is open.'),
      if (topics.isNotEmpty)
        (
          Icons.alt_route,
          'placement-topics',
          '${topics.length == 1 ? 'Topic' : 'Topics'} open from their branches: ${topics.join(', ')}.',
        ),
      if (o.inferredUnits.isNotEmpty)
        (
          Icons.fast_forward_outlined,
          'placement-inferred',
          '${unitRanges(course, o.inferredUnits)} ${o.inferredUnits.length == 1 ? 'was' : 'were'} skipped: '
              'the unit after went well, so ${o.inferredUnits.length == 1 ? 'it counts' : 'they count'} too.',
        ),
      for (final g in o.gapUnits)
        (
          Icons.construction_outlined,
          'placement-gap-$g',
          '${placementUnitLabel(course, g, lang)} still has gaps: it stays open to practise.',
        ),
      if (o.passed)
        (
          Icons.event_repeat,
          'placement-review',
          o.selfDeclared
              ? 'You marked these yourself, so their words come back for review in about 2 days. '
                    'If a skill turns out to be new, reset it from its sheet on the map.'
              : 'Their words come back for a light review in a few days: nothing counts as mastered yet.',
        ),
      if (!o.selfDeclared && o.total > 0)
        (Icons.quiz_outlined, 'placement-score', '${o.correct} of ${o.total} answers right.'),
    ];
    return Card(
      key: const ValueKey('placement-result'),
      margin: const EdgeInsets.only(bottom: 16),
      color: mono ? kBwWhite : theme.colorScheme.primaryContainer,
      shape: mono
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kBwBlack, width: 2))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.showTosk) ...[
                  ToskImage(pose: o.passed ? ToskPose.celebrating : ToskPose.pointing, height: 64),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      headline,
                      key: const ValueKey('placement-headline'),
                      style: theme.textTheme.serifTitle?.copyWith(
                        color: mono ? kBwBlack : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final (icon, key, text) in lines)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: mono ? kBwBlack : theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        key: ValueKey(key),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: mono ? kBwBlack : theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- skip ahead

/// "Skip ahead without a test" (route [Routes.skipAhead]): a warning, the
/// main-tree units to tick (ticking one ticks the ones before it; units
/// already learned are ticked and fixed), and "Mark N units as known" pinned
/// at the bottom. Credits are self-declared ([SessionFactory.skipAhead]);
/// the result card follows.
class SkipAheadScreen extends ConsumerStatefulWidget {
  const SkipAheadScreen({super.key});

  @override
  ConsumerState<SkipAheadScreen> createState() => _SkipAheadScreenState();
}

class _SkipAheadScreenState extends ConsumerState<SkipAheadScreen> {
  final Set<String> _ticked = {};
  bool _busy = false;
  AssessmentOutcome? _outcome;
  Object? _error;

  Future<void> _confirm(List<String> unitIds) async {
    if (_busy || unitIds.isEmpty) return;
    setState(() => _busy = true);
    try {
      final factory = await ref.read(sessionFactoryProvider.future);
      final o = await factory.skipAhead(unitIds);
      ref.read(progressRevisionProvider.notifier).bump();
      if (mounted) setState(() => _outcome = o);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.map);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final stats = ref.watch(skillStatsProvider).value ?? const {};
    final mono = isBw(context);
    final outcome = _outcome;

    Widget pinned(Widget child) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: child),
        ),
      ),
    );

    Widget body;
    Widget? bottom;
    if (course == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (outcome != null) {
      body = _Column(children: [PlacementResultCard(outcome: outcome)]);
      bottom = pinned(
        FilledButton(
          key: const ValueKey('skip-ahead-done'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _close,
          child: const Text('Done'),
        ),
      );
    } else {
      final main = [
        for (final u in CourseTrees.of(course).mainUnits)
          if (course.skills.any((s) => s.unitId == u.id && course.skillFacets(s.id).isNotEmpty)) u,
      ];
      bool learned(Unit u) => course.skills
          .where((s) => s.unitId == u.id && course.skillFacets(s.id).isNotEmpty)
          .every((s) => (stats[s.id]?.tier.index ?? 0) >= MapTier.bronze.index);
      final chosen = [for (final u in main) if (_ticked.contains(u.id) && !learned(u)) u.id];
      body = _Column(
        children: [
          Container(
            key: const ValueKey('skip-ahead-warning'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: mono ? kBwWhite : theme.colorScheme.tertiaryContainer,
              border: mono ? Border.all(color: kBwBlack, width: 2) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: mono ? kBwBlack : theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Without a test, Tosk takes your word for it. The units you tick count as learned and '
                    'unlock what follows, but their words come back for review in about 2 days. If a skill '
                    'turns out to be new, reset it from its sheet on the map. Not sure? Take the test instead.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: mono ? kBwBlack : theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Which units do you know?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Ticking a unit also ticks the ones before it.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final (i, u) in main.indexed)
            _UnitTile(
              key: ValueKey('skip-unit-${u.id}'),
              number: i + 1,
              title: pickLang(u.title, lang),
              skills: [
                for (final s in course.skills)
                  if (s.unitId == u.id && course.skillFacets(s.id).isNotEmpty) pickLang(s.title, lang),
              ],
              learned: learned(u),
              ticked: learned(u) || _ticked.contains(u.id),
              onChanged: (v) => setState(() {
                if (v) {
                  for (final m in main.take(i + 1)) {
                    _ticked.add(m.id);
                  }
                } else {
                  _ticked.remove(u.id);
                }
              }),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline),
                  const SizedBox(width: 8),
                  Expanded(child: Text("Couldn't mark the units: $_error")),
                ],
              ),
            ),
        ],
      );
      final n = chosen.length;
      bottom = pinned(
        FilledButton.icon(
          key: const ValueKey('skip-ahead-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: n == 0 || _busy ? null : () => unawaited(_confirm(chosen)),
          icon: const Icon(Icons.fast_forward),
          label: Text(n == 0 ? 'Tick the units you know' : 'Mark $n unit${n == 1 ? '' : 's'} as known'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('skip-ahead-close'),
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
        title: Text(outcome == null ? 'Skip ahead' : 'Your level'),
      ),
      body: Column(
        children: [
          Expanded(child: body),
          ?bottom,
        ],
      ),
    );
  }
}

/// A scrolling, centred column of at most 640 dp.
class _Column extends StatelessWidget {
  const _Column({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ),
  );
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({
    super.key,
    required this.number,
    required this.title,
    required this.skills,
    required this.learned,
    required this.ticked,
    required this.onChanged,
  });

  final int number;
  final String title;
  final List<String> skills;
  final bool learned;
  final bool ticked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = isBw(context);
    final sample = skills.take(3).join(', ') + (skills.length > 3 ? ', …' : '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: CheckboxListTile(
        value: ticked,
        onChanged: learned ? null : (v) => onChanged(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: ticked ? theme.colorScheme.onSurface : theme.colorScheme.outlineVariant,
            // The ticked state also shows as a heavier frame (not colour alone).
            width: ticked ? (mono ? 3 : 2) : 1,
          ),
        ),
        title: Text(
          'Unit $number: $title',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: ticked ? FontWeight.w700 : FontWeight.w500),
        ),
        subtitle: Text(learned ? 'Already learned · $sample' : sample),
      ),
    );
  }
}
