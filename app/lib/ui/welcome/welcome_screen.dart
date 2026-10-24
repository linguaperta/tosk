/// The first-run welcome: who Tosk is, how the app works, then two optional
/// setup steps (Google sign-in for sync, where sync exists; a Claude API key).
/// A fresh install shows it once before the course picker; Settings → About
/// → "Show welcome again" opens it on demand. Leaving it in any way sets
/// [SettingKeys.welcomeDone].
///
/// Swipeable pages with motion on; with reduced motion (and so in black &
/// white) the pages change only through the buttons, without sliding.
/// Keyboard: Enter is the page's main button, Esc its skip.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai/ai_config.dart';
import '../../providers.dart';
import '../../sync/sync_providers.dart';
import '../../sync/sync_service.dart';
import '../brand/tosk.dart';
import '../common/external_link.dart';
import '../routes.dart';
import '../settings/setting_keys.dart';
import '../settings/sync_section.dart' show SyncSignInButton;
import '../theme/tosk_palette.dart';

/// Where Claude API keys are made.
const kClaudeKeysUrl = 'https://console.anthropic.com/settings/keys';

/// A light format check (no network call): Anthropic keys start with
/// `sk-ant-`, have no spaces and are long.
bool looksLikeClaudeKey(String key) {
  final k = key.trim();
  return k.startsWith('sk-ant-') && k.length >= 20 && !k.contains(RegExp(r'\s'));
}

