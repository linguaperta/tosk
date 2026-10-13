import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/app_data.dart';
import 'package:tosk/data/course/course_bytes.dart';
import 'package:tosk/data/packs/local_pack_source.dart';
import 'package:tosk/data/packs/pack_file_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/ui/debug/debug_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../fixtures/course_fixture.dart';

class _Bundled implements BundledPacks {
  _Bundled(this.packs);
  final Map<String, Uint8List> packs;
  @override
  Future<List<String>> list() async => packs.keys.toList();
  @override
  Future<Uint8List> load(String key) async => packs[key]!;
}

void main() {
  testWidgets('lists both courses with skills, counts and strength', (tester) async {
    final it = fixtureCourseBytes();
    final nl = fixtureCourseBytes(overrideMeta: {
      'course_id': 'nl',
      'title': '{"en":"Dutch","nl":"Nederlands"}',
    });
    // Synchronous loaders keep everything inside the widget test's fake async zone.
    final app = AppData(
      progress: ProgressRepo(ProgressDb(NativeDatabase.memory())),
      packs: LocalPackSource(
        bundled: _Bundled({'assets/courses/it.sqlite': it, 'assets/courses/nl.sqlite': nl}),
        store: MemoryPackFileStore(),
        readMeta: (d) async => readCourseMetaFromBytes(sqlite3, (d as PackBytes).bytes),
      ),
      loadPack: (d) async => loadCourseRepoFromBytes(sqlite3, (d as PackBytes).bytes),
    );
    final now = DateTime.utc(2026, 10, 13, 12);
    await tester.runAsync(() => app.progress.record(ReviewEvent(
          id: 'e1',
          facetId: 'it:ciao#rec',
          at: now.subtract(const Duration(hours: 2)),
          rating: Rating.easy,
          exerciseType: 'flashcard',
          inputMode: InputMode.self,
          responseMs: 900,
          correct: true,
        )));

    await tester.pumpWidget(MaterialApp(home: DebugScreen(app: app, clock: () => now)));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(find.textContaining('Italian (it) v0.1.0'), findsOneWidget);
    expect(find.textContaining('Dutch (nl) v0.1.0'), findsOneWidget);
    expect(find.textContaining('Greetings'), findsNWidgets(2));
    expect(find.textContaining('5 items · 10 facets'), findsNWidgets(2));
    expect(find.textContaining('Present: -are verbs'), findsNWidgets(2));
    expect(find.textContaining('4 items · 4 facets'), findsNWidgets(2));
    // One facet of 10 reviewed 2 h ago with recall ~1 -> 10%.
    expect(find.text('10%'), findsOneWidget);
    expect(find.textContaining('last practiced 2 h ago'), findsOneWidget);

    await tester.runAsync(app.close);
  });
}
