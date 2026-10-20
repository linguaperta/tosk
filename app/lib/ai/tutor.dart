/// AI conversation practice (v0.4): a chat with an AI tutor in the target
/// language, limited to the learner's unlocked grammar and known words (both
/// listed in the system prompt), with gentle corrections and a translation
/// line per reply. Pure Dart: the prompt, the reply format, the conversation
/// model and its storage (settings `chat.conversations.{course}`, local only:
/// never in a backup). The client is the configured [LlmExplainer]. See
/// docs/feedback.md, "AI conversation practice".
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'llm_explainer.dart';
import 'prompts.dart';

/// Words listed in the prompt at most (the most frequent known ones).
const int kTutorMaxWords = 400;

/// Messages sent with each request at most (the latest ones).
const int kTutorHistory = 24;

/// Conversations kept per course, and messages per conversation.
const int kMaxConversations = 12;
const int kMaxConversationMessages = 120;

/// Room for the reply; models that think first spend part of it.
const int kTutorMaxTokens = 1200;

/// Settings key of a course's conversations (a `chat.` key: never exported).
String conversationsKey(String courseId) => 'chat.conversations.$courseId';

/// Topics offered when starting a conversation (English; the tutor speaks
/// the target language).
const List<(String, String)> kTutorTopics = [
  ('free', 'Free conversation'),
  ('intro', 'Introduce yourself'),
  ('food', 'Food and drink'),
  ('day', 'Your day'),
  ('family', 'Family and friends'),
  ('shopping', 'Shopping'),
  ('travel', 'Travel and places'),
];

String topicLabel(String id) => kTutorTopics.firstWhere((t) => t.$1 == id, orElse: () => (id, id)).$2;

/// What the tutor may use: the learner's known words and unlocked grammar.
@immutable
class TutorContext {
  const TutorContext({
    required this.courseTitle,
    required this.targetLang,
    required this.sourceLang,
    required this.words,
    required this.grammar,
    this.beginner = false,
  });

  final String courseTitle;

  /// The language practiced (course target) and the learner's own language.
  final String targetLang;
  final String sourceLang;

  /// Known words as `lemma (gloss)`, most frequent first.
  final List<String> words;

  /// Unlocked grammar, described in English (`present tense (presente)`, `aux:essere`).
  final List<String> grammar;

  /// Nothing practiced yet: the tutor keeps to greetings and the first words.
  final bool beginner;
}

/// The system prompt for [ctx] and [topic].
String tutorSystemPrompt(TutorContext ctx, {required String topic}) {
  final target = promptLanguage(ctx.targetLang);
  final source = promptLanguage(ctx.sourceLang);
  final words = ctx.words.take(kTutorMaxWords).join(', ');
  final grammar = ctx.grammar.isEmpty ? 'only the present tense of the most common verbs' : ctx.grammar.join('; ');
  return '''
You are Tosk, a friendly and patient $target conversation partner in a language-learning app (course: ${ctx.courseTitle}). The learner's own language is $source.

How to reply:
- Write in $target only, at the learner's level: at most 3 short sentences (under 40 words), then one simple question that keeps the conversation going.
- Use only this grammar, which the learner has unlocked: $grammar. Do not use other tenses, moods or constructions.
- Use the learner's known words wherever you can: $words. Use at most one other word per reply, and only a very common one.${ctx.beginner ? '\n- The learner is a beginner: keep to greetings, yes/no questions and the words listed.' : ''}
- If the learner's last message has a mistake, start with one line: CORRECTION: <their sentence, corrected> — <a very short, kind explanation in $source>. Correct only the most important mistake. Leave the line out when the message is fine, very close, or written in $source.
- End with one line: TRANSLATION: <your reply in $source>.
- If the learner writes in $source or asks for help, help briefly in $source, then continue in $target.
- Plain text only: no markdown, lists, emojis or romanization.

Topic: $topic.''';
}

/// The user message that asks the tutor to open a conversation.
String tutorKickoff(String topic) =>
    '(The learner opened a new conversation. Greet them and start talking about: $topic.)';

/// One line of a conversation.
@immutable
class ChatMessage {
  const ChatMessage({required this.fromTutor, required this.text, required this.at});
  final bool fromTutor;

  /// The tutor's raw reply (with its CORRECTION and TRANSLATION lines), or the learner's text.
  final String text;
  final DateTime at;

  Map<String, Object?> toJson() => {'r': fromTutor ? 't' : 'l', 'x': text, 'at': at.toUtc().millisecondsSinceEpoch};

  static ChatMessage? fromJson(Object? j) {
    if (j is! Map) return null;
    final text = j['x'], at = j['at'];
    if (text is! String || at is! num) return null;
    return ChatMessage(
      fromTutor: j['r'] == 't',
      text: text,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt(), isUtc: true),
    );
  }
}

/// A conversation: its topic and messages, oldest first.
@immutable
class Conversation {
  const Conversation({required this.id, required this.topic, required this.startedAt, this.messages = const []});
  final String id;

  /// A [kTutorTopics] id.
  final String topic;
  final DateTime startedAt;
  final List<ChatMessage> messages;

  DateTime get lastAt => messages.isEmpty ? startedAt : messages.last.at;

