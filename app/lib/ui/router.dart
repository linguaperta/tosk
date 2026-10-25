import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/core.dart';
import '../providers.dart';
import 'bookmarks/bookmarks_ui.dart';
import 'bookmarks/starred_screen.dart';
import 'chat/chat_screen.dart';
import 'debug/debug_route.dart';
import 'feedback/flags_screen.dart';
import 'feedback/send_feedback_screen.dart';
import 'lesson/player_screen.dart';
import 'lesson/session_request.dart';
import 'map/map_screen.dart';
import 'map/skill_sheet.dart';
import 'placement/placement_ui.dart';
import 'mistakes/mistakes_screen.dart';
import 'my_words/my_words_screen.dart';
import 'practice/practice_screen.dart';
import 'progress/progress_screen.dart';
import 'progress/stats_view.dart';
import 'progress/verb_collection_screen.dart';
import 'reading/reading_screen.dart';
import 'reference/reference_screen.dart';
import 'reference/word_screen.dart';
import 'routes.dart';
import 'settings/settings_screen.dart';
import 'stories/stories_view.dart';
import 'stories/story_reader.dart';
import 'shell/app_shell.dart';
import 'welcome/welcome_screen.dart';

/// A go_router page that shows its child as a modal bottom sheet.
class BottomSheetPage<T> extends Page<T> {
  const BottomSheetPage({required this.child, super.key, super.name});
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
    settings: this,
    // From the theme (transparent in black & white: no dimming overlay).
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
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
      // The lab and non-stop live in the Practice tab since v0.3.
      GoRoute(path: '/lab', redirect: (_, _) => Routes.lab),
      GoRoute(path: '/nonstop', redirect: (_, _) => Routes.nonstop),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.map, builder: (_, _) => const MapScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.practice,
                builder: (_, state) => PracticeScreen(tab: state.uri.queryParameters['tab']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.reference,
                builder: (_, state) =>
                    ReferenceScreen(query: state.uri.queryParameters['q'], tab: state.uri.queryParameters['tab']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.progress,
                builder: (_, _) => const ProgressScreen(),
                routes: [
                  GoRoute(path: 'verbs', builder: (_, _) => const VerbCollectionScreen()),
                  GoRoute(path: 'stats', builder: (_, _) => const StatsScreen()),
                  GoRoute(path: 'starred', builder: (_, _) => const StarredScreen()),
                ],
              ),
            ],
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
          child: SkillSheet(
            skillId: state.pathParameters['skillId']!,
            section: state.uri.queryParameters['section'],
          ),
        ),
      ),
      GoRoute(
        path: '/play/lesson/:skillId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final focus = state.uri.queryParameters['focus'];
          final length = int.tryParse(state.uri.queryParameters['length'] ?? '');
          return PlayerScreen(
            request: LessonRequest(
              state.pathParameters['skillId']!,
              focus: focus == null ? null : LessonFocus.values.asNameMap()[focus],
              length: length?.clamp(1, 100),
            ),
          );
        },
      ),
      GoRoute(
        path: '/play/testout/:skillId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => PlayerScreen(request: TestOutRequest(state.pathParameters['skillId']!)),
      ),
      GoRoute(
        path: Routes.placement,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PlayerScreen(request: PlacementRequest()),
      ),
      GoRoute(
        path: Routes.skipAhead,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const SkipAheadScreen(),
      ),
      GoRoute(
        path: Routes.tough,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) =>
              PlayerScreen(request: ToughWordsRequest(minLapses: ref.read(settingsProvider).value?.leechLapses ?? 4)),
        ),
      ),
      GoRoute(
        path: Routes.starredPlay,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => Consumer(
          builder: (context, ref, _) => PlayerScreen(
            request: StarredRequest(
              () async => starredPracticeOf(await ref.read(bookmarksProvider.future)),
              length: kStarredSessionLength,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/chat/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => ChatScreen(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/story/:storyId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => StoryReaderScreen(storyId: state.pathParameters['storyId']!),
      ),
      GoRoute(
        path: '/stories/unit/:unitId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => BottomSheetPage<void>(
          key: state.pageKey,
          child: UnitStoriesSheet(unitId: state.pathParameters['unitId']!),
        ),
      ),
      GoRoute(
        path: '/word/:itemId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => WordScreen(itemId: state.pathParameters['itemId']!),
      ),
      GoRoute(
        path: Routes.fading,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PlayerScreen(request: FadingRequest()),
      ),
      GoRoute(
        path: Routes.review,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PlayerScreen(request: ReviewRequest()),
      ),
      GoRoute(path: Routes.mistakes, parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const MistakesScreen()),
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
        path: '/welcome',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => WelcomeScreen(firstRun: state.uri.queryParameters['first'] == '1'),
      ),
      GoRoute(
        path: Routes.flags,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const FlagsScreen(),
      ),
      GoRoute(
        path: Routes.feedback,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const SendFeedbackScreen(),
      ),
      GoRoute(path: Routes.debug, parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const DebugRoute()),
      GoRoute(path: Routes.myWords, parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const MyWordsScreen()),
      GoRoute(
        path: Routes.myWordsPlay,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PlayerScreen(request: MyWordsRequest()),
      ),
      GoRoute(
        path: '/read/:textId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => ReadingScreen(textId: state.pathParameters['textId']!),
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
