import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/bw_skin.dart';

/// Top-level destinations. Order matches the shell branches in `router.dart`.
const _destinations = [
  (icon: Icons.map_outlined, selected: Icons.map, label: 'Map'),
  (icon: Icons.science_outlined, selected: Icons.science, label: 'Lab'),
  (icon: Icons.all_inclusive, selected: Icons.all_inclusive, label: 'Non-stop'),
  (icon: Icons.insights_outlined, selected: Icons.insights, label: 'Progress'),
  (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Settings'),
];

/// Bottom navigation bar on phones, a navigation rail on tablets and desktop
/// (extended with labels on wide windows).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const railBreakpoint = 600.0;
  static const extendedBreakpoint = 1100.0;

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < railBreakpoint) {
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
    final extended = width >= extendedBreakpoint;
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
