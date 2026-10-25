/// Which device the app runs on (v0.5): only to recognize ONYX (Boox)
/// e-readers, through the app's own `tosk/device` platform channel
/// (`MainActivity.kt`; `Build.MANUFACTURER`), so no plugin is needed.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class DeviceInfo {
  const DeviceInfo({this.manufacturer = '', this.brand = '', this.model = '', this.abis = const []});

  /// Not Android, or the channel isn't there (tests, other platforms).
  static const unknown = DeviceInfo();

  final String manufacturer;
  final String brand;
  final String model;

  /// `Build.SUPPORTED_ABIS`, preferred first (`arm64-v8a`, ...): which APK of
  /// a release fits (the update notice).
  final List<String> abis;

  /// An ONYX (Boox) e-reader: `Build.MANUFACTURER` or `Build.BRAND` is ONYX.
  bool get isOnyx => manufacturer.toLowerCase().contains('onyx') || brand.toLowerCase().contains('onyx');

  @override
  String toString() => '$manufacturer $brand $model';
}

const MethodChannel _deviceChannel = MethodChannel('tosk/device');

/// Asks the Android side; [DeviceInfo.unknown] everywhere else or on failure.
Future<DeviceInfo> loadDeviceInfo() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return DeviceInfo.unknown;
  try {
    final m = await _deviceChannel.invokeMapMethod<String, Object?>('info');
    if (m == null) return DeviceInfo.unknown;
    return DeviceInfo(
      manufacturer: '${m['manufacturer'] ?? ''}',
      brand: '${m['brand'] ?? ''}',
      model: '${m['model'] ?? ''}',
      abis: [for (final a in (m['abis'] as List?) ?? const []) '$a'],
    );
  } catch (e) {
    debugPrint('[device] no device info: $e');
    return DeviceInfo.unknown;
  }
}

/// Opens this app's notification settings (Android: the app's page in the
/// system settings, to allow notifications again); false when it can't.
Future<bool> openNotificationSettings() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await _deviceChannel.invokeMethod<bool>('openNotificationSettings') ?? false;
  } catch (e) {
    debugPrint('[device] no notification settings: $e');
    return false;
  }
}

/// Opens Android's text-to-speech settings (to install a voice); false when
/// that isn't possible (not Android, no such screen).
Future<bool> openTtsSettings() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await _deviceChannel.invokeMethod<bool>('openTtsSettings') ?? false;
  } catch (e) {
    debugPrint('[device] no TTS settings: $e');
    return false;
  }
}
