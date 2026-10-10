-- =====================================================================
--  Moderación: funciones, triggers y reglas (aplicado el 10/10/2026)
--  Registro de lo que está en producción; no hace falta volver a correrlo.
-- =====================================================================

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from administradores where user_id = auth.uid())
$$;

create or replace function public.esta_sancionado(u uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from sanciones
                 where user_id = u and not levantada and tipo in ('suspension', 'bloqueo')
                   and (hasta is null or hasta > now()))
$$;
grant execute on function public.es_admin() to authenticated;
grant execute on function public.esta_sancionado(uuid) to authenticated;

-- Solo un admin puede ocultar o mostrar contenido moderado
create or replace function public.app_proteger_moderada() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.moderada is distinct from old.moderada and not public.es_admin() then
    raise exception 'Solo la moderación puede cambiar este estado';
  end if;
  return new;
end $$;
create trigger app_proteger_moderada before update on public.publicaciones for each row execute function public.app_proteger_moderada();
create trigger app_proteger_moderada before update on public.recetas       for each row execute function public.app_proteger_moderada();
create trigger app_proteger_moderada before update on public.resenas       for each row execute function public.app_proteger_moderada();
create trigger app_proteger_moderada before update on public.comentarios   for each row execute function public.app_proteger_moderada();

-- Al denunciar, el autor del contenido lo completa la base
create or replace function public.app_denuncia_autor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.autor_id := case new.tipo
    when 'publicacion' then (select user_id from publicaciones where id = new.objeto_id)
    when 'comentario'  then (select user_id from comentarios  where id = new.objeto_id)
    when 'receta'      then (select user_id from recetas      where id = new.objeto_id)
    when 'resena'      then (select user_id from resenas      where id = new.objeto_id)
  end;
  if new.autor_id is null then raise exception 'Ese contenido no existe'; end if;
  if new.autor_id = new.denunciante_id then raise exception 'No podés denunciar tu propio contenido'; end if;
  new.estado := 'pendiente'; new.resolucion := null; new.resuelta_por := null; new.resuelta_at := null;
  return new;
end $$;
create trigger app_denuncia_autor before insert on public.denuncias for each row execute function public.app_denuncia_autor();

-- Aviso al autor del post cuando alguien comenta
create or replace function public.app_notif_comentario() returns trigger
language plpgsql security definer set search_path = public as $$
declare duenio uuid; rec uuid;
begin
  select user_id, receta_id into duenio, rec from publicaciones where id = new.publicacion_id;
  if duenio is not null and duenio <> new.user_id then
    insert into notificaciones (user_id, actor_id, tipo, publicacion_id, receta_id, detalle)
    values (duenio, new.user_id, 'comentario', new.publicacion_id, rec, left(new.texto, 140));
  end if;
  return new;
end $$;
create trigger app_notif_comentario after insert on public.comentarios for each row execute function public.app_notif_comentario();

-- Resolver una denuncia (solo admins): desestimar, u ocultar el contenido y opcionalmente sancionar
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
                       when 'receta' then 'recetas' when 'resena' then 'resenas' end;
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

