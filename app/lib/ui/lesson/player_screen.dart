import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../progression/nonstop.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../routes.dart';
import '../slots/progression_slots.dart';
import 'exercises/exercise_view.dart';
import 'feedback_banner.dart';
import '../../data/progress/replay.dart' show toStoredTime;
import '../../engine/engine.dart';
import 'session_request.dart';
import 'session_summary_view.dart';

enum PlayerPhase { loading, playing, empty, summary, error }

/// Plays one practice session (lesson, lab, non-stop, fading) to its summary.
///
/// Desktop shortcuts: 1-9 pick options/tiles, Enter checks / continues (reveals a
/// flashcard), Esc leaves.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.request});
  final SessionRequest request;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  PlayerPhase _phase = PlayerPhase.loading;
  Object? _error;
  PracticeSession? _session;
  Exercise? _exercise;
  int _counter = 0;
  Answer? _draft;
  Result? _result;
  bool _busy = false;
  SessionSummary? _summary;

  /// Non-stop scoring (combo, multiplier, bonus rounds), fed one graded
  /// exercise at a time with the `at` the session recorded.
  NonStopRun _run = const NonStopRun();
  StreamSubscription<AnswerEvent>? _answers;

  /// Completed when the engine's result event for the last submit has been
  /// handled, so a bonus round is enqueued before the next exercise is drawn.
  Completer<void>? _answerHandled;
  final _watch = Stopwatch();
  final _keys = ExerciseKeys();
  final _focus = FocusNode(debugLabel: 'player');

  bool get _endless => widget.request.endless;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_answers?.cancel());
    _keys.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final factory = await ref.read(sessionFactoryProvider.future);
      final settings = await ref.read(settingsProvider.future);
      final session = await widget.request.start(factory, defaultFocus: settings.defaultFocus);
      if (!mounted) {
        session.stop();
        return;
      }
      _session = session;
      // The engine reports every graded answer with the events it recorded;
      // non-stop scoring is fed from there (same `at` as the review log).
      if (_endless && session is EngineSession) _answers = session.results.listen(_onAnswer);
      await _advance(first: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = PlayerPhase.error;
          _error = e;
        });
      }
    }
  }

  Future<void> _advance({bool first = false}) async {
    final s = _session;
    if (s == null) return;
    final pending = _answerHandled;
    if (pending != null) {
      // Bounded: the engine emits one event per new answer; never hang on it.
      await pending.future.timeout(const Duration(seconds: 2), onTimeout: () {});
      _answerHandled = null;
    }
    final next = await s.next();
    if (!mounted) return;
    if (next == null) {
      if (first) {
        setState(() => _phase = PlayerPhase.empty);
      } else {
        _finish();
      }
      return;
    }
    setState(() {
      _exercise = next;
      _counter++;
      _draft = null;
      _result = null;
      _phase = PlayerPhase.playing;
    });
    _watch
      ..reset()
      ..start();
    _focus.requestFocus();
  }

  Future<void> _submit(Answer answer) async {
    final s = _session, ex = _exercise;
    if (_busy || _result != null || s == null || ex == null) return;
    _busy = true;
    _watch.stop();
    try {
      if (_answers != null) _answerHandled = Completer<void>();
      final r = await s.submit(ex, answer, elapsed: _watch.elapsed);
      if (!mounted) return;
      final fx = ref.read(fxProvider);
      r.correct ? fx.correct() : fx.wrong();
      // Sessions without a result stream (test fakes) feed the run here.
      if (_endless && s is! EngineSession) _feedRun(ex, r, ref.read(clockProvider)().toUtc());
      if (ex is FlashcardExercise) {
        // Self-graded: the back was already shown, go straight on.
        _busy = false;
        await _advance();
        return;
      }
      setState(() => _result = r);
      _focus.requestFocus();
    } finally {
      _busy = false;
    }
  }

  /// One engine answer. [_advance] waits for it ([_answerHandled]), so a bonus
  /// round is enqueued before the next exercise is drawn.
  void _onAnswer(AnswerEvent e) {
    final done = _answerHandled;
    if (done != null && !done.isCompleted) done.complete();
    if (!mounted) return;
    // The stored `at` (UTC, whole ms): the replayed best run then equals the
    // live score. A re-ask after a mistake records nothing; use the clock.
    final at = e.events.isEmpty ? ref.read(clockProvider)().toUtc() : toStoredTime(e.events.first.at);
    _feedRun(e.exercise, e.result, at);
  }

  void _feedRun(Exercise ex, Result r, DateTime at) {
    _run = _run.applyResult(ex, r, at: at);
    final s = _session;
    final round = _run.bonusRound;
    if (round != null && _run.lastSignals.contains(NonStopSignal.bonusRoundStarted) && s is NonStopSession) {
      final types = {
        for (final id in _run.preferredTypes)
          for (final t in ExerciseType.values)
            if (t.id == id) t,
      };
      if (types.isNotEmpty) s.enqueueBonus(types: types, count: round.targetAnswers);
    }
    if (mounted) setState(() {});
  }

  void _check() {
    final d = _draft;
    if (d != null) unawaited(_submit(d));
  }

  void _continue() {
    if (_result != null && !_busy) unawaited(_advance());
  }

  void _finish() {
    final s = _session;
    if (s == null) return;
    final summary = s.summary();
    ref.read(progressRevisionProvider.notifier).bump();
    ref.read(fxProvider).finished();
    setState(() {
      _summary = summary;
      _phase = PlayerPhase.summary;
    });
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.map);
    }
  }

  /// Leave button, Esc and system back.
  Future<void> _requestExit() async {
    if (_phase != PlayerPhase.playing) {
      _close();
      return;
    }
    if (_endless) {
      _session?.stop();
      _finish();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quit this session?'),
        content: const Text('Your answers so far are saved.'),
        actions: [
          TextButton(
            key: const ValueKey('exit-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            key: const ValueKey('exit-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quit'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _session?.stop();
      ref.read(progressRevisionProvider.notifier).bump();
      setState(() => _phase = PlayerPhase.summary); // lets PopScope pop
      _close();
    }
  }

  void _why() {
    final ex = _exercise, r = _result;
    if (ex == null || r == null) return;
    final s = _session;
    // The engine keeps the context of every wrong answer; other sessions get one built here.
    final ctx = (s is EngineSession ? s.mistakeContext(ex.id) : null) ?? _fallbackContext(ex, r);
    final stream = ref.read(explainerProvider).explain(ctx);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _WhySheet(stream: stream),
    );
  }

  MistakeContext _fallbackContext(Exercise ex, Result r) {
    final course = ref.read(courseDataProvider).value;
    final lang = ref.read(sourceLangProvider);
    return MistakeContext(
      courseId: course?.meta.id ?? '',
      facetId: ex.facetId,
      exerciseType: ex.type,
      prompt: exercisePrompt(ex),
      expected: r.expected,
      given: r.given,
      sourceLang: lang,
      targetLang: course?.meta.target ?? '',
      skillId: ex.skillId,
      note: ex.skillId == null ? null : course?.note(ex.skillId!, lang),
      at: ref.read(clockProvider)().toUtc(),
    );
  }

  bool _editingText() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static final _digits = {
    for (var i = 1; i <= 9; i++) ...{
      LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i): i,
      LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + i): i,
    },
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _editingText()) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      unawaited(_requestExit());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      switch (_phase) {
        case PlayerPhase.summary || PlayerPhase.empty:
          _close();
        case PlayerPhase.playing:
          if (_result != null) {
            _continue();
          } else if (_draft != null) {
            _check();
          } else {
            _keys.primary();
          }
        default:
          break;
      }
      return KeyEventResult.handled;
    }
    final d = _digits[key];
    if (d != null && _phase == PlayerPhase.playing && _result == null) {
      _keys.digit(d);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final playing = _phase == PlayerPhase.playing;
    return PopScope(
      canPop: !playing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestExit());
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              key: const ValueKey('player-close'),
              tooltip: _endless && playing ? 'Stop' : 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => unawaited(_requestExit()),
            ),
            title: _title(context),
            actions: [
              if (_endless && playing)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    key: const ValueKey('nonstop-stop'),
                    onPressed: () => unawaited(_requestExit()),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop'),
                  ),
                ),
            ],
          ),
          body: _body(context),
        ),
      ),
    );
  }

  Widget _title(BuildContext context) {
    if (_phase == PlayerPhase.summary) return Text(widget.request.title);
    final s = _session;
    if (_endless) {
      return Text(
        s == null ? widget.request.title : '${s.answered} answered · ${s.correctCount} correct',
        key: const ValueKey('nonstop-count'),
        overflow: TextOverflow.ellipsis,
      );
    }
    final planned = s?.plannedLength ?? 0;
    final value = planned == 0 ? 0.0 : (s!.answered / planned).clamp(0.0, 1.0);
    final motion = ref.watch(motionProvider);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: motion.long,
      curve: motion.curve,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(key: const ValueKey('lesson-progress'), value: v, minHeight: 12),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_phase) {
      case PlayerPhase.loading:
        return const Center(child: CircularProgressIndicator());
      case PlayerPhase.error:
        return ErrorPanel(
          error: _error ?? 'Unknown error',
          onRetry: () {
            setState(() => _phase = PlayerPhase.loading);
            unawaited(_start());
          },
        );
      case PlayerPhase.empty:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.inbox_outlined, size: 48),
                const SizedBox(height: 12),
                const Text('Nothing to practice here right now.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _close, child: const Text('Back')),
              ],
            ),
          ),
        );
      case PlayerPhase.summary:
        final summary = _summary;
        if (summary == null) return const SizedBox.shrink();
        return SessionSummaryView(summary: summary, endless: _endless, onDone: _close);
      case PlayerPhase.playing:
        return _playing(context);
    }
  }

  Widget _playing(BuildContext context) {
    final ex = _exercise!;
    final result = _result;
    final reduce = ref.watch(reduceMotionProvider);
    final whyAvailable = ref.watch(explainerAvailableProvider);
    return Column(
      children: [
        if (_endless) NonStopHudSlot(run: _run),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ExerciseView(
                  key: ValueKey('exercise-$_counter'),
                  exercise: ex,
                  result: result,
                  keys: _keys,
                  onChanged: (a) => setState(() => _draft = a),
                  onSubmit: (a) => unawaited(_submit(a)),
                  onCheck: _check,
                ),
              ),
            ),
          ),
        ),
        if (result != null)
          FeedbackBanner(
            key: ValueKey('feedback-$_counter'),
            result: result,
            reduceMotion: reduce,
            onContinue: _continue,
            onWhy: whyAvailable && !result.correct ? _why : null,
          )
        else if (!selfSubmitting(ex.type))
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('check-button'),
                      onPressed: _draft == null ? null : _check,
                      child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Check')),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WhySheet extends StatelessWidget {
  const _WhySheet({required this.stream});
  final Stream<String> stream;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: StreamBuilder<String>(
          stream: stream.transform(_accumulate()),
          builder: (context, snap) {
            if (snap.hasError) return Text('Could not get an explanation: ${snap.error}');
            final text = snap.data ?? '';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Why?', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (text.isEmpty && snap.connectionState != ConnectionState.done)
                  const LinearProgressIndicator()
                else
                  Text(text),
              ],
            );
          },
        ),
      ),
    );
  }

  static StreamTransformer<String, String> _accumulate() {
    var acc = '';
    return StreamTransformer.fromHandlers(
      handleData: (chunk, sink) {
        acc += chunk;
        sink.add(acc);
      },
    );
  }
}
