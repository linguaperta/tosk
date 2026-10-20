/// Practice → Chat (v0.4, only with AI configured): what AI conversation
/// practice is, a topic choice, the recent conversations, and "Start a
/// conversation" pinned at the bottom. A conversation opens `/chat/:id`
/// (`chat_screen.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../ai/ai_config.dart';
import '../../ai/tutor.dart';
import '../../core/core.dart';
import '../../providers.dart';
import '../brand/tosk.dart';
import '../routes.dart';
import '../theme/tosk_palette.dart';
import 'chat_providers.dart';

class ChatHomeView extends ConsumerStatefulWidget {
  const ChatHomeView({super.key});

  @override
  ConsumerState<ChatHomeView> createState() => _ChatHomeViewState();
}

class _ChatHomeViewState extends ConsumerState<ChatHomeView> {
  String _topic = kTutorTopics.first.$1;
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final course = await ref.read(activeCourseIdProvider.future);
      final c = Conversation(id: const Uuid().v4(), topic: _topic, startedAt: ref.read(clockProvider)().toUtc());
      await ref.read(conversationStoreProvider).save(course, c);
      ref.read(chatRevisionProvider.notifier).bump();
      if (mounted) await _open(c.id);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Opens a conversation; the list reloads when it is closed (this view
  /// is paused while covered).
  Future<void> _open(String id) async {
    await context.push(Routes.chat(id));
    if (mounted) ref.invalidate(conversationsProvider);
  }

  Future<void> _delete(Conversation c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('chat-delete-confirm'),
        title: const Text('Delete this conversation?'),
        content: Text('"${topicLabel(c.topic)}" and its ${c.messages.length} messages are removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('chat-delete-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final course = await ref.read(activeCourseIdProvider.future);
    await ref.read(conversationStoreProvider).delete(course, c.id);
    ref.read(chatRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final target = course == null ? 'the course language' : pickLang(course.meta.title, lang);
    final provider = ref.watch(aiConfigProvider).value?.provider;
    final conversations = ref.watch(conversationsProvider).value ?? const <Conversation>[];
    final now = ref.watch(clockProvider)();
    return Column(
      key: const ValueKey('chat-home'),
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                key: const ValueKey('chat-home-list'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Talk with Tosk', style: theme.textTheme.serifTitle),
                            const SizedBox(height: 6),
                            Text(
                              'Chat in $target about everyday things. Tosk only uses the grammar and words '
                              'you have unlocked, corrects you gently, and every reply has a translation. '
                              'Tap a word for its meaning.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const ToskImage(pose: ToskPose.pointing, height: 72),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Replies come from ${provider == null || provider == AiProvider.none ? 'your AI provider' : provider.label} '
                    'and need an internet connection. Conversations stay on this device.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Text('Topic', style: theme.textTheme.serifSection),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (id, label) in kTutorTopics)
                        ChoiceChip(
                          key: ValueKey('chat-topic-$id'),
                          label: Text(label),
                          selected: _topic == id,
                          onSelected: (_) => setState(() => _topic = id),
                        ),
                    ],
                  ),
                  if (conversations.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Recent conversations', style: theme.textTheme.serifSection),
                    const SizedBox(height: 8),
                    for (final c in conversations) ...[
                      Card(
                        key: ValueKey('chat-conversation-${c.id}'),
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.forum_outlined),
                          title: Text(topicLabel(c.topic)),
                          subtitle: Text(
                            '${c.messages.length} message${c.messages.length == 1 ? '' : 's'} · ${_ago(c.lastAt, now)}',
                          ),
                          onTap: () => _open(c.id),
                          trailing: IconButton(
                            key: ValueKey('chat-delete-${c.id}'),
                            tooltip: 'Delete conversation',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(c),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('chat-start'),
                    onPressed: _starting ? null : _start,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('Start: ${topicLabel(_topic)}', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _ago(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}
