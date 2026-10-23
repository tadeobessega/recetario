# Mi Recetario

Recetario social: cargás tus recetas, las organizás en colecciones, seguís a otras personas, ves lo que publican en el inicio, calificás y reseñás, y te escribís con quienes se siguen mutuamente.

- `index.html`: toda la app (HTML + Tailwind + Supabase JS).
- `worker.js`: worker de Cloudflare. Sirve la app, resuelve los enlaces de salida (`/go`) y sirve `/ads.txt`.
- `ingredientes.js`: base de ~690 ingredientes que se sugieren al cargar recetas.
- `supabase/esquema.sql`: tablas, reglas de acceso y funciones de la base. `supabase/moderacion.sql`: comentarios, denuncias y sanciones. `supabase/plan_y_recompensas.sql`: plan semanal, avisos, racha, puntos, niveles y desafíos. `supabase/diario.sql`: diario de cocina, racha cocinando y semana cumplida.
- `supabase/functions/enviar-push`: función que manda las notificaciones push del plan.
- `sw.js`, `manifest.webmanifest` e íconos: la app se puede instalar en el celular y recibir notificaciones.
- `pol_tica_de_privacidad.html` y `politica-seguridad.html`: políticas, enlazadas al pie de la app.

## Puesta en marcha

1. **Base de datos.** La base de producción está al día: `supabase/aplicado-2026-10-10.sql`, `supabase/plan_y_recompensas.sql` y `supabase/diario.sql` ya están aplicados (22/10/2026). Para armar una base nueva desde cero, en Supabase → *SQL Editor* pegá `supabase/esquema.sql` completo y apretá *Run*: crea todo lo que la app necesita.
   En el plan gratis, Supabase pausa el proyecto después de una semana sin uso. Para evitarlo, el worker hace una consulta liviana a la base todos los días (cron de Cloudflare, `triggers` en `wrangler.jsonc`). Si igual deja de cargar, entrá al panel y apretá *Restore project*.
2. **Google y recuperación de contraseña.** En Supabase → *Authentication* → *URL Configuration*, poné tu dominio en *Site URL* y en *Redirect URLs*. El ingreso con Google es gratis: se activa en *Authentication → Providers → Google*, con el Client ID y el Secret de Google Cloud.
3. **Deploy.** Cloudflare Workers publica el repo con `wrangler.jsonc` (los assets salen de la raíz).

## Monetizar los enlaces de las recetas

Los botones de Instagram, TikTok y web de las recetas públicas pasan por `https://tu-dominio/go?r=<receta>&t=<ig|tt|web>`. El worker busca el destino real en la base y registra el clic en `clics_enlaces`. Si hay un anuncio configurado, muestra una **página puente propia**: "Te llevamos a Instagram…", con el nombre de la receta, un solo banner y redirección automática a los 3 segundos (con botón "Ir ahora"). No abre ventanas emergentes.

El banner se configura en `wrangler.jsonc → vars`. Completá una sola opción:

| Opción | Qué cargar | Notas |
|---|---|---|
| **A-ADS** (recomendada) | `AADS_ID`: el número de tu bloque de anuncios | Solo banners, sin pop-ups ni cookies, sin aprobación ni tráfico mínimo. Paga poco y en Bitcoin. |
| Otra red | `ANUNCIO_SALIDA_HTML`: el código del anuncio | Por ejemplo, el "Native Banner" de Adsterra. Usá solo banners, nunca Popunder ni Social Bar. |
| Google AdSense | `ADSENSE_CLIENTE` y `ADSENSE_BLOQUE_SALIDA` | Requiere que Google apruebe el sitio. |

Todo vacío = salida directa. Los acortadores que pagan por clic (`MONETIZAR_URL`) siguen soportados, pero no los recomiendo: abren muchas ventanas y espantan a la gente.

**Cómo crear el bloque en A-ADS:** entrá a a-ads.com, creá una cuenta, elegí *Create ad unit*, tamaño **300×250**, y copiá el número que aparece en el código (`data-aa="…"`). Ese mismo número sirve para los anuncios del feed (`AADS_ID` en `index.html`).

## Publicidad en el inicio

Cada 10 publicaciones del inicio aparece un espacio publicitario (`ANUNCIO_CADA_N_POSTS` en `index.html`). Para que muestre anuncios reales:

