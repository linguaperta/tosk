/// "Check the words you already know" (docs/ui.md, "Placement"): after the
/// placement test, a quick flashcard-style pass over the words of the units
/// whose grammar was credited. Reveal and self-grade ("Knew it" / "Didn't
/// know"), or type the word in typing mode. A few words per skill first;
/// when those went well, "Mark the other N as known". Any unit can be left
/// as new. The engine's [WordCheckRun] keeps the state; the player credits
/// [WordCheckRun.known] when it is done ([PlacementControl.confirmWords]).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../engine/engine.dart' show matchAnswer;
import '../../providers.dart';
import '../brand/tosk.dart';
import '../lesson/typing.dart' show AccentLetters, TypedAnswerField, accentLettersProvider;
import '../settings/learner_settings.dart' show typingModeProvider;
import '../theme/bw_skin.dart';
import '../theme/tosk_palette.dart';
import 'placement_ui.dart' show placementUnitLabel, unitRanges;

class WordCheckView extends ConsumerStatefulWidget {
  const WordCheckView({super.key, required this.run, required this.onDone});

  /// The check's state (owned by the player, which credits its [WordCheckRun.known]).
  final WordCheckRun run;

  /// Called once the run is done (every unit through, or skipped).
  final VoidCallback onDone;

  @override
  ConsumerState<WordCheckView> createState() => _WordCheckViewState();
}

class _WordCheckViewState extends ConsumerState<WordCheckView> {
  bool _intro = true;
  bool _revealed = false;

  /// Typing mode: the typed answer was checked (null: not yet).
  bool? _typedRight;
  String _typed = '';

  /// Takes the keys (Enter, 1, 2) from the player, which held the focus.
  final _focus = FocusNode(debugLabel: 'word-check');
  bool _doneCalled = false;

