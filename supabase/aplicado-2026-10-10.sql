-- =====================================================================
--  Cambios aplicados a la base de producción el 10/10/2026
-- =====================================================================
--  Ya están aplicados: este archivo es solo un registro, no hace falta
--  volver a correrlo. Se aplicaron sin borrar nada (sin DROP): las
--  reglas se modificaron y los triggers viejos quedaron desactivados.
-- =====================================================================

-- 1. Columna, tabla de clics e índices
alter table public.notificaciones add column if not exists puntaje numeric(2,1);
create table if not exists public.clics_enlaces (id bigserial primary key, receta_id text not null, tipo text not null, created_at timestamptz not null default now());
alter table public.clics_enlaces enable row level security;
create index if not exists publicaciones_user_fecha_idx  on public.publicaciones (user_id, created_at desc);
create index if not exists publicaciones_fecha_idx       on public.publicaciones (created_at desc);
create index if not exists publicaciones_receta_idx      on public.publicaciones (receta_id);
create index if not exists resenas_receta_idx            on public.resenas (receta_id);
create index if not exists seguidores_seguido_idx        on public.seguidores (seguido_id);
create index if not exists notificaciones_user_fecha_idx on public.notificaciones (user_id, created_at desc);
create index if not exists mensajes_conv_fecha_idx       on public.mensajes (conversacion_id, created_at);
create index if not exists recetas_publica_fecha_idx     on public.recetas (publica, created_at desc);
create index if not exists recetas_guardadas_receta_idx  on public.recetas_guardadas (receta_id);

-- 2. Funciones
create or replace function public.link_de_receta(p_receta text, p_tipo text) returns text
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

create or replace function public.conteo_guardadas(p_ids text[]) returns table (receta_id text, guardadas bigint)
language sql stable security definer set search_path = public as $$
  select g.receta_id::text, count(*)
  from recetas_guardadas g
  join recetas r on r.id = g.receta_id
  where r.publica and g.receta_id::text = any (p_ids)
  group by g.receta_id
$$;
revoke execute on function public.conteo_guardadas(text[]) from public, anon;
grant execute on function public.conteo_guardadas(text[]) to authenticated;

-- 3. Tipos de notificación: se suma 'puntaje'
alter table public.notificaciones drop constraint notificaciones_tipo_check;
alter table public.notificaciones add constraint notificaciones_tipo_valido check (tipo in ('seguidor', 'resena', 'puntaje', 'mensaje'));

-- 4. Notificaciones nuevas (renuevan el aviso existente en vez de duplicarlo)
create or replace function public.app_notif_seguidor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update notificaciones set leida = false, created_at = now()
   where user_id = new.seguido_id and actor_id = new.seguidor_id and tipo = 'seguidor';
  if not found then
    insert into notificaciones (user_id, actor_id, tipo)
    values (new.seguido_id, new.seguidor_id, 'seguidor');
  end if;
  return new;
end $$;

create or replace function public.app_notif_resena() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  duenio uuid;
  nuevo_tipo text := case when coalesce(btrim(new.texto), '') <> '' then 'resena' else 'puntaje' end;
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
  update notificaciones set tipo = nuevo_tipo, puntaje = new.puntaje, created_at = now()
   where user_id = duenio and actor_id = new.user_id and receta_id = new.receta_id
     and tipo in ('resena', 'puntaje') and not leida;
  if not found then
    insert into notificaciones (user_id, actor_id, tipo, receta_id, puntaje)
    values (duenio, new.user_id, nuevo_tipo, new.receta_id, new.puntaje);
  end if;
  return new;
end $$;

create trigger app_notif_seguidor after insert on public.seguidores
  for each row execute function public.app_notif_seguidor();
create trigger app_notif_resena after insert or update on public.resenas
  for each row execute function public.app_notif_resena();

-- 5. Triggers viejos desactivados (siguen en la base, apagados)
--    - trg_recetas_generar_post: publicaba sola cada receta pública; ahora la app pregunta
--    - trg_notificar_*: avisos sin puntaje y duplicados; trg_notificar_mensaje: los mensajes
--      se avisan en su propio ícono, no en la campana
alter table public.seguidores disable trigger trg_notificar_seguidor;
alter table public.resenas   disable trigger trg_notificar_resena;
alter table public.mensajes  disable trigger trg_notificar_mensaje;
alter table public.recetas   disable trigger trg_recetas_generar_post;

-- 6. Reglas de acceso ajustadas
alter policy "agregar a mi coleccion" on public.coleccion_recetas
  with check (exists (select 1 from public.colecciones c where c.id = coleccion_id and c.user_id = auth.uid())
              and exists (select 1 from public.recetas r where r.id = receta_id));
alter policy resenas_select on public.resenas
  using (exists (select 1 from public.recetas r where r.id = receta_id));
alter policy resenas_insert on public.resenas
  with check (user_id = auth.uid()
              and exists (select 1 from public.recetas r where r.id = receta_id and r.user_id <> auth.uid()));
