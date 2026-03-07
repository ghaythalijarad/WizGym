// WizGym Admin Dashboard - Service Worker
const CACHE_NAME = 'wizgym-admin-v1';
const urlsToCache = [
  '/',
  '/index.html',
  '/login.html',
  '/style.css',
  '/app.js',
  '/config.js',
  'https://fonts.googleapis.com/css2?family=Inter:wght@500;700;800&family=Tajawal:wght@500;700;800&display=swap',
  'https://fonts.googleapis.com/icon?family=Material+Icons+Round',
];

// Install event
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(urlsToCache))
  );
});

// Fetch event - Network first, fallback to cache
self.addEventListener('fetch', (event) => {
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // Clone the response
        const responseToCache = response.clone();
        
        caches.open(CACHE_NAME)
          .then((cache) => {
            cache.put(event.request, responseToCache);
          });
        
        return response;
      })
      .catch(() => {
        return caches.match(event.request);
      })
  );
});

// Activate event - Clean up old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
});
