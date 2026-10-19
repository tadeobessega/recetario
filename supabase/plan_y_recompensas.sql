-- =====================================================================
--  Plan semanal con avisos + rachas, puntos, niveles y desafíos
--  Se aplica una sola vez en Supabase → SQL Editor (todo es "if not exists" / "or replace").
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Preferencias de avisos y plan semanal
-- ---------------------------------------------------------------------
create table if not exists public.preferencias_avisos (
  user_id        uuid primary key references auth.users (id) on delete cascade,
  activos        boolean  not null default true,
  zona           text     not null default 'America/Argentina/Buenos_Aires',
  desayuno_dias  smallint not null default 1 check (desayuno_dias between 0 and 7),
  desayuno_hora  time     not null default '18:00',
  almuerzo_dias  smallint not null default 1 check (almuerzo_dias between 0 and 7),
  almuerzo_hora  time     not null default '18:00',
  merienda_dias  smallint not null default 0 check (merienda_dias between 0 and 7),
  merienda_hora  time     not null default '12:00',
  cena_dias      smallint not null default 0 check (cena_dias between 0 and 7),
  cena_hora      time     not null default '18:00',
  updated_at     timestamptz not null default now()
);
alter table public.preferencias_avisos enable row level security;

create table if not exists public.plan_comidas (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  fecha            date not null,
  momento          text not null check (momento in ('desayuno', 'almuerzo', 'merienda', 'cena')),
  receta_id        uuid references public.recetas (id) on delete set null,
  titulo           text check (titulo is null or char_length(titulo) <= 120),
  nota             text check (nota is null or char_length(nota) <= 300),
  aviso            text not null default 'predeterminado' check (aviso in ('predeterminado', 'personalizado', 'sin_aviso')),
  aviso_dias       smallint check (aviso_dias is null or aviso_dias between 0 and 7),
  aviso_hora       time,
  aviso_at         timestamptz,
  aviso_enviado_at timestamptz,
  hecha            boolean not null default false,
  created_at       timestamptz not null default now(),
  check (receta_id is not null or titulo is not null)
);
create index if not exists plan_user_fecha_idx on public.plan_comidas (user_id, fecha);
create index if not exists plan_aviso_idx on public.plan_comidas (aviso_at) where aviso_enviado_at is null;
alter table public.plan_comidas enable row level security;

create or replace function public.zona_de(u uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select zona from preferencias_avisos where user_id = u), 'America/Argentina/Buenos_Aires')
$$;

-- Calcula cuándo sale el aviso de cada comida (predeterminado, personalizado o sin aviso)
create or replace function public.app_plan_calcular_aviso() returns trigger
language plpgsql security definer set search_path = public as $$
declare p preferencias_avisos; dias int; hora time; zona text;
begin
  select * into p from preferencias_avisos where user_id = new.user_id;
  zona := coalesce(p.zona, 'America/Argentina/Buenos_Aires');
  -- se guarda el nombre de la receta: si después la borran, la comida sigue en el plan
  if new.titulo is null and new.receta_id is not null then
    select titulo into new.titulo from recetas where id = new.receta_id;
  end if;
  if new.aviso = 'sin_aviso' then
    new.aviso_at := null;
  else
    if new.aviso = 'personalizado' then
      dias := coalesce(new.aviso_dias, 0); hora := coalesce(new.aviso_hora, '18:00');
    else
      dias := case new.momento
        when 'desayuno' then coalesce(p.desayuno_dias, 1) when 'almuerzo' then coalesce(p.almuerzo_dias, 1)
        when 'merienda' then coalesce(p.merienda_dias, 0) else coalesce(p.cena_dias, 0) end;
      hora := case new.momento
        when 'desayuno' then coalesce(p.desayuno_hora, '18:00') when 'almuerzo' then coalesce(p.almuerzo_hora, '18:00')
        when 'merienda' then coalesce(p.merienda_hora, '12:00') else coalesce(p.cena_hora, '18:00') end;
    end if;
    new.aviso_at := ((new.fecha - dias) + hora) at time zone zona;
  end if;
  -- si se reprogramó a futuro, vuelve a avisar
  if tg_op = 'UPDATE' and new.aviso_at is distinct from old.aviso_at and (new.aviso_at is null or new.aviso_at > now()) then
    new.aviso_enviado_at := null;
  end if;
  return new;
