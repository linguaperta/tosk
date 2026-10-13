import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../progression/progression.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../progression/progression_widgets.dart';
import '../routes.dart';

/// Progress / profile page: level and XP, streak and heatmap, the verb
/// collection, weekly and monthly challenges, and badges.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(progressProfileProvider);
    final heatmap = ref.watch(heatmapProvider).value;
    final board = ref.watch(challengeBoardProvider).value;
    final verbs = ref.watch(verbCollectionProvider).value;
    final reduce = ref.watch(reduceMotionProvider);
    final theme = Theme.of(context);

    Widget section(String title, Widget child, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: AsyncView(
        value: profile,
        onRetry: () => ref.invalidate(progressProfileProvider),
        builder: (p) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              key: const ValueKey('progress-list'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _ProfileCard(profile: p, reduceMotion: reduce),
                if (heatmap != null)
                  section(
                    'Activity',
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: StreakHeatmap(data: heatmap, reduceMotion: reduce),
                      ),
                    ),
                    key: const ValueKey('progress-heatmap'),
                  ),
                section(
                  'Verb collection',
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      key: const ValueKey('open-verbs'),
                      leading: const Icon(Icons.auto_stories_outlined),
                      title: Text(
                        verbs == null
                            ? 'Conjugation tables'
                            : '${verbs.count(VerbMastery.known) + verbs.count(VerbMastery.mastered)} of '
                                  '${verbs.totalTables} tables known',
                      ),
                      subtitle: verbs == null
                          ? null
                          : Text('${verbs.count(VerbMastery.mastered)} mastered · ${verbs.verbs.length} verbs'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go(Routes.verbs),
                    ),
                  ),
                ),
                if (board != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: ChallengesList(
                      key: const ValueKey('progress-challenges'),
                      board: board,
                      today: p.today,
                      reduceMotion: reduce,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.reduceMotion});
  final ProgressProfile profile;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = profile;
    return Card(
      key: const ValueKey('progress-profile'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 20,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            LevelBadge(level: p.level, size: 72, reduceMotion: reduceMotion),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 140, maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Level ${p.level.level}', style: theme.textTheme.headlineSmall),
                  Text('${p.totalXp} XP in total', key: const ValueKey('progress-total-xp')),
                  Text('Today: ${p.todayReviews} reviews · +${p.todayXp} XP', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  StreakCounter(streak: p.streak, reduceMotion: reduceMotion, showLongest: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
