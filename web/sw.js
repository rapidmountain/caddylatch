const CACHE = 'caddylatch-v1';

// API paths that must always go to the network
const API_PREFIXES = [
  '/status', '/health', '/stats', '/enable', '/disable', '/extend',
  '/set-timer', '/update-filters', '/tunnel', '/ip-lists', '/settings', '/test-ntfy',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(['/']).catch(() => {}))
  );
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  // Always network for API calls
  if (API_PREFIXES.some(p => url.pathname.startsWith(p))) return;
  // Serve from cache with network fallback for app shell
  e.respondWith(
    caches.match(e.request).then(r => r || fetch(e.request).then(resp => {
      if (resp && resp.status === 200 && e.request.method === 'GET') {
        const clone = resp.clone();
        caches.open(CACHE).then(c => c.put(e.request, clone));
      }
      return resp;
    }))
  );
});
