import 'package:web/web.dart' as web;

import 'crash_log.dart';

const _key = 'tosk.last_crash_dart';

/// The browser's localStorage (this origin only).
class CrashLogStore {
  web.Storage? _storage;

  Future<bool> init() async {
    try {
      _storage = web.window.localStorage;
      return true;
    } catch (_) {
      return false;
    }
  }

  void writeDart(String text, {required bool append}) {
    final s = _storage;
    if (s == null) return;
    try {
      s.setItem(_key, append ? '${s.getItem(_key) ?? ''}$text' : text);
    } catch (_) {}
  }

  Future<CrashParts> take() async {
    try {
      final s = _storage ?? web.window.localStorage;
      final text = s.getItem(_key)?.trim();
      s.removeItem(_key);
      return (native: null, dart: (text == null || text.isEmpty) ? null : text);
    } catch (_) {
      return (native: null, dart: null);
    }
  }
}
