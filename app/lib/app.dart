import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'ui/router.dart';

/// Root widget: Material 3 theme from the active skin, light/dark/system mode,
/// and the go_router configuration.
class ToskApp extends ConsumerWidget {
  const ToskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(skinProvider);
    final mode = ref.watch(themeModeProvider);
    final reduceMotion = ref.watch(reduceMotionProvider);
    final router = ref.watch(routerProvider);

    var light = skin.theme(Brightness.light);
    var dark = skin.theme(Brightness.dark);
    if (reduceMotion) {
      // No page transition animations (e-ink friendly).
      final noAnim = PageTransitionsTheme(
        builders: {for (final p in TargetPlatform.values) p: _NoTransitionsBuilder()},
      );
      light = light.copyWith(pageTransitionsTheme: noAnim);
      dark = dark.copyWith(pageTransitionsTheme: noAnim);
    }

    return MaterialApp.router(
      title: 'tosk',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      themeAnimationDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      routerConfig: router,
    );
  }
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
