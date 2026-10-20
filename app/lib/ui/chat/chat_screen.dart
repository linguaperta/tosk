/// `/chat/:id`: one AI conversation (v0.4). The tutor's replies stream in;
/// once complete, every word the course knows is tappable for its gloss
/// (`WordLookup` + `TappableSentence`), a correction of the learner's last
/// message shows above the reply (icon and "Correction", never color alone),
/// and the translation is one tap away. The input sits at the bottom with the
/// course's accent bar. Offline or with a bad key the screen says so and
/// offers "Try again"; nothing typed is lost (messages are saved locally).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai/ai_errors.dart';
import '../../ai/tutor.dart';
import '../../core/core.dart' show pickLang;
import '../../engine/word_lookup.dart';
import '../../providers.dart';
import '../common/word_popover.dart';
import '../lesson/typing.dart';
import '../routes.dart';
import '../theme/bw_skin.dart';
import 'chat_providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  Conversation? _conversation;
  String? _courseId;
  bool _loading = true;

  /// The reply streaming in (null when none is).
  String? _streaming;
  StreamSubscription<String>? _sub;
  Object? _error;

  /// Tutor messages whose translation is shown (by index).
  final Set<int> _translated = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final course = await ref.read(activeCourseIdProvider.future);
    final c = await ref.read(conversationStoreProvider).get(course, widget.conversationId);
    if (!mounted) return;
    setState(() {
      _courseId = course;
      _conversation = c;
      _loading = false;
    });
    // A new conversation (or one whose last reply failed): the tutor speaks.
    if (c != null && (c.messages.isEmpty || !c.messages.last.fromTutor)) unawaited(_ask());
  }

  Future<void> _save(Conversation c) async {
    final course = _courseId;
    if (course == null) return;
    await ref.read(conversationStoreProvider).save(course, c);
    ref.read(chatRevisionProvider.notifier).bump();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final reduce = ref.read(reduceMotionProvider);
      final end = _scroll.position.maxScrollExtent;
      if (reduce) {
        _scroll.jumpTo(end);
      } else {
        unawaited(_scroll.animateTo(end, duration: const Duration(milliseconds: 200), curve: Curves.easeOut));
      }
    });
  }

  /// Requests the tutor's next reply.
  Future<void> _ask() async {
    final c = _conversation;
    final llm = ref.read(llmExplainerProvider);
    if (c == null || llm == null || _streaming != null) return;
    setState(() {
      _streaming = '';
      _error = null;
    });
    _toBottom();
    final TutorContext ctx;
    try {
      ctx = await ref.read(tutorContextProvider.future);
    } catch (e) {
      if (mounted) {
        setState(() {
          _streaming = null;
          _error = e;
        });
      }
      return;
    }
    if (!mounted) return;
    final buffer = StringBuffer();
    _sub = tutorReply(llm, ctx, c).listen(
      (chunk) {
        buffer.write(chunk);
        if (mounted) setState(() => _streaming = buffer.toString());
        _toBottom();
      },
      onError: (Object e) {
        _sub = null;
        if (mounted) {
          setState(() {
            _streaming = null;
            _error = e;
          });
        }
      },
      onDone: () async {
        _sub = null;
        final text = buffer.toString().trim();
        if (text.isEmpty) {
          if (mounted) {
            setState(() {
              _streaming = null;
              _error = const AiException(AiErrorKind.other, 'empty reply');
            });
          }
          return;
        }
        final next = c.withMessage(ChatMessage(fromTutor: true, text: text, at: ref.read(clockProvider)().toUtc()));
        if (mounted) {
          setState(() {
            _conversation = next;
            _streaming = null;
          });
        }
        await _save(next);
        _toBottom();
      },
      cancelOnError: true,
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final c = _conversation;
    if (text.isEmpty || c == null || _streaming != null) return;
    final next = c.withMessage(ChatMessage(fromTutor: false, text: text, at: ref.read(clockProvider)().toUtc()));
    _input.clear();
    setState(() => _conversation = next);
    await _save(next);
    await _ask();
  }

  @override
  Widget build(BuildContext context) {
    final c = _conversation;
    final available = ref.watch(chatAvailableProvider);
    final theme = Theme.of(context);
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (c == null) {
      body = const _Notice(
        key: ValueKey('chat-missing'),
        icon: Icons.forum_outlined,
        text: 'This conversation is no longer on this device.',
      );
    } else if (!available) {
      body = const _Notice(
        key: ValueKey('chat-unavailable'),
        icon: Icons.key_off,
        text: 'AI conversation needs an AI provider. Set one up in Settings → AI explanations.',
      );
    } else {
      final tutorIndexes = <int>[];
      final items = <Widget>[];
      for (var i = 0; i < c.messages.length; i++) {
        final m = c.messages[i];
        if (m.fromTutor) tutorIndexes.add(i);
        items.add(
          m.fromTutor
              ? _TutorBubble(
                  key: ValueKey('chat-tutor-$i'),
                  index: i,
                  reply: TutorReply.parse(m.text),
                  translated: _translated.contains(i),
                  onTranslate: () =>
                      setState(() => _translated.contains(i) ? _translated.remove(i) : _translated.add(i)),
                )
              : _LearnerBubble(key: ValueKey('chat-learner-$i'), text: m.text),
        );
      }
      final streaming = _streaming;
      if (streaming != null) {
        items.add(
          streaming.isEmpty
              ? Padding(
                  key: const ValueKey('chat-typing'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Tosk is typing…',
                    style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                  ),
                )
              : _TutorBubble(
                  key: const ValueKey('chat-streaming'),
                  index: -1,
                  reply: TutorReply.parse(streaming, streaming: true),
                  streaming: true,
                ),
        );
      }
      if (_error != null) items.add(_ErrorNotice(error: _error!, onRetry: _ask));
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            key: const ValueKey('chat-messages'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            children: items,
          ),
        ),
      );
    }
    final canWrite = c != null && available;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.chats)),
        title: Text(c == null ? 'Conversation' : topicLabel(c.topic)),
      ),
      body: body,
      bottomNavigationBar: canWrite ? _composer(context) : null,
    );
  }

  Widget _composer(BuildContext context) {
    final letters = ref.watch(accentLettersProvider);
    final course = ref.watch(courseDataProvider).value;
    final target = course == null ? '' : ' in ${pickLang(course.meta.title, ref.watch(sourceLangProvider))}';
    final busy = _streaming != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (letters.isNotEmpty) ...[
                    AccentBar(letters: letters, onInsert: (l) => insertAtCursor(_input, l)),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chat-input'),
                          controller: _input,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 500,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => unawaited(_send()),
                          decoration: InputDecoration(
                            hintText: 'Write$target…',
                            counterText: '',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        key: const ValueKey('chat-send'),
                        tooltip: 'Send',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: busy ? null : () => unawaited(_send()),
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tutor reply: the correction (if any), the reply with tappable words,
/// and the translation toggle.
class _TutorBubble extends ConsumerWidget {
  const _TutorBubble({
    super.key,
    required this.index,
    required this.reply,
    this.translated = false,
    this.onTranslate,
    this.streaming = false,
  });

  final int index;
  final TutorReply reply;
  final bool translated;
  final VoidCallback? onTranslate;
  final bool streaming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = isMonochrome(scheme);
    final course = ref.watch(courseDataProvider).value;
    final style = theme.textTheme.bodyLarge;
    final correction = reply.correction;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10, right: 32),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('Tosk', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (correction != null)
                    Container(
                      key: ValueKey('chat-correction-$index'),
                      margin: const EdgeInsets.only(top: 6, bottom: 4, right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: mono ? kBwWhite : scheme.tertiaryContainer,
                        border: Border.all(color: mono ? kBwBlack : scheme.outlineVariant, width: mono ? 2 : 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.edit_note, size: 20, color: mono ? kBwBlack : scheme.onTertiaryContainer),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(
                                    text: 'Correction: ',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  TextSpan(text: correction),
                                ],
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: mono ? kBwBlack : scheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: streaming || course == null
                        ? Text(reply.reply, style: style)
                        : TappableSentence(
                            key: ValueKey('chat-reply-$index'),
                            tokens: WordLookup.of(course).tokenize(reply.reply),
                            keyPrefix: 'chat$index-',
                            style: style,
                          ),
                  ),
                  if (!streaming && reply.translation != null) ...[
                    if (translated)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 8),
                        child: Text(
                          reply.translation!,
                          key: ValueKey('chat-translation-$index'),
                          style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: ValueKey('chat-translate-$index'),
                        onPressed: onTranslate,
                        icon: const Icon(Icons.translate, size: 18),
                        label: Text(translated ? 'Hide translation' : 'Translate'),
                      ),
                    ),
                  ] else
                    const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The learner's message: right-aligned, in the "selected" color (inverted
/// in black & white), labelled "You".
class _LearnerBubble extends StatelessWidget {
  const _LearnerBubble({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 48),
          child: Semantics(
            label: 'You: $text',
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outline, width: isMonochrome(scheme) ? 2 : 1),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'You',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    Text(text, style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSecondaryContainer)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final e = error;
    final kind = e is AiException ? e.kind : null;
    final text = switch (kind) {
      AiErrorKind.network =>
        "You're offline, or the AI service can't be reached. AI conversation needs an internet connection; "
            'your messages are kept.',
      _ when e is AiException => e.userMessage,
      _ => 'Something went wrong getting a reply.',
    };
    return Padding(
      key: ValueKey('chat-error-${kind?.name ?? 'other'}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(switch (kind) {
                    AiErrorKind.network => Icons.cloud_off,
                    AiErrorKind.auth => Icons.key_off,
                    _ => Icons.error_outline,
                  }),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text)),
                ],
              ),
              if (kind != AiErrorKind.auth && kind != AiErrorKind.model)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('chat-retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                )
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
