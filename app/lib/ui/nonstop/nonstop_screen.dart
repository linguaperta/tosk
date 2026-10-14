import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../routes.dart';
import '../slots/progression_slots.dart';

/// Non-stop start screen. The run itself is the shared player in endless mode.
class NonStopScreen extends ConsumerWidget {
  const NonStopScreen({super.key, this.embedded = false});

  /// Inside the Practice tab: no own app bar.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meta = ref.watch(courseDataProvider).value?.meta;
    final lang = ref.watch(sourceLangProvider);
    // The description scrolls; Start is pinned at the bottom (thumb zone).
    final body = Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Icon(Icons.all_inclusive, size: 72, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Non-stop', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'An endless mix of due reviews from every unlocked skill, with new words '
                    'mixed in${meta == null ? '' : ' (${pickLang(meta.title, lang)})'}. '
                    'Stop whenever you like; every answer counts.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  const NonStopRecordSlot(),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('nonstop-start'),
                    onPressed: () => context.push(Routes.nonstopPlay),
                    icon: const Icon(Icons.play_arrow),
                    label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Start')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Non-stop')),
      body: body,
    );
  }
}