enum WelcomeStep { tosk, howItWorks, signIn, claudeKey }

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.firstRun = false});

  /// The course picker follows (the last button says "Choose a course").
  final bool firstRun;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pages = PageController();
  final _key = TextEditingController();
  final _focus = FocusNode(debugLabel: 'welcome');
  int _index = 0;
  bool _showKey = false;
  bool _keySaved = false;
  bool _saving = false;
  String? _keyError;
  String? _linkError;
  bool _finished = false;

  @override
  void dispose() {
    _pages.dispose();
    _key.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<WelcomeStep> get _steps => [
    WelcomeStep.tosk,
    WelcomeStep.howItWorks,
    if (ref.read(syncServiceProvider) != null) WelcomeStep.signIn,
    WelcomeStep.claudeKey,
  ];

  WelcomeStep get _step => _steps[_index.clamp(0, _steps.length - 1)];

  void _goTo(int i) {
    final target = i.clamp(0, _steps.length - 1);
    if (target == _index) return;
    setState(() => _index = target);
    _keepFocus();
    if (!_pages.hasClients) return;
    final motion = ref.read(motionProvider);
    if (motion.reduced) {
      _pages.jumpToPage(target);
    } else {
      unawaited(_pages.animateToPage(target, duration: motion.medium, curve: motion.curve));
    }
  }

  void _next() => _index >= _steps.length - 1 ? unawaited(_finish()) : _goTo(_index + 1);
  void _back() => _goTo(_index - 1);

  /// Esc and the skip buttons: past the intro, past a setup step, or out.
  void _skip() {
    switch (_step) {
      case WelcomeStep.tosk || WelcomeStep.howItWorks:
        _goTo(2);
      case WelcomeStep.signIn:
        _next();
      case WelcomeStep.claudeKey:
        unawaited(_finish());
    }
  }

  /// After a page change the focused button may be gone: focus the screen
  /// again, so Enter and Esc keep working.
  void _keepFocus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && !_focus.hasFocus) _focus.requestFocus();
  });

  /// Enter: a focused button activates itself; otherwise (nothing focused,
  /// or the key field) the page's main button.
  void _enter() {
    final focused = FocusManager.instance.primaryFocus;
    final ctx = focused?.context;
    if (focused != null && focused != _focus && ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() == null) {
      if (Actions.maybeInvoke(ctx, const ActivateIntent()) != null) return;
    }
    _primary();
  }

  /// The page's main button.
  void _primary() {
    switch (_step) {
      case WelcomeStep.tosk || WelcomeStep.howItWorks:
        _next();
      case WelcomeStep.signIn:
        final service = ref.read(syncServiceProvider);
        final status = ref.read(syncStatusProvider);
        if (service == null || (status?.signedIn ?? false)) {
          _next();
        } else if (service.identity.canCallSignIn && status?.phase != SyncPhase.signingIn) {
          unawaited(service.signIn());
        }
      case WelcomeStep.claudeKey:
        _keySaved ? unawaited(_finish()) : unawaited(_saveKey());
    }
  }

  Future<void> _markDone() => ref.read(progressStoreProvider).setSetting(SettingKeys.welcomeDone, 'true');

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    await _markDone();
    if (!mounted) return;
    final router = GoRouter.of(context);
    router.canPop() ? router.pop() : router.go(Routes.map);
  }

  Future<void> _saveKey() async {
    if (_saving) return;
    final key = _key.text.trim();
    final error = key.isEmpty
        ? 'Paste your key first, or skip this step.'
        : looksLikeClaudeKey(key)
        ? null
        : "That doesn't look like a Claude API key. Keys start with sk-ant-.";
    setState(() => _keyError = error);
    if (error != null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(aiConfigProvider.notifier)
          .change((c) => c.copyWith(provider: AiProvider.anthropic, model: '', baseUrl: '', apiKey: key));
      if (mounted) setState(() => _keySaved = true);
      _keepFocus();
    } on Object {
      if (mounted) setState(() => _keyError = "The key couldn't be saved on this device. You can add it later in Settings.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _key.text = text;
      _key.selection = TextSelection.collapsed(offset: text.length);
      _keyError = null;
    });
  }

  Future<void> _openKeysPage() async {
    final ok = await ref.read(externalLinkOpenerProvider)(Uri.parse(kClaudeKeysUrl));
    if (mounted) setState(() => _linkError = ok ? null : "Couldn't open the browser. Go to the address below yourself.");
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final reduced = ref.watch(reduceMotionProvider);
    final sync = ref.watch(syncStatusProvider);
    final pages = [
      for (final s in steps)
        switch (s) {
          WelcomeStep.tosk => const _ToskPage(),
          WelcomeStep.howItWorks => const _HowItWorksPage(),
          WelcomeStep.signIn => _SignInPage(status: sync),
          WelcomeStep.claudeKey => _ClaudeKeyPage(
            controller: _key,
            showKey: _showKey,
            saved: _keySaved,
            error: _keyError,
            linkError: _linkError,
            alreadySet: ref.watch(aiConfigProvider.select((c) => c.value?.isConfigured ?? false)),
            onToggleShow: () => setState(() => _showKey = !_showKey),
            onPaste: () => unawaited(_paste()),
            onChanged: () {
              if (_keyError != null) setState(() => _keyError = null);
            },
            onSubmit: () => unawaited(_saveKey()),
            onOpenKeys: () => unawaited(_openKeysPage()),
          ),
        },
    ];

    return PopScope(
      // System back walks back through the pages; on the first page it leaves.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _finished = true;
          unawaited(_markDone());
        } else {
          _back();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _enter,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): _enter,
          const SingleActivator(LogicalKeyboardKey.escape): _skip,
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: Scaffold(
            key: const ValueKey('welcome'),
            body: SafeArea(
              child: Column(
                children: [
                  _TopBar(
                    index: _index,
                    count: steps.length,
                    onBack: _index > 0 ? _back : null,
                    onSkipIntro: _index < 2 ? _skip : null,
                  ),
                  Expanded(
                    child: PageView(
                      key: const ValueKey('welcome-pages'),
                      controller: _pages,
                      // No sliding on e-ink: buttons only with reduced motion.
                      physics: reduced ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                      onPageChanged: (i) {
                        if (i == _index) return;
                        setState(() => _index = i);
                        _keepFocus();
                      },
                      children: pages,
                    ),
                  ),
                  _Actions(children: _actions(steps[_index.clamp(0, steps.length - 1)], sync)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(WelcomeStep step, SyncStatus? sync) {
    final finishLabel = widget.firstRun ? 'Choose a course' : 'Done';
    switch (step) {
      case WelcomeStep.tosk || WelcomeStep.howItWorks:
        return [_wide(FilledButton(key: const ValueKey('welcome-next'), onPressed: _next, child: const Text('Next')))];
      case WelcomeStep.signIn:
        final service = ref.read(syncServiceProvider);
        if (service == null || (sync?.signedIn ?? false)) {
          return [
            _wide(FilledButton(key: const ValueKey('welcome-next'), onPressed: _next, child: const Text('Continue'))),
          ];
        }
        final busy = sync?.phase == SyncPhase.signingIn || sync?.phase == SyncPhase.syncing;
        return [
          Center(child: SyncSignInButton(service: service, busy: busy, expand: true)),
          _wide(
            OutlinedButton(
              key: const ValueKey('welcome-sync-skip'),
              onPressed: _next,
              child: const Text('Skip — keep everything on this device', textAlign: TextAlign.center),
            ),
          ),
        ];
      case WelcomeStep.claudeKey:
        if (_keySaved) {
          return [
            _wide(FilledButton(key: const ValueKey('welcome-finish'), onPressed: _finish, child: Text(finishLabel))),
          ];
        }
        return [
          _wide(
            FilledButton(
              key: const ValueKey('welcome-key-save'),
              onPressed: _saving ? null : _saveKey,
              child: Text(_saving ? 'Saving…' : 'Save key'),
            ),
          ),
          _wide(
            OutlinedButton(
              key: const ValueKey('welcome-key-skip'),
              onPressed: _finish,
              child: Text(widget.firstRun ? 'Skip — choose a course' : 'Skip'),
            ),
          ),
        ];
    }
  }

  static Widget _wide(Widget button) => SizedBox(width: double.infinity, child: button);
}

/// Back, the step dots, and "Skip" while on the intro pages.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.index, required this.count, this.onBack, this.onSkipIntro});
  final int index;
  final int count;
  final VoidCallback? onBack;
  final VoidCallback? onSkipIntro;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Align(
                alignment: Alignment.centerLeft,
                child: onBack == null
                    ? null
                    : IconButton(
                        key: const ValueKey('welcome-back'),
                        tooltip: 'Back',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
              ),
            ),
            Expanded(
              child: Semantics(
                key: const ValueKey('welcome-steps'),
                label: 'Step ${index + 1} of $count',
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < count; i++)
                        Container(
                          // The current step is a longer, filled pill (shape, not colour).
                          width: i == index ? 22 : 10,
                          height: 10,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: i == index ? scheme.primary : null,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: i == index ? scheme.primary : scheme.outline, width: 1.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 104,
              child: Align(
                alignment: Alignment.centerRight,
                child: onSkipIntro == null
                    ? null
                    : TextButton(
                        key: const ValueKey('welcome-skip-intro'),
                        onPressed: onSkipIntro,
                        child: const Text('Skip'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page's buttons, pinned at the bottom (thumb zone), full width up to 480.
class _Actions extends StatelessWidget {
  const _Actions({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 8), c],
          ],
        ),
      ),
    ),
  );
}

/// A scrolling, centred column of at most 560 dp.
class _Page extends StatelessWidget {
  const _Page({required this.pageKey, required this.children});
  final Key pageKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: pageKey,
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ),
  );
}

/// Tosk's size for the room there is: smaller on short screens.
double _toskHeight(BuildContext context, double tall) {
  final h = MediaQuery.sizeOf(context).height;
  return h < 640 ? tall * 0.6 : (h < 760 ? tall * 0.8 : tall);
}

class _ToskPage extends StatelessWidget {
  const _ToskPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Page(
      pageKey: const ValueKey('welcome-page-tosk'),
      children: [
        ToskImage(pose: ToskPose.standing, height: _toskHeight(context, 170)),
        const SizedBox(height: 8),
        const Center(child: Wordmark(size: 56)),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text("Hi, I'm Tosk!", textAlign: TextAlign.center, style: theme.textTheme.serifHeadline),
        ),
        const SizedBox(height: 12),
        Text(
          "I'm named after Ratatosk, the red squirrel of Norse myth who scurries up and down the world tree "
          'Yggdrasil, carrying messages between its crown and its roots. Here I carry words between '
          "languages, and I'd love to help you learn a few.",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Page(
      pageKey: const ValueKey('welcome-page-how'),
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('How it works', style: theme.textTheme.serifHeadline),
              ),
            ),
            ToskImage(pose: ToskPose.pointing, height: _toskHeight(context, 96)),
          ],
        ),
        const SizedBox(height: 8),
        const _Point(
          icon: Icons.inventory_2_outlined,
          title: 'Courses are packs you add',
          text: 'Pick one to start and add more any time. Once added, a course works offline.',
        ),
        const _Point(
          icon: Icons.park_outlined,
          title: 'Your course is a tree',
          text: 'Grammar grows along the main tree. Themed topics sit on side branches: tap a branch to open its topic.',
        ),
        const _Point(
          icon: Icons.timer_outlined,
          title: 'Short lessons',
          text: "Lessons only use grammar you've already started, so nothing comes out of nowhere.",
        ),
        const _Point(
          icon: Icons.replay,
          title: 'Words come back just in time',
          text: "Spaced repetition brings each word back right before you'd forget it.",
        ),
        const _Point(
          icon: Icons.military_tech_outlined,
          title: 'Bronze, silver, gold',
          text: 'Skills earn medals. A medal cracks when a skill fades; a little practice mends it.',
        ),
      ],
    );
  }
}

