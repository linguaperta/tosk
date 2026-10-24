/// The browser side of the web update path: `index.html` dispatches
/// `tosk-update` on `window` (and sets `window.toskUpdateReady`) when a new
/// service worker takes over a page that already had one.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'web_update.dart';

WebUpdateSource? createWebUpdateSource() => BrowserWebUpdateSource();

class BrowserWebUpdateSource implements WebUpdateSource {
  BrowserWebUpdateSource() {
    web.window.addEventListener('tosk-update', _listener);
  }

  final _updates = StreamController<void>.broadcast();
  late final JSFunction _listener = ((web.Event _) => _updates.add(null)).toJS;

  @override
  Stream<void> get workerUpdated => _updates.stream;

  @override
  bool get workerUpdatedBefore {
    final flag = globalContext['toskUpdateReady'];
    return flag.isA<JSBoolean>() && (flag as JSBoolean).toDart;
  }

  @override
  Future<WhatsNew?> fetchWhatsNew() async {
    try {
      final url = Uri.parse(web.document.baseURI).resolve('whats_new.json');
      // Revalidated with the server (Pages caches for 10 minutes); the
      // service worker is network first, so this reaches the deploy.
      final res = await web.window.fetch('$url'.toJS, web.RequestInit(cache: 'no-cache')).toDart;
      if (!res.ok) return null;
      return WhatsNew.parse((await res.text().toDart).toDart);
    } on Object catch (e) {
      debugPrint('[update] whats_new.json unavailable: $e');
      return null;
    }
  }

  @override
  void reload() => web.window.location.reload();
}
