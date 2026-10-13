/// Riverpod wiring for the whole app.
///
/// Every dependency the UI has on data, engine and progression goes through a
/// provider here. `main.dart` opens the data layer (`bootApp` in
/// `app_bootstrap.dart`) and overrides [appDataProvider], [progressStoreProvider]
/// and [courseCatalogProvider]. Without overrides (widget tests) the app runs
/// on the demo courses and an in-memory FSRS progress store. See `docs/ui.md`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/core.dart';
import 'data/app_data.dart';
import 'data/fsrs/fsrs_scheduler.dart';
import 'data/progress/in_memory_progress_store.dart';
import 'data/stats/skill_stats.dart' as data;
import 'progression/progression.dart';
import 'ui/common/fx.dart';
import 'ui/course_catalog.dart';
import 'ui/demo/demo_courses.dart';
import 'ui/demo/demo_session.dart';
import 'ui/lesson/answer_input.dart';
import 'ui/lesson/recording_store.dart';
import 'ui/lesson/why_explainer.dart';
import 'ui/map/map_layout.dart';
import 'ui/map/skill_stats.dart';
import 'ui/settings/app_settings.dart';
import 'ui/theme/skin.dart';

// ------------------------------------------------------------------ platform

/// Current time; overridden in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The user's calendar (local dates for streaks, the heatmap and challenges).
final calendarProvider = Provider<LocalCalendar>((ref) => LocalCalendar.system());

// ------------------------------------------------------------------ data

/// The opened data layer (progress DB, packs, scheduler). Set by `main.dart`;
/// null in widget tests that run on the demo defaults.
final appDataProvider = Provider<AppData?>((ref) => null);

/// FSRS scheduler (the data layer's, so stored states and progression agree).
final schedulerProvider = Provider<Scheduler>((ref) => ref.watch(appDataProvider)?.scheduler ?? FsrsScheduler());

/// Installed courses and how to open them. `main.dart` overrides this with a
/// `PackCourseCatalog` (packs, falling back to the demo courses when none is installed).
final courseCatalogProvider = Provider<CourseCatalog>((ref) => DemoCourseCatalog());

/// Progress database (review log, facet states, mistakes, settings).
/// `main.dart` overrides this with `AppData.progress` (drift `ProgressRepo`).
final progressStoreProvider = Provider<ProgressStore>(
  (ref) => InMemoryProgressStore(scheduler: ref.watch(schedulerProvider)),
);

/// The store sessions record through: [progressStoreProvider] plus the last
/// recorded event per session (the non-stop HUD reads its `at`).
final recordingStoreProvider = Provider<RecordingProgressStore>(
  (ref) => RecordingProgressStore(ref.watch(progressStoreProvider)),
);

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

