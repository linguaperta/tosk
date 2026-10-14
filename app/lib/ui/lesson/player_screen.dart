import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/core.dart';
import '../../device/device_providers.dart';
import '../../device/onyx.dart';
import '../../feedback/answer_context.dart';
import '../../progression/nonstop.dart';
import '../../providers.dart';
import '../ai/ai_explanation_sheet.dart';
import '../common/async_view.dart';
import '../feedback/flag_sheet.dart';
import '../routes.dart';
import '../slots/progression_slots.dart';
import 'exercises/exercise_layout.dart';
import 'exercises/exercise_view.dart';
import 'intro/exercise_intro_view.dart';
import 'intro/exercise_intros.dart';
import 'answer_override.dart';
import 'assessment_result.dart';
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

  /// "I was right": the current wrong answer was counted as right. The
  /// exercise keeps its marks; the feedback panel shows [_bannerResult].
  bool _overridden = false;
  Result? _bannerResult;
  /// The current exercise was flagged (the Report action shows "Reported").
  bool _flagged = false;

  /// The first-time intro of the current exercise's type is showing (before
  /// the exercise; "Got it" marks the type as seen).
  bool _intro = false;

  /// Non-stop scoring (combo, multiplier, bonus rounds), fed one graded
  /// exercise at a time with the `at` the session recorded.
  NonStopRun _run = const NonStopRun();
  StreamSubscription<AnswerEvent>? _answers;

  /// Completed when the engine's result event for the last submit has been
  /// handled, so a bonus round is enqueued before the next exercise is drawn.
  Completer<void>? _answerHandled;
  final _watch = Stopwatch();
  final _keys = ExerciseKeys();

  /// The exercise's scroll view: each exercise starts at the top, and after
  /// Check the prompt is scrolled back into view ([ExerciseLayout.revealPrompt]).
  final _exerciseScroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'player');

  bool get _endless => widget.request.endless;

  /// E-ink (ONYX): a full refresh after the summary and when leaving the
  /// player, against ghosting (Settings → E-reader). Read up front: `ref`
  /// can't be used in [dispose].
  EinkScreen _eink = const NoEinkScreen();

  void _fullRefresh() {
    if (!_refreshOnLeave) return;
    final eink = _eink;
    // After the next screen has been drawn.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 350), eink.fullRefresh));
  }

  bool _refreshOnLeave = false;

  /// Kept for [dispose], where `ref` can no longer be used.
  late final ProgressRevision _revision;

  /// Progress was refreshed for this session's answers ([_bumpProgress]).
  bool _bumped = false;

  @override
  void initState() {
    super.initState();
    // Kept current (the device and settings may still be loading).
    ref.listenManual(einkScreenProvider, (_, v) => _eink = v, fireImmediately: true);
    ref.listenManual(fullRefreshAfterLessonsProvider, (_, v) => _refreshOnLeave = v, fireImmediately: true);
    _revision = ref.read(progressRevisionProvider.notifier);
    unawaited(_start());
  }

  /// Refreshes everything derived from progress (map, header, progress pages)
  /// after this session's answers: on finishing, quitting or stopping.
  void _bumpProgress() {
    _bumped = true;
    _revision.bump();
  }

  @override
  void dispose() {
    if (_refreshOnLeave) {
      final eink = _eink;
      unawaited(Future<void>.delayed(const Duration(milliseconds: 350), eink.fullRefresh));
    }
    // Left some other way (the route was replaced or removed) with answers
    // recorded: the map and progress pages must still see them.
    final s = _session;
    if (s != null && !_bumped && s.answered > 0) {
      s.stop();
      final revision = _revision;
      scheduleMicrotask(() {
        try {
          revision.bump();
        } catch (_) {
          // The provider scope is gone too (app closing): nothing to refresh.
        }
      });
    }
    unawaited(_answers?.cancel());
    _exerciseScroll.dispose();
    _keys.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final factory = await ref.read(sessionFactoryProvider.future);
      final settings = await ref.read(settingsProvider.future);
      final session = await widget.request.start(
        factory,
        defaultFocus: settings.defaultFocus,
        defaultLength: settings.defaultLength.exercises,
      );
      if (!mounted) {
        session.stop();
        return;
      }
      _session = session;
      ref.read(soundServiceProvider).warmUp();
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
    // A type met for the first time gets its intro first.
    var intro = false;
    if (next != null && ref.read(exerciseIntrosEnabledProvider)) {
      try {
        final seen = await ref.read(introSeenProvider.future);
        intro = !seen.contains(next.type);
      } catch (_) {
        intro = false;
      }
      if (!mounted) return;
    }
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
      _overridden = false;
      _bannerResult = null;
      _flagged = false;
      _intro = intro;
      _phase = PlayerPhase.playing;
    });
    _watch
      ..reset()
      ..start();
    // A new exercise starts at the top, not where the last one was scrolled.
    if (_exerciseScroll.hasClients) _exerciseScroll.jumpTo(0);
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
      final sound = ref.read(soundServiceProvider);
      if (r.correct) {
        fx.correct();
        sound.correct();
      } else {
        fx.wrong();
        sound.wrong();
      }
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
      // Once the feedback panel is laid out: the instruction back in view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ExerciseLayout.revealPrompt(_exerciseScroll, duration: ref.read(motionProvider).medium);
      });
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
    if (round != null && _run.lastSignals.contains(NonStopSignal.bonusRoundStarted)) {
      ref.read(soundServiceProvider).bonus();
    }
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

  /// "Got it" on a first-time intro: the type is seen, the exercise starts
  /// (its response time from now).
  void _dismissIntro() {
    final ex = _exercise;
    if (!_intro || ex == null) return;
    unawaited(ref.read(introSeenProvider.notifier).markSeen(ex.type));
    setState(() => _intro = false);
    _watch
      ..reset()
      ..start();
    _focus.requestFocus();
  }

  /// The intro example for [ex]'s type, from the course's own data.
  List<IntroLine> _introExample(Exercise ex) =>
      introExample(ex.type, ref.read(courseDataProvider).value, ref.read(sourceLangProvider), current: ex);

  /// The (?) button: the current type's explanation again.
  void _help() {
    final ex = _exercise;
    if (ex == null) return;
    unawaited(showExerciseIntroSheet(context, type: ex.type, example: _introExample(ex)));
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
    _bumpProgress();
    ref.read(fxProvider).finished();
    unawaited(_celebrate(summary.sessionId));
    setState(() {
      _summary = summary;
      _phase = PlayerPhase.summary;
    });
    _fullRefresh();
  }

  /// The end-of-session sound: the level-up fanfare when this session gained
  /// a level, else the lesson-complete arpeggio.
  Future<void> _celebrate(String sessionId) async {
    var levelUp = false;
    try {
      final p = await ref
          .read(sessionProgressSummaryProvider(sessionId).future)
          .timeout(const Duration(milliseconds: 800));
      levelUp = p?.leveledUp ?? false;
    } catch (_) {
      // No progression summary (yet): just the lesson sound.
    }
    if (!mounted) return;
    final sound = ref.read(soundServiceProvider);
    levelUp ? sound.levelUp() : sound.complete();
  }

  /// Select tick and haptic for taps on options, tiles, chips and cards.
  void _selectTick() {
    ref.read(soundServiceProvider).select();
    ref.read(fxProvider).tap();
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
      _bumpProgress();
      setState(() => _phase = PlayerPhase.summary); // lets PopScope pop
      _close();
    }
  }

  /// The checked answer's context (engine mistake context when there is one,
  /// so the cached explanation is shared with mistake review).
  ExplainContext _answerContext(Exercise ex, Result r) {
    final s = _session;
    return buildExplainContext(
      exercise: ex,
      result: r,
      sourceLang: ref.read(sourceLangProvider),
      course: ref.read(courseDataProvider).value,
      explainLang: ref.read(explainLangProvider),
      at: ref.read(clockProvider)().toUtc(),
      mistake: s is EngineSession ? s.mistakeContext(ex.id) : null,
    );
  }

  /// "Explain answer with AI" (right or wrong answers).
  void _explain() {
    final ex = _exercise, r = _result;
    if (ex == null || r == null) return;
    final ctx = _answerContext(ex, r);
    final explainer = ref.read(explainerProvider);
    unawaited(showAiExplanationSheet(context, request: () => explainer.explain(ctx), note: ctx.note));
  }

  /// "Report": the flag sheet for the checked exercise.
  Future<void> _flag() async {
    final ex = _exercise, r = _result;
    if (ex == null || r == null) return;
    final draft = FlagDraft(
      exercise: ex,
      result: r,
      context: _answerContext(ex, r),
      packVersion: ref.read(courseDataProvider).value?.meta.version,
    );
    final saved = await showFlagSheet(context, draft);
    if (saved == true && mounted && _exercise == ex) setState(() => _flagged = true);
  }

  /// "I was right" in the feedback panel: only for a wrong verdict the
  /// session can override (engine sessions), once.
  List<FeedbackAction> _overrideActions(Exercise ex, Result r) {
    final Object? s = _session;
    if (r.correct || _overridden || s is! OverridableSession || !s.canOverride(ex.id)) return const [];
    return [
      FeedbackAction(
        key: const ValueKey('override-button'),
        icon: Icons.thumb_up_alt_outlined,
        label: 'I was right',
        onPressed: () => unawaited(_override(ex, r)),
      ),
    ];
  }

  Future<void> _override(Exercise ex, Result r) async {
    final Object? s = _session;
    if (s is! OverridableSession || !await confirmOverride(context) || !mounted) return;
    if (_exercise != ex) return;
    final events = await s.overrideAnswer(ex.id);
    final course = ref.read(courseDataProvider).value;
    try {
      await ref.read(feedbackStoreProvider).saveFlag(
        overrideFlag(
          id: const Uuid().v4(),
          at: ref.read(clockProvider)(),
          courseId: course?.meta.id ?? '',
          exercise: ex,
          result: r,
          overrides: events,
          packVersion: course?.meta.version,
          sourceLang: ref.read(sourceLangProvider),
        ),
      );
      ref.read(flagsRevisionProvider.notifier).bump();
    } catch (e) {
      debugPrint('[override] flag not saved: $e');
    }
    if (!mounted || _exercise != ex) return;
    setState(() {
      _overridden = true;
      _bannerResult = overriddenResult(r);
    });
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
          if (_intro) {
            _dismissIntro();
          } else if (_result != null) {
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
    if (d != null && _phase == PlayerPhase.playing && _result == null && !_intro) {
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
              // How this exercise type works (its first-time intro, again).
              if (playing && _exercise != null && !_intro)
                IconButton(
                  key: const ValueKey('exercise-help'),
                  tooltip: 'How this exercise works',
                  icon: const Icon(Icons.help_outline),
                  onPressed: _help,
                ),
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
                Text(widget.request.emptyMessage, key: const ValueKey('player-empty'), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _close, child: const Text('Back')),
              ],
            ),
          ),
        );
      case PlayerPhase.summary:
        final summary = _summary;
        if (summary == null) return const SizedBox.shrink();
        final s = _session;
        final outcome = s is AssessmentSession ? s.outcome : null;
        return SessionSummaryView(
          summary: summary,
          endless: _endless,
          onDone: _close,
          header: outcome == null ? null : AssessmentResultCard(outcome: outcome, mode: summary.mode),
        );
      case PlayerPhase.playing:
        return _playing(context);
    }
  }

  Widget _playing(BuildContext context) {
    final ex = _exercise!;
    if (_intro) {
      return Column(
        children: [
          if (_endless) NonStopHudSlot(run: _run),
          Expanded(
            child: ExerciseIntroView(type: ex.type, example: _introExample(ex), onGotIt: _dismissIntro),
          ),
        ],
      );
    }
    final result = _result;
    final reduce = ref.watch(reduceMotionProvider);
    final aiAvailable = ref.watch(explainerAvailableProvider);
    return Column(
      children: [
        if (_endless) NonStopHudSlot(run: _run),
        Expanded(
          // The exercise fills at least the visible height, so its controls
          // (`ExerciseLayout`) sit at the bottom, in the thumb zone; the
          // column is centered and at most 640 px wide.
          child: LayoutBuilder(
            builder: (context, viewport) {
              // Self-submitting exercises (match pairs, flashcards) have no
              // Check row or banner below them, so their bottom-aligned
              // controls must clear the system navigation bar themselves
              // (Android 15+ draws edge-to-edge; the inset is per device).
              final bareBottom = result == null && selfSubmitting(ex.type);
              const top = 12.0;
              final bottom = 16.0 + (bareBottom ? MediaQuery.viewPaddingOf(context).bottom : 0);
              final side = math.max(16.0, (viewport.maxWidth - 640) / 2);
              return SingleChildScrollView(
                key: const ValueKey('exercise-scroll'),
                controller: _exerciseScroll,
                padding: EdgeInsets.fromLTRB(side, top, side, bottom),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: math.max(0, viewport.maxHeight - top - bottom)),
                  child: ExerciseView(
                    key: ValueKey('exercise-$_counter'),
                    exercise: ex,
                    result: result,
                    keys: _keys,
                    onChanged: (a) => setState(() => _draft = a),
                    onSubmit: (a) => unawaited(_submit(a)),
                    onCheck: _check,
                    onSelect: _selectTick,
                  ),
                ),
              );
            },
          ),
        ),
        if (result != null)
          FeedbackBanner(
            key: ValueKey('feedback-$_counter'),
            result: _bannerResult ?? result,
            reduceMotion: reduce,
            onContinue: _continue,
            extraActions: [
              // "I was right" after a wrong verdict (engine sessions).
              ..._overrideActions(ex, result),
              // Only exists when an AI provider and key are configured.
              if (aiAvailable)
                FeedbackAction(
                  key: const ValueKey('ai-explain-button'),
                  icon: Icons.auto_awesome_outlined,
                  label: 'Explain answer with AI',
                  onPressed: _explain,
                ),
              FeedbackAction(
                key: const ValueKey('flag-button'),
                icon: _flagged ? Icons.flag : Icons.outlined_flag,
                label: _flagged ? 'Reported' : 'Report',
                onPressed: _flagged ? null : () => unawaited(_flag()),
              ),
            ],
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
