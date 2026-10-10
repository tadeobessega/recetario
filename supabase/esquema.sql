-- =====================================================================
--  Mi Recetario · esquema completo de la base (Supabase / Postgres)
-- =====================================================================
--  Cómo usarlo: Supabase → SQL Editor → New query → pegar todo → Run.
--
--  Se puede correr las veces que haga falta: crea lo que falta y deja
--  las reglas de acceso (RLS) exactamente como las espera la app.
--  No borra recetas, perfiles ni ningún otro dato.
--
--  Importante: reemplaza TODAS las reglas de acceso (policies) de las
--  tablas de la app por las de este archivo, para que no quede ninguna
--  regla vieja más permisiva dando vueltas.
-- =====================================================================

begin;

-- Devuelve el tipo de la columna id de una tabla (uuid, bigint...), para
-- que las claves foráneas coincidan con lo que ya existe en tu base.
create or replace function pg_temp.tipo_id(tabla text) returns text
language sql stable as $$
  select format_type(a.atttypid, a.atttypmod)
  from pg_attribute a
  where a.attrelid = to_regclass(tabla) and a.attname = 'id' and not a.attisdropped
$$;

-- ---------------------------------------------------------------------
-- 1. Columnas nuevas en tablas que ya existían
-- ---------------------------------------------------------------------
alter table public.recetas  add column if not exists publica     boolean     not null default true;
alter table public.recetas  add column if not exists tipo_comida text;
alter table public.recetas  add column if not exists porciones   integer;
alter table public.recetas  add column if not exists created_at  timestamptz not null default now();
alter table public.perfiles add column if not exists bio         text;
alter table public.perfiles add column if not exists link        text;
alter table public.perfiles add column if not exists avatar_url  text;
alter table public.perfiles add column if not exists created_at  timestamptz not null default now();

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'recetas_tipo_comida_valido') then
    alter table public.recetas add constraint recetas_tipo_comida_valido
      check (tipo_comida is null or tipo_comida in ('almuerzo_cena', 'desayuno_merienda', 'postre')) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'recetas_porciones_valida') then
    alter table public.recetas add constraint recetas_porciones_valida
      check (porciones is null or porciones between 1 and 200) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'perfiles_bio_largo') then
    alter table public.perfiles add constraint perfiles_bio_largo
      check (bio is null or char_length(bio) <= 280) not valid;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Tablas nuevas (solo se crean si no existen)
