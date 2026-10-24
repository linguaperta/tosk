import 'crash_log.dart';

/// No storage on this platform: nothing is recorded.
class CrashLogStore {
  Future<bool> init() async => false;
  void writeDart(String text, {required bool append}) {}
  Future<CrashParts> take() async => (native: null, dart: null);
}
