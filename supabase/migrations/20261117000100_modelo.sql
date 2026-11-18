-- RF-01..12 / RN-01..09. Modelo canónico, una organización.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create type public.rol_usuario as enum ('CIUDADANO','RECICLADOR','ADMIN');
create type public.modalidad_reciclador as enum ('CON_APP','SIN_APP');
create type public.estado_reciclador as enum ('ACTIVO','INACTIVO');
create type public.estado_solicitud as enum ('PENDIENTE','ASIGNADA','RECOLECTADA','CANCELADA');
create type public.tipo_material as enum ('PAPEL','CARTON','PLASTICO','VIDRIO','METAL');
create table public.usuarios (
 uid uuid primary key references auth.users(id),
 nombre text,
 rol public.rol_usuario not null,
 fecha_aceptacion_politica timestamptz,
 created_at timestamptz not null default now(),
 constraint nombre_por_rol check (rol = 'RECICLADOR' or (nombre is not null and btrim(nombre) <> '')),
 constraint aceptacion_ciudadano check (rol <> 'CIUDADANO' or fecha_aceptacion_politica is not null)
);
create table public.recicladores (
 id uuid primary key default gen_random_uuid(),
 usuario_uid uuid unique references public.usuarios(uid),
 nombre text not null check (btrim(nombre) <> ''),
 documento text not null unique check (btrim(documento) <> ''),
 telefono text,
 modalidad public.modalidad_reciclador not null,
 estado public.estado_reciclador not null default 'ACTIVO',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint cuenta_por_modalidad check ((modalidad = 'CON_APP') = (usuario_uid is not null))
);
create table public.solicitudes (
 id uuid primary key default gen_random_uuid(),
 ciudadano_uid uuid not null references public.usuarios(uid),
 descripcion_material text check (char_length(descripcion_material) <= 250),
 direccion text,
 latitud double precision,
 longitud double precision,
 estado public.estado_solicitud not null default 'PENDIENTE',
 reciclador_id uuid references public.recicladores(id),
 fecha_creacion timestamptz not null default now(),
 fecha_asignacion timestamptz,
 constraint ubicacion_exclusiva check (
  (direccion is not null and btrim(direccion) <> '' and latitud is null and longitud is null)
  or (direccion is null and latitud is not null and longitud is not null
      and latitud between -90 and 90 and longitud between -180 and 180)),
 constraint asignacion_por_estado check (
  (estado = 'PENDIENTE' and reciclador_id is null and fecha_asignacion is null)
  or (estado in ('ASIGNADA','RECOLECTADA') and reciclador_id is not null and fecha_asignacion is not null)
  or (estado = 'CANCELADA' and ((reciclador_id is null and fecha_asignacion is null)
                           or (reciclador_id is not null and fecha_asignacion is not null))))
);
create table public.solicitud_materiales (
 solicitud_id uuid not null references public.solicitudes(id),
 tipo_material public.tipo_material not null,
 primary key (solicitud_id, tipo_material)
);
create table public.historial_estados (
 id uuid primary key default gen_random_uuid(),
 solicitud_id uuid not null references public.solicitudes(id),
 estado_anterior public.estado_solicitud not null,
 estado_nuevo public.estado_solicitud not null,
 fecha_hora timestamptz not null default clock_timestamp(),
 usuario_ejecutor_uid uuid not null references public.usuarios(uid),
 rol_ejecutor public.rol_usuario not null,
 reciclador_id uuid references public.recicladores(id),
 constraint transicion_valida check (
  (estado_anterior = 'PENDIENTE' and estado_nuevo in ('ASIGNADA','CANCELADA'))
  or (estado_anterior = 'ASIGNADA' and estado_nuevo in ('RECOLECTADA','CANCELADA')))
);
create index solicitudes_ciudadano_fecha on public.solicitudes(ciudadano_uid, fecha_creacion desc);
create index solicitudes_reciclador_estado on public.solicitudes(reciclador_id, estado);
create index solicitudes_estado_fecha on public.solicitudes(estado, fecha_creacion desc);
create index materiales_tipo_solicitud on public.solicitud_materiales(tipo_material, solicitud_id);
create index historial_solicitud_fecha on public.historial_estados(solicitud_id, fecha_hora);
create index recicladores_estado on public.recicladores(estado);

-- Invariantes entre tablas, también para herramientas privilegiadas de aprovisionamiento.
create function private.validar_reciclador() returns trigger language plpgsql
set search_path = '' as $$
begin
 if TG_OP = 'UPDATE' and (new.modalidad <> old.modalidad or new.usuario_uid is distinct from old.usuario_uid) then
  raise exception 'Modalidad y cuenta de acceso inmutables' using errcode = '23514';
 end if;
 if new.usuario_uid is not null and not exists (
  select 1 from public.usuarios where uid = new.usuario_uid and rol = 'RECICLADOR') then
  raise exception 'La cuenta debe tener rol RECICLADOR' using errcode = '23514';
 end if;
 new.updated_at := clock_timestamp();
 return new;
end $$;
create trigger validar_reciclador before insert or update on public.recicladores
for each row execute function private.validar_reciclador();

create function private.validar_ciudadano() returns trigger language plpgsql
set search_path = '' as $$
begin
 if not exists (select 1 from public.usuarios where uid = new.ciudadano_uid and rol = 'CIUDADANO') then
  raise exception 'Propietario debe ser CIUDADANO' using errcode = '23514';
 end if;
 return new;
end $$;
create trigger validar_ciudadano before insert or update of ciudadano_uid on public.solicitudes
for each row execute function private.validar_ciudadano();

-- Al commit, una solicitud siempre contiene al menos un material.
create function private.validar_materiales() returns trigger language plpgsql security definer
set search_path = '' as $$
declare sid uuid;
begin
 if TG_TABLE_NAME = 'solicitudes' then sid := new.id;
 elsif TG_OP = 'INSERT' then sid := new.solicitud_id;
 else sid := old.solicitud_id;
 end if;
 if exists (select 1 from public.solicitudes where id = sid)
 and not exists (select 1 from public.solicitud_materiales where solicitud_id = sid) then
  raise exception 'Solicitud sin materiales' using errcode = '23514';
 end if;
 return null;
end $$;
create constraint trigger solicitud_tiene_materiales after insert or update on public.solicitudes
 deferrable initially deferred for each row execute function private.validar_materiales();
create constraint trigger materiales_no_vacios after delete or update on public.solicitud_materiales
 deferrable initially deferred for each row execute function private.validar_materiales();
revoke all on all functions in schema private from public, anon, authenticated;