-- ---------------------------------------------------------------------
create table if not exists public.colecciones (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nombre      text not null check (char_length(nombre) between 1 and 60),
  descripcion text check (descripcion is null or char_length(descripcion) <= 200),
  publica     boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.seguidores (
  seguidor_id uuid not null references auth.users (id) on delete cascade,
  seguido_id  uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (seguidor_id, seguido_id),
  check (seguidor_id <> seguido_id)
);

create table if not exists public.conversaciones (
  id         uuid primary key default gen_random_uuid(),
  usuario_a  uuid not null references auth.users (id) on delete cascade,
  usuario_b  uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (usuario_a, usuario_b),
  check (usuario_a < usuario_b)
);

-- Registro de clics en los enlaces de salida (/go). Solo lo escribe la
-- función link_de_receta; lo ves desde el panel de Supabase.
create table if not exists public.clics_enlaces (
  id         bigserial primary key,
  receta_id  text not null,
  tipo       text not null,
  created_at timestamptz not null default now()
);

-- Tablas que apuntan a recetas / colecciones / conversaciones: se crean con
-- el mismo tipo de id que ya tenga cada tabla.
do $$
declare
  t_receta text := pg_temp.tipo_id('public.recetas');
  t_col    text := pg_temp.tipo_id('public.colecciones');
  t_conv   text := pg_temp.tipo_id('public.conversaciones');
begin
  execute format($f$
    create table if not exists public.recetas_guardadas (
      user_id    uuid not null references auth.users (id) on delete cascade,
      receta_id  %1$s not null references public.recetas (id) on delete cascade,
      created_at timestamptz not null default now(),
      primary key (user_id, receta_id)
    )$f$, t_receta);

  execute format($f$
    create table if not exists public.coleccion_recetas (
      coleccion_id %2$s not null references public.colecciones (id) on delete cascade,
      receta_id    %1$s not null references public.recetas (id) on delete cascade,
      created_at   timestamptz not null default now(),
      primary key (coleccion_id, receta_id)
    )$f$, t_receta, t_col);

  execute format($f$
    create table if not exists public.colecciones_guardadas (
      user_id      uuid not null references auth.users (id) on delete cascade,
      coleccion_id %1$s not null references public.colecciones (id) on delete cascade,
      created_at   timestamptz not null default now(),
      primary key (user_id, coleccion_id)
    )$f$, t_col);

  execute format($f$
    create table if not exists public.resenas (
      id         uuid primary key default gen_random_uuid(),
      receta_id  %1$s not null references public.recetas (id) on delete cascade,
      user_id    uuid not null references auth.users (id) on delete cascade,
      puntaje    numeric(2,1) not null,
      texto      text check (texto is null or char_length(texto) <= 1000),
      created_at timestamptz not null default now(),
      unique (receta_id, user_id)
    )$f$, t_receta);

  execute format($f$
    create table if not exists public.publicaciones (
      id          uuid primary key default gen_random_uuid(),
      user_id     uuid not null references auth.users (id) on delete cascade,
      receta_id   %1$s not null references public.recetas (id) on delete cascade,
      descripcion text check (descripcion is null or char_length(descripcion) <= 500),
      created_at  timestamptz not null default now()
    )$f$, t_receta);

  execute format($f$
    create table if not exists public.notificaciones (
      id         uuid primary key default gen_random_uuid(),
      user_id    uuid not null references auth.users (id) on delete cascade,
      actor_id   uuid references auth.users (id) on delete cascade,
      tipo       text not null,
      receta_id  %1$s references public.recetas (id) on delete cascade,
      puntaje    numeric(2,1),
      leida      boolean not null default false,
      created_at timestamptz not null default now()
    )$f$, t_receta);

  execute format($f$
    create table if not exists public.mensajes (
      id              uuid primary key default gen_random_uuid(),
      conversacion_id %1$s not null references public.conversaciones (id) on delete cascade,
      remitente_id    uuid not null references auth.users (id) on delete cascade,
      texto           text not null check (char_length(texto) between 1 and 2000),
      leido           boolean not null default false,
      created_at      timestamptz not null default now()
    )$f$, t_conv);
end $$;

-- Columnas que pueden faltar si estas tablas ya existían de antes
alter table public.seguidores            add column if not exists created_at timestamptz not null default now();
alter table public.recetas_guardadas     add column if not exists created_at timestamptz not null default now();
alter table public.coleccion_recetas     add column if not exists created_at timestamptz not null default now();
alter table public.colecciones_guardadas add column if not exists created_at timestamptz not null default now();
alter table public.publicaciones         add column if not exists descripcion text;
alter table public.notificaciones        add column if not exists puntaje numeric(2,1);
alter table public.notificaciones        add column if not exists leida boolean not null default false;
alter table public.mensajes              add column if not exists leido boolean not null default false;

-- Puntaje de 0 a 5 en pasos de 0,5 (si la columna era entera, se convierte)
do $$
declare c record;
begin
  if (select format_type(atttypid, atttypmod) from pg_attribute
      where attrelid = 'public.resenas'::regclass and attname = 'puntaje') not like 'numeric%' then
    alter table public.resenas alter column puntaje type numeric(2,1) using puntaje::numeric(2,1);
  end if;
  for c in select conname from pg_constraint
           where conrelid = 'public.resenas'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%puntaje%' and conname <> 'resenas_puntaje_medio'
  loop
    execute format('alter table public.resenas drop constraint %I', c.conname);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'resenas_puntaje_medio') then
    alter table public.resenas add constraint resenas_puntaje_medio
      check (puntaje between 0 and 5 and puntaje * 2 = trunc(puntaje * 2));
  end if;
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.resenas'::regclass and contype = 'u'
                   and pg_get_constraintdef(oid) ilike '%receta_id%user_id%') then
    alter table public.resenas add constraint resenas_una_por_persona unique (receta_id, user_id);
  end if;

  -- Tipos de notificación válidos (se suma 'puntaje' a lo que hubiera)
  for c in select conname from pg_constraint
           where conrelid = 'public.notificaciones'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%tipo%' and conname <> 'notificaciones_tipo_valido'
  loop
    execute format('alter table public.notificaciones drop constraint %I', c.conname);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'notificaciones_tipo_valido') then
    alter table public.notificaciones add constraint notificaciones_tipo_valido
      check (tipo in ('seguidor', 'resena', 'puntaje', 'mensaje')) not valid;
  end if;
