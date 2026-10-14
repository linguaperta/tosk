/// Riverpod wiring for the whole app.
///
/// Every dependency the UI has on data, engine and progression goes through a
/// provider here. `main.dart` opens the data layer (`bootApp` in
/// `app_bootstrap.dart`) and overrides [appDataProvider], [progressStoreProvider]
/// and [courseCatalogProvider]. Without overrides (widget tests) the app runs
/// on the demo courses and an in-memory FSRS progress store. See `docs/ui.md`.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'ai/ai_config.dart';
import 'ai/caching_explainer.dart';
import 'ai/flag_reviewer.dart';
import 'ai/llm_explainer.dart';
import 'ai/secret_store.dart';
import 'audio/sound_service.dart';
import 'audio/test_env.dart';
import 'core/core.dart';
import 'data/app_data.dart';
import 'data/progress/feedback_store.dart';
import 'data/fsrs/fsrs_scheduler.dart';
import 'data/progress/in_memory_progress_store.dart';
import 'data/stats/skill_stats.dart' as data;
import 'engine/engine.dart' show EngineSessionFactory, FocusPresets, OpenMistake, openMistakes;
import 'progression/progression.dart';
import 'ui/common/fx.dart';
import 'ui/course_catalog.dart';
import 'ui/demo/demo_courses.dart';
import 'ui/lesson/answer_input.dart';
import 'ui/map/map_layout.dart';
import 'ui/map/skill_stats.dart';
import 'ui/settings/app_settings.dart';
import 'ui/theme/bw_skin.dart';
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

/// Black & white (e-ink) display: the [BwSkin], always light, no motion.
final bwProvider = Provider<bool>((ref) => ref.watch(settingsProvider.select((s) => s.value?.bw ?? false)));

final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(bwProvider)
      ? ThemeMode.light
      : ref.watch(settingsProvider.select((s) => s.value?.themeMode ?? ThemeMode.system)),
);

/// True disables animations (page transitions, slides, fades, progress
/// tweens): the "Reduce motion" setting, and always in black & white mode
/// (e-ink screens can't show animations).
final reduceMotionProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.value?.reduceMotion ?? false)) || ref.watch(bwProvider),
);

final motionProvider = Provider<Motion>((ref) => Motion(ref.watch(reduceMotionProvider)));

/// Haptics and sounds follow the "Reduce motion" setting only; black & white
/// mode doesn't silence them.
final fxProvider = Provider<Fx>(
  (ref) => Fx(enabled: !ref.watch(settingsProvider.select((s) => s.value?.reduceMotion ?? false))),
);

/// Visual skin (theme + map style): black & white for e-ink, else the default.
/// A forest skin can come later.
final skinProvider = Provider<Skin>((ref) => ref.watch(bwProvider) ? const BwSkin() : const DefaultSkin());

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

/// Focus-preset weights from `assets/config/focus_presets.json` (the engine's
/// embedded defaults if the asset can't be read).
final focusPresetsProvider = FutureProvider<FocusPresets>((ref) async {
  try {
    return FocusPresets.fromJsonString(await rootBundle.loadString('assets/config/focus_presets.json'));
  } catch (e) {
    debugPrint('[engine] focus presets asset unreadable, using defaults: $e');
    return FocusPresets.defaults;
  }
});

/// Creates practice sessions for the active course: the exercise engine over
/// the course (a pack, or the demo course), the progress store, FSRS and the
/// session options. Rebuilt when the course or the settings change.
final sessionFactoryProvider = FutureProvider<SessionFactory>((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  await ref.watch(settingsProvider.future);
  final presets = await ref.watch(focusPresetsProvider.future);
  return EngineSessionFactory(
    course: course,
    store: ref.watch(progressStoreProvider),
    scheduler: ref.watch(schedulerProvider),
    options: ref.watch(sessionOptionsProvider),
    presets: presets,
    clock: ref.watch(clockProvider),
  );
});

/// Answer explanations (`core/interfaces/hooks.dart`): the cached AI
/// explainer once a provider and key are configured in Settings, else
/// [NullExplainer] (every explain button is hidden).
final explainerProvider = Provider<Explainer>((ref) => ref.watch(aiExplainerProvider) ?? const NullExplainer());

final explainerAvailableProvider = Provider<bool>((ref) => ref.watch(explainerProvider).isAvailable);

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