/// Whether the active course is built-in demo content (labelled "Demo").
final activeCourseIsDemoProvider = Provider<bool>((ref) {
  final id = ref.watch(activeCourseIdProvider).value;
  ref.watch(availableCoursesProvider);
  return id != null && ref.watch(courseCatalogProvider).isDemo(id);
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
///
/// Contract for the factory: record through `ref.watch(recordingStoreProvider)`
/// (not the raw progress store), with every facet outcome of one exercise at
/// the same `at`, and `sessionId` = `PracticeSession.id`. See docs/ui.md.
final sessionFactoryProvider = FutureProvider<SessionFactory>((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  await ref.watch(settingsProvider.future);
  // TODO(integration-engine): return the engine's SessionFactory here (course,
  // ref.watch(recordingStoreProvider), ref.watch(schedulerProvider),
  // ref.watch(sessionOptionsProvider), ref.watch(clockProvider)), then delete
  // ui/demo/demo_session.dart, demo_exercises.dart and demo_grader.dart.
  return DemoSessionFactory(
    course: course,
    store: ref.watch(recordingStoreProvider),
    options: ref.watch(sessionOptionsProvider),
    clock: ref.watch(clockProvider),
  );
});

/// "Why?" explanations. Hidden while unavailable.
/// TODO(integration-engine): `Explainer` from `core/interfaces/hooks.dart` (NullExplainer in v1).
final explainerProvider = Provider<WhyExplainer>((ref) => const UnavailableWhyExplainer());

final explainerAvailableProvider = Provider<bool>((ref) => ref.watch(explainerProvider).available);

/// Free-text input widget: keyboard now, handwriting later.
final answerInputBuilderProvider = Provider<AnswerInputBuilder>((ref) => keyboardAnswerInputBuilder);

// ------------------------------------------------------------------ progression

/// Bumped whenever the review log changed outside a provider's view (after
/// every session, after the debug screen). Everything derived from progress
/// watches it, so one bump refreshes the map, header and progress pages.
final progressRevisionProvider = NotifierProvider<ProgressRevision, int>(ProgressRevision.new);

class ProgressRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Progression facade for the active course (XP, tiers, streaks, challenges,
/// verb collection, session summaries, non-stop records). It caches its log
/// replay and re-reads the log on every query, so it lives as long as the course.
final progressionServiceProvider = FutureProvider<ProgressionService>((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  return ProgressionService(
    store: ref.watch(progressStoreProvider),
    scheduler: ref.watch(schedulerProvider),
    course: course,
    clock: ref.watch(clockProvider),
    calendar: ref.watch(calendarProvider),
  );
});

/// Strength, last practice, tier and fading per skill id, for the map:
/// strength and last practice from the data layer's [data.SkillStatsService]
/// (facet states), tier and fading from [ProgressionService.skillTiers].
final skillStatsProvider = FutureProvider<Map<String, SkillStats>>((ref) async {
  ref.watch(progressRevisionProvider);
  final course = await ref.watch(courseDataProvider.future);
  final progression = await ref.watch(progressionServiceProvider.future);
  final now = ref.watch(clockProvider)().toUtc();
  final stats = await data.SkillStatsService(
    ref.watch(progressStoreProvider),
    ref.watch(schedulerProvider),
  ).forCourse(course, now: now);
  final tiers = await progression.skillTiers(now);
  return mapSkillStats(stats, tiers);
});

/// Combines data-layer stats and progression tiers into the map's [SkillStats].
Map<String, SkillStats> mapSkillStats(Map<String, data.SkillStats> stats, Map<String, SkillProgress> tiers) {
  final out = <String, SkillStats>{};
  for (final id in {...stats.keys, ...tiers.keys}) {
    final s = stats[id], t = tiers[id];
    out[id] = SkillStats(
      strength: s?.strength ?? t?.strength ?? 0,
      lastPracticed: s?.lastPracticed ?? t?.lastPracticed,
      tier: t == null ? MapTier.available : mapTier(t.tier),
      practicedFacets: s?.reviewedFacetCount ?? t?.reviewedCount ?? 0,
      totalFacets: s?.facetCount ?? t?.facetCount ?? 0,
      fading: t?.fading,
    );
  }
  return out;
}

MapTier mapTier(SkillTier t) => switch (t) {
  SkillTier.locked => MapTier.locked,
  SkillTier.available => MapTier.available,
  SkillTier.started => MapTier.started,
  SkillTier.bronze => MapTier.bronze,
  SkillTier.silver => MapTier.silver,
  SkillTier.gold => MapTier.gold,
};

SkillTier skillTierOf(MapTier t) => switch (t) {
  MapTier.locked => SkillTier.locked,
  MapTier.available => SkillTier.available,
  MapTier.started => SkillTier.started,
  MapTier.bronze => SkillTier.bronze,
  MapTier.silver => SkillTier.silver,
  MapTier.gold => SkillTier.gold,
};

/// XP, level, streak and today's numbers (whole log, all courses).
final progressProfileProvider = FutureProvider<ProgressProfile>((ref) async {
  ref.watch(progressRevisionProvider);
  final svc = await ref.watch(progressionServiceProvider.future);
  return svc.profile(ref.watch(clockProvider)());
});

/// Streak heatmap for the last 26 weeks.
final heatmapProvider = FutureProvider<HeatmapData>((ref) async {
  ref.watch(progressRevisionProvider);
  final svc = await ref.watch(progressionServiceProvider.future);
  return svc.heatmap(now: ref.watch(clockProvider)());
});

/// This week's and month's challenges, plus every badge.
final challengeBoardProvider = FutureProvider<ChallengeBoard>((ref) async {
  ref.watch(progressRevisionProvider);
  final svc = await ref.watch(progressionServiceProvider.future);
  return svc.challenges(ref.watch(clockProvider)());
});

/// Verb tables of the active course with their mastery.
final verbCollectionProvider = FutureProvider<VerbCollection>((ref) async {
  ref.watch(progressRevisionProvider);
  final svc = await ref.watch(progressionServiceProvider.future);
  return svc.verbCollection(ref.watch(clockProvider)());
});

/// Best non-stop run in the log (null when there is none).
final bestNonStopRunProvider = FutureProvider<NonStopRecord?>((ref) async {
  ref.watch(progressRevisionProvider);
  final svc = await ref.watch(progressionServiceProvider.future);
  return svc.bestNonStopRun();
});

/// Progression summary of one finished session (XP, improved words, tier changes).
final sessionProgressSummaryProvider = FutureProvider.family<SessionProgressSummary?, String>((ref, sessionId) async {
  ref.watch(progressRevisionProvider);
  final svc = await ref.watch(progressionServiceProvider.future);
  return svc.sessionSummary(sessionId);
});
