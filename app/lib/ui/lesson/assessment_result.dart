import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../theme/bw_skin.dart';

/// The verdict of a test out or placement, on the session summary: passed or
/// not (icon and words, never color alone), the score against the pass mark,
/// and what was marked as learned.
class AssessmentResultCard extends ConsumerWidget {
  const AssessmentResultCard({super.key, required this.outcome, required this.mode});
  final AssessmentOutcome outcome;
  final SessionMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final mono = isBw(context);
    String skillName(String id) => course?.skill(id) == null ? id : pickLang(course!.skill(id)!.title, lang);
    String unitName(String id) {
      final u = course?.units.where((u) => u.id == id).firstOrNull;
      return u == null ? id : pickLang(u.title, lang);
    }

    final placement = mode == SessionMode.placement;
    final pct = (outcome.score * 100).round();
    final mark = (outcome.passMark * 100).round();
    final String title;
    final String body;
    if (placement) {
      title = outcome.passed
          ? 'Your level: ${outcome.passedUnits.length} unit${outcome.passedUnits.length == 1 ? '' : 's'} done'
          : 'Start from the beginning';
      body = [
        if (outcome.passedUnits.isNotEmpty) 'Marked as learned: ${outcome.passedUnits.map(unitName).join(', ')}.',
        if (outcome.failedUnit != null) 'Continue with ${unitName(outcome.failedUnit!)}.',
        if (outcome.failedUnit == null && outcome.passed) 'You passed every unit.',
      ].join(' ');
    } else {
      title = outcome.passed ? 'Tested out!' : 'Not yet';
      body = outcome.passed
          ? '$pct % (pass mark $mark %). ${outcome.creditedSkills.map(skillName).join(', ')} is marked as learned, and what follows is unlocked.'
          : '$pct % (pass mark $mark %). Practice the skill a little and try again.';
    }
    return Card(
      key: const ValueKey('assessment-result'),
      margin: const EdgeInsets.only(bottom: 16),
      color: mono
          ? kBwWhite
          : (outcome.passed ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHigh),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              outcome.passed ? Icons.verified : Icons.replay,
              size: 32,
              color: mono ? kBwBlack : theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: const ValueKey('assessment-title'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(body, key: const ValueKey('assessment-body')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