/// One point: an icon, a bold line and a sentence (read as one by screen readers).
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 28, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(text, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInPage extends StatelessWidget {
  const _SignInPage({required this.status});
  final SyncStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status;
    return _Page(
      pageKey: const ValueKey('welcome-page-sign-in'),
      children: [
        ToskImage(pose: ToskPose.thinking, height: _toskHeight(context, 120)),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            'Keep your progress on all your devices',
            textAlign: TextAlign.center,
            style: theme.textTheme.serifHeadline,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Sign in with Google and your answers and settings stay in step on your phone, tablet and the web.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'Or skip it and keep everything on this device. You can turn sync on later in Settings, under Account & sync.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (s != null && s.signedIn) ...[
          const SizedBox(height: 16),
          _StatusLine(
            key: const ValueKey('welcome-signed-in'),
            icon: Icons.check_circle_outline,
            text: 'Signed in as ${s.email ?? s.name ?? 'your Google account'}.',
          ),
        ],
        if (s?.notice case final n?) ...[
          const SizedBox(height: 12),
          _StatusLine(key: const ValueKey('welcome-sync-notice'), icon: Icons.info_outline, text: n),
        ],
        if (s?.lastError case final e? when !(s?.signedIn ?? false)) ...[
          const SizedBox(height: 12),
          _StatusLine(key: const ValueKey('welcome-sync-error'), icon: Icons.error_outline, text: e),
        ],
      ],
    );
  }
}

