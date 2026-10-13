import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Haptics and system sounds for feedback. Everything is a no-op when
/// [enabled] is false (driven by the `reduceMotion` setting, which the future
/// e-ink mode turns on).
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
    SystemSound.play(SystemSoundType.click);
  }

  void wrong() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
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
