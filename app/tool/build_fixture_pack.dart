/// Writes the test fixture course (Italian sample) as a pack file, e.g. to try
/// the debug screen's "add pack" button before real packs exist:
///
///     dart run tool/build_fixture_pack.dart build/fixture-it.sqlite
///
/// Optional `key=value` arguments override meta values, e.g. `version=0.2.0`.
library;

import 'dart:io';

import 'package:tosk/data/course/course_file.dart';

import '../test/fixtures/course_fixture.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/build_fixture_pack.dart OUT.sqlite [key=value ...]');
    exit(64);
  }
  final overrides = {
    for (final a in args.skip(1))
      if (a.contains('=')) a.substring(0, a.indexOf('=')): a.substring(a.indexOf('=') + 1),
  };
  final out = File(args.first);
  out.parent.createSync(recursive: true);
  writeFixtureCourseFile(out.path, overrideMeta: overrides);
  final repo = loadCourseRepoFile(out.path);
  stdout.writeln('Wrote ${out.path}: ${repo.meta.id} ${repo.version}, ${repo.counts}');
}
