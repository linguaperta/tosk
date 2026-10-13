import 'dart:async';

import 'package:flutter/material.dart';

import '../../progression/progression.dart';
import '../theme/bw_skin.dart';
import 'progression_colors.dart';

/// Heads-up display for non-stop mode: score, combo multiplier, progress to the
/// next bonus round, and the bonus-round countdown while one is active.
///
/// While a bonus round is active the countdown refreshes once a second (also
/// with [reduceMotion]; only transitions are disabled then).
class NonStopHud extends StatefulWidget {
  const NonStopHud({
    super.key,
    required this.run,
    this.best,
    this.clock = DateTime.now,
    this.reduceMotion = false,
  });

  final NonStopRun run;

  /// Best previous run, shown as a target.
  final NonStopRecord? best;

  /// Current time for the countdown (injectable for tests).
  final DateTime Function() clock;
  final bool reduceMotion;

  @override
  State<NonStopHud> createState() => _NonStopHudState();
}

class _NonStopHudState extends State<NonStopHud> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(NonStopHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    final active = widget.run.bonusRound != null;
    if (active && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        final round = widget.run.bonusRound;
        if (round == null || round.isExpired(widget.clock())) _stopTimer();
      });
    } else if (!active) {
      _stopTimer();
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  Widget _animated(Widget child) => widget.reduceMotion
      ? child
      : AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: child,
        );

  static String _mmss(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  static String _mult(double m) => m == m.roundToDouble() ? '×${m.toInt()}' : '×${m.toStringAsFixed(1)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final run = widget.run;
    final now = widget.clock();
    final round = run.bonusRound;
    final live = round != null && !round.isExpired(now);
    final multColor = run.multiplier > 1 ? ProgressionColors.flame(cs) : cs.onSurfaceVariant;

    final scoreText = Text(
      '${run.score}',
      key: ValueKey('score-${run.score}'),
      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
    );
    final multText = Text(
      _mult(run.multiplier),
      key: ValueKey('mult-${run.multiplier}'),
      style: theme.textTheme.titleLarge?.copyWith(color: multColor, fontWeight: FontWeight.bold),
    );

    return Semantics(
      container: true,
      label: 'Score ${run.score}, combo ${run.combo}, multiplier ${_mult(run.multiplier)}'
          '${live ? ', bonus round, ${round.remaining(now).inSeconds} seconds left' : ''}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Score', style: theme.textTheme.labelSmall),
                  _animated(scoreText),
                  if (widget.best != null)
                    Text('Best ${widget.best!.score}', style: theme.textTheme.labelSmall),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.whatshot, color: multColor, size: 20),
                    const SizedBox(width: 2),
                    _animated(multText),
                  ]),
                  Text('Combo ${run.combo}', key: const ValueKey('combo'), style: theme.textTheme.labelMedium),
                  if (!live && run.correctUntilBonus > 0)
                    Text('Bonus in ${run.correctUntilBonus}', style: theme.textTheme.labelSmall),
                ],
              ),
            ],
          ),
          if (live) ...[
            const SizedBox(height: 8),
            _BonusBanner(round: round, now: now),
          ],
        ],
      ),
    );
  }
}

class _BonusBanner extends StatelessWidget {
  const _BonusBanner({required this.round, required this.now});
  final BonusRound round;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final gold = ProgressionColors.gold(cs);
    final total = round.deadline.difference(round.startedAt).inMilliseconds;
    final left = round.remaining(now);
    final title = round.kind == 'conj_blitz' ? 'Conjugation blitz' : 'Bonus round';
    return Container(
      key: const ValueKey('bonus-banner'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ProgressionColors.tint(gold, 0.15, cs),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: gold, width: isMonochrome(cs) ? 3 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.bolt, color: gold),
            const SizedBox(width: 4),
            Expanded(child: Text('$title ×${round.multiplier}', style: theme.textTheme.titleSmall)),
            Text('${round.remainingAnswers} left', style: theme.textTheme.labelMedium),
            const SizedBox(width: 10),
            Text(_NonStopHudState._mmss(left),
                key: const ValueKey('bonus-countdown'),
                style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: total <= 0 ? 0 : left.inMilliseconds / total,
            color: gold,
            backgroundColor: isMonochrome(cs) ? kBwGray : cs.surfaceContainerHighest,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }
}
