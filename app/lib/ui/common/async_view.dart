import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loading spinner / error with retry / data, for `AsyncValue`s.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v.hasValue) return builder(v.requireValue);
    if (v.hasError) return ErrorPanel(error: v.error!, onRetry: onRetry);
    return const Center(child: CircularProgressIndicator());
  }
}

/// An error in words: what happened, what to do (Retry), and the technical
/// details small and selectable underneath (to copy into feedback).
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = '$error'.replaceFirst(RegExp(r'^(Exception|Bad state|StateError): '), '');
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('Something went wrong', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                onRetry != null
                    ? 'Please try again. If it keeps happening, tell the developer in Settings → Send feedback.'
                    : 'If it keeps happening, tell the developer in Settings → Send feedback.',
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
              const SizedBox(height: 12),
              SelectableText(
                details,
                key: const ValueKey('error-details'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
