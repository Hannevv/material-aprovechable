# Gestión de material aprovechable — Popayán

Iteración de backend: fases 1–4. Flutter móvil/web y core Dart tienen únicamente ubicaciones reservadas; no contienen implementación. Una organización, cinco tablas y ocho RPC de casos de uso. No hay Edge Function, publicación Realtime ni interfaces en esta iteración.

## Estructura

- `apps/mobile_flutter/`, `apps/admin_flutter_web/`: presentación/bootstrap futuros.
- `packages/domain/`, `packages/application/`, `packages/infrastructure_supabase/`, `packages/infrastructure_mobile/`: paquetes futuros, sin código Dart.
- `supabase/config.toml`: configuración local Supabase CLI; Auth sin confirmación de correo y contraseña mínima de 8 caracteres.
- `supabase/migrations/`: modelo, RLS/permisos, registro/gestión y transiciones.
- `supabase/functions/`: ubicación reservada; el alta CON_APP se implementará en una fase posterior.
- `supabase/tests/`: pgTAP, integración SQL/concurrencia e integración HTTP con Auth/PostgREST.
- `config/politica_tratamiento.example.json`: referencia configurable, sin texto jurídico inventado.
- `docs/`: contrato, trazabilidad, decisiones y resultados reales.

## Ejecución reproducible

Requisitos: Docker, Python 3.12 y dependencias fijadas en `supabase/tests/requirements.txt`. Se probó el runtime ligero descrito abajo. El CLI 2.75.0 generó la configuración, pero el arranque de su imagen completa quedó bloqueado por espacio de Docker.

**Ruta estándar prevista para Supabase CLI, pendiente de ejecutar completamente en un entorno con espacio suficiente:**

```sh
supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
supabase db reset --local
python3 -m venv .venv
.venv/bin/pip install -r supabase/tests/requirements.txt
PYTHON_BIN=.venv/bin/python scripts/test-backend.sh
```

`supabase start` también aplica las migraciones al crear la base. `db reset --local` permite comprobar su reproducción desde cero. La suite Python borra los datos de las cinco tablas públicas: ejecutar **únicamente en una instancia local desechable y dedicada a este proyecto**. Requiere localhost:54322 y habilitación explícita de reset; el script la proporciona. Las pruebas HTTP crean cuentas locales sintéticas, eliminables mediante el siguiente reset. Ningún secreto de un entorno remoto es necesario.

Para un CLI ubicado fuera de PATH, definir `SUPABASE_BIN`. Las claves locales se leen en memoria con `supabase status -o json` y no se imprimen ni se guardan en el repositorio.

## Runtime ligero probado

Este entorno de pruebas ejecuta PostgreSQL 17.12, GoTrue 2.186.0 y PostgREST 14.3 reales. GoTrue instala su propio esquema Auth; no se simula `auth.users`. El bootstrap incorpora roles y el contexto JWT de Supabase. Se prueban las mismas cuatro migraciones. No incluye Kong ni todos los servicios de la distribución Supabase.

```sh
python3 -m venv .venv
.venv/bin/pip install -r supabase/tests/requirements.txt
PYTHON_BIN=.venv/bin/python scripts/test-runtime/run.sh --reset-local
```

El comando anterior **recrea únicamente el entorno desechable `material-backend-tests`**, aplica las migraciones desde cero y ejecuta las suites. Necesita Docker, curl y acceso a la versión fijada de pgTAP. Fue ejecutado satisfactoriamente antes de la interrupción. No se repitió la reconstrucción al reanudar.

Para reanudar los contenedores existentes y repetir únicamente las pruebas HTTP, conservando los datos:

```sh
docker compose -f scripts/test-runtime/compose.yml start
LIGHTWEIGHT_TEST_RUNTIME=1 .venv/bin/python supabase/tests/auth_http_test.py
```

Resultados finales: **28 pruebas SQL/backend, 5 HTTP y 12 aserciones pgTAP aprobadas**. Evidencias en `docs/evidencias/`; detalle en `docs/informe-fases-1-4.md`. Las credenciales del Compose son valores públicos exclusivos de este entorno local desechable; no sirven para producción.

## Seguridad

El rol efectivo procede de `public.usuarios`; `auth.uid()` identifica al ejecutor. `user_metadata` nunca autoriza. Los clientes tienen SELECT bajo RLS y EXECUTE sobre ocho RPC; no INSERT/UPDATE/DELETE sobre las cinco tablas. Los helpers están en `private`, fuera de los esquemas API. Todas las funciones privilegiadas fijan `search_path = ''`.

La política permite al reciclador leer su perfil incluso estando inactivo para informar su estado, pero sus solicitudes/materiales solo son visibles mientras esté ACTIVO y la solicitud siga ASIGNADA a él. No puede consultar historial ni solicitudes finales.

ADMIN debe aprovisionarse fuera de los clientes: crear su cuenta Auth mediante herramientas administrativas seguras y después insertar su registro `usuarios` con rol ADMIN y nombre. No hay autorregistro ADMIN. No se incluyen contraseñas ADMIN ni semillas de producción.

## Límite de esta entrega

La capacidad visual de mostrar la política, los guards del cliente, la reconciliación automática, el GPS y las suscripciones se implementarán en fases posteriores. Esta entrega exige una fecha de aceptación no nula en la RPC de perfil y conserva la primera aceptación en reintentos; el futuro cliente debe mostrar el contenido suministrado antes de obtenerla. Si falta el contenido, no debe presentar una política ficticia ni habilitar el registro como si estuviera completa.
