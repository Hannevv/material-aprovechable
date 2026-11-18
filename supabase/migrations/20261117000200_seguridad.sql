-- El helper no acepta identidad ajena, evita recursión RLS sobre usuarios.
create function private.rol_actual() returns public.rol_usuario
language sql stable security definer set search_path = '' as $$
 select rol from public.usuarios where uid = (select auth.uid())
$$;
revoke all on function private.rol_actual() from public, anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.rol_actual() to authenticated;
revoke create on schema public from public, anon, authenticated;
revoke all on public.usuarios, public.recicladores, public.solicitudes,
 public.solicitud_materiales, public.historial_estados from public, anon, authenticated;
grant select on public.usuarios, public.recicladores, public.solicitudes,
 public.solicitud_materiales, public.historial_estados to authenticated;
alter table public.usuarios enable row level security;
alter table public.recicladores enable row level security;
alter table public.solicitudes enable row level security;
alter table public.solicitud_materiales enable row level security;
alter table public.historial_estados enable row level security;
create policy usuarios_lectura on public.usuarios for select to authenticated
 using (uid = (select auth.uid()) or (select private.rol_actual()) = 'ADMIN');
create policy recicladores_lectura on public.recicladores for select to authenticated
 using (usuario_uid = (select auth.uid()) or (select private.rol_actual()) = 'ADMIN');
create policy solicitudes_lectura on public.solicitudes for select to authenticated using (
 (select private.rol_actual()) = 'ADMIN'
 or ((select private.rol_actual()) = 'CIUDADANO' and ciudadano_uid = (select auth.uid()))
 or ((select private.rol_actual()) = 'RECICLADOR' and estado = 'ASIGNADA' and exists (
  select 1 from public.recicladores r where r.id = reciclador_id
   and r.usuario_uid = (select auth.uid()) and r.estado = 'ACTIVO'))
);
create policy materiales_lectura on public.solicitud_materiales for select to authenticated
 using (exists (select 1 from public.solicitudes s where s.id = solicitud_id));
create policy historial_admin on public.historial_estados for select to authenticated
 using ((select private.rol_actual()) = 'ADMIN');
-- Las migraciones posteriores conceden EXECUTE únicamente a RPC públicas de casos de uso.
alter default privileges for role postgres in schema public revoke execute on functions from public;
alter default privileges for role postgres in schema private revoke execute on functions from public;
