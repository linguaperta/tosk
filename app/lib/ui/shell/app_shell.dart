import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../courses/course_picker.dart';
import '../theme/bw_skin.dart';

/// Top-level destinations. Order matches the shell branches in `router.dart`.
const _destinations = [
  (icon: Icons.map_outlined, selected: Icons.map, label: 'Map'),
  (icon: Icons.fitness_center_outlined, selected: Icons.fitness_center, label: 'Practice'),
  (icon: Icons.menu_book_outlined, selected: Icons.menu_book, label: 'Reference'),
  (icon: Icons.insights_outlined, selected: Icons.insights, label: 'Progress'),
  (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Settings'),
];

/// Bottom navigation bar on phones, a navigation rail on tablets and desktop
/// (extended with labels on wide windows). On a fresh install (no course
/// added yet) it opens the course picker once.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const railBreakpoint = 600.0;
  static const extendedBreakpoint = 1100.0;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _pickerShown = false;

  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(needsCoursePickerProvider, (_, needs) {
      if (!needs || _pickerShown) return;
      _pickerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showCoursePicker(context, firstRun: true);
      });
    }, fireImmediately: true);
  }

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppShell.railBreakpoint) {
      return Scaffold(
        body: shell,
        // Five labels of up to ~8 letters: on narrow phones larger text would
        // wrap them ("Non-/stop"), so the bar caps its own text scale.
        bottomNavigationBar: MediaQuery.withClampedTextScaling(
          maxScaleFactor: width < 400 ? 1.0 : 1.2,
          // Black & white: a rule above the bar (it has no tint or shadow there).
          child: DecoratedBox(
            decoration: isBw(context)
                ? const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: kBwBlack, width: kBwBorder),
                    ),
                  )
                : const BoxDecoration(),
            child: NavigationBar(
              key: const ValueKey('bottom-nav'),
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
              ],
            ),
          ),
        ),
      );
    }
    final extended = width >= AppShell.extendedBreakpoint;
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            child: NavigationRail(
              key: const ValueKey('nav-rail'),
              extended: extended,
              labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: extended
                    ? Text('tosk', style: Theme.of(context).textTheme.titleLarge)
                    : Icon(Icons.translate, color: Theme.of(context).colorScheme.primary),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: Text(d.label)),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}
