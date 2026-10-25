// tosk service worker (v0.7): offline app shell for the PWA.
//
// Network first, cache as the fallback: online you always get the newest
// build (Flutter's file names carry no hashes, so serving them from a cache
// first could mix two versions); offline the last copy of every file the app
// loaded is served, including the bundled course packs. Downloaded packs
// (packs/) are not cached here: the app keeps them in IndexedDB.
const CACHE = 'tosk-shell-v2';
// The deployed commit: the Pages workflow stamps it in, so every deploy that
// changes the app changes this file. The browser then installs this worker
// anew, and index.html tells the running app ("tosk was updated, reload";
// lib/updates/web_update.dart). Local builds keep the placeholder.
const BUILD = '__TOSK_BUILD__';
const SHELL = [
  './',
  'index.html',
  'manifest.json',
  'flutter_bootstrap.js',
  'main.dart.js',
  'sqlite3.wasm',
  'drift_worker.js',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      // One missing file must not stop the install.
      Promise.all(SHELL.map((url) => cache.add(new Request(url, { cache: 'reload' })).catch(() => {}))),
    ).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('tosk-') && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

// What the first visit loaded before this worker controlled the page
// (CanvasKit, fonts, the asset manifests, ...): index.html sends the page's
// same-origin resource URLs once the worker is active, and the ones not
// cached yet are stored (from the HTTP cache, so nothing is fetched twice).
// Without this, the app shell didn't start offline after a single visit.
self.addEventListener('message', (event) => {
  const data = event.data;
  if (!data || data.type !== 'tosk-cache-urls' || !Array.isArray(data.urls)) return;
  event.waitUntil(cacheUrls(data.urls));
});

async function cacheUrls(urls) {
  const cache = await caches.open(CACHE);
  const scope = new URL(self.registration.scope);
  await Promise.all(urls.map(async (u) => {
    let url;
    try {
      url = new URL(u, scope);
    } catch (_) {
      return;
    }
    if (!cacheable(url)) return;
    if (await cache.match(url.href, { ignoreSearch: true })) return;
    try {
      const res = await fetch(url.href);
      if (res.ok && res.type === 'basic') await cache.put(url.href, res);
    } catch (_) {}
  }));
}

/// Same origin, inside the app's scope, not a pack (those are in IndexedDB).
function cacheable(url) {
  const scope = new URL(self.registration.scope);
  return url.origin === self.location.origin &&
    url.pathname.startsWith(scope.pathname) &&
    !url.pathname.startsWith(scope.pathname + 'packs/');
}

// A byte range of a cached file (sound effects are played with range
// requests), so the sounds also work offline.
async function rangeFromCache(req) {
  const hit = await caches.match(req.url, { ignoreSearch: true });
  if (!hit) return Response.error();
  const buf = await hit.arrayBuffer();
  const size = buf.byteLength;
  const m = /bytes=(\d*)-(\d*)/.exec(req.headers.get('range') || '');
  let start = 0;
  let end = size - 1;
  if (m && m[1]) {
    start = +m[1];
    if (m[2]) end = Math.min(+m[2], size - 1);
  } else if (m && m[2]) {
    start = Math.max(0, size - +m[2]);
  }
  if (start > end) {
    return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${size}` } });
  }
  return new Response(buf.slice(start, end + 1), {
    status: 206,
    headers: {
      'Content-Type': hit.headers.get('Content-Type') || 'application/octet-stream',
      'Content-Range': `bytes ${start}-${end}/${size}`,
      'Content-Length': `${end - start + 1}`,
      'Accept-Ranges': 'bytes',
    },
  });
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Google sign-in and Firestore are never cached; packs are in IndexedDB.
  if (!cacheable(url)) return;
  if (req.headers.has('range')) {
    // Partial responses are not cached; offline they come from the full copy.
    event.respondWith(fetch(req).catch(() => rangeFromCache(req)));
    return;
  }
  event.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok && res.type === 'basic') {
          const copy = res.clone();
          caches.open(CACHE).then((cache) => cache.put(req, copy));
        }
        return res;
      })
      .catch(async () => {
        const hit = await caches.match(req, { ignoreSearch: true });
        if (hit) return hit;
        if (req.mode === 'navigate') {
          const shell = await caches.match('index.html', { ignoreSearch: true }) || await caches.match('./');
          if (shell) return shell;
        }
        return Response.error();
      }),
  );
});
