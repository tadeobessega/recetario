-- =====================================================================
--  Diario de cocina (estilo Letterboxd) + recompensas por cumplir el plan
--  · Cada comida que hacés queda anotada con fecha, puntaje, "me encantó", nota y fotos.
--  · Marcar una comida del plan como hecha la anota sola en el diario.
--  · Racha cocinando: días seguidos con algo en el diario (un comodín por semana).
--  · Semana cumplida: hiciste todo lo que planeaste para la semana (mínimo 5 comidas).
--  Aplicado en producción el 22/10/2026.
-- =====================================================================

alter table public.progreso add column if not exists racha_cocina       int not null default 0;
alter table public.progreso add column if not exists racha_cocina_mejor int not null default 0;
alter table public.progreso add column if not exists semanas_cumplidas  int not null default 0;

create table if not exists public.diario (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  fecha      date not null,
  momento    text check (momento is null or momento in ('desayuno', 'almuerzo', 'merienda', 'cena')),
  receta_id  uuid references public.recetas (id) on delete set null,
  titulo     text check (titulo is null or char_length(titulo) <= 120),
  puntaje    numeric(2,1) check (puntaje is null or (puntaje between 0.5 and 5 and puntaje * 2 = floor(puntaje * 2))),
  me_gusto   boolean not null default false,
  nota       text check (nota is null or char_length(nota) <= 1000),
  fotos      text[] not null default '{}' check (cardinality(fotos) <= 4),
  publica    boolean not null default true,
  repetida   boolean not null default false,
  plan_id    uuid unique references public.plan_comidas (id) on delete set null,
  moderada   boolean not null default false,
  created_at timestamptz not null default now(),
  check (receta_id is not null or titulo is not null)
);
create index if not exists diario_user_fecha_idx on public.diario (user_id, fecha desc, created_at desc);
create index if not exists diario_publico_idx on public.diario (created_at desc) where publica and not moderada;
alter table public.diario enable row level security;

-- Antes de guardar: nombre de la receta, nada en el futuro y "la volví a hacer"
create or replace function public.app_diario_antes() returns trigger
language plpgsql security definer set search_path = public as $$
declare hoy date := (now() at time zone zona_de(new.user_id))::date;
begin
  if new.fecha > hoy then raise exception 'Todavía no llegó ese día: el diario es para lo que ya cocinaste.'; end if;
  if new.titulo is null and new.receta_id is not null then
    select titulo into new.titulo from recetas where id = new.receta_id;
  end if;
  new.repetida := new.receta_id is not null and exists (
    select 1 from diario d where d.user_id = new.user_id and d.receta_id = new.receta_id and d.id <> new.id
      and (d.fecha < new.fecha or (d.fecha = new.fecha and d.created_at < new.created_at)));
  return new;
end $$;
create trigger app_diario_antes before insert or update of fecha, receta_id, titulo on public.diario
  for each row execute function public.app_diario_antes();
create trigger app_proteger_moderada before update on public.diario
  for each row execute function public.app_proteger_moderada();

