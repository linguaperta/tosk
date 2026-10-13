import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/core.dart';
import 'lab/lab_screen.dart';
import 'lesson/player_screen.dart';
import 'lesson/session_request.dart';
import 'map/map_screen.dart';
import 'map/skill_sheet.dart';
import 'nonstop/nonstop_screen.dart';
import 'routes.dart';
import 'settings/settings_screen.dart';
import 'shell/app_shell.dart';
import 'shell/debug_placeholder.dart';

/// A go_router page that shows its child as a modal bottom sheet.
class BottomSheetPage<T> extends Page<T> {
  const BottomSheetPage({required this.child, super.key, super.name});
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
    settings: this,
    builder: (_) => child,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
  );
}

GoRouter buildRouter({String initialLocation = Routes.map}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.map, builder: (_, _) => const MapScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.lab, builder: (_, _) => const LabScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.nonstop, builder: (_, _) => const NonStopScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen())],
          ),
        ],
      ),
      GoRoute(
        path: '/skill/:skillId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => BottomSheetPage<void>(
          key: state.pageKey,
          child: SkillSheet(skillId: state.pathParameters['skillId']!),
        ),
      ),
      GoRoute(
        path: '/play/lesson/:skillId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final focus = state.uri.queryParameters['focus'];
          return PlayerScreen(
            request: LessonRequest(
              state.pathParameters['skillId']!,
              focus: focus == null ? null : LessonFocus.values.asNameMap()[focus],
            ),
          );
        },
      ),
      GoRoute(
        path: Routes.fading,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PlayerScreen(request: FadingRequest()),
      ),
      GoRoute(
        path: '/play/lab',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => PlayerScreen(request: LabRequest.fromQuery(state.uri.queryParameters)),
      ),
      GoRoute(
        path: Routes.nonstopPlay,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PlayerScreen(request: NonStopRequest()),
      ),
      GoRoute(
        path: Routes.debug,
        parentNavigatorKey: rootNavigatorKey,
        // TODO(integration): the data layer's DebugScreen (lib/ui/debug/debug_screen.dart).
        builder: (_, _) => const DebugPlaceholderScreen(),
      ),
    ],
  );
}

/// The app router; one per ProviderScope.
final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter();
  ref.onDispose(router.dispose);
  return router;
});
