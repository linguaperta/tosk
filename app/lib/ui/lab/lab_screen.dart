import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../settings/app_settings.dart';

/// Exercise lab: pick any skills and exercise types, and a session length.
class LabScreen extends ConsumerStatefulWidget {
  const LabScreen({super.key, this.embedded = false});

  /// Inside the Practice tab: no own app bar.
  final bool embedded;

  static const lengths = [5, 10, 20, 30, 50];

  @override
  ConsumerState<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends ConsumerState<LabScreen> {
  final Set<String> _skills = {};
  final Set<ExerciseType> _types = {...ExerciseType.values};
  int _length = 10;
  String? _courseId;

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseDataProvider);
    final lang = ref.watch(sourceLangProvider);
    final theme = Theme.of(context);

    final body = AsyncView<CourseData>(
      value: course,
      onRetry: () => ref.invalidate(courseDataProvider),
      builder: (course) {
        if (_courseId != course.meta.id) {
          // New course: forget skill ids from the old one.
          _courseId = course.meta.id;
          _skills.clear();
        }
        final canStart = _skills.isNotEmpty && _types.isNotEmpty;
        return Column(
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('lab-list'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _Header(
                    title: 'Skills',
                    trailing: TextButton(
                      onPressed: () => setState(() {
                        if (_skills.length == course.skills.length) {
                          _skills.clear();
                        } else {
                          _skills.addAll(course.skills.map((s) => s.id));
                        }
                      }),
                      child: Text(_skills.length == course.skills.length ? 'Clear' : 'All'),
                    ),
                  ),
                  for (final unit in course.units) ...[_unitSection(context, course, unit, lang)],
                  const SizedBox(height: 12),
                  _Header(
                    title: 'Exercise types',
                    trailing: TextButton(
                      onPressed: () => setState(() {
                        if (_types.length == ExerciseType.values.length) {
                          _types.clear();
                        } else {
                          _types.addAll(ExerciseType.values);
                        }
                      }),
                      child: Text(_types.length == ExerciseType.values.length ? 'Clear' : 'All'),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in ExerciseType.values)
                        FilterChip(
                          key: ValueKey('lab-type-${t.id}'),
                          avatar: _types.contains(t) ? null : Icon(exerciseTypeIcon(t), size: 18),
                          label: Text(exerciseTypeLabel(t)),
                          selected: _types.contains(t),
                          onSelected: (v) => setState(() => v ? _types.add(t) : _types.remove(t)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _Header(title: 'Session length'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final n in LabScreen.lengths)
                        ChoiceChip(
                          key: ValueKey('lab-length-$n'),
                          label: Text('$n'),
                          selected: _length == n,
                          onSelected: (_) => setState(() => _length = n),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      canStart
                          ? '${_skills.length} skills · ${_types.length} types · $_length exercises'
                          : 'Pick at least one skill and one exercise type',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const ValueKey('lab-start'),
                      onPressed: canStart
                          ? () => context.push(
                              Routes.labPlay(
                                skills: [
                                  for (final s in course.skills)
                                    if (_skills.contains(s.id)) s.id,
                                ],
                                types: [
                                  for (final t in ExerciseType.values)
                                    if (_types.contains(t)) t,
                                ],
                                length: _length,
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.science_outlined),
                      label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Start')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise lab')),
      body: body,
    );
  }

  Widget _unitSection(BuildContext context, CourseData course, Unit unit, String lang) {
    final skills = course.skills.where((s) => s.unitId == unit.id).toList();
    if (skills.isEmpty) return const SizedBox.shrink();
    final all = skills.every((s) => _skills.contains(s.id));
    final some = skills.any((s) => _skills.contains(s.id));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            key: ValueKey('lab-unit-${unit.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            tristate: true,
            value: all ? true : (some ? null : false),
            title: Text(pickLang(unit.title, lang), style: Theme.of(context).textTheme.titleSmall),
            onChanged: (_) => setState(() {
              if (all) {
                _skills.removeAll(skills.map((s) => s.id));
              } else {
                _skills.addAll(skills.map((s) => s.id));
              }
            }),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in skills)
                FilterChip(
                  key: ValueKey('lab-skill-${s.id}'),
                  label: Text(pickLang(s.title, lang)),
                  selected: _skills.contains(s.id),
                  onSelected: (v) => setState(() => v ? _skills.add(s.id) : _skills.remove(s.id)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ?trailing,
      ],
    ),
  );
}
