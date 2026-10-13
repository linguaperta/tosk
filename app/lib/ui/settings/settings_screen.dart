import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../shell/course_switcher.dart';
import 'app_settings.dart';

/// Settings, persisted through the progress store (see `setting_keys.dart`).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final courses = ref.watch(availableCoursesProvider).value ?? const <CourseMeta>[];
    final activeId = ref.watch(activeCourseIdProvider).value;
    // The opened course's meta (listing metas from packs carry no translations).
    final meta = ref.watch(courseDataProvider).value?.meta ?? courses.where((c) => c.id == activeId).firstOrNull;
    final lang = ref.watch(sourceLangProvider);
    final ctl = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AsyncView(
        value: settings,
        onRetry: () => ref.invalidate(settingsProvider),
        builder: (s) {
          final languages = (meta == null || meta.translations.isEmpty) ? const ['en', 'nl'] : meta.translations;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                key: const ValueKey('settings-list'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  const _Section('Course'),
                  for (final c in courses)
                    ListTile(
                      key: ValueKey('course-${c.id}'),
                      leading: Icon(c.id == activeId ? Icons.radio_button_checked : Icons.radio_button_off),
                      title: Row(
                        children: [
                          Flexible(child: Text(pickLang(c.title, lang), overflow: TextOverflow.ellipsis)),
                          if (c.unverified) ...[const SizedBox(width: 8), const UnverifiedBadge(compact: true)],
                        ],
                      ),
                      subtitle: Text(
                        '${ref.read(courseCatalogProvider).isDemo(c.id) ? 'Demo content · ' : ''}v${c.version}',
                      ),
                      selected: c.id == activeId,
                      onTap: () => ctl.change((s) => s.copyWith(courseId: c.id)),
                    ),
                  const _Section('Learning'),
                  _Choice<String>(
                    keyName: 'source-lang',
                    title: 'Translations in',
                    subtitle: languages.length < 2 ? 'This course only has ${languageName(languages.first)}' : null,
                    values: languages,
                    selected: lang,
                    label: languageName,
                    onChanged: (v) => ctl.change((s) => s.copyWith(sourceLang: v)),
                  ),
                  _Choice<LessonFocus>(
                    keyName: 'focus',
                    title: 'Default lesson focus',
                    values: LessonFocus.values,
                    selected: s.defaultFocus,
                    label: focusShortLabel,
                    onChanged: (v) => ctl.change((s) => s.copyWith(defaultFocus: v)),
                  ),
                  _Choice<AccentStrictness>(
                    keyName: 'accents',
                    title: 'Accents',
                    subtitle: s.accents == AccentStrictness.lenient
                        ? 'A missing accent still counts as right'
                        : 'Accents must be exact',
                    values: AccentStrictness.values,
                    selected: s.accents,
                    label: (a) => a == AccentStrictness.strict ? 'Strict' : 'Lenient',
                    onChanged: (v) => ctl.change((s) => s.copyWith(accents: v)),
                  ),
                  const _Section('Display'),
                  _Choice<ThemeMode>(
                    keyName: 'theme',
                    title: 'Theme',
                    values: const [ThemeMode.light, ThemeMode.dark, ThemeMode.system],
                    selected: s.themeMode,
                    label: (m) => switch (m) {
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                      ThemeMode.system => 'System',
                    },
                    onChanged: (v) => ctl.change((s) => s.copyWith(themeMode: v)),
                  ),
                  SwitchListTile(
                    key: const ValueKey('reduce-motion'),
                    title: const Text('Reduce motion'),
                    subtitle: const Text('No animations, haptics or sounds'),
                    value: s.reduceMotion,
                    onChanged: (v) => ctl.change((s) => s.copyWith(reduceMotion: v)),
                  ),
                  const _Section('About'),
                  if (meta != null && meta.attribution.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Course content'),
                      subtitle: Text(meta.attribution),
                    ),
                  ListTile(
                    key: const ValueKey('open-debug'),
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Debug'),
                    subtitle: const Text('Courses, skills and strength'),
                    onTap: () => context.push(Routes.debug),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
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

/// A setting with a few options as a segmented button under its title.
class _Choice<T> extends StatelessWidget {
  const _Choice({
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
