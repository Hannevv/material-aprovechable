create function public.crear_perfil_ciudadano(nombre text, fecha_aceptacion_politica timestamptz)
returns public.usuarios language plpgsql security definer set search_path = '' as $$
declare perfil public.usuarios; uid_actual uuid := auth.uid();
begin
 if uid_actual is null then raise exception 'No autorizado' using errcode = '42501'; end if;
 if nombre is null or btrim(nombre) = '' or fecha_aceptacion_politica is null then
  raise exception 'Nombre y aceptación de política requeridos' using errcode = '22023';
 end if;
 insert into public.usuarios(uid,nombre,rol,fecha_aceptacion_politica)
 values (uid_actual,btrim(nombre),'CIUDADANO',fecha_aceptacion_politica)
 on conflict (uid) do nothing;
 select * into perfil from public.usuarios u where u.uid = uid_actual;
 if perfil.rol <> 'CIUDADANO' then raise exception 'No autorizado' using errcode = '42501'; end if;
 return perfil;
end $$;
create function public.crear_solicitud(materiales public.tipo_material[], descripcion text default null,
 direccion text default null, latitud double precision default null, longitud double precision default null)
returns public.solicitudes language plpgsql security definer set search_path = '' as $$
declare solicitud public.solicitudes;
begin
 if private.rol_actual() is distinct from 'CIUDADANO'::public.rol_usuario then
  raise exception 'No autorizado' using errcode = '42501';
 end if;
 if materiales is null or cardinality(materiales) < 1 or array_position(materiales,null) is not null then
  raise exception 'Seleccione al menos un material válido' using errcode = '22023';
 end if;
 if char_length(descripcion) > 250 then raise exception 'Descripción supera 250 caracteres' using errcode = '22023'; end if;
 insert into public.solicitudes(ciudadano_uid,descripcion_material,direccion,latitud,longitud)
 values (auth.uid(),nullif(btrim(descripcion),''),direccion,latitud,longitud) returning * into solicitud;
 insert into public.solicitud_materiales(solicitud_id,tipo_material)
 select solicitud.id, m from unnest(materiales) m group by m;
 return solicitud;
end $$;
create function public.crear_reciclador_sin_app(nombre text, documento text, telefono text default null)
returns public.recicladores language plpgsql security definer set search_path = '' as $$
declare reciclador public.recicladores;
begin
 if private.rol_actual() is distinct from 'ADMIN'::public.rol_usuario then
  raise exception 'No autorizado' using errcode = '42501';
 end if;
 insert into public.recicladores(nombre,documento,telefono,modalidad)
 values (btrim(nombre),btrim(documento),nullif(btrim(telefono),''),'SIN_APP') returning * into reciclador;
 return reciclador;
end $$;
create function public.actualizar_reciclador(reciclador_id uuid, nombre text, documento text, telefono text default null)
returns public.recicladores language plpgsql security definer set search_path = '' as $$
declare reciclador public.recicladores;
begin
 if private.rol_actual() is distinct from 'ADMIN'::public.rol_usuario then
  raise exception 'No autorizado' using errcode = '42501';
 end if;
 update public.recicladores r set nombre = btrim(actualizar_reciclador.nombre),
 documento = btrim(actualizar_reciclador.documento), telefono = nullif(btrim(actualizar_reciclador.telefono),'')
 where r.id = reciclador_id returning * into reciclador;
 if not found then raise exception 'Reciclador no encontrado' using errcode = 'P0002'; end if;
 return reciclador;
end $$;
create function public.cambiar_estado_reciclador(reciclador_id uuid, estado public.estado_reciclador)
returns public.recicladores language plpgsql security definer set search_path = '' as $$
declare reciclador public.recicladores;
begin
 if private.rol_actual() is distinct from 'ADMIN'::public.rol_usuario then
  raise exception 'No autorizado' using errcode = '42501';
 end if;
 -- UPDATE se serializa con los bloqueos FOR SHARE de asignación/recolección.
 update public.recicladores r set estado = cambiar_estado_reciclador.estado
 where r.id = reciclador_id returning * into reciclador;
 if not found then raise exception 'Reciclador no encontrado' using errcode = 'P0002'; end if;
 return reciclador;
end $$;
revoke all on function public.crear_perfil_ciudadano(text,timestamptz),
 public.crear_solicitud(public.tipo_material[],text,text,double precision,double precision),
 public.crear_reciclador_sin_app(text,text,text), public.actualizar_reciclador(uuid,text,text,text),
 public.cambiar_estado_reciclador(uuid,public.estado_reciclador) from public, anon, authenticated;
grant execute on function public.crear_perfil_ciudadano(text,timestamptz),
 public.crear_solicitud(public.tipo_material[],text,text,double precision,double precision),
 public.crear_reciclador_sin_app(text,text,text), public.actualizar_reciclador(uuid,text,text,text),
 public.cambiar_estado_reciclador(uuid,public.estado_reciclador) to authenticated;
