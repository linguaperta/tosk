import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Haptics for feedback. Everything is a no-op when [enabled] is false
/// (the "Reduce motion" setting). Sounds are separate: `audio/sound_service.dart`
/// behind the "Sound effects" setting.
class Fx {
  const Fx({required this.enabled});
  final bool enabled;

  void tap() {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  void correct() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }

  void wrong() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }

  void finished() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }
}

/// Animation durations that collapse to zero when motion is reduced.
class Motion {
  const Motion(this.reduced);
  final bool reduced;

  Duration get short => reduced ? Duration.zero : const Duration(milliseconds: 150);
  Duration get medium => reduced ? Duration.zero : const Duration(milliseconds: 250);
  Duration get long => reduced ? Duration.zero : const Duration(milliseconds: 400);
  Curve get curve => Curves.easeOutCubic;
}
