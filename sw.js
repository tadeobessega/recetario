// Service worker de Mi Recetario: recibe las notificaciones push del plan semanal.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let datos = {};
  try { datos = event.data ? event.data.json() : {}; } catch (e) { datos = { cuerpo: event.data && event.data.text() }; }
  const titulo = datos.titulo || 'Mi Recetario';
  event.waitUntil(self.registration.showNotification(titulo, {
    body: datos.cuerpo || '',
    icon: '/icon-192.png',
    badge: '/badge-72.png',
    tag: datos.tag || undefined,
    data: { url: datos.url || '/' }
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const destino = new URL((event.notification.data && event.notification.data.url) || '/', self.location.origin).href;
  event.waitUntil((async () => {
    const ventanas = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const v of ventanas) {
      if (new URL(v.url).origin === self.location.origin) {
        await v.focus();
        try { await v.navigate(destino); } catch (e) { /* algunas ventanas no se pueden redirigir */ }
        return;
      }
    }
    await self.clients.openWindow(destino);
  })());
});
