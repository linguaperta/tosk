import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../providers.dart';

/// Stand-in for the data layer's debug screen (`lib/ui/debug/debug_screen.dart`).
///
/// TODO(integration): route `/debug` to the data layer's DebugScreen in `router.dart`.
class DebugPlaceholderScreen extends ConsumerWidget {
  const DebugPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseDataProvider).value;
    final stats = ref.watch(skillStatsProvider).value ?? const {};
    final lang = ref.watch(sourceLangProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Debug')),
      body: course == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  title: Text('${pickLang(course.meta.title, lang)} (${course.meta.id})'),
                  subtitle: Text(
                    'v${course.meta.version} · ${course.skills.length} skills · '
                    '${course.allItems.length} items',
                  ),
                ),
                for (final s in course.skills)
                  ListTile(
                    dense: true,
                    title: Text(pickLang(s.title, lang)),
                    subtitle: Text(
                      '${s.id} · ${course.skillItems(s.id).length} items · '
                      '${course.skillFacets(s.id).length} facets',
                    ),
                    trailing: Text('${((stats[s.id]?.strength ?? 0) * 100).round()}%'),
                  ),
              ],
            ),
    );
  }
}
