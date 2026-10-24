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
import 'data/progress/bookmarks.dart';
import 'data/progress/feedback_store.dart';
import 'data/fsrs/fsrs_scheduler.dart';
import 'data/progress/in_memory_progress_store.dart';
import 'data/progress/user_words.dart';
import 'data/stats/skill_stats.dart' as data;
import 'engine/engine.dart' show CourseIndex, EngineSessionFactory, FocusPresets, OpenMistake, openMistakes;
import 'progression/progression.dart';
import 'speech/speech_providers.dart';
import 'ui/common/fx.dart';
import 'ui/course_catalog.dart';
import 'ui/demo/demo_courses.dart';
import 'ui/ink/ink_answer_input.dart';
import 'ui/ink/ink_providers.dart';
import 'ui/lesson/answer_input.dart';
import 'ui/map/map_layout.dart';
import 'ui/map/skill_stats.dart';
import 'ui/settings/app_settings.dart';
import 'ui/settings/learner_settings.dart';
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

/// Visual skin (theme + map style): black & white for e-ink, else tosk's
/// storybook look. Another skin can come later.
final skinProvider = Provider<Skin>((ref) => ref.watch(bwProvider) ? const BwSkin() : const ToskSkin());

/// Whether the map's medal twinkles animate: motion on, and never under
/// `flutter test` (a repeating animation would never settle; tests that want
/// it override this).
final twinkleProvider = Provider<bool>((ref) => !ref.watch(reduceMotionProvider) && !runningInFlutterTest);

// ------------------------------------------------------------------ course

final availableCoursesProvider = FutureProvider<List<CourseMeta>>(
  (ref) => ref.watch(courseCatalogProvider).listCourses(),
);

/// The user's courses ("my courses", added in the course picker) that are
/// installed, in the order added. The rest of the app only shows these.
final myCoursesProvider = FutureProvider<List<CourseMeta>>((ref) async {
  final courses = await ref.watch(availableCoursesProvider.future);
  final mine = await ref.watch(settingsProvider.selectAsync((s) => s.myCourseIds.join(',')));
  final byId = {for (final c in courses) c.id: c};
  return [for (final id in mine.split(',')) ?byId[id]];
});

/// True on a fresh install (no course added yet): the shell opens the course picker.
final needsCoursePickerProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final available = ref.watch(availableCoursesProvider).value;
  final mine = ref.watch(myCoursesProvider).value;
  return settings != null && available != null && available.isNotEmpty && mine != null && mine.isEmpty;
});

/// The course in use: the saved choice among the user's courses, else their
/// first; before any course is added, the first installed course.
final activeCourseIdProvider = FutureProvider<String>((ref) async {
  final courses = await ref.watch(availableCoursesProvider.future);
  final mine = await ref.watch(myCoursesProvider.future);
  final wanted = await ref.watch(settingsProvider.selectAsync((s) => s.courseId));
  if (courses.isEmpty) throw StateError('No courses installed');
  final pool = mine.isEmpty ? courses : mine;
  return pool.any((c) => c.id == wanted) ? wanted! : pool.first.id;
});

/// What the course picker shows about a course before it is added.
class CoursePreview {
  const CoursePreview({
    required this.meta,
    required this.outline,
    required this.words,
    required this.verbs,
    required this.sentences,
    required this.sampleWords,
    this.sampleSentence,
  });

  final CourseMeta meta;

  /// Units in order with their skills.
  final List<(Unit, List<Skill>)> outline;
  final int words;
  final int verbs;
  final int sentences;

  /// A few frequent words of the first skills.
  final List<Item> sampleWords;
  final Sentence? sampleSentence;
}

