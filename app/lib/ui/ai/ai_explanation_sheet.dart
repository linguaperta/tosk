import 'dart:async';

import 'package:flutter/material.dart';

import '../../ai/ai_errors.dart';
import '../common/markdown.dart';

/// Opens the AI explanation as a bottom sheet. [request] starts the stream
/// (called again on "Try again"); [note] is the skill's grammar note, shown
/// instead when the AI can't be reached.
Future<void> showAiExplanationSheet(
  BuildContext context, {
  required Stream<String> Function() request,
  String? note,
  String title = 'Explanation',
  VoidCallback? onOpenSettings,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) =>
      AiExplanationSheet(request: request, note: note, title: title, onOpenSettings: onOpenSettings),
);

/// Streams an explanation in, rendered as markdown as it arrives.
///
/// Errors: offline (or the service unreachable) shows the bundled grammar note
/// instead; a rejected key says to check it in Settings; anything else offers
/// "Try again". Self-contained: no providers, so it works from any screen.
class AiExplanationSheet extends StatefulWidget {
  const AiExplanationSheet({
    super.key,
    required this.request,
    this.note,
    this.title = 'Explanation',
    this.onOpenSettings,
  });

  final Stream<String> Function() request;
  final String? note;
  final String title;
  final VoidCallback? onOpenSettings;

  @override
  State<AiExplanationSheet> createState() => _AiExplanationSheetState();
}

class _AiExplanationSheetState extends State<AiExplanationSheet> {
  StreamSubscription<String>? _sub;
  final _text = StringBuffer();
  Object? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    unawaited(_sub?.cancel());
    _text.clear();
    _error = null;
    _done = false;
    try {
      _sub = widget.request().listen(
        (chunk) => setState(() => _text.write(chunk)),
        onError: (Object e) => setState(() {
          _error = e;
          _done = true;
        }),
        onDone: () => setState(() => _done = true),
        cancelOnError: true,
      );
    } catch (e) {
      _error = e;
      _done = true;
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _text.toString();
    final error = _error;
    final kind = error is AiException ? error.kind : null;
    final note = widget.note?.trim();

    final body = <Widget>[];
    if (text.isNotEmpty) {
      body.add(KeyedSubtree(key: const ValueKey('ai-explanation-text'), child: MarkdownView(text)));
    }
    if (error == null && !_done && text.isEmpty) {
      body.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(key: ValueKey('ai-explanation-loading')),
        ),
      );
    }
    if (error == null && _done && text.isEmpty) {
      body.add(const Text('No explanation came back.', key: ValueKey('ai-explanation-empty')));
    }
    if (error != null) {
      if (text.isNotEmpty) body.add(const SizedBox(height: 12));
      body.add(
        _Notice(
          key: const ValueKey('ai-explanation-error'),
          icon: switch (kind) {
            AiErrorKind.network => Icons.cloud_off,
            AiErrorKind.auth => Icons.key_off,
            _ => Icons.error_outline,
          },
          message: error is AiException ? error.userMessage : 'Could not get an explanation.',
        ),
      );
      if (kind == AiErrorKind.network && note != null && note.isNotEmpty) {
        body
          ..add(const SizedBox(height: 16))
          ..add(Text('Grammar note', style: theme.textTheme.titleMedium))
          ..add(const SizedBox(height: 6))
          ..add(KeyedSubtree(key: const ValueKey('ai-explanation-note'), child: MarkdownView(note)));
      }
      body.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            children: [
              if (kind == AiErrorKind.auth || kind == AiErrorKind.model)
                if (widget.onOpenSettings != null)
                  TextButton.icon(
                    key: const ValueKey('ai-explanation-settings'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenSettings!();
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open settings'),
                  ),
              if (kind != AiErrorKind.auth)
                TextButton.icon(
                  key: const ValueKey('ai-explanation-retry'),
                  onPressed: () => setState(_start),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          key: const ValueKey('ai-explanation-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(widget.title, style: theme.textTheme.titleLarge)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...body,
                  if (text.isNotEmpty && _done && error == null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'AI-generated. It can be wrong: check it against the grammar note.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