end $$;
drop trigger if exists app_plan_calcular_aviso on public.plan_comidas;
create trigger app_plan_calcular_aviso before insert or update of fecha, momento, receta_id, aviso, aviso_dias, aviso_hora
  on public.plan_comidas for each row execute function public.app_plan_calcular_aviso();

-- Si cambian las preferencias, se recalculan los avisos pendientes
create or replace function public.app_prefs_recalcular() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update plan_comidas set aviso = aviso
   where user_id = new.user_id and aviso_enviado_at is null and fecha >= current_date - 1;
  return new;
end $$;
drop trigger if exists app_prefs_recalcular on public.preferencias_avisos;
create trigger app_prefs_recalcular after insert or update on public.preferencias_avisos
  for each row execute function public.app_prefs_recalcular();

-- ---------------------------------------------------------------------
-- 2. Notificaciones push (suscripciones, claves y cola de envío)
-- ---------------------------------------------------------------------
create table if not exists public.suscripciones_push (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  endpoint   text not null unique,
  p256dh     text not null,
  auth       text not null,
  created_at timestamptz not null default now()
);
alter table public.suscripciones_push enable row level security;

create table if not exists public.config_push (clave text primary key, valor text not null);
alter table public.config_push enable row level security;  -- sin reglas: solo la usa el servidor

create table if not exists public.cola_push (
  id         bigserial primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  titulo     text not null,
  cuerpo     text not null,
  url        text,
  intentos   int not null default 0,
  enviada_at timestamptz,
  error      text,
  created_at timestamptz not null default now()
);
create index if not exists cola_push_pendientes_idx on public.cola_push (created_at) where enviada_at is null;
alter table public.cola_push enable row level security;  -- sin reglas: solo la usa el servidor

