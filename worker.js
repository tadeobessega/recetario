// Worker de Cloudflare: sirve la app y resuelve los enlaces de salida (/go).
//
// Los enlaces de las recetas públicas (Instagram, TikTok, web) apuntan a
//   https://TU-DOMINIO/go?r=<id de receta>&t=<ig|tt|web>
// El destino se busca en la base de datos (no viaja en la URL), así nadie puede
// usar /go para redirigir a un sitio cualquiera. Cada salida queda registrada en
// la tabla clics_enlaces de Supabase.
//
// Cómo se monetiza cada salida (se configura en wrangler.jsonc → "vars"):
//
//   1) MONETIZAR_URL (acortador que paga por clic, tipo ShrinkMe / ouo.io / Linkvertise):
//        "MONETIZAR_URL": "https://servicio.com/api?api=TU_TOKEN&url={url}"
//      {url} se reemplaza por el destino. La persona pasa por la página del acortador.
//
//   2) ADSENSE_CLIENTE + ADSENSE_BLOQUE_SALIDA (página propia con un anuncio):
//        "ADSENSE_CLIENTE": "ca-pub-1234567890123456",
//        "ADSENSE_BLOQUE_SALIDA": "1234567890"
//      Antes de salir se muestra una página de Mi Recetario con un anuncio y una
//      cuenta regresiva de unos segundos. Con ADSENSE_CLIENTE cargado, además se
//      sirve /ads.txt, que AdSense pide para pagar.
//
//   Si los dos están vacíos, la salida es directa (sin monetizar).
//   Si están los dos, gana MONETIZAR_URL.

const SUPABASE_URL = 'https://nwkmdonyrqantliwlebi.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53a21kb255cnFhbnRsaXdsZWJpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MzU0NjAsImV4cCI6MjEwNTUxMTQ2MH0.lh28WPqEKoWBUycuaVf_6tnG0LK_sVLpxP0Yd6lhlxY';   // clave "anon": es pública por diseño
const TIPOS_VALIDOS = new Set(['ig', 'tt', 'web']);
const SEGUNDOS_ESPERA = 5;

const cabecerasSupabase = {
  apikey: SUPABASE_KEY,
  Authorization: `Bearer ${SUPABASE_KEY}`,
  'Content-Type': 'application/json'
};

async function destinoDe(id, tipo) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/link_de_receta`, {
    method: 'POST',
    headers: cabecerasSupabase,
    body: JSON.stringify({ p_receta: id, p_tipo: tipo })
  });
  if (!res.ok) return null;
  const destino = await res.json();
  return typeof destino === 'string' && /^https?:\/\//i.test(destino) ? destino : null;
}

async function tituloDe(id) {
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/recetas?id=eq.${encodeURIComponent(id)}&select=titulo&limit=1`, {
      headers: cabecerasSupabase
    });
    if (!res.ok) return '';
    const filas = await res.json();
    return (filas && filas[0] && filas[0].titulo) || '';
  } catch (e) {
    return '';
  }
}

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function nombreDestino(tipo, destino) {
  if (tipo === 'ig') return 'Instagram';
  if (tipo === 'tt') return 'TikTok';
  try { return new URL(destino).hostname.replace(/^www\./, ''); } catch (e) { return 'el sitio'; }
}