/// An icon and a sentence (never colour alone).
class _StatusLine extends StatelessWidget {
  const _StatusLine({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
}

class _ClaudeKeyPage extends StatelessWidget {
  const _ClaudeKeyPage({
    required this.controller,
    required this.showKey,
    required this.saved,
    required this.error,
    required this.linkError,
    required this.alreadySet,
    required this.onToggleShow,
    required this.onPaste,
    required this.onChanged,
    required this.onSubmit,
    required this.onOpenKeys,
  });

  final TextEditingController controller;
  final bool showKey;
  final bool saved;
  final String? error;
  final String? linkError;
  final bool alreadySet;
  final VoidCallback onToggleShow;
  final VoidCallback onPaste;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onOpenKeys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final where = kIsWeb ? 'in this browser' : 'on this device';
    return _Page(
      pageKey: const ValueKey('welcome-page-key'),
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Help from Claude', style: theme.textTheme.serifHeadline),
              ),
            ),
            ToskImage(pose: ToskPose.thinking, height: _toskHeight(context, 88)),
          ],
        ),
        const SizedBox(height: 4),
        Text('Optional. With your own Claude API key, tosk can also:', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        const _Point(icon: Icons.lightbulb_outline, title: 'Explain an answer', text: 'Why it was right or wrong, in plain words.'),
        const _Point(
          icon: Icons.outlined_flag,
          title: 'Check a flagged exercise',
          text: 'A second opinion when an exercise looks wrong to you.',
        ),
        const _Point(
          icon: Icons.chat_bubble_outline,
          title: 'Practice conversations',
          text: 'Chat in the language you are learning, at your level.',
        ),
        const SizedBox(height: 4),
        Text(
          'Usage is billed to your own Anthropic account, and the key stays only $where. '
          'Everything else in tosk works without it.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (saved)
          const _StatusLine(
            key: ValueKey('welcome-key-saved'),
            icon: Icons.check_circle_outline,
            text: 'Saved. Claude is on; you can change it any time in Settings, under AI explanations.',
          )
        else ...[
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('welcome-get-key'),
                onPressed: onOpenKeys,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Get a key'),
              ),
              SelectableText('console.anthropic.com/settings/keys', style: theme.textTheme.bodySmall),
            ],
          ),
          if (linkError case final e?) ...[
            const SizedBox(height: 8),
            _StatusLine(icon: Icons.error_outline, text: e),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('welcome-key-field'),
            controller: controller,
            obscureText: !showKey,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              labelText: 'Claude API key',
              hintText: 'sk-ant-…',
              helperText: alreadySet ? 'A key is already saved; a new one replaces it.' : null,
              errorText: error,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('welcome-key-paste'),
                    tooltip: 'Paste',
                    onPressed: onPaste,
                    icon: const Icon(Icons.content_paste),
                  ),
                  IconButton(
                    tooltip: showKey ? 'Hide key' : 'Show key',
                    onPressed: onToggleShow,
                    icon: Icon(showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
