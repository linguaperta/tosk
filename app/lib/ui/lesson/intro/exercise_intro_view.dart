import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../../settings/app_settings.dart' show exerciseTypeIcon;
import '../../theme/bw_skin.dart';
import 'exercise_intros.dart';

/// One screen explaining an exercise type: icon, title, what to do, a small
/// static example from the course, and "Got it" (pinned at the bottom).
class ExerciseIntroView extends StatelessWidget {
  const ExerciseIntroView({super.key, required this.type, required this.example, required this.onGotIt});

  final ExerciseType type;
  final List<IntroLine> example;
  final VoidCallback onGotIt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          key: ValueKey('exercise-intro-${type.id}'),
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: ExerciseIntroContent(type: type, example: example),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('intro-got-it'),
                    onPressed: onGotIt,
                    child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Got it')),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The intro's text and example (shared by the first-time screen and the (?) sheet).
class ExerciseIntroContent extends StatelessWidget {
  const ExerciseIntroContent({super.key, required this.type, required this.example});

  final ExerciseType type;
  final List<IntroLine> example;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = isMonochrome(scheme);
    final intro = introFor(type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: mono ? kBwWhite : scheme.primaryContainer,
              foregroundColor: mono ? kBwBlack : scheme.onPrimaryContainer,
              child: Icon(exerciseTypeIcon(type)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(intro.title, key: const ValueKey('intro-title'), style: theme.textTheme.headlineSmall),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(intro.body, key: const ValueKey('intro-body'), style: theme.textTheme.bodyLarge),
        if (example.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('For example', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('intro-example'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: mono ? kBwWhite : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: mono ? Border.all(color: kBwBlack, width: kBwBorder) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, line) in example.indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Text(line.from, style: theme.textTheme.titleMedium),
                      Text(line.arrow, style: theme.textTheme.titleMedium),
                      Text(line.to, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The (?) button's sheet: the same explanation, closed with "Got it".
Future<void> showExerciseIntroSheet(BuildContext context, {required ExerciseType type, required List<IntroLine> example}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: Column(
        key: ValueKey('exercise-intro-sheet-${type.id}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: ExerciseIntroContent(type: type, example: example),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('intro-sheet-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Got it')),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