end $$;

-- Índices para que la timeline, reseñas y mensajes respondan rápido
create index if not exists publicaciones_user_fecha_idx  on public.publicaciones (user_id, created_at desc);
create index if not exists publicaciones_fecha_idx       on public.publicaciones (created_at desc);
create index if not exists publicaciones_receta_idx      on public.publicaciones (receta_id);
create index if not exists resenas_receta_idx            on public.resenas (receta_id);
create index if not exists seguidores_seguido_idx        on public.seguidores (seguido_id);
create index if not exists notificaciones_user_fecha_idx on public.notificaciones (user_id, created_at desc);
create index if not exists mensajes_conv_fecha_idx       on public.mensajes (conversacion_id, created_at);
create index if not exists recetas_publica_fecha_idx     on public.recetas (publica, created_at desc);
create index if not exists recetas_guardadas_receta_idx  on public.recetas_guardadas (receta_id);

-- ---------------------------------------------------------------------
-- 3. Funciones auxiliares
-- ---------------------------------------------------------------------
-- ¿Se siguen mutuamente? (condición para poder escribirse mensajes)
create or replace function public.es_mutuo(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from seguidores where seguidor_id = a and seguido_id = b)
     and exists (select 1 from seguidores where seguidor_id = b and seguido_id = a)
$$;
revoke all on function public.es_mutuo(uuid, uuid) from public;
grant execute on function public.es_mutuo(uuid, uuid) to authenticated;

-- ¿Ese nombre de usuario está libre? (se usa en el registro, antes de tener sesión)
drop function if exists public.usuario_disponible(text);
create function public.usuario_disponible(p_usuario text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from perfiles where lower(usuario) = lower(p_usuario))
$$;
grant execute on function public.usuario_disponible(text) to anon, authenticated;

-- Destino real de un enlace de receta pública (lo usa el worker de /go).
-- Además registra el clic, para que sepas cuántas salidas genera cada receta.
do $$
declare f record;
begin
  for f in select oid::regprocedure as firma from pg_proc
           where proname = 'link_de_receta' and pronamespace = 'public'::regnamespace
  loop
    execute 'drop function ' || f.firma;
  end loop;
end $$;

create function public.link_de_receta(p_receta text, p_tipo text) returns text
language plpgsql security definer set search_path = public as $$
declare destino text;
begin
  select case p_tipo when 'ig' then link_ig when 'tt' then link_tiktok when 'web' then link_otro end
    into destino
  from recetas
  where id::text = p_receta and publica;

  if destino is null or destino !~* '^https?://' then
    return null;
  end if;

  insert into clics_enlaces (receta_id, tipo) values (p_receta, p_tipo);
  return destino;
end $$;
grant execute on function public.link_de_receta(text, text) to anon, authenticated;

-- Cuántas veces se guardó cada receta pública (para las sugerencias "con llegada").
drop function if exists public.conteo_guardadas(text[]);
create function public.conteo_guardadas(p_ids text[]) returns table (receta_id text, guardadas bigint)
language sql stable security definer set search_path = public as $$
  select g.receta_id::text, count(*)
  from recetas_guardadas g
  join recetas r on r.id = g.receta_id
  where r.publica and g.receta_id::text = any (p_ids)
  group by g.receta_id