function paginaSalida({ destino, tipo, titulo, cliente, bloque }) {
  const sitio = nombreDestino(tipo, destino);
  const destinoJson = JSON.stringify(destino).replace(/</g, '\\u003c');
  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="robots" content="noindex">
<title>Saliendo de Mi Recetario</title>
<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${esc(cliente)}" crossorigin="anonymous"></script>
<style>
  body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 16px; box-sizing: border-box;
         font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #fcfbf8; color: #2b2d42; }
  .caja { width: 100%; max-width: 440px; background: #fff; border: 1px solid #ebe7dc; border-radius: 18px; padding: 28px 24px;
          box-shadow: 0 12px 40px rgba(27,67,50,.10); text-align: center; }
  h1 { font-size: 1.1rem; color: #1b4332; margin: 0 0 6px; }
  p { margin: 0; font-size: .9rem; color: #6b7280; }
  .receta { margin-top: 14px; font-weight: 600; color: #1b4332; }
  .anuncio { margin: 20px 0; min-height: 120px; }
  .etiqueta { display: block; font-size: 10px; letter-spacing: .12em; text-transform: uppercase; color: #9ca3af; margin-bottom: 6px; }
  a.boton { display: inline-block; background: #1b4332; color: #fff; text-decoration: none; padding: 12px 22px; border-radius: 12px; font-size: .9rem; font-weight: 600; }
  a.boton[aria-disabled="true"] { opacity: .5; pointer-events: none; }
  .volver { display: block; margin-top: 16px; font-size: .8rem; color: #6b7280; }
</style>
</head>
<body>
  <div class="caja">
    <h1>Te llevamos a ${esc(sitio)}</h1>
    <p>Abrimos el enlace original de la receta en <span id="cuenta">${SEGUNDOS_ESPERA}</span> segundos.</p>
    ${titulo ? `<p class="receta">${esc(titulo)}</p>` : ''}
    <div class="anuncio">
      <span class="etiqueta">Publicidad</span>
      <ins class="adsbygoogle" style="display:block" data-ad-client="${esc(cliente)}" data-ad-slot="${esc(bloque)}" data-ad-format="auto" data-full-width-responsive="true"></ins>
    </div>
    <a id="ir" class="boton" href="${esc(destino)}" rel="noopener noreferrer nofollow" aria-disabled="true">Ir a ${esc(sitio)}</a>
    <a class="volver" href="/">Volver a Mi Recetario</a>
  </div>
<script>
  try { (window.adsbygoogle = window.adsbygoogle || []).push({}); } catch (e) {}
  var destino = ${destinoJson};
  var n = ${SEGUNDOS_ESPERA};
  var cuenta = document.getElementById('cuenta');
  var ir = document.getElementById('ir');
  setTimeout(function () { ir.setAttribute('aria-disabled', 'false'); }, 2000);
  var t = setInterval(function () {
    n -= 1;
    cuenta.textContent = Math.max(n, 0);
    if (n <= 0) { clearInterval(t); window.location.replace(destino); }
  }, 1000);
</script>
<noscript><meta http-equiv="refresh" content="${SEGUNDOS_ESPERA};url=${esc(destino)}"></noscript>
</body>
</html>`;
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

  // 1) Acortador que paga por clic
  const plantilla = (env.MONETIZAR_URL || '').trim();
  if (plantilla.includes('{url}')) {
    return new Response(null, {
      status: 302,
      headers: {
        Location: plantilla.replace('{url}', encodeURIComponent(destino)),
        'Cache-Control': 'no-store',
        'Referrer-Policy': 'no-referrer'
      }
    });
  }

  // 2) Página propia con anuncio
  const cliente = (env.ADSENSE_CLIENTE || '').trim();
  const bloque = (env.ADSENSE_BLOQUE_SALIDA || '').trim();
  if (cliente && bloque) {
    const titulo = await tituloDe(id);
    return new Response(paginaSalida({ destino, tipo, titulo, cliente, bloque }), {
      status: 200,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
        'Referrer-Policy': 'no-referrer',
        'X-Robots-Tag': 'noindex'
      }
    });
  }

  // 3) Directo
  return new Response(null, {
    status: 302,
    headers: {
      Location: destino,
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer'
    }
  });
}

function adsTxt(env) {
  const cliente = (env.ADSENSE_CLIENTE || '').trim();
  const pub = cliente.replace(/^ca-/, '');
  if (!/^pub-\d+$/.test(pub)) return new Response('', { status: 404 });
  return new Response(`google.com, ${pub}, DIRECT, f08c47fec0942fa0\n`, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'public, max-age=3600' }
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/go') return manejarSalida(url, env);
    if (url.pathname === '/ads.txt') return adsTxt(env);
    return env.ASSETS.fetch(request);
  }
};
