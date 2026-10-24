/// The update notice in the app shell, above the navigation bar: "Version
/// X.Y.Z is available" for sideloaded builds (GitHub Releases), "tosk was
/// updated" with Reload on the web; the web's one-time "What's new" sheet;
/// and Settings → About → Check for updates.
///
/// Calm on purpose: a card under the screen's content (it never covers
/// anything), shown at most once a day, never during a lesson (lessons are
/// outside the shell), and nothing downloads without a tap.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../updates/update_check.dart';
import '../../updates/web_update.dart';
import '../common/markdown.dart';
import '../theme/bw_skin.dart';
import '../theme/tosk_palette.dart';

/// [child] (the shell's page) with the update notice under it when there is one.
class UpdateNoticeHost extends StatelessWidget {
  const UpdateNoticeHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        Expanded(child: child),
        // At most 40% of the height (large text, small phones): the page
        // keeps the rest, and the notice scrolls inside.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.4),
          child: const UpdateNotice(),
        ),
      ],
    ),
  );
}

/// The notice itself, or nothing.
class UpdateNotice extends ConsumerWidget {
  const UpdateNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final web = ref.watch(webUpdateProvider);
    if (web.showReload) {
      final version = web.deployed?.version;
      return _NoticeCard(
        cardKey: const ValueKey('web-update-notice'),
        icon: Icons.refresh,
        title: 'tosk was updated',
        subtitle: version == null || version == ref.watch(currentAppVersionProvider)
            ? 'Reload to use the new version. Your progress stays.'
            : 'Reload to use version $version. Your progress stays.',
        actions: [
          TextButton(
            key: const ValueKey('web-update-later'),
            onPressed: ref.read(webUpdateProvider.notifier).later,
            child: const Text('Later'),
          ),
          FilledButton.icon(
            key: const ValueKey('web-update-reload'),
            onPressed: ref.read(webUpdateProvider.notifier).reload,
            icon: const Icon(Icons.refresh),
            label: const Text('Reload'),
          ),
        ],
      );
    }
    final update = ref.watch(appUpdateProvider);
    final release = update.release;
    if (!update.visible || release == null) return const SizedBox.shrink();
    final ctl = ref.read(appUpdateProvider.notifier);
    final excerpt = release.notesExcerpt();
    return _NoticeCard(
      cardKey: const ValueKey('app-update-notice'),
      icon: Icons.system_update_alt,
      title: 'Version ${release.version} is available',
      subtitle: release.title,
      excerpt: excerpt.isEmpty ? null : excerpt,
      secondary: TextButton(
        key: const ValueKey('app-update-skip'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: AlignmentDirectional.centerStart,
          textStyle: Theme.of(context).textTheme.labelMedium,
        ),
        onPressed: () => unawaited(ctl.skipVersion()),
        child: const Text("Don't show again for this version"),
      ),
      actions: [
        TextButton(
          key: const ValueKey('app-update-later'),
          onPressed: () => unawaited(ctl.later()),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          key: const ValueKey('app-update-download'),
          onPressed: () => unawaited(_download(context, ref)),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Download'),
        ),
      ],
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final release = ref.read(appUpdateProvider).release;
    if (await ref.read(appUpdateProvider.notifier).download()) return;
    messenger?.showSnackBar(
      SnackBar(
        key: const ValueKey('app-update-open-failed'),
        content: Text("Couldn't open the browser. The release is at ${release?.page ?? 'github.com/$kAppReleaseRepo'}"),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.excerpt,
    this.secondary,
  });

  final Key cardKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? excerpt;
  final List<Widget> actions;

  /// A quieter action on the left of the button row (wraps when narrow).
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final bw = isBw(context);
    return Semantics(
      container: true,
      liveRegion: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        key: cardKey,
        decoration: BoxDecoration(
          color: bw ? kBwWhite : scheme.surfaceContainerHigh,
          border: Border(
            top: bw ? const BorderSide(color: kBwBlack, width: kBwBorder) : BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 12),
                            child: Icon(icon, color: bw ? kBwBlack : scheme.primary),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(header: true, child: Text(title, style: text.serifSection)),
                                const SizedBox(height: 2),
                                Text(subtitle, style: text.bodyMedium),
                                if (excerpt != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    excerpt!,
                                    key: const ValueKey('update-notes-excerpt'),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(color: bw ? kBwBlack : scheme.onSurfaceVariant),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (secondary case final secondary?)
                            Expanded(
                              child: Align(alignment: AlignmentDirectional.centerStart, child: secondary),
                            )
                          else
                            const Spacer(),
                          // Stacks the buttons instead of overflowing (huge text).
                          Flexible(
                            flex: 2,
                            child: OverflowBar(
                              alignment: MainAxisAlignment.end,
                              overflowAlignment: OverflowBarAlignment.end,
                              spacing: 4,
                              children: actions,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The web's one-time "What's new in X.Y.Z" sheet.
Future<void> showWhatsNewSheet(BuildContext context, WhatsNew info) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SafeArea(
        child: Column(
          key: const ValueKey('whats-new-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Semantics(header: true, child: Text("What's new in ${info.version}", style: text.serifTitle)),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (info.title.isNotEmpty) ...[Text(info.title, style: text.titleSmall), const SizedBox(height: 8)],
                    MarkdownView(info.notes),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const ValueKey('whats-new-close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  },
);

/// Settings → About: "Check for updates" (sideloaded builds only).
class UpdateCheckTile extends ConsumerWidget {
  const UpdateCheckTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(updateModeProvider) != UpdateMode.github) return const SizedBox.shrink();
    final s = ref.watch(appUpdateProvider);
    final release = s.release;
    final subtitle = s.checking
        ? 'Checking…'
        : switch (s.lastResult) {
            _ when release != null => 'Version ${release.version} is available',
            UpdateCheckResult.upToDate => 'You have the latest version',
            UpdateCheckResult.failed => "Couldn't check. Are you online?",
            _ => 'Checks once a day when online. Nothing downloads without a tap',
          };
    return ListTile(
      key: const ValueKey('check-updates'),
      leading: const Icon(Icons.system_update_alt),
      title: const Text('Check for updates'),
      subtitle: Text(subtitle, key: const ValueKey('check-updates-status')),
      trailing: s.checking
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      onTap: s.checking
          ? null
          : () async {
              await ref.read(appUpdateProvider.notifier).check(manual: true);
            },
    );
  }
}