$$;
grant execute on function public.conteo_guardadas(text[]) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Notificaciones automáticas (nuevo seguidor, reseña, puntaje)
-- ---------------------------------------------------------------------
-- Se quitan triggers viejos que escribían notificaciones o publicaban
-- recetas solas, para que no haya avisos ni posts duplicados.
do $$
declare t record;
begin
  for t in
    select tg.tgname, c.relname
    from pg_trigger tg
    join pg_class c on c.oid = tg.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = tg.tgfoid
    where n.nspname = 'public' and not tg.tgisinternal
      and c.relname in ('seguidores', 'resenas', 'mensajes', 'recetas')
      and tg.tgname not like 'app\_%'
      and (p.prosrc ilike '%notificaciones%'
           or (c.relname = 'recetas' and p.prosrc ilike '%publicaciones%'))
  loop
    execute format('drop trigger %I on public.%I', t.tgname, t.relname);
  end loop;
end $$;

create or replace function public.app_notif_seguidor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- si alguien deja de seguir y vuelve a seguir, queda un solo aviso
  delete from notificaciones
   where user_id = new.seguido_id and actor_id = new.seguidor_id and tipo = 'seguidor';
  insert into notificaciones (user_id, actor_id, tipo)
  values (new.seguido_id, new.seguidor_id, 'seguidor');
  return new;
end $$;

drop trigger if exists app_notif_seguidor on public.seguidores;
create trigger app_notif_seguidor after insert on public.seguidores
  for each row execute function public.app_notif_seguidor();

create or replace function public.app_notif_resena() returns trigger
language plpgsql security definer set search_path = public as $$
declare duenio uuid;
begin
  select user_id into duenio from recetas where id = new.receta_id;
  if duenio is null or duenio = new.user_id then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.puntaje is not distinct from old.puntaje
     and coalesce(new.texto, '') = coalesce(old.texto, '') then
    return new;
  end if;

  delete from notificaciones
   where user_id = duenio and actor_id = new.user_id and receta_id = new.receta_id
     and tipo in ('resena', 'puntaje') and not leida;

  insert into notificaciones (user_id, actor_id, tipo, receta_id, puntaje)
  values (duenio, new.user_id,
          case when coalesce(btrim(new.texto), '') <> '' then 'resena' else 'puntaje' end,
          new.receta_id, new.puntaje);
  return new;
end $$;

drop trigger if exists app_notif_resena on public.resenas;
create trigger app_notif_resena after insert or update on public.resenas
  for each row execute function public.app_notif_resena();

-- Un mensaje enviado no puede cambiar de texto, remitente ni conversación
-- (solo se puede marcar como leído).
create or replace function public.app_mensaje_inmutable() returns trigger
language plpgsql as $$
begin
  if new.texto is distinct from old.texto
     or new.remitente_id is distinct from old.remitente_id
     or new.conversacion_id is distinct from old.conversacion_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Un mensaje enviado no se puede modificar';
  end if;
  return new;
end $$;

drop trigger if exists app_mensaje_inmutable on public.mensajes;
create trigger app_mensaje_inmutable before update on public.mensajes
  for each row execute function public.app_mensaje_inmutable();

-- ---------------------------------------------------------------------
-- 5. Reglas de acceso (Row Level Security)
-- ---------------------------------------------------------------------
-- Se borran las reglas anteriores de estas tablas y se crean las de abajo.
do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename in (
             'perfiles', 'recetas', 'recetas_guardadas', 'colecciones', 'coleccion_recetas',
             'colecciones_guardadas', 'seguidores', 'resenas', 'publicaciones',
             'notificaciones', 'conversaciones', 'mensajes', 'clics_enlaces')
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