  WordCheckRun get _run => widget.run;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    setState(() {
      change();
      _revealed = false;
      _typedRight = null;
      _typed = '';
    });
    _checkDone();
    // Keys to this screen (a typed word's new field takes the focus itself).
    if (!ref.read(typingModeProvider) || _run.step != WordCheckStep.word) _focus.requestFocus();
  }

  void _checkDone() {
    if (_run.isDone && !_doneCalled) {
      _doneCalled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
    }
  }

  void _start() => setState(() => _intro = false);

  void _skipAll() => _update(_run.stop);

  void _answer(bool knew) => _update(() => _run.answer(knew));

  void _checkTyped(bool typed) {
    final w = _run.word;
    if (w == null || _typedRight != null) return;
    final text = _typed.trim();
    if (text.isEmpty) return;
    final accents = ref.read(sessionOptionsProvider).accents;
    final right = matchAnswer(text, w.accepted.isEmpty ? [w.answer] : w.accepted, accents).correct;
    setState(() => _typedRight = right);
    // The field is locked now: Enter continues.
    _focus.requestFocus();
  }

  /// Enter: the screen's main action.
  void _primary(bool typed) {
    if (_intro) return _start();
    switch (_run.step) {
      case WordCheckStep.offer:
        _update(_run.markRest);
      case WordCheckStep.word:
        if (typed) {
          if (_typedRight == null) {
            _checkTyped(typed);
          } else {
            _answer(_typedRight!);
          }
        } else if (!_revealed) {
          setState(() => _revealed = true);
        }
      case WordCheckStep.done:
        break;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, bool typed) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _primary(typed);
      return KeyEventResult.handled;
    }
    // Reveal-and-self-grade: 1 knew it, 2 didn't.
    if (!_intro && !typed && _revealed && _run.step == WordCheckStep.word) {
      if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
        _answer(true);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
        _answer(false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final typed = ref.watch(typingModeProvider);
    if (course == null || _run.isDone) {
      _checkDone();
      return const Center(child: CircularProgressIndicator());
    }
    final language = pickLang(course.meta.title, 'en');
    final Widget body;
    final List<Widget> actions;
    if (_intro) {
      (body, actions) = _introScreen(context, course);
    } else if (_run.step == WordCheckStep.offer) {
      (body, actions) = _offerScreen(context, course, lang);
    } else {
      (body, actions) = _wordScreen(context, course, lang, language, typed);
    }
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) => _onKey(node, event, typed),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: body),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    key: const ValueKey('word-check-actions'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: actions,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static final ButtonStyle _big = FilledButton.styleFrom(minimumSize: const Size.fromHeight(48));
  static final ButtonStyle _bigOutlined = OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48));
  static final ButtonStyle _bigText = TextButton.styleFrom(minimumSize: const Size.fromHeight(48));

  (Widget, List<Widget>) _introScreen(BuildContext context, CourseData course) {
    final theme = Theme.of(context);
    final plan = _run.plan;
    final units = unitRanges(course, [for (final u in plan.units) u.unitId]);
    final n = plan.wordCount;
    return (
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ToskImage(pose: ToskPose.pointing, height: 88),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              'Check the words you already know',
              key: const ValueKey('word-check-title'),
              style: theme.textTheme.serifTitle,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your grammar is placed. Now a quick look at the words of $units ($n word${n == 1 ? '' : 's'}): '
            'for each one, say whether you know it. A few per skill first; if you know those, you can '
            'mark the rest of the skill as known.',
            key: const ValueKey('word-check-explain'),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            "Words you don't know, or skip, will be introduced as new.",
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      [
        FilledButton.icon(
          key: const ValueKey('word-check-start'),
          style: _big,
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Check my words'),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: const ValueKey('word-check-skip-all'),
          style: _bigText,
          onPressed: _skipAll,
          child: const Text('Skip: learn all these words as new'),
        ),
      ],
    );
  }

  /// "Unit 3: Home · Food"
  String _where(CourseData course, String lang) {
    final unit = _run.unit!;
    final skill = course.skill(_run.skill!.skillId);
    final unitLabel = placementUnitLabel(course, unit.unitId, lang);
    return skill == null ? unitLabel : '$unitLabel · ${pickLang(skill.title, lang)}';
  }

  String _skillTitle(CourseData course, String lang) {
    final skill = course.skill(_run.skill!.skillId);
    return skill == null ? 'this skill' : pickLang(skill.title, lang);
  }

  Widget _skipUnitButton(BuildContext context, CourseData course, String lang) {
    final unit = placementUnitLabel(course, _run.unit!.unitId, lang);
    return Semantics(
      label: "Skip the rest of $unit: I'll learn these words as new",
      excludeSemantics: true,
      button: true,
      child: TextButton.icon(
        key: const ValueKey('word-check-skip-unit'),
        style: _bigText,
        onPressed: () => _update(_run.skipUnit),
        icon: const Icon(Icons.skip_next),
        label: const Text("I'll learn these as new"),
      ),
    );
  }

  (Widget, List<Widget>) _offerScreen(BuildContext context, CourseData course, String lang) {
    final theme = Theme.of(context);
    final skill = _skillTitle(course, lang);
    final rest = _run.restCount;
    return (
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(text: _where(course, lang), progress: null),
          const SizedBox(height: 12),
          _Panel(
            key: const ValueKey('word-check-offer'),
            children: [
              Row(
                children: [
                  Icon(Icons.task_alt, color: isBw(context) ? kBwBlack : null),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You knew ${_run.sampleKnown} of ${_run.roundSize} words of $skill.',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Mark the other $rest word${rest == 1 ? '' : 's'} of $skill as known? They come back tomorrow '
                'for a quick check.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
      [
        FilledButton.icon(
          key: const ValueKey('word-check-mark-rest'),
          style: _big,
          onPressed: () => _update(_run.markRest),
          icon: const Icon(Icons.done_all),
          label: Text('Mark $rest word${rest == 1 ? '' : 's'} as known'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('word-check-check-all'),
          style: _bigOutlined,
          onPressed: () => _update(_run.checkRest),
          child: const Text('Check them one by one'),
        ),
        _skipUnitButton(context, course, lang),
      ],
    );
  }

  (Widget, List<Widget>) _wordScreen(BuildContext context, CourseData course, String lang, String language, bool typed) {
    final theme = Theme.of(context);
    final mono = isBw(context);
    final w = _run.word!;
    final progress = _run.checkingAll
        ? 'Every word of ${_skillTitle(course, lang)}: ${_run.position} of ${_run.roundSize}'
        : 'Word ${_run.position} of ${_run.roundSize}';
    final showAnswer = typed ? _typedRight != null : _revealed;
    final right = _typedRight;
    final card = _Panel(
      key: const ValueKey('word-check-card'),
      children: [
        Text('How do you say this in $language?', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
          w.prompt,
          key: const ValueKey('word-check-prompt'),
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (typed) ...[
          const SizedBox(height: 16),
          AccentLetters(
            letters: ref.watch(accentLettersProvider),
            // A fresh field per word.
            child: TypedAnswerField(
              key: ValueKey('word-check-field-${w.itemId}'),
              fieldKey: const ValueKey('word-check-input'),
              enabled: _typedRight == null,
              autofocus: true,
              hintText: 'Type the word',
              onChanged: (t) => setState(() => _typed = t),
              onSubmitted: () => _primary(true),
            ),
          ),
        ],
        if (showAnswer) ...[
          const SizedBox(height: 16),
          if (right != null)
            Row(
              key: const ValueKey('word-check-verdict'),
              children: [
                Icon(right ? Icons.check_circle_outline : Icons.cancel_outlined, color: mono ? kBwBlack : null),
                const SizedBox(width: 8),
                Text(right ? 'Right' : 'Not quite', style: theme.textTheme.titleMedium),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            w.answer,
            key: const ValueKey('word-check-answer'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ],
    );
    final List<Widget> actions;
    if (typed && _typedRight == null) {
      actions = [
        FilledButton(
          key: const ValueKey('word-check-check'),
          style: _big,
          onPressed: _typed.trim().isEmpty ? null : () => _checkTyped(true),
          child: const Text('Check'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('word-check-dont-know'),
          style: _bigOutlined,
          onPressed: () => _answer(false),
          child: const Text("I don't know"),
        ),
      ];
    } else if (typed) {
      actions = [
        FilledButton(
          key: const ValueKey('word-check-next'),
          style: _big,
          onPressed: () => _answer(_typedRight!),
          child: const Text('Continue'),
        ),
      ];
    } else if (!_revealed) {
      actions = [
        FilledButton.icon(
          key: const ValueKey('word-check-reveal'),
          style: _big,
          onPressed: () => setState(() => _revealed = true),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Show the word'),
        ),
      ];
    } else {
      actions = [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('word-check-didnt'),
                style: _bigOutlined,
                onPressed: () => _answer(false),
                icon: const Icon(Icons.close),
                label: const Text("Didn't know", textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('word-check-knew'),
                style: _big,
                onPressed: () => _answer(true),
                icon: const Icon(Icons.check),
                label: const Text('Knew it', textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ];
    }
    return (
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(text: _where(course, lang), progress: progress),
          const SizedBox(height: 12),
          card,
        ],
      ),
      [...actions, _skipUnitButton(context, course, lang)],
    );
  }
}

/// Where the check is: the unit and skill, and the word's number.
class _Header extends StatelessWidget {
  const _Header({required this.text, required this.progress});
  final String text;
  final String? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, key: const ValueKey('word-check-where'), style: theme.textTheme.titleSmall),
        if (progress != null)
          Text(progress!, key: const ValueKey('word-check-progress'), style: theme.textTheme.labelMedium),
      ],
    );
  }
}

/// A card: the surface tone in colour, a white card with a 2 px black frame in black & white.
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mono = isBw(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mono ? kBwWhite : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: mono ? Border.all(color: kBwBlack, width: 2) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}
