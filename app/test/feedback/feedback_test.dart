// Exercise snapshots, the flags JSON Lines export, the drift and in-memory
// feedback stores, and the flag reviewer.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:tosk/ai/ai_config.dart';
import 'package:tosk/ai/flag_reviewer.dart';
import 'package:tosk/ai/llm_explainer.dart';
import 'package:tosk/app_version.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/feedback_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/feedback/answer_context.dart';
import 'package:tosk/feedback/exercise_snapshot.dart';
import 'package:tosk/feedback/flags_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../ai/ai_fixtures.dart';
import '../fixtures/course_fixture.dart';
import 'feedback_fixtures.dart';

void main() {
  group('exercise snapshot', () {
    for (final e in everyExercise) {
      test('${e.type.id} round-trips through JSON', () {
        final json = exerciseToJson(e);
        expect(json['type'], e.type.id);
        expect(json['facet_ids'], e.facetIds);
        final decoded = (jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>();
        final back = exerciseFromJson(decoded);
        expect(back.runtimeType, e.runtimeType);
        expect(exerciseToJson(back), json);
      });
    }

    test('transform: the change and its from/to labels round-trip', () {
      const e = TransformExercise(
        id: 'x10',
        facetId: 'it:mangiare#form:passato_prossimo',
        instruction: 'Change the tense',
        source: 'Mangio.',
        targetDescription: '→ present perfect',
        tiles: ['Ho', 'mangiato'],
        answers: [
          ['Ho', 'mangiato'],
        ],
        change: TransformChange.tense,
        fromLabel: 'present',
        toLabel: 'present perfect',
      );
      final back = exerciseFromJson((jsonDecode(jsonEncode(exerciseToJson(e))) as Map).cast<String, Object?>())
          as TransformExercise;
      expect((back.change, back.fromLabel, back.toLabel), (TransformChange.tense, 'present', 'present perfect'));
    });

    test('unknown type and missing fields are format errors', () {
      expect(() => exerciseFromJson({'type': 'nope', 'id': 'a', 'facet_id': 'b'}), throwsFormatException);
      expect(() => exerciseFromJson({'type': 'cloze', 'id': 'a', 'facet_id': 'b'}), throwsFormatException);
    });
  });

  group('answer context', () {
    test('built from an exercise, its result and the course', () {
      final course = fixtureCourse();
      final skill = course.skills.firstWhere((s) => course.note(s.id, 'en') != null);
      final ex = ClozeExercise(
        id: 'c1',
        facetId: 'it:mangiare#form:presente',
        skillId: skill.id,
        instruction: 'Fill the gap',
        before: 'Noi ',
        after: '.',
        expected: 'mangiamo',
        accepted: const ['mangiamo', 'mangiam'],
        options: const ['mangiamo', 'mangiate'],
        correctIndex: 0,
        sentenceId: 's:1',
      );
      const result = Result(correct: true, expected: 'mangiamo', given: 'mangiamo', outcomes: []);
      final ctx = buildExplainContext(exercise: ex, result: result, sourceLang: 'en', course: course, explainLang: 'nl');
      expect(ctx.correct, isTrue);
      expect(ctx.courseId, course.meta.id);
      expect(ctx.targetLang, course.meta.target);
      expect(ctx.note, course.note(skill.id, 'en'));
      expect(ctx.options, ['mangiamo', 'mangiate']);
      expect(ctx.accepted, ['mangiam']);
      expect(ctx.sentenceId, 's:1');
      expect(ctx.instruction, 'Fill the gap');
      expect(ctx.replyLang, 'nl');
      expect(ctx.prompt, startsWith('Fill the gap: Noi ___.'));
    });
  });

  group('flags export', () {
    test('file name', () {
      expect(flagsFileName(DateTime(2026, 3, 7, 23)), 'tosk-flags-20260307.jsonl');
    });

    test('JSON Lines: one versioned object per flag, oldest first, all fields', () {
      final older = sampleFlag(id: 'a', at: DateTime.utc(2026, 1, 1), verdict: FlagVerdict.exerciseCorrect);
      final newer = sampleFlag(id: 'b', at: DateTime.utc(2026, 2, 1));
      final text = encodeFlagsJsonl([newer, older]);
      final lines = const LineSplitter().convert(text);
      expect(lines, hasLength(2));
      expect(text.endsWith('\n'), isTrue);
      final first = jsonDecode(lines.first) as Map<String, Object?>;
      expect(first['id'], 'a');
      expect(first.keys, [
        'format',
        'id',
        'created_at',
        'course_id',
        'skill_id',
        'facet_id',
        'exercise_type',
        'sentence_id',
        'exercise',
        'given',
        'expected',
        'correct',
        'reasons',
        'comment',
        'ai_verdict',
        'ai_reasoning',
        'app_version',
        'pack_version',
        'source_lang',
      ]);
      expect(first['format'], kFlagFormat);
      expect(first['created_at'], '2026-01-01T00:00:00.000Z');
      expect(first['sentence_id'], 's:456');
      expect(first['reasons'], ['multiple_answers', 'other']);
      expect(first['ai_verdict'], 'exercise_correct');
      expect((first['exercise'] as Map)['type'], 'cloze');

      final back = decodeFlagsJsonl(text);
      expect(back.map((f) => f.id), ['a', 'b']);
      expect(back.first.aiVerdict, FlagVerdict.exerciseCorrect);
      expect(exerciseFromJson(back.first.exercise), isA<ClozeExercise>());
    });

    test('the pipeline fixture is what the app writes (contract with `pipeline flags summarize`)', () {
      // Regenerate with: UPDATE_FLAG_FIXTURE=1 flutter test test/feedback/feedback_test.dart
      final text = encodeFlagsJsonl([
        for (final (i, e) in everyExercise.indexed)
          sampleFlag(
            id: 'flag-$i-${e.type.id}',
            at: DateTime.utc(2026, 10, 14, 9, i),
            exercise: e,
            courseId: i.isEven ? 'it' : 'nl',
            verdict: FlagVerdict.values[i % FlagVerdict.values.length],
          ),
      ]);
      final file = File('../pipeline/tests/fixtures/flags/sample.jsonl');
      if (Platform.environment.containsKey('UPDATE_FLAG_FIXTURE')) {
        file
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
      }
      expect(file.readAsStringSync().replaceAll('\r\n', '\n'), text);
    });

    test('exportFlags hands the bytes and the dated name to the save function', () async {
      String? name;
      Uint8List? bytes;
      final uri = await exportFlags(
        [sampleFlag()],
        now: DateTime(2026, 10, 14),
        save: (n, b) async {
          name = n;
          bytes = b;
          return Uri.file('/tmp/$n');
        },
      );
      expect(name, 'tosk-flags-20261014.jsonl');
      expect(utf8.decode(bytes!), encodeFlagsJsonl([sampleFlag()]));
      expect(uri?.pathSegments.last, name);
    });
  });

  for (final (name, FeedbackStore Function() make) in [
    (
      'drift',
      () {
        final db = ProgressDb(NativeDatabase.memory());
        addTearDown(db.close);
        return DriftFeedbackStore(db);
      },
    ),
    ('in memory', InMemoryFeedbackStore.new),
  ]) {
    group('$name feedback store', () {
      test('explanations: insert, replace, keyed by fingerprint + given + language', () async {
        final s = make();
        final e = CachedExplanation(
          fingerprint: 'fp',
          given: 'x',
          lang: 'en',
          text: 'one',
          createdAt: DateTime.utc(2026, 10, 14, 1, 2, 3, 4),
          facetId: 'it:a#rec',
          provider: 'anthropic',
          model: 'claude-haiku-5-5',
        );
        await s.saveExplanation(e);
        final got = await s.explanation('fp', 'x', 'en');
        expect(got?.text, 'one');
        expect(got?.createdAt, e.createdAt);
        expect(got?.model, 'claude-haiku-5-5');
        expect(await s.explanation('fp', 'y', 'en'), isNull);
        expect(await s.explanation('fp', 'x', 'nl'), isNull);
        await s.saveExplanation(
          CachedExplanation(fingerprint: 'fp', given: 'x', lang: 'en', text: 'two', createdAt: e.createdAt),
        );
        expect((await s.explanation('fp', 'x', 'en'))?.text, 'two');
      });

      test('flags: save, list newest first (by course), delete', () async {
        final s = make();
        final a = sampleFlag(id: 'a', at: DateTime.utc(2026, 1, 1), verdict: FlagVerdict.ambiguous);
        final b = sampleFlag(id: 'b', at: DateTime.utc(2026, 2, 1), courseId: 'nl');
        await s.saveFlag(a);
        await s.saveFlag(b);
        final all = await s.flags();
        expect(all.map((f) => f.id), ['b', 'a']);
        final back = all.last;
        expect(back.reasons, a.reasons);
        expect(back.exercise, a.exercise);
        expect(back.aiVerdict, FlagVerdict.ambiguous);
        expect(back.aiReasoning, a.aiReasoning);
        expect(back.packVersion, '1.2.0');
        expect(back.appVersion, '0.2.0+2');
        expect(back.createdAt, a.createdAt);
        expect((await s.flags(courseId: 'nl')).map((f) => f.id), ['b']);
        await s.deleteFlag('b');
        expect((await s.flags()).map((f) => f.id), ['a']);
      });
    });
  }

  test('FlagReviewer asks the model and parses its verdict', () async {
    late String userMessage;
    final client = MockClient((req) async {
      userMessage = ((jsonDecode(req.body) as Map)['messages'] as List).first['content'] as String;
      return http.Response(anthropicStream(['VERDICT: ambiguous\n', 'Both *mangiamo* and ', '*mangiate* fit.']), 200);
    });
    final llm = ClaudeExplainer(config: const AiConfig(provider: AiProvider.anthropic, apiKey: fakeKey), client: client);
    final v = await FlagReviewer(llm).review(
      context: wrongCtx,
      reasons: const [FlagReason.multipleAnswers],
      comment: 'both?',
      snapshot: exerciseToJson(everyExercise[3]),
    );
    expect(v.verdict, FlagVerdict.ambiguous);
    expect(v.reasoning, 'Both *mangiamo* and *mangiate* fit.');
    expect(userMessage, contains('both?'));
  });

  test('kAppVersion matches pubspec.yaml', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(kAppVersion, version);
  });
}