1. Creá tu cuenta en [AdSense](https://adsense.google.com) y agregá tu dominio.
2. Creá un bloque de anuncios (tipo *In-feed* o *Display*).
3. En `index.html`, completá `ADSENSE_CLIENTE` y `ADSENSE_BLOQUE`.
4. En `wrangler.jsonc`, completá `ADSENSE_CLIENTE` para que el worker sirva `/ads.txt`. Google lo pide para aprobar el sitio y pagar.

Mientras esos datos estén vacíos, el inicio muestra un recuadro "Espacio publicitario" en cada lugar donde va a ir un anuncio.

## Moderación

Cualquier persona puede denunciar publicaciones, comentarios, recetas y reseñas (menú ⋯ o el enlace "Denunciar"). Las cuentas que figuran en la tabla `administradores` ven el escudo en el encabezado, con la cantidad de denuncias pendientes. Desde ahí se puede:

- **Desestimar** la denuncia.
- **Ocultar** el contenido. Deja de verse para todo el mundo salvo su autor, que ve el aviso "Ocultada por moderación".
- **Ocultar y sancionar:** advertencia, suspensión de 1, 7 o 30 días, o bloqueo. Una cuenta suspendida o bloqueada puede seguir mirando, pero no puede publicar, comentar, calificar ni mandar mensajes. Esto lo controla la base, no solo la app.
- **Volver a mostrar** contenido ocultado y **levantar** sanciones.

Para sumar a otra persona como administradora: Supabase → *Table editor* → `administradores` → *Insert row* con su `user_id`.

## Plan semanal y avisos

En la pestaña **Plan** cada persona arma su semana: a cada día y comida (desayuno, almuerzo, merienda, cena) le asigna una receta suya o guardada, o escribe algo sin receta ("Pizza con amigos"). También se agrega desde el ícono de calendario de cualquier receta. Cada comida se puede marcar como hecha (+3 puntos).

**Avisos.** Por defecto: desayuno y almuerzo, el día anterior a las 18:00; merienda, el mismo día a las 12:00; cena, el mismo día a las 18:00. Se cambian para todas las comidas desde el botón *Avisos*, o para una sola comida al editarla ("Para esta comida" o "Sin aviso"). El aviso llega a la campanita y, si la persona activó las notificaciones en ese dispositivo, también como notificación push aunque la app esté cerrada. En iPhone hace falta instalar la app (Compartir → *Agregar a inicio*).

**Plantillas.** Una semana armada se guarda con un nombre (*Plantillas → Guardar esta semana*). Después, en cada semana se elige qué plantilla está activa: cambiarla reemplaza lo que había puesto la anterior, pero conserva lo agregado a mano y lo ya marcado como hecho.

Cómo funciona por dentro: la base calcula la hora de cada aviso; cada 5 minutos `pg_cron` corre `procesar_recordatorios()` y, si hay notificaciones pendientes, llama a la función `enviar-push`. Las claves de las notificaciones (VAPID) las crea esa función sola la primera vez.

## Racha, puntos, niveles y desafíos

- **Racha:** días seguidos usando la app. Tiene un comodín por semana: un día salteado no la corta.
- **Puntos y niveles:** Pinche (0), Ayudante (50), Cocinero/a (150), Chef (400), Gran chef (1000). Se suman solos al cargar recetas, publicar, reseñar, comentar, cocinar lo planeado, cuando te guardan una receta o te ponen 4★ o más, y con los bonus de racha. Hay topes diarios para que no se pueda inflar. La tabla completa está en la ventana de progreso (tocando la llama del encabezado).
- **Beneficio:** cuanto más nivel, más arriba aparecen tus recetas en «Quizás te interese». Las medallas (nivel, llama de 7+ días de racha y trofeo de desafíos) se ven al lado del nombre en todos lados. La primera vez que alguien abre la app se le muestra esta explicación.
- **Desafío semanal:** un tema por semana (lunes a domingo). Se participa publicando una foto, o una receta con foto, marcando "Participar del desafío" (+25 puntos, una vez por desafío). Las cuentas administradoras crean y editan los desafíos desde *Moderación → Desafíos*. Ya hay 6 cargados desde el 19/10/2026.

## Diario de cocina

Como el diario de Letterboxd, pero de comidas. Cada entrada tiene día, receta (o texto libre), comida del día, puntaje de media en media estrella, "me encantó", nota y hasta 4 fotos. Si es una receta que ya habías hecho, aparece el ícono de "la volví a hacer". Cada entrada puede ser visible en el perfil o solo para vos.

- Se anota desde el botón "La hice" de cada receta, desde *Perfil → Diario → Anotar*, o solo: al marcar una comida del plan como hecha queda en el diario y la app pregunta "¿Cómo te salió?" (se puede apagar).
- El diario de cada persona está en su perfil, agrupado por mes. En el inicio, "Lo que cocinaron" muestra las últimas entradas de la gente que seguís.
- Las entradas se pueden denunciar y moderar como el resto del contenido.

**Recompensas por cumplir el plan**

- **Racha cocinando:** días seguidos con algo en el diario, anotado ese día o al siguiente (con un comodín por semana). Hitos de 3, 7, 14, 30, 60 y 100 días: +5, +15, +25, +50, +80 y +120 puntos y una notificación "¡N días seguidos cocinando!". Con 3 días o más aparece la medalla de la olla al lado del nombre.
- **Semana cumplida:** si hacés todas las comidas que planeaste para la semana (mínimo 5, planeadas antes de cada día), +30 puntos, la notificación "¡Cumpliste con tu planificación semanal!" y la medalla del calendario. El plan muestra arriba cuántas llevás.
- Anotar a mano suma +2 (hasta 3 por día). Lo que viene del plan ya suma +3 al marcarlo.