/// Opens [courseId] (without making it active) and summarizes it.
final coursePreviewProvider = FutureProvider.family<CoursePreview, String>((ref, courseId) async {
  final course = await ref.watch(courseCatalogProvider).open(courseId);
  final lang = ref.watch(settingsProvider.select((s) => s.value?.sourceLang ?? 'en'));
  final items = course.allItems.toList();
  final sentences = CourseIndex.of(course).allSentences;
  final samples = <Item>[];
  for (final s in course.skills) {
    for (final i in course.skillItems(s.id)) {
      if (samples.length < 6 && !samples.contains(i) && i.glosses(lang).isNotEmpty) samples.add(i);
    }
    if (samples.length >= 6) break;
  }
  Sentence? sample;
  for (final s in sentences) {
    final words = s.tokens.where((t) => t.isWord).length;
    if (words >= 3 && words <= 7 && (s.translation(lang) ?? '').isNotEmpty) {
      sample = s;
      break;
    }
  }
  return CoursePreview(
    meta: course.meta,
    outline: [
      for (final u in course.units)
        (
          u,
          [
            for (final s in course.skills)
              if (s.unitId == u.id) s,
          ],
        ),
    ],
    words: items.length,
    verbs: items.where((i) => i.isVerb).length,
    sentences: sentences.length,
    sampleWords: samples,
    sampleSentence: sample,
  );
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

/// The main tree's layout (the topics are their own maps).
final mapLayoutProvider = FutureProvider<MapLayout>((ref) async {
  final course = await ref.watch(courseDataProvider.future);
  final trees = CourseTrees.of(course);
  return layoutSkillMap(trees.mainUnits, trees.mainSkills);
});

/// The band at the top of a topic's map: its root, the anchor skill of the
/// main tree it grows from ([topicMapSkills]).
const String kTopicRootUnit = '~root';

/// The skills of [topic]'s map: its root (the anchor skill, in the
/// [kTopicRootUnit] band) and the topic's skills. A skill that requires no
/// skill of the topic hangs from the root; the main-tree requirements of the
/// others draw no bough (a later main-tree skill one of them needs is a note
/// on its node instead, see `topicSkillNeed`).
List<Skill> topicMapSkills(CourseTrees trees, Topic topic) {
  final anchor = trees.course.skill(topic.anchor);
  bool rootOfTopic(Skill s) => !s.requires.any((r) => trees.treeOf(r) == topic.id);
  return [
    if (anchor != null)
      Skill(
        id: anchor.id,
        unitId: kTopicRootUnit,
        ord: 0,
        kind: anchor.kind,
        title: anchor.title,
        icon: anchor.icon,
        tense: anchor.tense,
      ),
    for (final s in trees.skillsOf(topic.id))
      Skill(
        id: s.id,
        unitId: s.unitId,
        ord: s.ord,
        kind: s.kind,
        title: s.title,
        icon: s.icon,
        tense: s.tense,
        exercises: s.exercises,
        posX: s.posX,
        posY: s.posY,
        requires: {
          for (final r in s.requires)
            if (trees.treeOf(r) == topic.id)
              r
            else if (anchor != null && rootOfTopic(s) && trees.course.skill(r) != null)
              anchor.id,
        }.toList(),
      ),
  ];
}

/// A topic tree's layout: the root band with the anchor, then the topic's units.
final topicLayoutProvider = FutureProvider.family<MapLayout, String>((ref, topicId) async {
  final course = await ref.watch(courseDataProvider.future);
  final trees = CourseTrees.of(course);
  final topic = trees.topic(topicId);
  if (topic == null) return MapLayout.empty;
  return layoutSkillMap(
    [const Unit(id: kTopicRootUnit, ord: -1, title: {}), ...trees.unitsOf(topicId)],
    topicMapSkills(trees, topic),
  );
});

/// The tree the map shows: null for the main tree, else a topic id. Back to
/// the main tree whenever the active course changes.
final mapTreeProvider = NotifierProvider<MapTree, String?>(MapTree.new);

class MapTree extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(activeCourseIdProvider);
    return null;
  }

  void show(String? tree) => state = tree;
}

/// A skill the map should bring into view, in its own tree (a locked topic
/// skill's "needs The conditional · unit 12" goes to that main-tree skill).
/// The map screen switches the tree, scrolls to the skill's unit and clears it.
final mapFocusProvider = NotifierProvider<MapFocus, String?>(MapFocus.new);

class MapFocus extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(activeCourseIdProvider);
    return null;
  }

  void focus(String skillId) => state = skillId;

  void clear() => state = null;
}

/// How many of [skillId]'s words the learner already knows (any facet of the
/// word practised, in any tree) out of its words: "34 of 120 words already
/// known" on a topic skill's sheet.
final skillKnownWordsProvider = FutureProvider.family<({int known, int total}), String>((ref, skillId) async {
  ref.watch(progressRevisionProvider);
  final course = await ref.watch(courseDataProvider.future);
  final items = course.skillItems(skillId);
  final facets = <String, Set<String>>{
    for (final i in items) i.id: {'${i.id}#rec', '${i.id}#prod'},
  };
  for (final f in course.skillFacets(skillId)) {
    facets[f.itemId]?.add(f.facetId);
  }
  final states = await ref.watch(progressStoreProvider).states({for (final s in facets.values) ...s});
  final known = facets.values.where((ids) => ids.any(states.containsKey)).length;
  return (known: known, total: items.length);
});

// ------------------------------------------------------------------ engine