create or replace function public.registrar_suscripcion(p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Necesitás iniciar sesión'; end if;
  insert into suscripciones_push (user_id, endpoint, p256dh, auth)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth;
end $$;

create or replace function public.borrar_suscripcion(p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from suscripciones_push where endpoint = p_endpoint and user_id = auth.uid()
$$;

create or replace function public.vapid_publica() returns text
language sql stable security definer set search_path = public as $$
  select valor from config_push where clave = 'vapid_publica'
$$;

-- ---------------------------------------------------------------------
-- 3. Disparo de recordatorios (lo corre pg_cron cada 5 minutos)
-- ---------------------------------------------------------------------
create or replace function public.procesar_recordatorios() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; zona text; hoy date; cuando text; frase text; texto text;
begin
  -- avisos muy atrasados (ej. la base estuvo pausada): se descartan sin molestar
  update plan_comidas set aviso_enviado_at = now()
   where aviso_enviado_at is null and aviso_at < now() - interval '12 hours';

  for r in
    select pc.*, coalesce(re.titulo, pc.titulo) as nombre, coalesce(pa.activos, true) as activos
    from plan_comidas pc
    left join recetas re on re.id = pc.receta_id
    left join preferencias_avisos pa on pa.user_id = pc.user_id
    where pc.aviso_enviado_at is null and pc.aviso_at <= now() and pc.aviso <> 'sin_aviso'
    for update of pc skip locked
  loop
    update plan_comidas set aviso_enviado_at = now() where id = r.id;
    continue when not r.activos or r.hecha;
    zona := zona_de(r.user_id);
    hoy := (now() at time zone zona)::date;
    cuando := case when r.fecha = hoy then 'Hoy' when r.fecha = hoy + 1 then 'Mañana'
                   else 'El ' || lower((array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'])[extract(isodow from r.fecha)::int]) || ' ' || to_char(r.fecha, 'DD/MM') end;
    frase := case r.momento when 'desayuno' then 'para el desayuno' when 'almuerzo' then 'para el almuerzo'
                            when 'merienda' then 'para la merienda' else 'para la cena' end;
    texto := cuando || ' ' || frase || ': ' || coalesce(r.nombre, 'lo que planeaste');
    insert into notificaciones (user_id, tipo, receta_id, detalle) values (r.user_id, 'plan', r.receta_id, texto);
    insert into cola_push (user_id, titulo, cuerpo, url)
    values (r.user_id, 'Tu plan de comidas', texto, case when r.receta_id is not null then '/?receta=' || r.receta_id else '/?plan=1' end);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 4. Rachas, puntos y niveles
-- ---------------------------------------------------------------------
create table if not exists public.progreso (
  user_id      uuid primary key references public.perfiles (id) on delete cascade,
  puntos       int not null default 0,
  racha_actual int not null default 0,
  racha_mejor  int not null default 0,
  ultimo_dia   date,
  desafios     int not null default 0,
  updated_at   timestamptz not null default now()
);
alter table public.progreso enable row level security;

create table if not exists public.puntos_movimientos (
  id         bigserial primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  motivo     text not null,
  puntos     int not null,
  ref        text not null,
  dia        date not null,
  created_at timestamptz not null default now(),
  unique (user_id, motivo, ref)
);
create index if not exists puntos_user_dia_idx on public.puntos_movimientos (user_id, motivo, dia);
alter table public.puntos_movimientos enable row level security;

create table if not exists public.actividad_diaria (
  user_id uuid not null references auth.users (id) on delete cascade,
  dia     date not null,
  primary key (user_id, dia)
);
alter table public.actividad_diaria enable row level security;

-- Niveles: 0 Pinche · 50 Ayudante · 150 Cocinero/a · 400 Chef · 1000 Gran chef
create or replace function public.nivel_de(p int) returns int
language sql immutable as $$
  select case when p >= 1000 then 4 when p >= 400 then 3 when p >= 150 then 2 when p >= 50 then 1 else 0 end
$$;
create or replace function public.nombre_nivel(n int) returns text
language sql immutable as $$
  select (array['Pinche', 'Ayudante', 'Cocinero/a', 'Chef', 'Gran chef'])[n + 1]
$$;

create or replace function public.sumar_puntos(u uuid, p_motivo text, p_puntos int, p_ref text, p_tope int default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare hoy date := (now() at time zone zona_de(u))::date; antes int; despues int; filas int;
begin
  if u is null then return false; end if;
  if p_tope is not null and
     (select count(*) from puntos_movimientos where user_id = u and motivo = p_motivo and dia = hoy) >= p_tope then
    return false;
  end if;
  insert into puntos_movimientos (user_id, motivo, puntos, ref, dia) values (u, p_motivo, p_puntos, p_ref, hoy)
  on conflict do nothing;
  get diagnostics filas = row_count;
  if filas = 0 then return false; end if;
  insert into progreso (user_id) values (u) on conflict do nothing;
  select puntos into antes from progreso where user_id = u;
  update progreso set puntos = puntos + p_puntos, updated_at = now() where user_id = u returning puntos into despues;
  if nivel_de(despues) > nivel_de(antes) then
    insert into notificaciones (user_id, tipo, detalle)
    values (u, 'logro', '¡Subiste de nivel! Ahora sos ' || nombre_nivel(nivel_de(despues)) || '.');
  end if;
  return true;
end $$;

create or replace function public.quitar_puntos(u uuid, p_motivo text, p_ref text) returns void
language plpgsql security definer set search_path = public as $$
declare pts int;
begin
  delete from puntos_movimientos where user_id = u and motivo = p_motivo and ref = p_ref returning puntos into pts;
  if pts is not null then
    update progreso set puntos = greatest(puntos - pts, 0), updated_at = now() where user_id = u;
  end if;
end $$;

-- Racha: días seguidos con actividad, con un comodín por semana (un día sin actividad no la corta)
create or replace function public.calcular_racha(u uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare d date := (now() at time zone zona_de(u))::date; primero date; racha int := 0; usadas date[] := '{}'; semana date; i int := 0;
begin
  select min(dia) into primero from actividad_diaria where user_id = u;
  if primero is null then return 0; end if;
  -- si hoy todavía no hubo actividad, se cuenta desde ayer
  if not exists (select 1 from actividad_diaria where user_id = u and dia = d) then d := d - 1; end if;
  while d >= primero and i < 2000 loop
    i := i + 1;
    if exists (select 1 from actividad_diaria where user_id = u and dia = d) then
      racha := racha + 1;
    else
      semana := date_trunc('week', d)::date;
      exit when semana = any (usadas);
      usadas := usadas || semana;
    end if;
    d := d - 1;
  end loop;
  return racha;
end $$;

-- Marca actividad del día, actualiza la racha y da los puntos por día y bonos de racha
create or replace function public.marcar_dia(u uuid) returns void
language plpgsql security definer set search_path = public as $$
declare hoy date := (now() at time zone zona_de(u))::date; filas int; r int;
begin
  if u is null then return; end if;
  insert into actividad_diaria (user_id, dia) values (u, hoy) on conflict do nothing;
  get diagnostics filas = row_count;
  insert into progreso (user_id) values (u) on conflict do nothing;
  if filas = 0 then return; end if;
  r := calcular_racha(u);
  update progreso set racha_actual = r, racha_mejor = greatest(racha_mejor, r), ultimo_dia = hoy, updated_at = now() where user_id = u;
  perform sumar_puntos(u, 'dia', 1, hoy::text);
  if r >= 7 then perform sumar_puntos(u, 'racha7', 10, (hoy - r + 1)::text); end if;
  if r >= 30 then perform sumar_puntos(u, 'racha30', 30, (hoy - r + 1)::text); end if;
end $$;

-- La llama la app al abrirse: registra el día y devuelve el progreso actualizado
create or replace function public.registrar_actividad() returns json
language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); p progreso; r int;
begin
  if u is null then return null; end if;
  perform marcar_dia(u);
  -- la racha puede haberse cortado aunque hoy ya hubiera actividad registrada
  r := calcular_racha(u);
  update progreso set racha_actual = r, racha_mejor = greatest(racha_mejor, r) where user_id = u returning * into p;
  return json_build_object('puntos', p.puntos, 'racha_actual', p.racha_actual, 'racha_mejor', p.racha_mejor,
                           'desafios', p.desafios, 'nivel', nivel_de(p.puntos), 'nombre_nivel', nombre_nivel(nivel_de(p.puntos)));
end $$;

-- ---------------------------------------------------------------------
-- 5. Desafíos semanales
-- ---------------------------------------------------------------------
create table if not exists public.desafios (
  id          uuid primary key default gen_random_uuid(),
  semana      date not null unique check (extract(isodow from semana) = 1),
  titulo      text not null check (char_length(titulo) between 3 and 80),
  descripcion text check (descripcion is null or char_length(descripcion) <= 300),
  creado_por  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);
alter table public.desafios enable row level security;
alter table public.publicaciones add column if not exists desafio_id uuid references public.desafios (id) on delete set null;

-- ---------------------------------------------------------------------
-- 6. Puntos automáticos por actividad (con topes diarios)
-- ---------------------------------------------------------------------
create or replace function public.app_puntos_recetas() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform sumar_puntos(new.user_id, 'receta', 10, new.id::text, 3);
    perform marcar_dia(new.user_id);
  else
    perform quitar_puntos(old.user_id, 'receta', old.id::text);
  end if;
  return null;
end $$;

create or replace function public.app_puntos_publicaciones() returns trigger
language plpgsql security definer set search_path = public as $$
declare d desafios; con_foto boolean; hoy date;
begin
  if tg_op = 'DELETE' then
    perform quitar_puntos(old.user_id, 'post', old.id::text);
    return null;
  end if;
  perform sumar_puntos(new.user_id, 'post', 5, new.id::text, 3);
  perform marcar_dia(new.user_id);
  if new.desafio_id is not null then
    select * into d from desafios where id = new.desafio_id;
    hoy := (now() at time zone zona_de(new.user_id))::date;
    con_foto := cardinality(new.fotos) > 0
                or exists (select 1 from recetas r where r.id = new.receta_id and cardinality(r.fotos) > 0);
    if d.id is not null and con_foto and hoy between d.semana and d.semana + 6 then
      if sumar_puntos(new.user_id, 'desafio', 25, d.id::text) then
        update progreso set desafios = desafios + 1 where user_id = new.user_id;
      end if;
    end if;
  end if;
  return null;
end $$;

create or replace function public.app_puntos_resenas() returns trigger
language plpgsql security definer set search_path = public as $$
declare duenio uuid;
begin
  if tg_op = 'DELETE' then
    perform quitar_puntos(old.user_id, 'resena', old.receta_id::text);
    select user_id into duenio from recetas where id = old.receta_id;
    perform quitar_puntos(duenio, 'recibio_resena', old.id::text);
    return null;
  end if;
  perform sumar_puntos(new.user_id, 'resena', 3, new.receta_id::text, 10);
  perform marcar_dia(new.user_id);
  select user_id into duenio from recetas where id = new.receta_id;
  if new.puntaje >= 4 and duenio is not null and duenio <> new.user_id then
    perform sumar_puntos(duenio, 'recibio_resena', 2, new.id::text);
  end if;
  return null;
end $$;

create or replace function public.app_puntos_comentarios() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    perform quitar_puntos(old.user_id, 'comentario', old.id::text);
  else
    perform sumar_puntos(new.user_id, 'comentario', 1, new.id::text, 10);
    perform marcar_dia(new.user_id);
  end if;
  return null;
end $$;

create or replace function public.app_puntos_guardadas() returns trigger
language plpgsql security definer set search_path = public as $$
declare duenio uuid; fila recetas_guardadas;
begin
  fila := case when tg_op = 'DELETE' then old else new end;
  select user_id into duenio from recetas where id = fila.receta_id;
  if duenio is null or duenio = fila.user_id then return null; end if;
  if tg_op = 'DELETE' then
    perform quitar_puntos(duenio, 'guardada', fila.user_id || ':' || fila.receta_id);
  else
    perform sumar_puntos(duenio, 'guardada', 2, fila.user_id || ':' || fila.receta_id);
  end if;
  return null;
end $$;

create or replace function public.app_puntos_plan() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.hecha and not old.hecha then
    perform sumar_puntos(new.user_id, 'plan', 3, new.id::text, 4);
    perform marcar_dia(new.user_id);
  elsif old.hecha and not new.hecha then
    perform quitar_puntos(new.user_id, 'plan', new.id::text);
  end if;
  return null;
end $$;

drop trigger if exists app_puntos_recetas on public.recetas;
create trigger app_puntos_recetas after insert or delete on public.recetas for each row execute function public.app_puntos_recetas();
drop trigger if exists app_puntos_publicaciones on public.publicaciones;
create trigger app_puntos_publicaciones after insert or delete on public.publicaciones for each row execute function public.app_puntos_publicaciones();
drop trigger if exists app_puntos_resenas on public.resenas;
create trigger app_puntos_resenas after insert or delete on public.resenas for each row execute function public.app_puntos_resenas();
drop trigger if exists app_puntos_comentarios on public.comentarios;
create trigger app_puntos_comentarios after insert or delete on public.comentarios for each row execute function public.app_puntos_comentarios();
drop trigger if exists app_puntos_guardadas on public.recetas_guardadas;
create trigger app_puntos_guardadas after insert or delete on public.recetas_guardadas for each row execute function public.app_puntos_guardadas();
drop trigger if exists app_puntos_plan on public.plan_comidas;
create trigger app_puntos_plan after update of hecha on public.plan_comidas for each row execute function public.app_puntos_plan();

-- ---------------------------------------------------------------------
-- 7. Notificaciones: tipos nuevos
-- ---------------------------------------------------------------------
alter table public.notificaciones drop constraint if exists notificaciones_tipo_valido;
alter table public.notificaciones add constraint notificaciones_tipo_valido
  check (tipo in ('seguidor', 'resena', 'puntaje', 'mensaje', 'comentario', 'moderacion', 'plan', 'logro'));

-- ---------------------------------------------------------------------
-- 8. Reglas de acceso
-- ---------------------------------------------------------------------
create policy prefs_ver     on public.preferencias_avisos for select to authenticated using (user_id = auth.uid());
create policy prefs_crear   on public.preferencias_avisos for insert to authenticated with check (user_id = auth.uid());
create policy prefs_editar  on public.preferencias_avisos for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy plan_ver      on public.plan_comidas for select to authenticated using (user_id = auth.uid());
create policy plan_crear    on public.plan_comidas for insert to authenticated
  with check (user_id = auth.uid() and (receta_id is null or exists (select 1 from public.recetas r where r.id = receta_id)));
create policy plan_editar   on public.plan_comidas for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy plan_quitar   on public.plan_comidas for delete to authenticated using (user_id = auth.uid());

create policy susc_ver      on public.suscripciones_push for select to authenticated using (user_id = auth.uid());

create policy progreso_ver  on public.progreso for select to authenticated using (true);
create policy puntos_ver    on public.puntos_movimientos for select to authenticated using (user_id = auth.uid());

create policy desafios_ver    on public.desafios for select to authenticated using (true);
create policy desafios_crear  on public.desafios for insert to authenticated with check (public.es_admin());
create policy desafios_editar on public.desafios for update to authenticated using (public.es_admin()) with check (public.es_admin());
create policy desafios_quitar on public.desafios for delete to authenticated using (public.es_admin());

-- Funciones internas: nadie las llama desde la API
revoke execute on function public.app_plan_calcular_aviso(), public.app_prefs_recalcular(), public.procesar_recordatorios(),
  public.sumar_puntos(uuid, text, int, text, int), public.quitar_puntos(uuid, text, text), public.calcular_racha(uuid),
  public.marcar_dia(uuid), public.zona_de(uuid), public.app_puntos_recetas(), public.app_puntos_publicaciones(),
  public.app_puntos_resenas(), public.app_puntos_comentarios(), public.app_puntos_guardadas(), public.app_puntos_plan()
  from public, anon, authenticated;
revoke execute on function public.registrar_suscripcion(text, text, text), public.borrar_suscripcion(text),
  public.vapid_publica(), public.registrar_actividad() from public, anon;
grant execute on function public.registrar_suscripcion(text, text, text), public.borrar_suscripcion(text),
  public.vapid_publica(), public.registrar_actividad() to authenticated;

-- Realtime para que el aviso del plan aparezca al instante (notificaciones ya está publicada)

-- ---------------------------------------------------------------------
-- 9. Primeros desafíos (6 semanas desde el lunes 19/10/2026)
-- ---------------------------------------------------------------------
insert into public.desafios (semana, titulo, descripcion) values
  ('2026-10-19', 'Algo con calabaza', 'Sopa, puré, budín o lo que se te ocurra: esta semana la calabaza es la protagonista.'),
  ('2026-10-26', 'La receta de la familia', 'Ese plato que te recuerda a la casa de tu abuela o a los domingos en familia.'),
  ('2026-11-02', 'Postre sin horno', 'Algo dulce que salga sin prender el horno: heladera, sartén o licuadora.'),
  ('2026-11-09', 'Legumbres al poder', 'Lentejas, garbanzos, porotos: mostrá cómo los cocinás vos.'),
  ('2026-11-16', 'Cociná con lo que hay', 'Armá un plato con lo que quedó en la heladera, sin ir a comprar.'),
  ('2026-11-23', 'Un desayuno distinto', 'Salí de la tostada de siempre: algo nuevo para arrancar el día.')
on conflict (semana) do nothing;

-- ---------------------------------------------------------------------
-- 10. Plantillas de plan semanal (lunes a domingo, con nombre)
-- ---------------------------------------------------------------------
create table if not exists public.plantillas_plan (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nombre     text not null check (char_length(btrim(nombre)) between 1 and 60),
  created_at timestamptz not null default now(),
  unique (user_id, nombre)
);
alter table public.plantillas_plan enable row level security;

create table if not exists public.plantilla_items (
  id           uuid primary key default gen_random_uuid(),
  plantilla_id uuid not null references public.plantillas_plan (id) on delete cascade,
  dia          smallint not null check (dia between 1 and 7),  -- 1 = lunes … 7 = domingo
  momento      text not null check (momento in ('desayuno', 'almuerzo', 'merienda', 'cena')),
  receta_id    uuid references public.recetas (id) on delete set null,
  titulo       text check (titulo is null or char_length(titulo) <= 120),
  nota         text check (nota is null or char_length(nota) <= 300),
  aviso        text not null default 'predeterminado' check (aviso in ('predeterminado', 'personalizado', 'sin_aviso')),
  aviso_dias   smallint check (aviso_dias is null or aviso_dias between 0 and 7),
  aviso_hora   time,
  check (receta_id is not null or titulo is not null)
);
create index if not exists plantilla_items_idx on public.plantilla_items (plantilla_id);
alter table public.plantilla_items enable row level security;

-- Qué plantilla está activa cada semana
create table if not exists public.plan_semanas (
  user_id      uuid not null references auth.users (id) on delete cascade,
  semana       date not null check (extract(isodow from semana) = 1),
  plantilla_id uuid references public.plantillas_plan (id) on delete set null,
  primary key (user_id, semana)
);
alter table public.plan_semanas enable row level security;

alter table public.plan_comidas add column if not exists plantilla_id uuid references public.plantillas_plan (id) on delete set null;

-- Activa una plantilla en una semana: reemplaza lo que había puesto otra plantilla
-- (lo que agregaste a mano y lo que ya marcaste como hecho se conserva)
create or replace function public.aplicar_plantilla(p_plantilla uuid, p_semana date) returns int
language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); lunes date := date_trunc('week', p_semana)::date; n int;
begin
  if u is null or not exists (select 1 from plantillas_plan where id = p_plantilla and user_id = u) then
    raise exception 'Esa plantilla no es tuya';
  end if;
  delete from plan_comidas where user_id = u and fecha between lunes and lunes + 6 and plantilla_id is not null and not hecha;
  insert into plan_comidas (user_id, fecha, momento, receta_id, titulo, nota, aviso, aviso_dias, aviso_hora, plantilla_id)
  select u, lunes + (i.dia - 1), i.momento, i.receta_id, i.titulo, i.nota, i.aviso, i.aviso_dias, i.aviso_hora, p_plantilla
  from plantilla_items i where i.plantilla_id = p_plantilla and (i.receta_id is not null or i.titulo is not null);
  get diagnostics n = row_count;
  insert into plan_semanas (user_id, semana, plantilla_id) values (u, lunes, p_plantilla)
  on conflict (user_id, semana) do update set plantilla_id = excluded.plantilla_id;
  return n;
end $$;

-- Desactiva la plantilla de una semana (saca lo que había puesto, salvo lo ya hecho)
create or replace function public.quitar_plantilla_semana(p_semana date) returns void
language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); lunes date := date_trunc('week', p_semana)::date;
begin
  if u is null then raise exception 'Necesitás iniciar sesión'; end if;
  delete from plan_comidas where user_id = u and fecha between lunes and lunes + 6 and plantilla_id is not null and not hecha;
  delete from plan_semanas where user_id = u and semana = lunes;
end $$;

-- Guarda la semana tal como está como una plantilla nueva
create or replace function public.guardar_semana_como_plantilla(p_semana date, p_nombre text) returns uuid
language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); lunes date := date_trunc('week', p_semana)::date; nueva uuid;
begin
  if u is null then raise exception 'Necesitás iniciar sesión'; end if;
  insert into plantillas_plan (user_id, nombre) values (u, btrim(p_nombre)) returning id into nueva;
  insert into plantilla_items (plantilla_id, dia, momento, receta_id, titulo, nota, aviso, aviso_dias, aviso_hora)
  select nueva, extract(isodow from fecha)::int, momento, receta_id, titulo, nota, aviso, aviso_dias, aviso_hora
  from plan_comidas where user_id = u and fecha between lunes and lunes + 6;
  update plan_comidas set plantilla_id = nueva where user_id = u and fecha between lunes and lunes + 6;
  insert into plan_semanas (user_id, semana, plantilla_id) values (u, lunes, nueva)
  on conflict (user_id, semana) do update set plantilla_id = excluded.plantilla_id;
  return nueva;
end $$;

create policy plantillas_todo on public.plantillas_plan for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy plantilla_items_todo on public.plantilla_items for all to authenticated
  using (exists (select 1 from public.plantillas_plan p where p.id = plantilla_id and p.user_id = auth.uid()))
  with check (exists (select 1 from public.plantillas_plan p where p.id = plantilla_id and p.user_id = auth.uid())
              and (receta_id is null or exists (select 1 from public.recetas r where r.id = receta_id)));
create policy plan_semanas_ver on public.plan_semanas for select to authenticated using (user_id = auth.uid());

revoke execute on function public.aplicar_plantilla(uuid, date), public.quitar_plantilla_semana(date),
  public.guardar_semana_como_plantilla(date, text) from public, anon;
grant execute on function public.aplicar_plantilla(uuid, date), public.quitar_plantilla_semana(date),
  public.guardar_semana_como_plantilla(date, text) to authenticated;

-- ---------------------------------------------------------------------
-- 11. Disparo automático cada 5 minutos (pg_cron + pg_net)
--     Procesa los avisos que vencieron y, si quedó algo en la cola, llama a la
--     Edge Function "enviar-push" (supabase/functions/enviar-push) para mandar las push.
--     La clave que va en Authorization es la "anon" del proyecto (es pública).
-- ---------------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule('avisos-plan', '*/5 * * * *', $cron$
  select public.procesar_recordatorios();
  select net.http_post(
    url     := 'https://nwkmdonyrqantliwlebi.supabase.co/functions/v1/enviar-push',
    headers := jsonb_build_object('Content-Type', 'application/json',
                 'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53a21kb255cnFhbnRsaXdsZWJpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MzU0NjAsImV4cCI6MjEwNTUxMTQ2MH0.lh28WPqEKoWBUycuaVf_6tnG0LK_sVLpxP0Yd6lhlxY'),
    body    := '{}'::jsonb)
  where exists (select 1 from public.cola_push where enviada_at is null and intentos < 5);
$cron$);