alter table public.perfiles              enable row level security;
alter table public.recetas               enable row level security;
alter table public.recetas_guardadas     enable row level security;
alter table public.colecciones           enable row level security;
alter table public.coleccion_recetas     enable row level security;
alter table public.colecciones_guardadas enable row level security;
alter table public.seguidores            enable row level security;
alter table public.resenas               enable row level security;
alter table public.publicaciones         enable row level security;
alter table public.notificaciones        enable row level security;
alter table public.conversaciones        enable row level security;
alter table public.mensajes              enable row level security;
alter table public.clics_enlaces         enable row level security;  -- sin reglas: nadie lee ni escribe desde la app

-- Perfiles: públicos; cada quien edita el suyo
create policy perfiles_ver       on public.perfiles for select to anon, authenticated using (true);
create policy perfiles_crear     on public.perfiles for insert to authenticated with check (id = auth.uid());
create policy perfiles_editar    on public.perfiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Recetas: las públicas las ve cualquiera; las privadas, solo su dueño
create policy recetas_ver        on public.recetas for select to anon, authenticated using (publica or user_id = auth.uid());
create policy recetas_crear      on public.recetas for insert to authenticated with check (user_id = auth.uid());
create policy recetas_editar     on public.recetas for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy recetas_borrar     on public.recetas for delete to authenticated using (user_id = auth.uid());

-- Recetas guardadas: cada quien ve y maneja las suyas
create policy guardadas_ver      on public.recetas_guardadas for select to authenticated using (user_id = auth.uid());
create policy guardadas_crear    on public.recetas_guardadas for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.recetas r where r.id = receta_id));
create policy guardadas_borrar   on public.recetas_guardadas for delete to authenticated using (user_id = auth.uid());

-- Colecciones
create policy colecciones_ver    on public.colecciones for select to anon, authenticated using (publica or user_id = auth.uid());
create policy colecciones_crear  on public.colecciones for insert to authenticated with check (user_id = auth.uid());
create policy colecciones_editar on public.colecciones for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy colecciones_borrar on public.colecciones for delete to authenticated using (user_id = auth.uid());

-- Recetas dentro de colecciones (las privadas igual quedan ocultas por la regla de recetas)
create policy col_recetas_ver    on public.coleccion_recetas for select to anon, authenticated
  using (exists (select 1 from public.colecciones c where c.id = coleccion_id));
create policy col_recetas_crear  on public.coleccion_recetas for insert to authenticated
  with check (exists (select 1 from public.colecciones c where c.id = coleccion_id and c.user_id = auth.uid())
              and exists (select 1 from public.recetas r where r.id = receta_id));
create policy col_recetas_borrar on public.coleccion_recetas for delete to authenticated
  using (exists (select 1 from public.colecciones c where c.id = coleccion_id and c.user_id = auth.uid()));

-- Colecciones de otras personas guardadas
create policy col_guardadas_ver    on public.colecciones_guardadas for select to authenticated using (user_id = auth.uid());
create policy col_guardadas_crear  on public.colecciones_guardadas for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.colecciones c where c.id = coleccion_id and c.publica));
create policy col_guardadas_borrar on public.colecciones_guardadas for delete to authenticated using (user_id = auth.uid());

-- Seguidores y seguidos: públicos
create policy seguidores_ver     on public.seguidores for select to anon, authenticated using (true);
create policy seguidores_seguir  on public.seguidores for insert to authenticated with check (seguidor_id = auth.uid());
create policy seguidores_dejar   on public.seguidores for delete to authenticated using (seguidor_id = auth.uid());

-- Reseñas: públicas para quien puede ver la receta; no se puede calificar la propia
create policy resenas_ver        on public.resenas for select to anon, authenticated
  using (exists (select 1 from public.recetas r where r.id = receta_id));
create policy resenas_crear      on public.resenas for insert to authenticated
  with check (user_id = auth.uid()
              and exists (select 1 from public.recetas r where r.id = receta_id and r.user_id <> auth.uid()));
