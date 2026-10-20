import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/sync_providers.dart';
import '../../sync/sync_service.dart';
import 'settings_parts.dart';

/// Settings → Account & sync (v0.7). Shown only when the build has a
/// Firebase configuration and the platform can sign in; otherwise nothing.
class SyncSection extends ConsumerWidget {
  const SyncSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(syncServiceProvider);
    final status = ref.watch(syncStatusProvider);
    if (service == null || status == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final busy = status.phase == SyncPhase.syncing || status.phase == SyncPhase.signingIn;

    final children = <Widget>[const SettingsHeader('Account & sync')];
    if (!status.signedIn) {
      children.addAll([
        const ListTile(
          leading: Icon(Icons.cloud_outlined),
          title: Text('Sync across your devices'),
          subtitle: Text(
            'Sign in with Google to keep your answers and settings in step on your phone, '
            'tablet and the web. Without an account everything stays on this device.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: service.identity.canCallSignIn
                ? FilledButton.icon(
                    key: const ValueKey('sync-sign-in'),
                    onPressed: busy ? null : service.signIn,
                    icon: const Icon(Icons.login),
                    label: Text(busy ? 'Signing in…' : 'Sign in with Google'),
                  )
                : KeyedSubtree(key: const ValueKey('sync-sign-in-web'), child: service.identity.button()),
          ),
        ),
      ]);
    } else {
      children.addAll([
        ListTile(
          key: const ValueKey('sync-account'),
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(status.email ?? status.name ?? 'Signed in'),
          subtitle: Text(_summary(status), key: const ValueKey('sync-summary')),
          trailing: busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
        ),
        ListTile(
          key: const ValueKey('sync-now'),
          enabled: !busy,
          leading: const Icon(Icons.sync),
          title: const Text('Sync now'),
          onTap: () => service.syncNow(),
        ),
        ListTile(
          key: const ValueKey('sync-sign-out'),
          enabled: !busy,
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          subtitle: const Text('Your progress stays on this device and in your account'),
          onTap: () => _signOut(context, service),
        ),
        ListTile(
          key: const ValueKey('sync-delete'),
          enabled: !busy,
          leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
          title: const Text('Delete my cloud data'),
          subtitle: const Text('Removes your answers and settings from the account; this device keeps its copy'),
          onTap: () => _delete(context, service),
        ),
      ]);
    }
    if (status.lastError case final e?) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(e, key: const ValueKey('sync-error'), style: TextStyle(color: theme.colorScheme.error)),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  static String _summary(SyncStatus s) {
    final parts = <String>[];
    if (s.phase == SyncPhase.syncing) {
      parts.add('Syncing…');
    } else if (s.offline) {
      parts.add('Offline');
    } else if (s.lastSync case final t?) {
      final l = t.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      parts.add('Synced ${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}');
    } else {
      parts.add('Not synced yet');
    }
    if (s.pending > 0) {
      parts.add('${s.pending} answer${s.pending == 1 ? '' : 's'} waiting to upload');
    }
    return parts.join(' · ');
  }

  Future<void> _signOut(BuildContext context, SyncService service) async {
    await service.signOut();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signed out')));
    }
  }

  Future<void> _delete(BuildContext context, SyncService service) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('sync-delete-confirm'),
        title: const Text('Delete your cloud data?'),
        content: const Text(
          'Every answer and setting stored in your account is deleted, and you are signed out. '
          'The progress on this device is kept, and so is the progress on your other devices.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('sync-delete-yes'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await service.deleteCloudData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cloud data deleted')));
      }
    } on Object {
      // The status shows the error.
    }
  }
}
