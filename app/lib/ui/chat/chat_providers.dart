/// Providers of AI conversation practice (`ai/tutor.dart`): whether it is
/// available (the same rule as "Explain answer with AI": a configured
/// provider and key), the stored conversations, and the tutor context (the
/// learner's known words and unlocked grammar). See docs/feedback.md.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/tutor.dart';
import '../../core/core.dart';
import '../../engine/engine.dart' show CourseIndex, SentenceGate;
import '../../providers.dart';

/// AI conversation exists only with a configured AI provider (and key).
final chatAvailableProvider = Provider<bool>((ref) => ref.watch(llmExplainerProvider)?.isAvailable ?? false);

final conversationStoreProvider = Provider<ConversationStore>(
  (ref) => ConversationStore(ref.watch(progressStoreProvider)),
);

/// Bumped whenever a conversation is saved or deleted.
final chatRevisionProvider = NotifierProvider<ProgressRevision, int>(ProgressRevision.new);

/// The active course's conversations, newest first.
final conversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  ref.watch(chatRevisionProvider);
  final course = await ref.watch(activeCourseIdProvider.future);
  return ref.watch(conversationStoreProvider).list(course);
});

/// What the tutor may use: the words of every started skill (most frequent
/// first) and the grammar features gating allows (base features plus those
/// of started skills and their prerequisites), with the started grammar
/// skills' titles. A learner who started nothing gets the first skill's words.
final tutorContextProvider = FutureProvider<TutorContext>((ref) async {
  ref.watch(progressRevisionProvider);
  final course = await ref.watch(courseDataProvider.future);
  final lang = ref.watch(sourceLangProvider);
  final states = await ref.watch(progressStoreProvider).allStates(courseId: course.meta.id);
  return tutorContextFor(course, states.where((s) => s.reps > 0).map((s) => s.facetId), lang: lang);
});

/// [tutorContextProvider]'s computation (pure, tested).
TutorContext tutorContextFor(CourseData course, Iterable<String> reviewedFacetIds, {required String lang}) {
  final started = SentenceGate.startedSkills(course, reviewedFacetIds);
  final gate = SentenceGate(course, started: started);
  final beginner = started.isEmpty;
  final ix = CourseIndex.of(course);
  final itemIds = beginner && course.skills.isNotEmpty
      ? {for (final i in course.skillItems(course.skills.first.id)) i.id}
      : gate.knownItems;
  final items = [for (final id in itemIds) ?course.item(id)]
    ..sort((a, b) => (a.freq ?? 1 << 30).compareTo(b.freq ?? 1 << 30));
  final meta = course.meta;
  String feature(String f) {
    if (f.startsWith('tense:')) {
      final t = f.substring(6);
      final label = meta.tenseLabel(t, 'en');
      return label == t.replaceAll('_', ' ') ? label : '$label ($t)';
    }
    return f.replaceAll(':', ' ').replaceAll('_', ' ');
  }

  return TutorContext(
    courseTitle: pickLang(meta.title, 'en'),
    targetLang: meta.target,
    sourceLang: lang,
    words: [
      for (final i in items)
        i.glosses(lang).isEmpty ? ix.withArticle(i) : '${ix.withArticle(i)} (${i.glosses(lang).take(2).join(', ')})',
    ],
    grammar: [
      for (final f in {
        ...gate.knownFeatures,
        // Packs without gating data: the tenses of started grammar skills.
        for (final sk in course.skills)
          if (started.contains(sk.id) && sk.tense != null) 'tense:${sk.tense}',
      }.toList()..sort())
        feature(f),
      for (final s in course.skills)
        if (started.contains(s.id) && s.kind == SkillKind.grammar) 'the skill "${pickLang(s.title, 'en')}"',
    ],
    beginner: beginner,
  );
}
