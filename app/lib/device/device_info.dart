/// Which device the app runs on (v0.5): only to recognize ONYX (Boox)
/// e-readers, through the app's own `tosk/device` platform channel
/// (`MainActivity.kt`; `Build.MANUFACTURER`), so no plugin is needed.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class DeviceInfo {
  const DeviceInfo({this.manufacturer = '', this.brand = '', this.model = ''});

  /// Not Android, or the channel isn't there (tests, other platforms).
  static const unknown = DeviceInfo();

  final String manufacturer;
  final String brand;
  final String model;

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
    );
  } catch (e) {
    debugPrint('[device] no device info: $e');
    return DeviceInfo.unknown;
  }
}
