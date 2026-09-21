// Worker de Cloudflare: sirve la app y resuelve los enlaces de salida (/go).
//
// Los enlaces de las recetas públicas (Instagram, TikTok, web) apuntan a
//   https://TU-DOMINIO/go?r=<id de receta>&t=<ig|tt|web>
// El destino se busca en la base de datos (no viaja en la URL), así nadie puede
// usar /go para redirigir a un sitio cualquiera.
//
// Para monetizar: en wrangler.jsonc completá MONETIZAR_URL con la plantilla de tu
// servicio, usando {url} donde va el destino. Ejemplo:
//   "MONETIZAR_URL": "https://tu-servicio.com/redirect?to={url}"
// Si queda vacío, se redirige directo al destino.

const SUPABASE_URL = 'https://nwkmdonyrqantliwlebi.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53a21kb255cnFhbnRsaXdsZWJpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MzU0NjAsImV4cCI6MjEwNTUxMTQ2MH0.lh28WPqEKoWBUycuaVf_6tnG0LK_sVLpxP0Yd6lhlxY';   // clave "anon": es pública por diseño
const TIPOS_VALIDOS = new Set(['ig', 'tt', 'web']);

async function destinoDe(id, tipo) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/link_de_receta`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ p_receta: id, p_tipo: tipo })
  });
  if (!res.ok) return null;
  const destino = await res.json();
  return typeof destino === 'string' && /^https?:\/\//i.test(destino) ? destino : null;
}

async function manejarSalida(url, env) {
  const id = url.searchParams.get('r') || '';
  const tipo = url.searchParams.get('t') || '';
  if (!id || id.length > 64 || !TIPOS_VALIDOS.has(tipo)) return Response.redirect(url.origin + '/', 302);

  let destino = null;
  try {
    destino = await destinoDe(id, tipo);
  } catch (e) { /* si falla, mostramos el aviso de abajo */ }

  if (!destino) {
    return new Response('Este enlace ya no está disponible.', {
      status: 404,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' }
    });
  }

  const plantilla = (env.MONETIZAR_URL || '').trim();
  const location = plantilla.includes('{url}')
    ? plantilla.replace('{url}', encodeURIComponent(destino))
    : destino;

  return new Response(null, {
    status: 302,
    headers: {
      Location: location,
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer'
    }
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/go') return manejarSalida(url, env);
    return env.ASSETS.fetch(request);
  }
};
