import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ink/ink_recognizer.dart';
import '../../speech/speech_providers.dart';
import '../ink/ink_providers.dart';
import 'learner_settings.dart';
import 'settings_parts.dart';

/// Settings → Challenge: answer input Tap / Type ("challenge mode") /
/// Handwrite (v0.5, where the recognizer runs: Android and iOS), the
/// handwriting model for the course, and listening exercises.
class AnswerInputSection extends ConsumerWidget {
  const AnswerInputSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(learnerSettingsProvider).value;
    if (s == null) return const SizedBox.shrink();
    final inkSupported = ref.watch(inkSupportedProvider);
    final values = [
      AnswerInputPref.tap,
      AnswerInputPref.type,
      if (inkSupported) AnswerInputPref.handwrite,
    ];
    final handwriting = s.handwriting && inkSupported;
    final voice = ref.watch(canPronounceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeader('Challenge'),
        SettingsChoice<AnswerInputPref>(
          keyName: 'answer-input',
          title: 'Answer input',
          subtitle: handwriting
              ? 'Write your answers with a finger or a stylus in cloze, conjugation, sentence and '
                    'transform exercises; recognition exercises stay tap'
              : s.typing
              ? 'Type your answers in cloze, conjugation, sentence and transform exercises; '
                    'recognition exercises stay tap'
              : 'Pick from options and word tiles. Type${inkSupported ? ' or write' : ''} for a harder challenge',
          values: values,
          // A "handwrite" restored where it can't run shows as Tap.
          selected: values.contains(s.answerInput) ? s.answerInput : AnswerInputPref.tap,
          label: (v) => switch (v) {
            AnswerInputPref.tap => 'Tap',
            AnswerInputPref.type => 'Type',
            AnswerInputPref.handwrite => 'Write',
          },
          onChanged: (v) =>
              unawaited(ref.read(learnerSettingsProvider.notifier).change((s) => s.copyWith(answerInput: v))),
        ),
        if (handwriting) const _InkModelTile(),
        if (voice)
          SwitchListTile(
            key: const ValueKey('setting-listening'),
            title: const Text('Listening exercises'),
            subtitle: const Text("Hear a sentence and pick what was said (uses the device's text-to-speech voice)"),
            value: s.listening,
            onChanged: (v) =>
                unawaited(ref.read(learnerSettingsProvider.notifier).change((s) => s.copyWith(listening: v))),
          ),
      ],
    );
  }
}

/// The course's handwriting model: status, download, delete.
class _InkModelTile extends ConsumerWidget {
  const _InkModelTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(inkModelProvider);
    final ctl = ref.read(inkModelProvider.notifier);
    final name = m.tag == null ? 'this course' : inkModelName(m.tag!);
    final sarnami = m.target == 'hns';
    final (String status, Widget? trailing) = switch (m.status) {
      InkModelStatus.checking => ('Checking…', null),
      InkModelStatus.ready => (
          'Downloaded: works offline${sarnami ? '. Sarnami uses the Dutch model, without ṯ ḏ ṟ ã õ' : ''}',
          TextButton(key: const ValueKey('ink-model-delete'), onPressed: () => unawaited(ctl.delete()), child: const Text('Delete')),
        ),
      InkModelStatus.missing => (
          'Not downloaded yet: about 20 MB, once (Wi-Fi recommended)',
          FilledButton(
            key: const ValueKey('ink-model-download'),
            onPressed: () => unawaited(ctl.download()),
            child: const Text('Download'),
          ),
        ),
      InkModelStatus.downloading => ('Downloading…', null),
      InkModelStatus.unsupported => ('No handwriting model for this language', null),
      InkModelStatus.error => (
          "Couldn't load the model",
          TextButton(
            key: const ValueKey('ink-model-retry'),
            onPressed: () => unawaited(m.tag == null ? ctl.refresh() : ctl.download()),
            child: const Text('Try again'),
          ),
        ),
    };
    return ListTile(
      key: const ValueKey('setting-ink-model'),
      leading: const Icon(Icons.draw_outlined),
      title: Text('Handwriting model: $name'),
      subtitle: Text(status),
      trailing: trailing,
    );
  }
}
