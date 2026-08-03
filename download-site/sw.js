const CACHE_PREFIX = "versiondeck-";
const CACHE_NAME = `${CACHE_PREFIX}shell-v3`;
const APP_SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./enhancements.css",
  "./app.js",
  "./relative-time.js",
  "./manifest.webmanifest",
  "./assets/versiondeck-mark.svg",
  "./assets/versiondeck-192.png",
  "./assets/versiondeck-512.png",
];

function cacheable(response) {
  return response?.ok && response.type === "basic";
}

async function cacheResponse(request, response) {
  if (!cacheable(response)) return;
  const cache = await caches.open(CACHE_NAME);
  await cache.put(request, response.clone());
}

async function networkFirst(request, fallbackRequest = request) {
  try {
    const response = await fetch(request);
    await cacheResponse(fallbackRequest, response);
    return response;
  } catch {
    return (
      (await caches.match(fallbackRequest)) ||
      new Response("VersionDeck is unavailable offline.", {
        status: 503,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      })
    );
  }
}

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
          .map((key) => caches.delete(key)),
      ),
    ),
  );
  self.clients.claim();
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(networkFirst(request, "./index.html"));
    return;
  }

  if (url.pathname.endsWith("/releases.json")) {
    event.respondWith(networkFirst(request));
    return;
  }

  const update = fetch(request)
    .then(async (response) => {
      await cacheResponse(request, response);
      return response;
    })
    .catch(() => null);

  event.waitUntil(update.then(() => undefined));
  event.respondWith(
    caches.match(request).then(async (cached) => cached || (await update) || fetch(request)),
  );
});
