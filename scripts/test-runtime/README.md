# Runtime de pruebas de fases 5–7

Solo entorno local desechable. No es un despliegue ni sustituye la validación pendiente con Supabase CLI completo.

## Base y servicios

Se reutilizó `material-backend-tests` de fases 1–4 sin reconstruir el repositorio. PostgreSQL 17.12, GoTrue 2.186.0, PostgREST 14.3; se aplicaron incrementalmente las migraciones 005 y 006, con `psql -v ON_ERROR_STOP=1 -1`. Después: `NOTIFY pgrst, 'reload schema'`.

Realtime probado: imagen oficial `public.ecr.aws/supabase/realtime:v2.68.0`. Por límite del disco/driver Docker vfs se exportó con `crane export` y se importó su filesystem a `material-realtime:2.68.0-flat`. Se restituyeron entrypoint `/usr/bin/tini -s -g -- /app/run.sh`, CMD `/app/bin/server` y WORKDIR `/app`. No se cambió el código de Realtime. El contenedor existente se llama `material-realtime-tests`, usa red `material-backend-tests_default`, puerto local 54325 → 4000.

Variables de ese contenedor, exclusivamente de prueba:

```text
PORT=4000
DB_HOST=db
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=postgres
DB_ENC_KEY=supabaserealtime
API_JWT_SECRET=local-test-jwt-secret-at-least-32-characters
SECRET_KEY_BASE=local-test-secret-key-base-at-least-sixty-four-characters-123456789
ERL_AFLAGS=-proto_dist inet_tcp
ECTO_IPV6=false
DNS_NODES=
APP_NAME=realtime
SEED_SELF_HOST=true
SELF_HOST_TENANT_NAME=realtime-dev
RUN_JANITOR=true
RLIMIT_NOFILE=10000
LANG=C.UTF-8
```

Se compiló wal2json 2.6 contra los headers del contenedor PostgreSQL (`make with_llvm=no && make with_llvm=no install`). Los paquetes temporales gcc/musl-dev/make se retiraron después. El plugin queda en el contenedor, no en una imagen reproducible del proyecto; recrearlo exige repetir su instalación. La configuración aplicada al servidor local fue:

```sql
ALTER SYSTEM SET wal_level = 'logical'; -- requiere reinicio
ALTER SYSTEM SET output_plugin_libraries TO 'wal2json', 'pgoutput';
SELECT pg_reload_conf();
CREATE SCHEMA IF NOT EXISTS realtime;
```

El servicio instala sus propias migraciones internas. En este runtime auxiliar sus tablas de catálogo `tenants`, `extensions`, `schema_migrations` quedaron en `public` por el search_path de la imagen; no forman parte del modelo del producto, no fueron publicadas ni se concedió acceso a clientes. Para reproducir con la distribución completa se usan los esquemas internos que provisiona Supabase CLI, no estas tablas auxiliares como migraciones de aplicación.

## Ejecución sobre servicios existentes

1. `docker compose -f scripts/test-runtime/compose.yml start` y `docker start material-realtime-tests`.
2. `npm ci --prefix scripts/test-runtime`; mantener `node scripts/test-runtime/proxy.cjs` en ejecución.
3. `DENO_BIN=/ruta/deno python3 scripts/test-runtime/edge_start.py` en otra terminal.
4. Si aún no hay fixtures válidas: `python3 scripts/test-runtime/prepare_phase567.py`. Crea cuentas sintéticas; no borra datos. El resultado `.test-artifacts/phase567.json` está ignorado por Git y contiene credenciales solo de prueba. La suite SQL de regresión trunca perfiles: después de ella estas fixtures deben prepararse nuevamente si se desea repetir integración.
5. `python3 supabase/tests/edge_integration_test.py` (requests y psycopg de requirements).
6. Dentro de `packages/infrastructure_supabase`: `LIVE_FIXTURES=/ruta/proyecto/.test-artifacts/phase567.json dart test test/live_test.dart -r expanded`.

El proxy solo escucha 127.0.0.1:54327; enruta Auth/REST/Edge y WebSocket a servicios locales. Sus endpoints `POST /__test/realtime/pause` y `/resume` cortan/restauran WebSocket para probar reconexión real; nunca desplegar este proxy. Las caídas se notifican como errores de Stream y las suscripciones siguen vivas hasta recuperar conexión.

`edge_start.py` genera en memoria un JWT local service_role; no hay claves remotas. La Edge ejecutada con Deno usa el mismo handler/backend del entrypoint de producción, pero este runner no verifica el gateway JWT de Supabase: la verificación del llamante se realiza además dentro del handler mediante Auth real.

## Suites sin servicios

- `deno test supabase/functions/crear_reciclador_con_app/tests`
- `deno check supabase/functions/crear_reciclador_con_app/index.ts`
- En domain/application/infrastructure_supabase: `dart pub get`, `dart test`, `dart analyze`.
- En infrastructure_mobile: `flutter pub get`, `flutter test`, `dart analyze`.

Versiones utilizadas: Flutter 3.38.3 / Dart 3.10.1 y Deno 2.5.6. Lockfiles fijan dependencias. En el sandbox se establecieron `CI=true`, `PUB_CACHE`, `XDG_CONFIG_HOME` y `ANALYZER_STATE_LOCATION_OVERRIDE` bajo `/workspace/work`, sin cambiar HOME.

La prueba live se omite explícitamente sin LIVE_FIXTURES. Su resultado aprobado se conserva por separado, no se cuenta una omisión como éxito de integración. No hay dispositivo/emulador: GPS usa plataforma inyectada.

## Cierre de fases 8–9: Chromium

`browser_admin.cjs` usa Playwright 1.62.1 y Chromium instalado (no descarga navegador). El build se sirve con `python3 -m http.server 54328 --bind 127.0.0.1 --directory apps/admin_flutter_web/build/web`. El proxy permite CORS solo desde `http://127.0.0.1:54328`; esa configuración es exclusivamente del runtime de pruebas. Ejecutar desde raíz: `node scripts/test-runtime/browser_admin.cjs`. Requiere Playwright disponible en Node, fixtures y un build configurado con URL/clave pública locales; la clave anon local caduca a las dos horas y debe renovarse al reanudar una sesión larga. No imprimir/copiar tokens a evidencias.

La automatización activa semántica Flutter, enfoca cada campo antes de escribir y comprueba las entradas sin imprimir contraseñas. El informe JSON y screenshot usan solo datos sintéticos. No es una suite E2E exhaustiva ni despliegue de producción.
