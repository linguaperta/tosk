/// Riverpod wiring of the device extras (v0.5): device info (ONYX
/// detection), the e-ink full refresh and the Onyx pen surface.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/test_env.dart';
import '../providers.dart' show bwProvider;
import '../ui/settings/learner_settings.dart';
import 'device_info.dart';
import 'onyx.dart';

/// The device (ONYX detection). [DeviceInfo.unknown] under `flutter test`
/// and off Android; tests override it.
final deviceInfoProvider = FutureProvider<DeviceInfo>(
  (ref) async => runningInFlutterTest ? DeviceInfo.unknown : loadDeviceInfo(),
);

/// Whether this is an ONYX (Boox) e-reader (false until known).
final isOnyxProvider = Provider<bool>((ref) => ref.watch(deviceInfoProvider).value?.isOnyx ?? false);

/// The e-ink screen: the Onyx SDK on ONYX devices, else a no-op.
final einkScreenProvider = Provider<EinkScreen>(
  (ref) => ref.watch(isOnyxProvider) ? const OnyxEinkScreen() : const NoEinkScreen(),
);

/// "Full refresh after lessons": only on ONYX devices; on by default in
/// black & white, else as set.
final fullRefreshAfterLessonsProvider = Provider<bool>((ref) {
  if (!ref.watch(einkScreenProvider).supported) return false;
  final set = ref.watch(learnerSettingsProvider.select((s) => s.value?.einkFullRefresh));
  return set ?? ref.watch(bwProvider);
});

/// The Onyx pen surface for the writing pad, or null (not ONYX, or switched
/// off in Settings): the pad then draws with Flutter.
final penSurfaceProvider = Provider<PenSurface?>((ref) {
  if (!ref.watch(isOnyxProvider)) return null;
  if (!ref.watch(learnerSettingsProvider.select((s) => s.value?.onyxPen ?? true))) return null;
  return OnyxPenSurface();
});
