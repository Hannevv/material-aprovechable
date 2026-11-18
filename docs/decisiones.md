# Decisiones y alcance de las fases 1–4

## Fuentes

Se utilizó la especificación técnica aprobada adjunta y las correcciones explícitas del usuario, incluidas en `Texto pegado.txt` de esta iteración. Los DOCX autoritativos mencionados anteriormente no fueron adjuntados; su comparación permanece pendiente. No se atribuye contenido a esos archivos. Los Markdown leídos en la planificación sirven como contexto provisional donde no han sido corregidos; no se certifica equivalencia con los DOCX.

## Cambios aprobados aplicados

1. E-04: cero solicitudes parciales; una respuesta perdida tras commit no implica rollback.
2. Cancelación con estado esperado obligatorio y destino fijo CANCELADA.
3. Rechazo sin datos para quien carece de autorización.
4. Lectura RECICLADOR limitada a ASIGNADA propia y perfil ACTIVO.
5. SQL/RPC en migraciones; reserva de `supabase/functions/` para Edge futura.
6. Política jurídica configurable, sin contenido inventado.
7. Postgres Changes y Streams permanecen como diseño futuro; no se implementaron en esta iteración.

## Detalles técnicos menores

- ENUM PostgreSQL para los cinco conjuntos canónicos.
- UUID generados por PostgreSQL; timestamps de cambios generados por servidor. La aceptación conserva la fecha recibida por la RPC documentada y no se reemplaza en reintentos.
- CHECK explícitos con IS NOT NULL para evitar aceptación por lógica SQL de tres valores.
- FK sin borrado en cascada para preservar referencias. No se expone ninguna operación de eliminación.
- Unicidad de documento y usuario_uid mediante constraints; PostgreSQL permite múltiples null en usuario_uid para SIN_APP.
- Trigger diferible garantiza 1..N materiales incluso ante un INSERT privilegiado que omita los materiales.
- Duplicados de un mismo material en la entrada se normalizan a un conjunto, sin duplicar filas.
- Espacios exteriores se recortan en nombres/documento/teléfono y descripción; el límite de descripción se comprueba antes de recortarla. No se cambia mayúsculas ni se elimina puntuación del documento.
- JSONB para resultados de transición; errores de autorización mediante SQLSTATE 42501. No se expone helper de transición genérica.
- Helper de rol en esquema privado evita recursión RLS. Ningún cliente puede crear objetos en public.
- Bloqueos de fila más comparación del estado esperado mantienen la condición de concurrencia aprobada y coordinan la inactivación. No se añade sistema de colas ni arquitectura nueva.
- CLI 2.75.0, configuración PostgreSQL 17. Las imágenes completas Supabase PostgreSQL 17 y 15 excedieron el espacio de Docker; las pruebas se ejecutaron con PostgreSQL 17.12 ligero y GoTrue/PostgREST reales. La versión del CLI es una herramienta de desarrollo, no un componente del producto.
- Monorepo inicializado como Git local sin commits ni remotos. Directorios Dart/Flutter reservados con README; no se generó core ni código de clientes, conforme a la exclusión de esta iteración.

## Pendientes explícitos

- Edge de CON_APP y su compensación: fase 5; las cuentas de reciclador en pruebas son fixtures de servidor, no una funcionalidad de alta ya implementada.
- Realtime y reconciliación de vistas: fases posteriores. Realtime está deshabilitado localmente para esta iteración y deberá habilitarse junto con las pruebas de visibilidad.
- Mostrar política y obtener aceptación en interfaz: fase móvil; configuración reservada y persistencia de aceptación implementada.
- El backend no deduplica creaciones repetidas por similitud; los clientes futuros no deben reintentar automáticamente resultados no confirmados. No se añadió una clave de idempotencia ni se alteró el contrato de creación.
- No se verificó E-06 completo (200 solicitudes y mapa ≤5 s): aún no hay panel.
- No se desplegó a un Supabase remoto ni se aprovisionó un ADMIN real.
- No se actualizó contenido de los adjuntos; las decisiones y E-04 corregido se registran aquí y en el contrato.

## Diferencia de entorno de validación

El runtime mínimo está exclusivamente en `scripts/test-runtime/`. Usa las mismas migraciones del producto, PostgreSQL 17.12, GoTrue 2.186.0 y PostgREST 14.3. GoTrue crea su esquema Auth real; el bootstrap de pruebas solo prepara roles, permisos y el contexto `auth.uid()` compatible con JWT verificados por PostgREST. No se sustituye Auth por una tabla simulada. PostgreSQL tiene privilegios iniciales más restrictivos que algunos proyectos Supabase; las migraciones revocan explícitamente permisos de clientes en ambos casos. No se verificó la distribución completa Supabase ni Kong en este runtime. El arranque completo con CLI debe comprobarse en un entorno con espacio suficiente antes de conectar clientes.

Los archivos del producto siguen siendo migraciones y configuración compatibles con CLI; el runtime de pruebas no agrega un servidor de aplicación ni modifica la arquitectura aprobada.
