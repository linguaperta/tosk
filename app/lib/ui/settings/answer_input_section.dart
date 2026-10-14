import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'learner_settings.dart';
import 'settings_parts.dart';

/// Settings → Challenge: answer input Tap / Type ("challenge mode").
class AnswerInputSection extends ConsumerWidget {
  const AnswerInputSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(learnerSettingsProvider).value;
    if (s == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeader('Challenge'),
        SettingsChoice<AnswerInputPref>(
          keyName: 'answer-input',
          title: 'Answer input',
          subtitle: s.typing
              ? 'Type your answers in cloze, conjugation, sentence and transform exercises; '
                    'recognition exercises stay tap'
              : 'Pick from options and word tiles. Type for a harder challenge',
          values: AnswerInputPref.values,
          selected: s.answerInput,
          label: (v) => v == AnswerInputPref.type ? 'Type' : 'Tap',
          onChanged: (v) => ref.read(learnerSettingsProvider.notifier).change((s) => s.copyWith(answerInput: v)),
        ),
      ],
    );
  }
}
