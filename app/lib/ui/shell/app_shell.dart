import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../device/device_info.dart' show openTtsSettings;
import '../../providers.dart';
import '../../speech/speech_providers.dart';
import '../../updates/update_check.dart';
import '../../updates/web_update.dart';
import '../courses/course_picker.dart';
import '../courses/course_updates.dart';
import '../goal/daily_goal_providers.dart';
import '../routes.dart';
import '../settings/setting_keys.dart';
import '../theme/bw_skin.dart';
import '../updates/update_notice.dart';

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
  AppLifecycleListener? _lifecycle;

  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(needsCoursePickerProvider, (_, needs) {
      if (!needs || _pickerShown) return;
      _pickerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_firstRun());
      });
    }, fireImmediately: true);
    // Daily reminder: keep the scheduled notifications in line with the
    // goal, the reminder setting and today's progress.
    syncReminders(ref);
    // Back in the app: re-check the notification permission and re-plan the
    // reminders (the day or the time zone may have changed).
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(reminderResumeProvider.notifier).bump());
    // Course updates: the cached index, and a check at most once a day.
    ref.read(courseUpdatesProvider.notifier).startup();
    // App updates: GitHub Releases at most once a day (sideloaded builds), a
    // new service worker on the web; the web's one-time "What's new".
    unawaited(ref.read(appUpdateProvider.notifier).startup());
    unawaited(ref.read(webUpdateProvider.notifier).startup());
    ref.listenManual<WhatsNew?>(webUpdateProvider.select((s) => s.whatsNew), (_, info) {
      if (info == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showWhatsNewSheet(context, info);
        await ref.read(webUpdateProvider.notifier).whatsNewShown();
      });
    }, fireImmediately: true);
    // No voice for the course language (Android): say how to install one,
    // once per language.
    ref.listenManual<VoiceNotice?>(voiceNoticeProvider, (_, notice) {
      if (notice == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showVoiceNotice(notice));
      });
    }, fireImmediately: true);
  }

  /// A fresh install: the welcome (once), then the course picker. Existing
  /// installs never get here (they have a course), so they skip the welcome.
  Future<void> _firstRun() async {
    final router = GoRouter.of(context);
    final done = await ref.read(progressStoreProvider).getSetting(SettingKeys.welcomeDone);
    if (!mounted) return;
    if (done != 'true') {
      await router.push<void>(Routes.welcome(firstRun: true));
      if (!mounted) return;
    }
    await showCoursePicker(context, firstRun: true);
  }

  Future<void> _showVoiceNotice(VoiceNotice notice) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    if (!await claimVoiceNotice(ref.read(progressStoreProvider), notice.languageCode)) return;
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('voice-notice'),
        content: Text(notice.message),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(label: 'Settings', onPressed: () => unawaited(openTtsSettings())),
      ),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppShell.railBreakpoint) {
      return Scaffold(
        body: UpdateNoticeHost(child: shell),
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
          Expanded(child: UpdateNoticeHost(child: shell)),
        ],
      ),
    );
  }
}