final sessionOptionsProvider = Provider<SessionOptions>(
  (ref) => SessionOptions(
    sourceLang: ref.watch(sourceLangProvider),
    accents: ref.watch(settingsProvider.select((s) => s.value?.accents ?? AccentStrictness.lenient)),
    // Typing ("challenge") mode and handwriting: cloze takes free text
    // (other production types switch to typed or handwritten input in the UI).
    preferredInput: ref.watch(inkModeProvider)
        ? InputMode.ink
        : ref.watch(typingModeProvider)
        ? InputMode.keyboard
        : InputMode.tap,
    // listen_pick only with a voice for the course language (v0.5).
    listening: ref.watch(listeningProvider),
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
  await ref.watch(learnerSettingsProvider.future);
  // Whether the device can speak the course language (listen_pick).
  await ref.watch(courseVoiceProvider.future).timeout(const Duration(seconds: 3), onTimeout: () => false);
  final presets = await ref.watch(focusPresetsProvider.future);
  final words = ref.watch(userWordRepoProvider);
  return EngineSessionFactory(
    course: course,
    store: ref.watch(progressStoreProvider),
    scheduler: ref.watch(schedulerProvider),
    options: ref.watch(sessionOptionsProvider),
    presets: presets,
    clock: ref.watch(clockProvider),
    // "My words": read when a lesson or a "My words" session starts.
    userWords: () async => (await words.load(course.meta.id)).all,
  );
});

/// Answer explanations (`core/interfaces/hooks.dart`): the cached AI
/// explainer once a provider and key are configured in Settings, else
/// [NullExplainer] (every explain button is hidden).
final explainerProvider = Provider<Explainer>((ref) => ref.watch(aiExplainerProvider) ?? const NullExplainer());

final explainerAvailableProvider = Provider<bool>((ref) => ref.watch(explainerProvider).isAvailable);

/// Free-text input widget: the keyboard, or the handwriting pad when
/// "Answer input: Handwrite" is on (and supported here).
final answerInputBuilderProvider = Provider<AnswerInputBuilder>(
  (ref) => ref.watch(inkModeProvider) ? inkAnswerInputBuilder : keyboardAnswerInputBuilder,
);

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

/// What a skill needs for its next tier (the skill sheet).
final skillNextTierProvider = FutureProvider.family<NextTierNeeds, String>((ref, skillId) async {
  ref.watch(progressRevisionProvider);
  final svc = await ref.watch(progressionServiceProvider.future);
  return svc.nextTier(skillId, ref.watch(clockProvider)());
});

/// The active course's XP, level and today's numbers; the account-wide
/// streak, freezes and today's XP for the daily goal.
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

/// "Tough words" of the active course: facets with at least the configured
/// number of lapses (Settings), most lapses first.
final toughWordsProvider = FutureProvider<List<ToughWord>>((ref) async {
  ref.watch(progressRevisionProvider);
  final course = await ref.watch(courseDataProvider.future);
  final minLapses = await ref.watch(settingsProvider.selectAsync((s) => s.leechLapses));
  final states = await ref.watch(progressStoreProvider).allStates(courseId: course.meta.id);
  return toughWords(course, states, minLapses: minLapses);
});

/// Verb tables of the active course with their mastery.
final verbCollectionProvider = FutureProvider<VerbCollection>((ref) async {
  ref.watch(progressRevisionProvider);
  final svc = await ref.watch(progressionServiceProvider.future);
  return svc.verbCollection(ref.watch(clockProvider)());
});

/// The active course's statistics: review forecast, accuracy per type and
/// per tense or table, time practiced, words learned over time.
final courseStatsProvider = FutureProvider<CourseStats>((ref) async {
  ref.watch(progressRevisionProvider);
  final svc = await ref.watch(progressionServiceProvider.future);
  return svc.stats(now: ref.watch(clockProvider)(), lang: ref.watch(sourceLangProvider));
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
/// Starred words, sentences and exercises (`AppData.bookmarks`, the progress
/// DB table), else in memory. The bookmark UI is in `ui/bookmarks/`.
final bookmarkRepoProvider = Provider<BookmarkRepo>((ref) => ref.watch(appDataProvider)?.bookmarks ?? InMemoryBookmarkRepo());

/// "My words" storage: `AppData.userWords` (the progress DB's `user_words`),
/// else in memory.
final userWordRepoProvider = Provider<UserWordRepo>((ref) => ref.watch(appDataProvider)?.userWords ?? InMemoryUserWordRepo());

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

/// A cached AI explanation by (fingerprint, given answer, reply language),
/// or null. Works offline and without a configured provider.
final cachedExplanationProvider = FutureProvider.autoDispose.family<String?, (String, String, String)>((ref, key) async {
  final (fingerprint, given, lang) = key;
  return (await ref.watch(feedbackStoreProvider).explanation(fingerprint, given, lang))?.text;
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
