create function public.asignar_solicitud(solicitud_id uuid, reciclador_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.solicitudes;
begin
 if private.rol_actual() is distinct from 'ADMIN'::public.rol_usuario then
  raise exception 'No autorizado' using errcode = '42501';
 end if;
 -- Orden de bloqueo: reciclador, luego solicitud. Inactivación usa la misma fila.
 perform 1 from public.recicladores r where r.id = asignar_solicitud.reciclador_id
  and r.estado = 'ACTIVO' for share;
 if not found then raise exception 'Reciclador no disponible' using errcode = '22023'; end if;
 select * into s from public.solicitudes where id = solicitud_id for update;
 if not found then raise exception 'No autorizado' using errcode = '42501'; end if;
 if s.estado <> 'PENDIENTE' then
  return jsonb_build_object('confirmada',false,'estado_actual',s.estado,'codigo','CONFLICTO_ESTADO');
 end if;
 update public.solicitudes set estado = 'ASIGNADA', reciclador_id = asignar_solicitud.reciclador_id,
 fecha_asignacion = clock_timestamp() where id = solicitud_id and estado = 'PENDIENTE';
 insert into public.historial_estados(solicitud_id,estado_anterior,estado_nuevo,usuario_ejecutor_uid,rol_ejecutor,reciclador_id)
 values (solicitud_id,'PENDIENTE','ASIGNADA',auth.uid(),'ADMIN',asignar_solicitud.reciclador_id);
 return jsonb_build_object('confirmada',true,'estado_actual','ASIGNADA');
end $$;

create function public.marcar_recolectada(solicitud_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.solicitudes; rol public.rol_usuario := private.rol_actual(); rid uuid;
begin
 if rol is null or rol not in ('ADMIN','RECICLADOR') then
  raise exception 'No autorizado' using errcode = '42501';
 end if;
 if rol = 'RECICLADOR' then
  select id into rid from public.recicladores where usuario_uid = auth.uid() and estado = 'ACTIVO' for share;
  if not found then raise exception 'No autorizado' using errcode = '42501'; end if;
 end if;
 select * into s from public.solicitudes where id = solicitud_id for update;
 if not found or (rol = 'RECICLADOR' and (s.reciclador_id is distinct from rid or s.estado <> 'ASIGNADA')) then
  -- Los estados finales tampoco son visibles al reciclador, aun si antes estuvo asociado.
  raise exception 'No autorizado' using errcode = '42501';
 end if;
 if s.estado <> 'ASIGNADA' then
  return jsonb_build_object('confirmada',false,'estado_actual',s.estado,'codigo','CONFLICTO_ESTADO');
 end if;
 update public.solicitudes set estado = 'RECOLECTADA' where id = solicitud_id and estado = 'ASIGNADA';
 insert into public.historial_estados(solicitud_id,estado_anterior,estado_nuevo,usuario_ejecutor_uid,rol_ejecutor,reciclador_id)
 values (solicitud_id,'ASIGNADA','RECOLECTADA',auth.uid(),rol,s.reciclador_id);
 return jsonb_build_object('confirmada',true,'estado_actual','RECOLECTADA');
end $$;

create function public.cancelar_solicitud(solicitud_id uuid, estado_esperado public.estado_solicitud)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.solicitudes; rol public.rol_usuario := private.rol_actual();
begin
 if rol is null or rol not in ('ADMIN','CIUDADANO') then
  raise exception 'No autorizado' using errcode = '42501';
 end if;
 select * into s from public.solicitudes where id = solicitud_id for update;
 if not found or (rol = 'CIUDADANO' and s.ciudadano_uid <> auth.uid()) then
  raise exception 'No autorizado' using errcode = '42501';
 end if;
 if estado_esperado is null or estado_esperado not in ('PENDIENTE','ASIGNADA')
 or (rol = 'CIUDADANO' and estado_esperado <> 'PENDIENTE') then
  raise exception 'Precondición no permitida' using errcode = '22023';
 end if;
 if s.estado <> estado_esperado then
  return jsonb_build_object('confirmada',false,'estado_actual',s.estado,'codigo','CONFLICTO_ESTADO');
 end if;
 update public.solicitudes set estado = 'CANCELADA' where id = solicitud_id and estado = estado_esperado;
 insert into public.historial_estados(solicitud_id,estado_anterior,estado_nuevo,usuario_ejecutor_uid,rol_ejecutor,reciclador_id)
 values (solicitud_id,s.estado,'CANCELADA',auth.uid(),rol,s.reciclador_id);
 return jsonb_build_object('confirmada',true,'estado_actual','CANCELADA');
end $$;
revoke all on function public.asignar_solicitud(uuid,uuid), public.marcar_recolectada(uuid),
 public.cancelar_solicitud(uuid,public.estado_solicitud) from public, anon, authenticated;
grant execute on function public.asignar_solicitud(uuid,uuid), public.marcar_recolectada(uuid),
 public.cancelar_solicitud(uuid,public.estado_solicitud) to authenticated;