create or replace function public.levantar_sancion(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not es_admin() then raise exception 'Solo administradores'; end if;
  update sanciones set levantada = true where id = p_id;
end $$;

create or replace function public.restaurar_contenido(p_tipo text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare tabla text;
begin
  if not es_admin() then raise exception 'Solo administradores'; end if;
  tabla := case p_tipo when 'publicacion' then 'publicaciones' when 'comentario' then 'comentarios'
                       when 'receta' then 'recetas' when 'resena' then 'resenas' end;
  if tabla is null then raise exception 'Tipo inválido'; end if;
  execute format('update public.%I set moderada = false where id = $1', tabla) using p_id;
end $$;

revoke execute on function public.resolver_denuncia(uuid, boolean, text, int, text), public.levantar_sancion(uuid), public.restaurar_contenido(text, uuid) from public, anon;
grant execute on function public.resolver_denuncia(uuid, boolean, text, int, text), public.levantar_sancion(uuid), public.restaurar_contenido(text, uuid) to authenticated;
revoke execute on function public.app_proteger_moderada(), public.app_denuncia_autor(), public.app_notif_comentario() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Reglas de acceso
-- ---------------------------------------------------------------------
alter policy "ver recetas" on public.recetas
  using (auth.uid() = user_id or (publica = true and not moderada) or public.es_admin());
alter policy "crear mis recetas" on public.recetas
  with check (auth.uid() = user_id and not public.esta_sancionado(auth.uid()));
alter policy "editar mis recetas" on public.recetas
  using (auth.uid() = user_id) with check (auth.uid() = user_id and not public.esta_sancionado(auth.uid()));

alter policy publicaciones_select on public.publicaciones
  using (user_id = auth.uid() or public.es_admin()
         or (not moderada and (receta_id is null
                               or exists (select 1 from public.recetas r where r.id = publicaciones.receta_id and r.publica))));
alter policy publicaciones_insert on public.publicaciones
  with check (user_id = auth.uid() and not public.esta_sancionado(auth.uid())
              and (receta_id is null or exists (select 1 from public.recetas r where r.id = publicaciones.receta_id and r.publica)));
alter policy publicaciones_update on public.publicaciones
  using (user_id = auth.uid()) with check (user_id = auth.uid() and not public.esta_sancionado(auth.uid()));

alter policy resenas_select on public.resenas
  using (user_id = auth.uid() or public.es_admin()
         or (not moderada and exists (select 1 from public.recetas r where r.id = resenas.receta_id)));
alter policy resenas_insert on public.resenas
  with check (user_id = auth.uid() and not public.esta_sancionado(auth.uid())
              and exists (select 1 from public.recetas r where r.id = resenas.receta_id and r.user_id <> auth.uid()));
alter policy resenas_update on public.resenas
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and not public.esta_sancionado(auth.uid())
              and exists (select 1 from public.recetas r where r.id = resenas.receta_id and r.user_id <> auth.uid()));

alter policy conversaciones_insert on public.conversaciones
  with check ((auth.uid() = usuario_a or auth.uid() = usuario_b) and hay_seguimiento_mutuo(usuario_a, usuario_b)
              and not public.esta_sancionado(auth.uid()));
alter policy mensajes_insert on public.mensajes
  with check (remitente_id = auth.uid() and not public.esta_sancionado(auth.uid())
              and exists (select 1 from public.conversaciones c
                          where c.id = mensajes.conversacion_id and (auth.uid() = c.usuario_a or auth.uid() = c.usuario_b)
                            and hay_seguimiento_mutuo(c.usuario_a, c.usuario_b)));

create policy comentarios_ver on public.comentarios for select to authenticated
  using (user_id = auth.uid() or public.es_admin()
         or (not moderada and exists (select 1 from public.publicaciones p where p.id = comentarios.publicacion_id)));
create policy comentarios_crear on public.comentarios for insert to authenticated
  with check (user_id = auth.uid() and not public.esta_sancionado(auth.uid())
              and exists (select 1 from public.publicaciones p where p.id = comentarios.publicacion_id));
create policy comentarios_quitar on public.comentarios for delete to authenticated
  using (user_id = auth.uid() or public.es_admin()
         or exists (select 1 from public.publicaciones p where p.id = comentarios.publicacion_id and p.user_id = auth.uid()));

create policy denuncias_ver on public.denuncias for select to authenticated
  using (denunciante_id = auth.uid() or public.es_admin());
create policy denuncias_crear on public.denuncias for insert to authenticated
  with check (denunciante_id = auth.uid());
create policy sanciones_ver on public.sanciones for select to authenticated
  using (user_id = auth.uid() or public.es_admin());
create policy admins_ver on public.administradores for select to authenticated
  using (user_id = auth.uid());
create policy publicaciones_borrar_admin on public.publicaciones for delete to authenticated using (public.es_admin());
