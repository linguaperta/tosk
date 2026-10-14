import 'dart:io' show Platform;

/// `flutter test` sets FLUTTER_TEST in the test process.
bool get isFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');
