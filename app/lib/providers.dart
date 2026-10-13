/// Riverpod wiring for the whole app.
///
/// Every dependency the UI has on data, engine and progression goes through a
/// provider here. Until integration they return the demo implementations from
/// `ui/demo/`; swapping in the real ones is a change to the provider body or a
/// `ProviderScope(overrides: [...])` in `main.dart`. See `docs/ui.md`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/core.dart';
import 'ui/common/fx.dart';
import 'ui/course_catalog.dart';
import 'ui/demo/demo_courses.dart';
import 'ui/demo/demo_progress_store.dart';
import 'ui/demo/demo_session.dart';
import 'ui/demo/demo_skill_stats.dart';
import 'ui/lesson/answer_input.dart';
import 'ui/lesson/why_explainer.dart';
import 'ui/map/map_layout.dart';
import 'ui/map/skill_stats.dart';
import 'ui/settings/app_settings.dart';
import 'ui/theme/skin.dart';

// ------------------------------------------------------------------ platform

/// Current time; overridden in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// ------------------------------------------------------------------ data

/// Installed courses and how to open them.
/// TODO(integration): adapter over the data layer's `LocalPackSource` + course repo.
final courseCatalogProvider = Provider<CourseCatalog>((ref) => DemoCourseCatalog());

/// Progress database (review log, facet states, mistakes, settings).
/// TODO(integration): the data layer's drift `ProgressRepo`. If opening it is
/// async, open it in `main()` before `runApp` and override this with the instance.
final progressStoreProvider = Provider<ProgressStore>((ref) => InMemoryProgressStore());

// ------------------------------------------------------------------ settings

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => AppSettings.load(ref.watch(progressStoreProvider));

  /// Applies [edit] and persists the keys that changed.
  Future<void> change(AppSettings Function(AppSettings s) edit) async {
    final old = state.value ?? await future;
    final next = edit(old);
    if (next == old) return;
    state = AsyncData(next);
    await next.save(ref.read(progressStoreProvider), old: old);
  }
}

final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(settingsProvider.select((s) => s.value?.themeMode ?? ThemeMode.system)),
);

/// True disables animations, haptics and sounds. The future e-ink mode sets it.
final reduceMotionProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.value?.reduceMotion ?? false)),
);

final motionProvider = Provider<Motion>((ref) => Motion(ref.watch(reduceMotionProvider)));

final fxProvider = Provider<Fx>((ref) => Fx(enabled: !ref.watch(reduceMotionProvider)));

/// Visual skin (theme + map style). Forest skin later.
final skinProvider = Provider<Skin>((ref) => const DefaultSkin());

// ------------------------------------------------------------------ course

final availableCoursesProvider = FutureProvider<List<CourseMeta>>(
  (ref) => ref.watch(courseCatalogProvider).listCourses(),
);

/// The course in use: the saved choice when installed, else the first course.
final activeCourseIdProvider = FutureProvider<String>((ref) async {
  final courses = await ref.watch(availableCoursesProvider.future);
  final wanted = await ref.watch(settingsProvider.selectAsync((s) => s.courseId));
  if (courses.isEmpty) throw StateError('No courses installed');
  return courses.any((c) => c.id == wanted) ? wanted! : courses.first.id;
});

final courseDataProvider = FutureProvider<CourseData>((ref) async {
  final id = await ref.watch(activeCourseIdProvider.future);
  return ref.watch(courseCatalogProvider).open(id);
});

/// Source language actually used: the setting when the course has it, else the course's first.
final sourceLangProvider = Provider<String>((ref) {
  final wanted = ref.watch(settingsProvider.select((s) => s.value?.sourceLang ?? 'en'));
  final meta = ref.watch(courseDataProvider.select((c) => c.value?.meta));
  return effectiveSourceLang(wanted, meta);
});

final mapLayoutProvider = FutureProvider<MapLayout>((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  return layoutSkillMap(course.units, course.skills);
});

// ------------------------------------------------------------------ engine

final sessionOptionsProvider = Provider<SessionOptions>(
  (ref) => SessionOptions(
    sourceLang: ref.watch(sourceLangProvider),
    accents: ref.watch(settingsProvider.select((s) => s.value?.accents ?? AccentStrictness.lenient)),
  ),
);

/// Creates practice sessions for the active course.
/// TODO(integration): the engine's SessionFactory (course data + progress store + options).
final sessionFactoryProvider = FutureProvider<SessionFactory>((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  await ref.watch(settingsProvider.future);
  return DemoSessionFactory(
    course: course,
    store: ref.watch(progressStoreProvider),
    options: ref.watch(sessionOptionsProvider),
    clock: ref.watch(clockProvider),
  );
});

/// "Why?" explanations. Hidden while unavailable.
/// TODO(integration): `Explainer` from `core/interfaces/hooks.dart` (NullExplainer in v1).
final explainerProvider = Provider<WhyExplainer>((ref) => const UnavailableWhyExplainer());

final explainerAvailableProvider = Provider<bool>((ref) => ref.watch(explainerProvider).available);

/// Free-text input widget: keyboard now, handwriting later.
final answerInputBuilderProvider = Provider<AnswerInputBuilder>((ref) => keyboardAnswerInputBuilder);

// ------------------------------------------------------------------ progression

/// Strength, last practice and tier per skill id, for the map.
/// Invalidated after every session.
/// TODO(integration): data layer's skill strength + progression's tiers.
final skillStatsProvider = FutureProvider<Map<String, SkillStats>>((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  return computeDemoSkillStats(course, ref.watch(progressStoreProvider), ref.watch(clockProvider)());
});
