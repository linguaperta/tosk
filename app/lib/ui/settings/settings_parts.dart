import 'package:flutter/material.dart';

/// A section title in the settings list.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// A setting with a few options as a segmented button under its title
/// (keys `setting-{keyName}` and `setting-{keyName}-{label}`).
class SettingsChoice<T> extends StatelessWidget {
  const SettingsChoice({
    super.key,
    required this.keyName,
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.subtitle,
  });

  final String keyName;
  final String title;
  final String? subtitle;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              key: ValueKey('setting-$keyName'),
              showSelectedIcon: false,
              segments: [
                for (final v in values)
                  ButtonSegment<T>(
                    value: v,
                    label: Text(label(v), key: ValueKey('setting-$keyName-${label(v)}')),
                  ),
              ],
              selected: {if (values.contains(selected)) selected},
              emptySelectionAllowed: !values.contains(selected),
              onSelectionChanged: (set) {
                if (set.isNotEmpty) onChanged(set.first);
              },
            ),
          ),
        ],
      ),
    );
  }
}
