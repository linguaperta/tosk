import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/tosk_palette.dart';
import '../../app_version.dart';
import '../brand/tosk.dart';
import '../../core/core.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../courses/course_picker.dart';
import '../courses/course_updates.dart';
import '../routes.dart';
import '../shell/course_switcher.dart';
import 'ai_settings_section.dart';
import 'answer_input_section.dart';
import 'app_settings.dart';
import 'backup_section.dart';
import 'daily_goal_section.dart';
import 'device_section.dart';

/// Settings, persisted through the progress store (see `setting_keys.dart`).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final courses = ref.watch(myCoursesProvider).value ?? const <CourseMeta>[];
    final activeId = ref.watch(activeCourseIdProvider).value;
    // The opened course's meta (listing metas from packs carry no translations).
    final meta = ref.watch(courseDataProvider).value?.meta ?? courses.where((c) => c.id == activeId).firstOrNull;
    final lang = ref.watch(sourceLangProvider);
    final ctl = ref.read(settingsProvider.notifier);
    // Course updates (v0.4 downloads): a dot on the course's row.
    final offers = ref.watch(courseOffersProvider);
    final anyUpdate = ref.watch(courseUpdateAvailableProvider);

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
                  // Courses are switched here (the map only shows the title),
                  // with the "update available" dot on a course's row.
                  for (final c in courses)
                    ListTile(
                      key: ValueKey('course-${c.id}'),
                      leading: Icon(c.id == activeId ? Icons.radio_button_checked : Icons.radio_button_off),
                      title: Row(
                        children: [
                          Flexible(child: Text(pickLang(c.title, lang), overflow: TextOverflow.ellipsis)),
                          if (c.unverified) ...[const SizedBox(width: 8), const UnverifiedBadge(compact: true)],
                          if (offers[c.id]?.status == OfferStatus.updateAvailable)
                            UpdateDot(dotKey: ValueKey('course-update-dot-${c.id}')),
                        ],
                      ),
                      subtitle: Text(
                        '${ref.read(courseCatalogProvider).isDemo(c.id) ? 'Demo content · ' : ''}v${c.version}'
                        '${offers[c.id]?.status == OfferStatus.updateAvailable ? ' · Update available' : ''}',
                      ),
                      selected: c.id == activeId,
                      onTap: () => ctl.change((s) => s.copyWith(courseId: c.id)),
                    ),
                  ListTile(
                    key: const ValueKey('manage-courses-tile'),
                    leading: const Icon(Icons.library_add_outlined),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            anyUpdate ? 'Courses (updates available)' : 'Add or remove courses',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (anyUpdate) const UpdateDot(),
                      ],
                    ),
                    onTap: () => showCoursePicker(context),
                  ),
                  SwitchListTile(
                    key: const ValueKey('auto-check-course-updates'),
                    title: const Text('Check for course updates automatically'),
                    subtitle: const Text('Once a day, when online. Downloads only start when you tap them.'),
                    value: s.autoCheckCourseUpdates,
                    onChanged: (v) => ctl.change((s) => s.copyWith(autoCheckCourseUpdates: v)),
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
                  _Choice<DisplayMode>(
                    keyName: 'display',
                    title: 'Display',
                    subtitle: s.bw
                        ? 'Pure black and white for e-ink readers, without animations'
                        : 'Black & white suits e-ink readers such as Boox',
                    values: DisplayMode.values,
                    selected: s.display,
                    label: (d) => d == DisplayMode.bw ? 'Black & white' : 'Color',
                    onChanged: (v) => ctl.change((s) => s.copyWith(display: v)),
                  ),
                  if (!s.bw)
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
                    subtitle: Text(
                      s.bw
                          ? 'No haptics (animations are always off in black & white)'
                          : 'No animations or haptics',
                    ),
                    value: s.reduceMotion,
                    onChanged: (v) => ctl.change((s) => s.copyWith(reduceMotion: v)),
                  ),
                  SwitchListTile(
                    key: const ValueKey('sound-effects'),
                    title: const Text('Sound effects'),
                    subtitle: const Text('Short sounds for answers, taps and finishing a lesson'),
                    value: s.soundEffects,
                    onChanged: (v) => ctl.change((s) => s.copyWith(soundEffects: v)),
                  ),
                  const _Section('AI explanations'),
                  const AiSettingsSection(),
                  const _Section('Feedback & flags'),
                  ListTile(
                    key: const ValueKey('open-flags'),
                    leading: const Icon(Icons.outlined_flag),
                    title: const Text('Flagged exercises'),
                    subtitle: Text(switch (ref.watch(flagsProvider).value?.length ?? 0) {
                      0 => 'None yet. Export them here for the developer',
                      1 => '1 flag on this device · export',
                      final n => '$n flags on this device · export',
                    }),
                    onTap: () => context.push(Routes.flags),
                  ),
                  const _Section('About'),
                  const Padding(
                    key: ValueKey('about-brand'),
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BrandLockup(caption: 'Version $kAppVersion · free and offline-first'),
                    ),
                  ),
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
                  const _Section('Practice'),
                  _Choice<SessionLength>(
                    keyName: 'length',
                    title: 'Default lesson length',
                    subtitle: '${s.defaultLength.exercises} exercises; the lesson sheet offers the others',
                    values: SessionLength.values,
                    selected: s.defaultLength,
                    label: sessionLengthLabel,
                    onChanged: (v) => ctl.change((s) => s.copyWith(defaultLength: v)),
                  ),
                  _Choice<int>(
                    keyName: 'leech',
                    title: 'Tough word after this many lapses',
                    subtitle: 'Words forgotten this often (after you knew them) go to the "Tough words" drill',
                    values: const [3, 4, 5, 6],
                    selected: s.leechLapses,
                    label: (n) => '$n',
                    onChanged: (v) => ctl.change((s) => s.copyWith(leechLapses: v)),
                  ),
                  // v0.3 practice extras (their own settings and widgets).
                  const AnswerInputSection(),
                  const DeviceSection(),
                  const DailyGoalSection(),
                  const BackupSection(),
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
      style: Theme.of(context).textTheme.serifSection?.copyWith(color: Theme.of(context).colorScheme.primary),
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
