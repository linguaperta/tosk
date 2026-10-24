/// Settings → Send feedback (route `/feedback`): free text for the developer
/// and, optionally, an email address for a reply.
///
/// * **Signed in** (a build with sync): **Send** queues it like a flag
///   (`report_outbox.dart`, Firestore `feedback/`, kind `general`); offline it
///   goes with the next sync.
/// * **Otherwise:** **Copy text** and, when the build has
///   `TOSK_FEEDBACK_EMAIL`, **Email** (a draft in the mail app). Where the app
///   can sign in, a note says signing in sends feedback directly.
///
/// Either way the GitHub issues link is offered for public bug reports.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_version.dart';
import '../../feedback/reports.dart';
import '../../providers.dart';
import '../../sync/sync_providers.dart';
import '../common/external_link.dart';
import '../common/links.dart';
import '../routes.dart';

/// The mail address the "Email" button uses (tests override it); empty
/// hides the button.
final feedbackEmailProvider = Provider<String>((ref) => kFeedbackEmail);

class SendFeedbackScreen extends ConsumerStatefulWidget {
  const SendFeedbackScreen({super.key});

  @override
  ConsumerState<SendFeedbackScreen> createState() => _SendFeedbackScreenState();
}

class _SendFeedbackScreenState extends ConsumerState<SendFeedbackScreen> {
  final _text = TextEditingController();
  final _email = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _hasText => _text.text.trim().isNotEmpty;

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _leave() => context.canPop() ? context.pop() : context.go(Routes.settings);

  Future<void> _send() async {
    if (!_hasText || _sending) return;
    final email = _email.text.trim();
    if (email.isNotEmpty && !_emailShape.hasMatch(email)) {
      setState(() => _error = "That email address doesn't look right. Leave it empty if you don't need a reply.");
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final ok = await queueReport(
      ref,
      generalFeedbackReport(
        text: _text.text,
        email: email,
        now: ref.read(clockProvider)(),
        courseId: ref.read(activeCourseIdProvider).value,
      ),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _sending = false;
        _error = "Couldn't send it. Copy the text instead, or try again.";
      });
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    _leave();
    messenger?.showSnackBar(const SnackBar(content: Text('Thank you! Your feedback is on its way to the developer.')));
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: feedbackPlainText(_text.text)));
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Copied')));
    }
  }

  Future<void> _open(Uri url) async {
    final ok = await ref.read(externalLinkOpenerProvider)(url);
    if (!ok && mounted) {
      setState(() => _error = "Couldn't open it on this device. Copy the text instead.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend = ref.watch(canSendReportsProvider);
    final canSignIn = ref.watch(canSignInProvider);
    final address = ref.watch(feedbackEmailProvider);
    final mail = feedbackMailto(
      address,
      subject: 'tosk feedback ($kAppVersion)',
      body: feedbackPlainText(_text.text),
    );

    final intro = canSend
        ? 'Tell the developer what you like, what is confusing or what is missing. '
              'It is sent with the app version and platform, nothing else.'
        : 'Tell the developer what you like, what is confusing or what is missing.';

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: _leave), title: const Text('Send feedback')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              key: const ValueKey('feedback-list'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(intro, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('feedback-text'),
                  controller: _text,
                  minLines: 5,
                  maxLines: 12,
                  maxLength: ReportLimits.text,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Your feedback',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (canSend) ...[
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('feedback-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    maxLength: ReportLimits.email,
                    decoration: const InputDecoration(
                      labelText: 'Email for a reply (optional)',
                      helperText: 'Only if you would like an answer. It is sent with your feedback.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_error case final e?) ...[
                  const SizedBox(height: 8),
                  Row(
                    key: const ValueKey('feedback-error'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e)),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                if (canSend)
                  FilledButton.icon(
                    key: const ValueKey('feedback-send'),
                    onPressed: _hasText && !_sending ? _send : null,
                    icon: const Icon(Icons.send_outlined),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_sending ? 'Sending…' : 'Send'),
                    ),
                  )
                else ...[
                  if (canSignIn)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Sign in (Settings → Account & sync) to send feedback directly from the app.',
                        key: const ValueKey('feedback-sign-in-hint'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  if (mail != null)
                    FilledButton.icon(
                      key: const ValueKey('feedback-email-draft'),
                      onPressed: _hasText ? () => unawaited(_open(mail)) : null,
                      icon: const Icon(Icons.mail_outline),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Write an email'),
                      ),
                    ),
                  if (mail != null) const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('feedback-copy'),
                    onPressed: _hasText ? () => unawaited(_copy()) : null,
                    icon: const Icon(Icons.copy),
                    label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Copy text')),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Found a bug? You can also report it publicly on GitHub.',
                  style: theme.textTheme.bodyMedium,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('feedback-issues'),
                    onPressed: () => unawaited(_open(Uri.parse(kIssuesUrl))),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open GitHub issues'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
