import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../../../speech/speaker.dart';
import '../../common/word_popover.dart';
import '../../theme/bw_skin.dart';
import 'common.dart';

/// Listen and pick (v0.5): a big play button (and a slow replay) speaks the
/// sentence or word with on-device text-to-speech; the options sit at the
/// bottom. It plays once by itself when shown. The spoken text is never
/// shown before checking; afterwards the translation appears under the
/// buttons and the right option's words are tappable for their gloss.
class ListenPickView extends ExerciseWidget<ListenPickExercise> {
  const ListenPickView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.result,
    super.keys,
    super.reduceMotion,
    required this.speaker,
    this.autoplay = true,
  });

  final Speaker speaker;

  /// Speak once when the exercise appears.
  final bool autoplay;

  @override
  State<ListenPickView> createState() => _ListenPickViewState();
}

class _ListenPickViewState extends State<ListenPickView> with ExerciseKeysMixin<ListenPickView> {
  int? _selected;

  /// Which button is playing (normal or slow), for its label.
  bool? _playingSlow;
  int _plays = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _plays == 0) unawaited(_play());
      });
    }
  }

  @override
  void dispose() {
    if (_playingSlow != null) unawaited(widget.speaker.stop());
    super.dispose();
  }

  Future<void> _play({bool slow = false}) async {
    final e = widget.exercise;
    setState(() {
      _playingSlow = slow;
      _plays++;
    });
    try {
      await widget.speaker.speak(e.text, e.languageCode, slow: slow);
    } finally {
      if (mounted) setState(() => _playingSlow = null);
    }
  }

  void _select(int i) {
    if (widget.locked) return;
    setState(() => _selected = i);
    widget.onChanged(ChoiceAnswer(i));
  }

  @override
  void onDigit(int n) {
    if (n >= 1 && n <= widget.exercise.options.length) _select(n - 1);
  }

  /// Enter without a choice: play again.
  @override
  void onPrimary() => unawaited(_play());

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = isMonochrome(scheme);
    final tokens = e.tokens;
    final tappableAnswer =
        widget.locked && e.isSentence && tokens != null && renderTokenRefs(tokens) == e.options[e.correctIndex];
    final playing = _playingSlow != null;
    return ExerciseLayout(
      prompt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InstructionText(e.instruction),
          const SizedBox(height: 12),
          Center(
            child: Semantics(
              button: true,
              label: playing && _playingSlow == false ? 'Playing' : 'Play the audio',
              excludeSemantics: true,
              child: SizedBox(
                width: 112,
                height: 112,
                child: FilledButton(
                  key: const ValueKey('listen-play'),
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    // Black & white: a solid black disc, white icon.
                    backgroundColor: mono ? kBwBlack : null,
                    foregroundColor: mono ? kBwWhite : null,
                  ),
                  onPressed: () => unawaited(_play()),
                  child: Icon(playing && _playingSlow == false ? Icons.graphic_eq : Icons.volume_up, size: 52),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              key: const ValueKey('listen-slow'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => unawaited(_play(slow: true)),
              icon: Icon(_playingSlow == true ? Icons.graphic_eq : Icons.slow_motion_video),
              label: const Text('Slower'),
            ),
          ),
          if (widget.locked && e.translation != null) ...[
            const SizedBox(height: 16),
            SubtleText(e.translation!, key: const ValueKey('listen-translation'), italic: true, icon: Icons.translate),
          ],
        ],
      ),
      controls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A list, as multiple choice: tiles keep their own height.
          ChoiceGrid(
            maxColumns: 1,
            uniformHeight: false,
            large: true,
            options: [
              for (var i = 0; i < e.options.length; i++)
                ChoiceOption(
                  key: ValueKey('option-$i'),
                  number: i + 1,
                  label: e.options[i],
                  labelWidget: tappableAnswer && i == e.correctIndex
                      ? TappableSentence(
                          key: const ValueKey('listen-answer-sentence'),
                          tokens: tokens,
                          style: optionLook(context, OptionState.correct, base: theme.textTheme.titleMedium).style,
                        )
                      : null,
                  state: choiceState(
                    index: i,
                    selected: _selected,
                    correctIndex: e.correctIndex,
                    result: widget.result,
                  ),
                  onTap: widget.locked ? null : () => _select(i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