create policy resenas_editar     on public.resenas for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid()
              and exists (select 1 from public.recetas r where r.id = receta_id and r.user_id <> auth.uid()));
create policy resenas_borrar     on public.resenas for delete to authenticated using (user_id = auth.uid());

-- Publicaciones (posts): se ven si la receta es pública
create policy posts_ver          on public.publicaciones for select to anon, authenticated
  using (user_id = auth.uid() or exists (select 1 from public.recetas r where r.id = receta_id and r.publica));
create policy posts_crear        on public.publicaciones for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.recetas r where r.id = receta_id and r.publica));
create policy posts_editar       on public.publicaciones for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy posts_borrar       on public.publicaciones for delete to authenticated using (user_id = auth.uid());

-- Notificaciones: solo las propias (las crean los triggers de arriba)
create policy notif_ver          on public.notificaciones for select to authenticated using (user_id = auth.uid());
create policy notif_leer         on public.notificaciones for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notif_borrar       on public.notificaciones for delete to authenticated using (user_id = auth.uid());

-- Conversaciones y mensajes: solo entre personas que se siguen mutuamente
create policy conv_ver           on public.conversaciones for select to authenticated
  using (auth.uid() in (usuario_a, usuario_b));
create policy conv_crear         on public.conversaciones for insert to authenticated
  with check (auth.uid() in (usuario_a, usuario_b) and usuario_a < usuario_b and public.es_mutuo(usuario_a, usuario_b));

create policy mensajes_ver       on public.mensajes for select to authenticated
  using (exists (select 1 from public.conversaciones c
                 where c.id = conversacion_id and auth.uid() in (c.usuario_a, c.usuario_b)));
create policy mensajes_enviar    on public.mensajes for insert to authenticated
  with check (remitente_id = auth.uid()
              and exists (select 1 from public.conversaciones c
                          where c.id = conversacion_id
                            and auth.uid() in (c.usuario_a, c.usuario_b)
                            and public.es_mutuo(c.usuario_a, c.usuario_b)));
create policy mensajes_marcar_leido on public.mensajes for update to authenticated
  using (remitente_id <> auth.uid()
         and exists (select 1 from public.conversaciones c
                     where c.id = conversacion_id and auth.uid() in (c.usuario_a, c.usuario_b)));

-- ---------------------------------------------------------------------
-- 6. Tiempo real (mensajes y notificaciones al instante)
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'mensajes') then
      alter publication supabase_realtime add table public.mensajes;
    end if;
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notificaciones') then
      alter publication supabase_realtime add table public.notificaciones;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 7. Primera carga de posts
-- ---------------------------------------------------------------------
-- Solo la primera vez (si todavía no hay ningún post): cada receta pública
-- existente pasa a ser un post de su autor, así la timeline no arranca vacía.
-- De acá en adelante, los posts los crea cada persona al guardar una receta.
do $$
begin
  if not exists (select 1 from public.publicaciones) then
    insert into public.publicaciones (user_id, receta_id, created_at)
    select r.user_id, r.id, coalesce(r.created_at, now())
    from public.recetas r
    where r.publica and r.user_id is not null;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 8. Fotos de recetas (hasta 8) y de posts (hasta 4)
-- ---------------------------------------------------------------------
alter table public.recetas       add column if not exists fotos text[] not null default '{}';
alter table public.publicaciones add column if not exists fotos text[] not null default '{}';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'recetas_fotos_max') then
    alter table public.recetas add constraint recetas_fotos_max check (cardinality(fotos) <= 8);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'publicaciones_fotos_max') then
    alter table public.publicaciones add constraint publicaciones_fotos_max check (cardinality(fotos) <= 4);
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'fotos lectura') then
    create policy "fotos lectura" on storage.objects for select using (bucket_id = 'fotos');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'fotos subir') then
    create policy "fotos subir" on storage.objects for insert to authenticated
      with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'fotos borrar') then
    create policy "fotos borrar" on storage.objects for delete to authenticated
      using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);
  end if;
end $$;

commit;
