import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../device/device_providers.dart';
import 'learner_settings.dart';
import 'settings_parts.dart';

/// Settings → E-reader (v0.5): only on ONYX (Boox) devices. A full e-ink
/// refresh after lessons (on by default in black & white) and the Onyx pen
/// SDK's fast drawing in the writing pad.
class DeviceSection extends ConsumerWidget {
  const DeviceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isOnyxProvider)) return const SizedBox.shrink();
    final s = ref.watch(learnerSettingsProvider).value;
    if (s == null) return const SizedBox.shrink();
    final ctl = ref.read(learnerSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeader('E-reader'),
        SwitchListTile(
          key: const ValueKey('setting-full-refresh'),
          title: const Text('Full refresh after lessons'),
          subtitle: const Text('Clears ghosting on the e-ink screen at the end of a lesson and when leaving it'),
          value: ref.watch(fullRefreshAfterLessonsProvider),
          onChanged: (v) => unawaited(ctl.change((s) => s.copyWith(einkFullRefresh: v))),
        ),
        SwitchListTile(
          key: const ValueKey('setting-onyx-pen'),
          title: const Text('Fast pen drawing'),
          subtitle: const Text('Uses the Boox pen engine in the writing pad; switch off if strokes misbehave'),
          value: s.onyxPen,
          onChanged: (v) => unawaited(ctl.change((s) => s.copyWith(onyxPen: v))),
        ),
      ],
    );
  }
}
