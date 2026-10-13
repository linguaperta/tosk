import 'package:flutter/material.dart';

import '../../progression/progression.dart';
import '../theme/bw_skin.dart';

/// Level number inside a ring showing progress to the next level, with XP below.
class LevelBadge extends StatelessWidget {
  const LevelBadge({
    super.key,
    required this.level,
    this.size = 64,
    this.reduceMotion = false,
    this.showXp = true,
  });

  final LevelInfo level;
  final double size;
  final bool reduceMotion;
  final bool showXp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget ring(double value) => SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: size / 12,
                  backgroundColor: isMonochrome(cs) ? kBwGray : cs.surfaceContainerHighest,
                  color: cs.primary,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('LV', style: theme.textTheme.labelSmall?.copyWith(fontSize: size / 7, height: 1)),
                  Text(
                    '${level.level}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: size / 3,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
    final progress = reduceMotion
        ? ring(level.progress)
        : TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: level.progress),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => ring(v),
          );
    return Semantics(
      label: 'Level ${level.level}, ${level.xpIntoLevel} of ${level.xpForNext} XP to the next level',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          progress,
          if (showXp) ...[
            const SizedBox(height: 4),
            Text('${level.xpIntoLevel} / ${level.xpForNext} XP', style: theme.textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}
