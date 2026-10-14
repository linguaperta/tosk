import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../common/async_view.dart';
import '../progression/progression_widgets.dart';
import '../routes.dart';

/// The verb collection: one card per verb, tense pills that light up as the
/// conjugation tables are mastered.
class VerbCollectionScreen extends ConsumerWidget {
  const VerbCollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(verbCollectionProvider);
    final meta = ref.watch(courseDataProvider).value?.meta;
    final lang = ref.watch(sourceLangProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verb collection'),
        actions: [
          IconButton(
            key: const ValueKey('verbs-lookup'),
            tooltip: 'Look up a verb',
            onPressed: () => context.go(Routes.reference),
            icon: const Icon(Icons.manage_search),
          ),
        ],
      ),
      body: AsyncView(
        value: collection,
        onRetry: () => ref.invalidate(verbCollectionProvider),
        builder: (c) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: VerbCollectionView(
              key: const ValueKey('verb-collection'),
              collection: c,
              lang: lang,
              tenseLabel: meta == null ? null : (t) => meta.tenseLabel(t, lang),
              reduceMotion: ref.watch(reduceMotionProvider),
              // A card opens the verb's full conjugation table.
              onVerbTap: (card) => context.push(Routes.word(card.item.id)),
            ),
          ),
        ),
      ),
    );
  }
}
