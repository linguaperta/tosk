/// Data-layer debug screen: available course packs and, per course, its skills
/// with item counts, facet counts, learned items and strength.
///
/// Standalone: `flutter run -t lib/main_debug.dart`.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/core.dart';
import '../../data/bootstrap.dart';
import '../../data/course/course_repo.dart';
import '../../data/stats/skill_stats.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key, required this.app, this.sourceLang = 'en', this.clock});

  final AppData app;
  final String sourceLang;

  /// Time source for stats (tests); defaults to now.
  final DateTime Function()? clock;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  late Future<List<PackInfo>> _packs = widget.app.availableCourses();
  int _generation = 0; // bumps to make course sections reload

  void _reload() => setState(() {
        _packs = widget.app.availableCourses();
        _generation++;
      });

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addPack() async {
    try {
      final f = await FilePicker.pickFile(dialogTitle: 'Choose a course pack (.sqlite)');
      if (f == null) return;
      final path = f.path;
      final PackData data = (supportsPackFiles && path != null)
          ? PackFile(path)
          : PackBytes(await f.readAsBytes(), name: f.name);
      final info = await widget.app.installPack(data);
      _toast('Installed ${info.id} ${info.version}');
      _reload();
    } on Object catch (e) {
      _toast('Could not add pack: $e');
    }
  }

  Future<void> _rebuild() async {
    final sw = Stopwatch()..start();
    await widget.app.progress.rebuildStates();
    final n = await widget.app.progress.logCount();
    _toast('Rebuilt states from $n events in ${sw.elapsedMilliseconds} ms');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data debug'),
        actions: [
          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _reload),
          IconButton(tooltip: 'Add pack from file', icon: const Icon(Icons.add), onPressed: _addPack),
          IconButton(
            tooltip: 'Rebuild states from the log',
            icon: const Icon(Icons.restart_alt),
            onPressed: _rebuild,
          ),
        ],
      ),
      body: FutureBuilder<List<PackInfo>>(
        future: _packs,
        builder: (context, snap) {
          if (snap.hasError) return _Message('Could not list packs: ${snap.error}');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final packs = snap.data!;
          if (packs.isEmpty) {
            return const _Message('No course packs. Bundle assets/courses/*.sqlite '
                'or add one with the + button.');
          }
          return ListView(
            children: [
              for (final p in packs)
                _CourseSection(
                  key: ValueKey('${p.id}/$_generation'),
                  app: widget.app,
                  pack: p,
                  lang: widget.sourceLang,
                  clock: widget.clock,
                  onToast: _toast,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text)));
}

class _CourseSection extends StatefulWidget {
  const _CourseSection({
    super.key,
    required this.app,
    required this.pack,
    required this.lang,
    required this.onToast,
    this.clock,
  });

  final AppData app;
  final PackInfo pack;
  final String lang;
  final DateTime Function()? clock;
  final void Function(String) onToast;

  @override
  State<_CourseSection> createState() => _CourseSectionState();
}

class _CourseSectionState extends State<_CourseSection> {
  late Future<(CourseRepo, Map<String, SkillStats>)> _data = _load();

  DateTime _now() => (widget.clock?.call() ?? DateTime.now()).toUtc();

  Future<(CourseRepo, Map<String, SkillStats>)> _load() async {
    final course = await widget.app.openCourse(widget.pack.id);
    final stats = await widget.app.stats.forCourse(course, now: _now());
    return (course, stats);
  }

  Future<void> _practice(CourseRepo course, Skill skill, Rating rating) async {
    const uuid = Uuid();
    final now = _now();
    for (final f in course.skillFacets(skill.id)) {
      await widget.app.progress.record(ReviewEvent(
        id: uuid.v4(),
        facetId: f.facetId,
        at: now,
        rating: rating,
        exerciseType: ExerciseType.flashcard.id,
        inputMode: InputMode.self,
        responseMs: 0,
        correct: rating != Rating.again,
        mode: 'debug',
      ));
    }
    widget.onToast('Recorded ${rating.name} for ${course.skillFacets(skill.id).length} facets');
    setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pack;
    return FutureBuilder<(CourseRepo, Map<String, SkillStats>)>(
      future: _data,
      builder: (context, snap) {
        final title = '${pickLang(p.title, widget.lang)} (${p.id}) v${p.version}';
        if (snap.hasError) {
          return ListTile(title: Text(title), subtitle: Text('Failed to load: ${snap.error}'));
        }
        if (!snap.hasData) {
          return ListTile(title: Text(title), subtitle: const LinearProgressIndicator());
        }
        final (course, stats) = snap.data!;
        final c = course.counts;
        final ms = course.loadTime?.inMilliseconds;
        return ExpansionTile(
          initiallyExpanded: true,
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(title),
          subtitle: Text('${p.origin.name}${p.unverified ? ' · unverified' : ''} · '
              '${c.items} items · ${c.verbs} verbs · ${c.sentences} sentences · '
              '${course.skills.length} skills${ms == null ? '' : ' · loaded in $ms ms'}'),
          children: [
            for (final u in course.units) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(pickLang(u.title, widget.lang),
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              for (final s in course.skillsInUnit(u.id))
                _SkillTile(
                  skill: s,
                  stats: stats[s.id]!,
                  lang: widget.lang,
                  now: _now(),
                  onPractice: (r) => _practice(course, s, r),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({
    required this.skill,
    required this.stats,
    required this.lang,
    required this.now,
    required this.onPractice,
  });

  final Skill skill;
  final SkillStats stats;
  final String lang;
  final DateTime now;
  final void Function(Rating) onPractice;

  String _ago(DateTime? t) {
    if (t == null) return 'never';
    final d = now.difference(t);
    if (d.inDays >= 1) return '${d.inDays} d ago';
    if (d.inHours >= 1) return '${d.inHours} h ago';
    return '${d.inMinutes} min ago';
  }

  @override
  Widget build(BuildContext context) {
    final pct = (stats.strength * 100).round();
    return ListTile(
      dense: true,
      key: ValueKey('skill-${skill.id}'),
      leading: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(value: stats.strength, strokeWidth: 4),
            Text('$pct%', style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
      title: Text('${pickLang(skill.title, lang)}  ·  ${skill.kind.name}'
          '${skill.tense == null ? '' : ' (${skill.tense})'}'),
      subtitle: Text('${stats.itemCount} items · ${stats.facetCount} facets · '
          '${stats.learnedCount} learned · ${stats.dueCount} due · '
          'last practiced ${_ago(stats.lastPracticed)}'
          '${skill.requires.isEmpty ? '' : ' · requires ${skill.requires.join(', ')}'}'),
      trailing: PopupMenuButton<Rating>(
        tooltip: 'Debug: record a review for every facet',
        onSelected: onPractice,
        itemBuilder: (_) => [
          for (final r in Rating.values)
            PopupMenuItem(value: r, child: Text('Record ${r.name} for all facets')),
        ],
      ),
    );
  }
}
