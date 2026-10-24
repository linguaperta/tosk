import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'crash_log.dart';

const _nativeFile = 'last_crash_native.txt';
const _dartFile = 'last_crash_dart.txt';

/// `last_crash_native.txt` (written by `ToskApplication.kt`) and
/// `last_crash_dart.txt` in the app support directory.
class CrashLogStore {
  Directory? _dir;

  Future<bool> init() async {
    try {
      _dir = await getApplicationSupportDirectory();
      return true;
    } catch (_) {
      return false;
    }
  }

  void writeDart(String text, {required bool append}) {
    final dir = _dir;
    if (dir == null) return;
    try {
      File('${dir.path}/$_dartFile').writeAsStringSync(text, mode: append ? FileMode.append : FileMode.write);
    } catch (_) {}
  }

  Future<CrashParts> take() async {
    try {
      final dir = _dir ?? await getApplicationSupportDirectory();
      String? read(String name) {
        final f = File('${dir.path}/$name');
        if (!f.existsSync()) return null;
        final text = f.readAsStringSync().trim();
        f.deleteSync();
        return text.isEmpty ? null : text;
      }

      return (native: read(_nativeFile), dart: read(_dartFile));
    } catch (_) {
      return (native: null, dart: null);
    }
  }
}