alter policy resenas_update on public.resenas
  using (user_id = auth.uid())
  with check (user_id = auth.uid()
              and exists (select 1 from public.recetas r where r.id = receta_id and r.user_id <> auth.uid()));
alter policy publicaciones_insert on public.publicaciones
  with check (user_id = auth.uid() and exists (select 1 from public.recetas r where r.id = receta_id and r.publica));
create policy publicaciones_update on public.publicaciones for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 7. Ajustes de seguridad sugeridos por Supabase
revoke execute on function public.app_notif_resena(), public.app_notif_seguidor(), public.crear_perfil_nuevo(),
  public.notificar_mensaje(), public.notificar_resena(), public.notificar_seguidor(), public.recetas_generar_post()
  from public, anon, authenticated;
alter function public.resenas_set_updated_at() set search_path = public;
alter function public.hay_seguimiento_mutuo(uuid, uuid) set search_path = public;
alter function public.mensajes_bloquear_edicion() set search_path = public;
alter function public.resenas_bloquear_autorresena() set search_path = public;
alter view public.recetas_ranking set (security_invoker = true);

-- 8. Fotos en recetas (hasta 8) y en posts (hasta 4)
alter table public.recetas       add column if not exists fotos text[] not null default '{}';
alter table public.publicaciones add column if not exists fotos text[] not null default '{}';
alter table public.recetas       add constraint recetas_fotos_max check (cardinality(fotos) <= 8);
alter table public.publicaciones add constraint publicaciones_fotos_max check (cardinality(fotos) <= 4);
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
create policy "fotos lectura" on storage.objects for select using (bucket_id = 'fotos');
create policy "fotos subir" on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "fotos borrar" on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);

-- =====================================================================
-- 9. Comentarios, denuncias, moderación y sanciones; posts sin receta
-- =====================================================================
update public.publicaciones set fotos = '{}' where receta_id is not null and cardinality(fotos) > 0;
alter table public.publicaciones alter column receta_id drop not null;
alter table public.publicaciones add constraint publicaciones_con_contenido check (receta_id is not null or cardinality(fotos) > 0) not valid;
alter table public.publicaciones add column if not exists moderada boolean not null default false;
alter table public.recetas       add column if not exists moderada boolean not null default false;
alter table public.resenas       add column if not exists moderada boolean not null default false;

create table if not exists public.administradores (user_id uuid primary key references auth.users (id) on delete cascade, created_at timestamptz not null default now());
alter table public.administradores enable row level security;
insert into public.administradores (user_id) values ('95ad4613-055d-4415-aff2-2e46811d553d') on conflict do nothing;  -- tadeo

create table if not exists public.comentarios (
  id uuid primary key default gen_random_uuid(),
  publicacion_id uuid not null references public.publicaciones (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  texto text not null check (char_length(btrim(texto)) between 1 and 1000),
  moderada boolean not null default false,
  created_at timestamptz not null default now());
create index if not exists comentarios_post_idx on public.comentarios (publicacion_id, created_at);
alter table public.comentarios enable row level security;

create table if not exists public.denuncias (
  id uuid primary key default gen_random_uuid(),
  denunciante_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tipo text not null check (tipo in ('publicacion', 'comentario', 'receta', 'resena')),
  objeto_id uuid not null,
  autor_id uuid references auth.users (id) on delete cascade,
  motivo text not null check (motivo in ('ofensivo', 'foto', 'acoso', 'spam', 'otro')),
  detalle text check (detalle is null or char_length(detalle) <= 500),
  estado text not null default 'pendiente' check (estado in ('pendiente', 'aceptada', 'desestimada')),
  resolucion text, resuelta_por uuid references auth.users (id) on delete set null, resuelta_at timestamptz,
  created_at timestamptz not null default now(),
  unique (denunciante_id, tipo, objeto_id));
create index if not exists denuncias_estado_idx on public.denuncias (estado, created_at desc);
alter table public.denuncias enable row level security;

create table if not exists public.sanciones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  tipo text not null check (tipo in ('advertencia', 'suspension', 'bloqueo')),
  motivo text, hasta timestamptz,
  denuncia_id uuid references public.denuncias (id) on delete set null,
  creada_por uuid references auth.users (id) on delete set null,
  levantada boolean not null default false,
  created_at timestamptz not null default now());
create index if not exists sanciones_user_idx on public.sanciones (user_id);
alter table public.sanciones enable row level security;

alter table public.notificaciones add column if not exists publicacion_id uuid references public.publicaciones (id) on delete cascade;
alter table public.notificaciones add column if not exists detalle text;
alter table public.notificaciones drop constraint notificaciones_tipo_valido;
alter table public.notificaciones add constraint notificaciones_tipo_valido check (tipo in ('seguidor', 'resena', 'puntaje', 'mensaje', 'comentario', 'moderacion'));
alter table public.notificaciones alter column actor_id drop not null;

-- Funciones, triggers y reglas de moderación: ver supabase/moderacion.sql
