import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'external_link.dart';
import 'links.dart';

/// "Privacy policy" as a text button that opens [kPrivacyPolicyUrl] (the
/// welcome's sign-in page, Settings → Account & sync). When no browser can
/// open it, a snack bar shows the address.
class PrivacyPolicyLink extends ConsumerWidget {
  const PrivacyPolicyLink({super.key, this.label = 'Privacy policy'});
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton.icon(
    onPressed: () => unawaited(() async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final ok = await ref.read(externalLinkOpenerProvider)(Uri.parse(kPrivacyPolicyUrl));
      if (!ok) messenger?.showSnackBar(const SnackBar(content: Text('The privacy policy is at $kPrivacyPolicyUrl')));
    }()),
    icon: const Icon(Icons.privacy_tip_outlined, size: 18),
    label: Text(label),
  );
}
