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
//   Página puente propia (recomendado): "Te llevamos a Instagram…" con el nombre de la
//   receta, UN banner y redirección automática a los 3 segundos (botón "Ir ahora").
//   Sin ventanas emergentes. El banner sale de lo primero que esté configurado:
//     - AADS_ID: número del bloque de anuncios de A-ADS (a-ads.com). Solo banners, sin
//       pop-ups ni cookies, sin aprobación ni tráfico mínimo. Paga en Bitcoin.
//     - ANUNCIO_SALIDA_HTML: código HTML de cualquier red (ej. "Native Banner" de Adsterra).
//       Usá solo formatos de banner, nunca "Popunder" ni "Social Bar".
//     - ADSENSE_CLIENTE + ADSENSE_BLOQUE_SALIDA: un bloque de Google AdSense.
//
//   MONETIZAR_URL: acortador con {url} (ShrinkMe, etc.). Tiene prioridad si está cargado.
//   Desaconsejado: esos servicios abren muchas ventanas y espantan a la gente.
//
//   Si no hay nada configurado, la salida es directa.

const SUPABASE_URL = 'https://nwkmdonyrqantliwlebi.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53a21kb255cnFhbnRsaXdsZWJpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MzU0NjAsImV4cCI6MjEwNTUxMTQ2MH0.lh28WPqEKoWBUycuaVf_6tnG0LK_sVLpxP0Yd6lhlxY';   // clave "anon": es pública por diseño
const TIPOS_VALIDOS = new Set(['ig', 'tt', 'web']);
const SEGUNDOS_ESPERA = 3;

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
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/titulo_de_receta`, {
      method: 'POST',
      headers: cabecerasSupabase,
      body: JSON.stringify({ p_receta: id })
    });
    if (!res.ok) return '';
    const t = await res.json();
    return typeof t === 'string' ? t : '';
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

// Banner a mostrar en la página puente, según lo configurado
function anuncioSalida(env) {
  const aads = String(env.AADS_ID || '').trim();
  if (/^\d+$/.test(aads)) {
    return { html: `<iframe data-aa="${aads}" src="https://ad.a-ads.com/${aads}?size=300x250" style="width:300px;height:250px;border:0;padding:0;overflow:hidden;background-color:transparent;" scrolling="no" title="Publicidad"></iframe>`, cabeza: '' };
  }
  const html = String(env.ANUNCIO_SALIDA_HTML || '').trim();
  if (html) return { html, cabeza: '' };
  const cliente = String(env.ADSENSE_CLIENTE || '').trim();
  const bloque = String(env.ADSENSE_BLOQUE_SALIDA || '').trim();
  if (cliente && bloque) {
    return {
      cabeza: `<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${esc(cliente)}" crossorigin="anonymous"></script>`,
      html: `<ins class="adsbygoogle" style="display:block;width:100%;min-height:250px" data-ad-client="${esc(cliente)}" data-ad-slot="${esc(bloque)}" data-ad-format="auto" data-full-width-responsive="true"></ins><script>try{(window.adsbygoogle=window.adsbygoogle||[]).push({})}catch(e){}</script>`
    };
  }
  return null;
}

function paginaSalida({ destino, tipo, titulo, anuncio }) {
  const sitio = nombreDestino(tipo, destino);
  const destinoJson = JSON.stringify(destino).replace(/</g, '\\u003c');
  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="robots" content="noindex">
<meta name="theme-color" content="#1E4D36">
<title>Te llevamos a ${esc(sitio)} · Mi Recetario</title>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700&family=Figtree:wght@400;600&display=swap" rel="stylesheet">
${anuncio.cabeza}
<style>
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 16px;
         font-family: Figtree, -apple-system, "Segoe UI", Roboto, sans-serif; background: #EEF2EB; color: #26332C; }
  .caja { width: 100%; max-width: 420px; background: #fff; border-radius: 22px; overflow: hidden;
          box-shadow: 0 18px 50px -12px rgba(30,77,54,.25); text-align: center; }
  .cabeza { background: #1E4D36; color: #fff; padding: 22px 22px 18px; }
  .marca { display: inline-flex; align-items: center; gap: 8px; font-family: "Bricolage Grotesque", Figtree, sans-serif; font-weight: 700; font-size: 15px; color: #F0B429; }
  h1 { font-family: "Bricolage Grotesque", Figtree, sans-serif; font-size: 1.35rem; margin: 10px 0 4px; letter-spacing: -.01em; }
  .receta { margin: 0; font-size: .92rem; color: rgba(255,255,255,.75); }
  .barra { height: 4px; background: rgba(255,255,255,.15); margin-top: 16px; border-radius: 4px; overflow: hidden; }
  .barra span { display: block; height: 100%; width: 0; background: #F0B429; animation: llenar ${SEGUNDOS_ESPERA}s linear forwards; }
  @keyframes llenar { to { width: 100%; } }
  @media (prefers-reduced-motion: reduce) { .barra span { animation: none; width: 100%; } }
  .cuerpo { padding: 18px 20px 22px; }
  .anuncio { min-height: 250px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 6px; }
  .etiqueta { font-size: 11px; color: #9aa59d; }
  a.boton { display: block; margin-top: 16px; background: #1E4D36; color: #fff; text-decoration: none; padding: 13px 22px; border-radius: 14px; font-weight: 600; }
  a.boton:hover { background: #163B29; }
  .volver { display: inline-block; margin-top: 12px; font-size: .82rem; color: #6b776f; }
</style>
</head>
<body>
  <div class="caja">
    <div class="cabeza">
      <span class="marca">Mi Recetario</span>
      <h1>Te llevamos a ${esc(sitio)}…</h1>
      ${titulo ? `<p class="receta">${esc(titulo)}</p>` : ''}
      <div class="barra"><span></span></div>
    </div>
    <div class="cuerpo">
      <div class="anuncio"><span class="etiqueta">Publicidad</span>${anuncio.html}</div>
      <a class="boton" href="${esc(destino)}" rel="noopener noreferrer nofollow">Ir ahora a ${esc(sitio)}</a>
      <a class="volver" href="/">Volver a Mi Recetario</a>
    </div>
  </div>
<script>
  setTimeout(function () { window.location.replace(${destinoJson}); }, ${SEGUNDOS_ESPERA * 1000});
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

  // 2) Página puente propia con un banner y redirección automática
  const anuncio = anuncioSalida(env);
  if (anuncio) {
    const titulo = await tituloDe(id);
    return new Response(paginaSalida({ destino, tipo, titulo, anuncio }), {
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
