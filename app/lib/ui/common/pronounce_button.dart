import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart' show courseDataProvider;
import '../../speech/speech_providers.dart';

/// A small 🔊 button that pronounces [text] in the course language with
/// on-device text-to-speech (v0.5: word popovers, flashcards, word pages).
/// Absent when the device has no voice for the language (and for Sarnami).
class PronounceButton extends ConsumerWidget {
  const PronounceButton({super.key, required this.text, this.languageCode, this.size = 22, this.buttonKey});

  final String text;

  /// Defaults to the active course's target language.
  final String? languageCode;
  final double size;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canPronounceProvider) || text.trim().isEmpty) return const SizedBox.shrink();
    final lang = languageCode ?? ref.watch(courseDataProvider).value?.meta.target;
    if (lang == null) return const SizedBox.shrink();
    return IconButton(
      key: buttonKey ?? const ValueKey('pronounce'),
      tooltip: 'Pronounce',
      iconSize: size,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: const Icon(Icons.volume_up_outlined),
      onPressed: () => unawaited(ref.read(speakerProvider).speak(text, lang)),
    );
  }
}
