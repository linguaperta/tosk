// tosk service worker (v0.7): offline app shell for the PWA.
//
// Network first, cache as the fallback: online you always get the newest
// build (Flutter's file names carry no hashes, so serving them from a cache
// first could mix two versions); offline the last copy of every file the app
// loaded is served, including the bundled course packs. Downloaded packs
// (packs/) are not cached here: the app keeps them in IndexedDB.
const CACHE = 'tosk-shell-v1';
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

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET' || req.headers.has('range')) return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // Google sign-in, Firestore: never cached
  const scope = new URL(self.registration.scope);
  if (url.pathname.startsWith(scope.pathname + 'packs/')) return; // in IndexedDB
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
