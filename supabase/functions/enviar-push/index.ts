// Edge Function "enviar-push": manda las notificaciones push que están en la cola (cola_push).
//
// La llama pg_cron cada 5 minutos, después de procesar_recordatorios(), solo si hay algo pendiente.
// La primera vez genera las claves VAPID y las guarda en config_push (la pública la lee la app
// con vapid_publica() para suscribir el dispositivo).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { buildPushPayload } from 'npm:@block65/webcrypto-web-push@2.0.0';

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
});
const CONTACTO = 'mailto:avisos@mirecetario.app';
const MAX_INTENTOS = 5;

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function clavesVapid() {
  const { data } = await db.from('config_push').select('clave, valor').in('clave', ['vapid_publica', 'vapid_privada']);
  const mapa = Object.fromEntries((data ?? []).map((x) => [x.clave, x.valor]));
  if (mapa.vapid_publica && mapa.vapid_privada) return { publicKey: mapa.vapid_publica, privateKey: mapa.vapid_privada };

  const par = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const publica = b64url(new Uint8Array(await crypto.subtle.exportKey('raw', par.publicKey)));
  const privada = (await crypto.subtle.exportKey('jwk', par.privateKey)).d!;
  // si dos llamadas compiten, gana la primera que escribió
  await db.from('config_push').upsert([
    { clave: 'vapid_publica', valor: publica },
    { clave: 'vapid_privada', valor: privada },
  ], { onConflict: 'clave', ignoreDuplicates: true });
  return clavesVapid();
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Usá POST', { status: 405 });
  try {
    const claves = await clavesVapid();
    const vapid = { subject: CONTACTO, ...claves };

    const { data: cola, error } = await db.from('cola_push').select('*')
      .is('enviada_at', null).lt('intentos', MAX_INTENTOS).order('created_at').limit(200);
    if (error) throw error;

    let enviadas = 0, fallidas = 0;
    for (const item of cola ?? []) {
      const { data: subs } = await db.from('suscripciones_push').select('*').eq('user_id', item.user_id);
      let algunaOk = false, ultimoError = '';
      for (const s of subs ?? []) {
        try {
          const payload = await buildPushPayload(
            { data: JSON.stringify({ titulo: item.titulo, cuerpo: item.cuerpo, url: item.url, tag: 'plan-' + item.id }), options: { ttl: 6 * 3600, urgency: 'normal' } },
            { endpoint: s.endpoint, expirationTime: null, keys: { p256dh: s.p256dh, auth: s.auth } },
            vapid,
          );
          const res = await fetch(s.endpoint, payload);
          if (res.ok) { algunaOk = true; continue; }
          // 404/410: el dispositivo ya no existe (se desinstaló o venció la suscripción)
          if (res.status === 404 || res.status === 410) await db.from('suscripciones_push').delete().eq('id', s.id);
          ultimoError = `HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`;
        } catch (e) {
          ultimoError = String((e as Error).message ?? e).slice(0, 200);
        }
      }
      // sin dispositivos suscriptos no hay nada que reintentar: el aviso ya está en la campanita
      const terminado = algunaOk || !(subs ?? []).length || item.intentos + 1 >= MAX_INTENTOS;
      await db.from('cola_push').update({
        intentos: item.intentos + 1,
        enviada_at: terminado ? new Date().toISOString() : null,
        error: algunaOk ? null : (ultimoError || (subs?.length ? null : 'sin dispositivos suscriptos')),
      }).eq('id', item.id);
      if (algunaOk) enviadas++; else fallidas++;
    }
    return Response.json({ ok: true, procesadas: cola?.length ?? 0, enviadas, fallidas, vapid_publica: claves.publicKey });
  } catch (e) {
    console.error(e);
    return Response.json({ ok: false, error: String((e as Error).message ?? e) }, { status: 500 });
  }
});
