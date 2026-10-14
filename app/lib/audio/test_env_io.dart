import 'dart:io';

/// `flutter test` sets FLUTTER_TEST in the test process environment.
bool get runningInFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');
