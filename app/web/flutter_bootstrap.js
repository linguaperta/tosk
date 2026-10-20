// Custom bootstrap (v0.7): the same as Flutter's default, but without
// serviceWorkerSettings. Flutter's own service worker is deprecated and now
// unregisters itself (and reloads the page), which would also remove tosk's
// offline worker (web/sw.js, registered from index.html) on the same scope.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();