-- Racha cocinando: días seguidos con algo anotado en el diario, con un comodín por semana.
-- Cuenta lo anotado ese mismo día o al siguiente (rellenar semanas viejas no arma racha).
create or replace function public.calcular_racha_cocina(u uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare zona text := zona_de(u); d date := (now() at time zone zona_de(u))::date; primero date;
        racha int := 0; usadas date[] := '{}'; semana date; i int := 0;
begin
  select min(fecha) into primero from diario where user_id = u;
  if primero is null then return 0; end if;
  if not exists (select 1 from diario where user_id = u and fecha = d) then d := d - 1; end if;
  while d >= primero and i < 2000 loop
    i := i + 1;
    if exists (select 1 from diario where user_id = u and fecha = d
               and created_at < ((d + 2)::timestamp at time zone zona)) then
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

-- Recalcula la racha cocinando y da los premios por hitos (3, 7, 14, 30, 60 y 100 días),
-- una vez por racha: si ya se dio ese hito desde que empezó la racha actual, no se repite.
create or replace function public.actualizar_racha_cocina(u uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r int; hoy date := (now() at time zone zona_de(u))::date; inicio date; hito int; pts int;
begin
  r := calcular_racha_cocina(u);
  insert into progreso (user_id) values (u) on conflict do nothing;
  update progreso set racha_cocina = r, racha_cocina_mejor = greatest(racha_cocina_mejor, r), updated_at = now() where user_id = u;
  inicio := hoy - r;
  foreach hito in array array[3, 7, 14, 30, 60, 100] loop
    exit when r < hito;
    continue when exists (select 1 from puntos_movimientos
                          where user_id = u and motivo = 'racha_cocina_' || hito and dia >= inicio);
    pts := case hito when 3 then 5 when 7 then 15 when 14 then 25 when 30 then 50 when 60 then 80 else 120 end;
    if sumar_puntos(u, 'racha_cocina_' || hito, pts, hoy::text) then
      insert into notificaciones (user_id, tipo, detalle)
      values (u, 'logro', '¡' || hito || ' días seguidos cocinando! Sumaste ' || pts || ' puntos.');
    end if;
  end loop;
end $$;

-- Después de anotar o borrar: puntos (solo lo anotado a mano; lo del plan ya suma al marcarlo) y racha
create or replace function public.app_diario_despues() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    perform quitar_puntos(old.user_id, 'diario', old.id::text);
    perform actualizar_racha_cocina(old.user_id);
    return null;
  end if;
  if new.plan_id is null then
    perform sumar_puntos(new.user_id, 'diario', 2, new.id::text, 3);
  end if;
  perform marcar_dia(new.user_id);
  perform actualizar_racha_cocina(new.user_id);
  return null;
end $$;
create trigger app_diario_despues after insert or delete on public.diario
  for each row execute function public.app_diario_despues();

-- Semana cumplida: todo lo planeado de la semana está hecho (mínimo 5 comidas, planeadas a tiempo)
create or replace function public.revisar_semana_cumplida(u uuid, p_fecha date) returns void
language plpgsql security definer set search_path = public as $$
declare lunes date := date_trunc('week', p_fecha)::date; zona text := zona_de(u); total int; hechas int; a_tiempo int;
begin
  select count(*), count(*) filter (where hecha),
         count(*) filter (where created_at < ((fecha + 1)::timestamp at time zone zona))
    into total, hechas, a_tiempo
  from plan_comidas where user_id = u and fecha between lunes and lunes + 6;
  if total >= 5 and hechas = total and a_tiempo = total then
    if sumar_puntos(u, 'semana_cumplida', 30, lunes::text) then
      update progreso set semanas_cumplidas = semanas_cumplidas + 1 where user_id = u;
      insert into notificaciones (user_id, tipo, detalle)
      values (u, 'logro', '¡Cumpliste con tu planificación semanal! Hiciste las ' || total || ' comidas que planeaste. +30 puntos.');
    end if;
  end if;
end $$;

-- Marcar como hecha: suma, anota en el diario y revisa si se cumplió la semana
create or replace function public.app_puntos_plan() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.hecha and not old.hecha then
    perform sumar_puntos(new.user_id, 'plan', 3, new.id::text, 4);
    insert into diario (user_id, fecha, momento, receta_id, titulo, plan_id)
    values (new.user_id, new.fecha, new.momento, new.receta_id, new.titulo, new.id)
    on conflict (plan_id) do nothing;
    perform revisar_semana_cumplida(new.user_id, new.fecha);
  elsif old.hecha and not new.hecha then
    perform quitar_puntos(new.user_id, 'plan', new.id::text);
  end if;
  return null;
end $$;

-- No se puede marcar como hecha una comida de un día que todavía no llegó
create or replace function public.app_plan_no_futuro() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.hecha and not coalesce(old.hecha, false) and new.fecha > (now() at time zone zona_de(new.user_id))::date then
    raise exception 'Todavía no llegó ese día.';
  end if;
  return new;
end $$;
create trigger app_plan_no_futuro before update of hecha on public.plan_comidas
  for each row execute function public.app_plan_no_futuro();

-- Reglas de acceso: lo público lo ve cualquiera con sesión; cada uno maneja lo suyo
create policy diario_ver on public.diario for select to authenticated
  using (user_id = auth.uid() or public.es_admin() or (publica and not moderada));
create policy diario_crear on public.diario for insert to authenticated
  with check (user_id = auth.uid()
              and (receta_id is null or exists (select 1 from public.recetas r where r.id = receta_id))
              and (not publica or not public.esta_sancionado(auth.uid())));
create policy diario_editar on public.diario for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and (not publica or not public.esta_sancionado(auth.uid())));
create policy diario_quitar on public.diario for delete to authenticated using (user_id = auth.uid());

-- Denuncias: también se pueden denunciar entradas del diario
alter table public.denuncias drop constraint if exists denuncias_tipo_check;
alter table public.denuncias add constraint denuncias_tipo_check
  check (tipo in ('publicacion', 'comentario', 'receta', 'resena', 'diario'));

create or replace function public.app_denuncia_autor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.autor_id := case new.tipo
    when 'publicacion' then (select user_id from publicaciones where id = new.objeto_id)
    when 'comentario'  then (select user_id from comentarios  where id = new.objeto_id)
    when 'receta'      then (select user_id from recetas      where id = new.objeto_id)
    when 'resena'      then (select user_id from resenas      where id = new.objeto_id)
    when 'diario'      then (select user_id from diario       where id = new.objeto_id)
  end;
  if new.autor_id is null then raise exception 'Ese contenido no existe'; end if;
  if new.autor_id = new.denunciante_id then raise exception 'No podés denunciar tu propio contenido'; end if;
  new.estado := 'pendiente'; new.resolucion := null; new.resuelta_por := null; new.resuelta_at := null;
  return new;
end $$;

create or replace function public.resolver_denuncia(p_id uuid, p_aceptar boolean, p_sancion text default null, p_dias int default null, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare d denuncias; tabla text; hasta_ts timestamptz;
begin
  if not es_admin() then raise exception 'Solo administradores'; end if;
  select * into d from denuncias where id = p_id;
  if not found then raise exception 'La denuncia no existe'; end if;

  if not p_aceptar then
    update denuncias set estado = 'desestimada', resolucion = p_nota, resuelta_por = auth.uid(), resuelta_at = now()
     where tipo = d.tipo and objeto_id = d.objeto_id and estado = 'pendiente';
    return;
  end if;

  tabla := case d.tipo when 'publicacion' then 'publicaciones' when 'comentario' then 'comentarios'
                       when 'receta' then 'recetas' when 'resena' then 'resenas' when 'diario' then 'diario' end;
  execute format('update public.%I set moderada = true where id = $1', tabla) using d.objeto_id;

  update denuncias set estado = 'aceptada', resolucion = p_nota, resuelta_por = auth.uid(), resuelta_at = now()
   where tipo = d.tipo and objeto_id = d.objeto_id and estado = 'pendiente';

  if p_sancion in ('advertencia', 'suspension', 'bloqueo') then
    hasta_ts := case when p_sancion = 'suspension' then now() + make_interval(days => greatest(coalesce(p_dias, 7), 1)) end;
    insert into sanciones (user_id, tipo, motivo, hasta, denuncia_id, creada_por)
    values (d.autor_id, p_sancion, coalesce(p_nota, d.motivo), hasta_ts, d.id, auth.uid());
  end if;

  insert into notificaciones (user_id, tipo, detalle, receta_id, publicacion_id)
  values (d.autor_id, 'moderacion',
          case p_sancion
            when 'advertencia' then 'Ocultamos contenido tuyo que infringe las normas. Esto es una advertencia.'
            when 'suspension'  then 'Ocultamos contenido tuyo que infringe las normas. Tu cuenta no puede publicar hasta el ' || to_char(hasta_ts at time zone 'America/Argentina/Buenos_Aires', 'DD/MM/YYYY') || '.'
            when 'bloqueo'     then 'Ocultamos contenido tuyo que infringe las normas. Tu cuenta ya no puede publicar.'
            else 'Ocultamos contenido tuyo que infringe las normas de la comunidad.'
          end,
          case when d.tipo = 'receta' then d.objeto_id end,
          case when d.tipo = 'publicacion' then d.objeto_id end);
end $$;

create or replace function public.restaurar_contenido(p_tipo text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare tabla text;
begin
  if not es_admin() then raise exception 'Solo administradores'; end if;
  tabla := case p_tipo when 'publicacion' then 'publicaciones' when 'comentario' then 'comentarios'
                       when 'receta' then 'recetas' when 'resena' then 'resenas' when 'diario' then 'diario' end;
  if tabla is null then raise exception 'Tipo inválido'; end if;
  execute format('update public.%I set moderada = false where id = $1', tabla) using p_id;
end $$;

revoke execute on function public.app_diario_antes(), public.app_diario_despues(), public.calcular_racha_cocina(uuid),
  public.actualizar_racha_cocina(uuid), public.revisar_semana_cumplida(uuid, date), public.app_plan_no_futuro()
  from public, anon, authenticated;