  Conversation withMessage(ChatMessage m) {
    final all = [...messages, m];
    return Conversation(
      id: id,
      topic: topic,
      startedAt: startedAt,
      messages: all.length > kMaxConversationMessages ? all.sublist(all.length - kMaxConversationMessages) : all,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'topic': topic,
    'at': startedAt.toUtc().millisecondsSinceEpoch,
    'm': [for (final m in messages) m.toJson()],
  };

  static Conversation? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], topic = j['topic'], at = j['at'], m = j['m'];
    if (id is! String || topic is! String || at is! num) return null;
    return Conversation(
      id: id,
      topic: topic,
      startedAt: DateTime.fromMillisecondsSinceEpoch(at.toInt(), isUtc: true),
      messages: [
        if (m is List)
          for (final x in m) ?ChatMessage.fromJson(x),
      ],
    );
  }
}

/// The parts of a tutor reply: an optional correction of the learner's last
/// message, the reply itself, and its translation. Lenient: case, bold
/// markers and a missing line are fine; while streaming, a half-written
/// marker line is held back from [reply].
@immutable
class TutorReply {
  const TutorReply({this.correction, required this.reply, this.translation});
  final String? correction;
  final String reply;
  final String? translation;

  static final RegExp _marker = RegExp(r'^\W*(correction|translation)\W*:\s*(.*)$', caseSensitive: false);

  static final RegExp _inlineMarker = RegExp(r'(?<=\S)[ \t]+(?=\**(?:TRANSLATION|CORRECTION)\**\s*:)');

  static TutorReply parse(String raw, {bool streaming = false}) {
    String? correction, translation;
    final reply = <String>[];
    // A marker the model put at the end of a line starts a line of its own.
    final lines = raw.replaceAll(_inlineMarker, '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].replaceAll('**', '').trimRight();
      final last = i == lines.length - 1;
      final m = _marker.firstMatch(line.trim());
      if (m != null) {
        final text = m.group(2)!.trim();
        if (m.group(1)!.toLowerCase() == 'correction') {
          correction = text;
        } else {
          translation = [?translation, text].where((s) => s.isNotEmpty).join(' ');
        }
        continue;
      }
      // A line that may still turn into a marker ("CORRECT", "TRANSL").
      if (streaming && last && _maybeMarker(line.trim())) continue;
      if (translation != null && line.trim().isNotEmpty) {
        translation = '$translation ${line.trim()}'; // a translation spanning lines
        continue;
      }
      reply.add(line);
    }
    return TutorReply(
      correction: correction == null || correction.isEmpty ? null : correction,
      reply: reply.join('\n').trim(),
      translation: translation == null || translation.isEmpty ? null : translation,
    );
  }

  static bool _maybeMarker(String s) {
    final w = s.replaceAll(RegExp(r'[^A-Za-z]'), '').toLowerCase();
    if (w.isEmpty) return s.isEmpty ? false : !RegExp(r'[\p{L}]', unicode: true).hasMatch(s);
    return 'correction'.startsWith(w) || 'translation'.startsWith(w);
  }
}

/// The request for the tutor's next reply in [c].
ChatPrompt tutorPrompt(TutorContext ctx, Conversation c) {
  final topic = topicLabel(c.topic);
  final recent = c.messages.length > kTutorHistory ? c.messages.sublist(c.messages.length - kTutorHistory) : c.messages;
  return ChatPrompt(
    system: tutorSystemPrompt(ctx, topic: topic),
    turns: [
      ChatTurn.user(tutorKickoff(topic)),
      for (final m in recent) m.fromTutor ? ChatTurn.assistant(m.text) : ChatTurn.user(m.text),
    ],
    maxTokens: kTutorMaxTokens,
  );
}

/// Streams the tutor's next reply in [c] (errors are `AiException`s).
Stream<String> tutorReply(LlmExplainer llm, TutorContext ctx, Conversation c) => llm.complete(tutorPrompt(ctx, c));

/// A course's conversations in the progress store's settings (newest first).
class ConversationStore {
  ConversationStore(this.store);
  final ProgressStore store;

  Future<List<Conversation>> list(String courseId) async {
    final raw = await store.getSetting(conversationsKey(courseId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return const [];
      return [for (final c in j) ?Conversation.fromJson(c)]..sort((a, b) => b.lastAt.compareTo(a.lastAt));
    } on Object {
      return const [];
    }
  }

  Future<Conversation?> get(String courseId, String id) async =>
      (await list(courseId)).where((c) => c.id == id).firstOrNull;

  /// Inserts or replaces [c]; the oldest beyond [kMaxConversations] are dropped.
  Future<void> save(String courseId, Conversation c) async {
    final all = [c, ...(await list(courseId)).where((x) => x.id != c.id)]..sort((a, b) => b.lastAt.compareTo(a.lastAt));
    await _write(courseId, all.take(kMaxConversations).toList());
  }

  Future<void> delete(String courseId, String id) async =>
      _write(courseId, (await list(courseId)).where((c) => c.id != id).toList());

  Future<void> _write(String courseId, List<Conversation> all) =>
      store.setSetting(conversationsKey(courseId), all.isEmpty ? null : jsonEncode([for (final c in all) c.toJson()]));
}
