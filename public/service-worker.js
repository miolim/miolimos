// #634: Minimaler Service Worker — macht miolimOS als PWA installierbar
// (Voraussetzung fürs Android-Share-Target). Kein Caching: alles geht
// normal übers Netz; der fetch-Handler existiert nur, damit Chromium
// die App als installierbar einstuft.
self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))
self.addEventListener("fetch", () => {})
