import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../providers.dart';
import 'debug_screen.dart';

/// `/debug`: the data layer's [DebugScreen] over the app's [appDataProvider].
///
/// Leaving it refreshes the course list and everything derived from progress,
/// since the screen can install packs and rebuild facet states. Without a data
/// layer (widget tests on the demo defaults) it shows [DemoDebugScreen].
class DebugRoute extends ConsumerWidget {
  const DebugRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appDataProvider);
    if (app == null) return const DemoDebugScreen();
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        ref.invalidate(availableCoursesProvider);
        ref.read(progressRevisionProvider.notifier).bump();
      },
      child: DebugScreen(app: app, sourceLang: ref.watch(sourceLangProvider), clock: ref.watch(clockProvider)),
    );
  }
}

/// Minimal debug view of the active course when no data layer is open.
class DemoDebugScreen extends ConsumerWidget {
  const DemoDebugScreen({super.key});

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
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('No data layer open (demo providers).'),
                ),
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
