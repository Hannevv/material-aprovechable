-- Operación interna de servidor: solo service_role, invocada por la Edge tras verificar JWT.
create function public._crear_perfil_reciclador_con_app(
 ejecutor_uid uuid, cuenta_uid uuid, nombre text, documento text, telefono text default null
) returns public.recicladores language plpgsql security definer set search_path = '' as $$
declare r public.recicladores;
begin
 if coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','') <> 'service_role'
 or not exists (select 1 from public.usuarios where uid = ejecutor_uid and rol = 'ADMIN') then
  raise exception 'No autorizado' using errcode = '42501';
 end if;
 -- Reintento seguro de persistencia para la MISMA cuenta creada por esta operación.
 select * into r from public.recicladores where usuario_uid = cuenta_uid;
 if found then
  if r.documento <> btrim(documento) or r.nombre <> btrim(nombre)
    or r.telefono is distinct from nullif(btrim(telefono),'') then
   raise exception 'Cuenta ya vinculada con otros datos' using errcode = '23505';
  end if;
  return r;
 end if;
 insert into public.usuarios(uid,rol) values (cuenta_uid,'RECICLADOR');
 insert into public.recicladores(usuario_uid,nombre,documento,telefono,modalidad,estado)
 values (cuenta_uid,btrim(nombre),btrim(documento),nullif(btrim(telefono),''),'CON_APP','ACTIVO')
 returning * into r;
 return r;
end $$;
revoke all on function public._crear_perfil_reciclador_con_app(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public._crear_perfil_reciclador_con_app(uuid,uuid,text,text,text) to service_role;
grant select on public.usuarios,public.recicladores to service_role;