/// Open mistakes of the active course, one per facet, in review order (still
/// weak first, then most recent). Resolved once answered correctly in a later
/// session (the engine's `openMistakes`, see docs/engine.md).
final openMistakesProvider = FutureProvider<List<OpenMistake>>((ref) async {
  ref.watch(progressRevisionProvider);
  final course = await ref.watch(courseDataProvider.future);
  return openMistakes(
    store: ref.watch(progressStoreProvider),
    course: course,
    scheduler: ref.watch(schedulerProvider),
    now: ref.watch(clockProvider)().toUtc(),
  );
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

// ------------------------------------------------------------------ AI, flags, sounds

/// HTTP for AI providers (tests override it with `MockClient`).
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Where the AI API key is kept: the platform's secure storage (in memory
/// under `flutter test`, which has no plugin).
final secretStoreProvider = Provider<SecretStore>(
  (ref) => runningInFlutterTest ? MemorySecretStore() : const SecureSecretStore(),
);

/// AI explanation settings (provider, model, base URL, reply language, key).
final aiConfigProvider = AsyncNotifierProvider<AiConfigController, AiConfig>(AiConfigController.new);

class AiConfigController extends AsyncNotifier<AiConfig> {
  @override
  Future<AiConfig> build() => AiConfig.load(ref.watch(progressStoreProvider), ref.watch(secretStoreProvider));

  /// Applies [edit] and persists what changed (the key in the secret store).
  Future<void> change(AiConfig Function(AiConfig c) edit) async {
    final old = state.value ?? await future;
    final next = edit(old);
    if (next == old) return;
    state = AsyncData(next);
    await next.save(ref.read(progressStoreProvider), ref.read(secretStoreProvider), old: old);
  }
}

/// AI explanation cache and flags: tables in the progress database (in
/// memory on the defaults).
final feedbackStoreProvider = Provider<FeedbackStore>(
  (ref) => ref.watch(appDataProvider)?.feedback ?? InMemoryFeedbackStore(),
);

/// The configured provider's client, or null (AI not configured).
final llmExplainerProvider = Provider<LlmExplainer?>((ref) {
  final config = ref.watch(aiConfigProvider).value;
  if (config == null) return null;
  return llmExplainerFor(config, ref.watch(httpClientProvider), browser: kIsWeb);
});

/// [llmExplainerProvider] behind the explanation cache, with the reply
/// language from the AI settings. Null when AI isn't configured.
final aiExplainerProvider = Provider<CachingExplainer?>((ref) {
  final llm = ref.watch(llmExplainerProvider);
  if (llm == null) return null;
  return CachingExplainer(
    llm,
    ref.watch(feedbackStoreProvider),
    clock: ref.watch(clockProvider),
    provider: llm.providerId,
    model: llm.model,
  );
});

/// The language AI replies are written in (the setting, or the source language).
final explainLangProvider = Provider<String>((ref) {
  final config = ref.watch(aiConfigProvider).value;
  final source = ref.watch(sourceLangProvider);
  return config?.replyLang(source) ?? source;
});

/// "Confer with AI" on a flag; null when AI isn't configured.
final flagReviewerProvider = Provider<FlagReviewer?>((ref) {
  final llm = ref.watch(llmExplainerProvider);
  return llm == null ? null : FlagReviewer(llm);
});

/// Bumped when flags are added or deleted.
final flagsRevisionProvider = NotifierProvider<ProgressRevision, int>(ProgressRevision.new);

/// Every flag on this device, most recent first.
final flagsProvider = FutureProvider<List<FlagRecord>>((ref) {
  ref.watch(flagsRevisionProvider);
  return ref.watch(feedbackStoreProvider).flags();
});

/// Plays the sound files (silent under `flutter test`; tests override it with a fake).
final audioBackendProvider = Provider<AudioBackend>((ref) {
  final AudioBackend backend = runningInFlutterTest ? const SilentAudioBackend() : AudioplayersBackend();
  ref.onDispose(() => backend.dispose());
  return backend;
});

/// The "Sound effects" setting (on by default; separate from reduce motion).
final soundEffectsProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.value?.soundEffects ?? true)),
);

/// Sound effects for the UI: correct, wrong, lesson complete, level up, bonus
/// round and the select tick.
final soundServiceProvider = Provider<SoundService>(
  (ref) => SoundService(ref.watch(audioBackendProvider), enabled: ref.watch(soundEffectsProvider)),
);
