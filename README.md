# Mi Recetario

Recetario social: cargás tus recetas, las organizás en colecciones, seguís a otras personas, ves lo que publican en el inicio, calificás y reseñás, y te escribís con quienes se siguen mutuamente.

- `index.html`: toda la app (HTML + Tailwind + Supabase JS).
- `worker.js`: worker de Cloudflare. Sirve la app, resuelve los enlaces de salida (`/go`) y sirve `/ads.txt`.
- `supabase/esquema.sql`: tablas, reglas de acceso y funciones de la base.
- `pol_tica_de_privacidad.html` y `politica-seguridad.html`: políticas, enlazadas al pie de la app.

## Puesta en marcha

1. **Base de datos.** La base de producción ya está al día (ver `supabase/aplicado-2026-10-10.sql`). Para armar una base nueva desde cero, en Supabase → *SQL Editor* pegá `supabase/esquema.sql` completo y apretá *Run*: crea todo lo que la app necesita.
   Ojo: en el plan gratis, Supabase pausa el proyecto después de una semana sin uso. Si la app deja de cargar, entrá al panel y apretá *Restore project*.
2. **Google y recuperación de contraseña.** En Supabase → *Authentication* → *URL Configuration*, poné tu dominio en *Site URL* y en *Redirect URLs*. El ingreso con Google es gratis: se activa en *Authentication → Providers → Google*, con el Client ID y el Secret de Google Cloud.
3. **Deploy.** Cloudflare Workers publica el repo con `wrangler.jsonc` (los assets salen de la raíz).

## Monetizar los enlaces de las recetas

Los botones de Instagram, TikTok y web de las recetas públicas no van directo al destino: pasan por `https://tu-dominio/go?r=<receta>&t=<ig|tt|web>`. El worker busca el destino real en la base, registra el clic en la tabla `clics_enlaces` y después hace una de estas tres cosas, según lo que configures en `wrangler.jsonc → vars`:

| Modo | Qué configurar | Qué ve la persona |
|---|---|---|
| Acortador que paga por clic | `MONETIZAR_URL` con `{url}` donde va el destino. Ej: `https://servicio.com/api?api=TU_TOKEN&url={url}` | La página del acortador (ShrinkMe, ouo.io, Linkvertise, etc.) y después el destino. |
| Página propia con anuncio | `ADSENSE_CLIENTE` (`ca-pub-…`) y `ADSENSE_BLOQUE_SALIDA` (ID de un bloque de AdSense) | Una página de Mi Recetario con el nombre de la receta, un anuncio y una cuenta regresiva de 5 segundos. |
| Directo | Todo vacío | El destino, sin pasos intermedios. |

Si cargás las dos opciones, gana el acortador. Cuántas salidas genera cada receta lo ves en Supabase → *Table editor* → `clics_enlaces`.

Recomendación: empezá con la página propia con anuncio. La gente sigue dentro de tu marca, no hay pop-ups de terceros y todo queda en una sola cuenta de AdSense. Los acortadores pagan por clic pero suelen mostrar publicidad agresiva, y eso puede hacer que la gente deje de tocar los enlaces.

## Publicidad en el inicio

Cada 6 publicaciones del inicio aparece un espacio publicitario (`ANUNCIO_CADA_N_POSTS` en `index.html`). Para que muestre anuncios reales:

1. Creá tu cuenta en [AdSense](https://adsense.google.com) y agregá tu dominio.
2. Creá un bloque de anuncios (tipo *In-feed* o *Display*).
3. En `index.html`, completá `ADSENSE_CLIENTE` y `ADSENSE_BLOQUE`.
4. En `wrangler.jsonc`, completá `ADSENSE_CLIENTE` para que el worker sirva `/ads.txt`. Google lo pide para aprobar el sitio y pagar.

Mientras esos datos estén vacíos, el inicio muestra un recuadro "Espacio publicitario" en cada lugar donde va a ir un anuncio.
