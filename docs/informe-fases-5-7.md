# Checkpoint fases 5–7

Base: `dfec956af078fb25be45d20a7d9ed671ef1264da`. Se retomó el trabajo existente; no se regeneró el proyecto. No se implementaron interfaces, Composition Roots de aplicaciones ni fases 8/9. El hash de esta entrega se obtiene con `git log -1 --format=%H`; el manifiesto completo relativo al checkpoint base está en `archivos-fases-5-7.txt`.

## Implementación y seguridad

**Fase 5.** `supabase/functions/crear_reciclador_con_app/`: `index.ts` configura secretos exclusivamente de servidor, `handler.ts` valida entrada/autorización y coordina compensación, `backend.ts` usa Auth y PostgREST mediante fetch. Exige bearer verificado contra Auth y ADMIN en `usuarios`, nunca metadata editable. Acepta nombre/documento/teléfono/correo/contraseña inicial; rechaza propiedades adicionales. Devuelve solo perfil o código de error saneado. No hay service_role en paquetes Dart; las pruebas comprueban su ausencia en respuestas.

Migración **20261118000500_alta_con_app.sql**: `_crear_perfil_reciclador_con_app(ejecutor_uid, cuenta_uid, nombre, documento, telefono)` crea `usuarios` y `recicladores` en una transacción, fijando RECICLADOR / CON_APP / ACTIVO. Solo service_role tiene EXECUTE; PUBLIC/anon/authenticated revocados. SECURITY DEFINER con search_path vacío y verificación adicional del rol JWT y ADMIN protegido. SELECT de servidor sobre usuarios/recicladores para verificar resultados. No se crean tablas, constraints ni índices de negocio nuevos; se reutilizan FK, UNIQUE de documento y constraints existentes. El cliente ADMIN tampoco puede invocar directamente la operación interna.

La persistencia admite repetición para la misma cuenta y mismos datos. Ante pérdida de respuesta de esa RPC, el backend intenta una vez la misma persistencia; nunca repite ciegamente la creación Auth. Ante fallo definitivo de perfiles: consulta por la cuenta recién creada, conserva un perfil ya confirmado y, si está ausente, elimina únicamente esa cuenta Auth. Si la consulta falla, la RPC continúa incierta o falla la eliminación, responde 503 con RESULTADO_NO_CONFIRMADO / COMPENSACION_PENDIENTE y registra el UID para revisión. Un SELECT vacío no se interpreta como prueba de rollback de una RPC todavía en vuelo. La creación Auth con respuesta perdida antes de conocer el UID requiere revisión administrativa; no hay una transacción distribuida entre Auth y PostgreSQL ni promesa de compensación infalible ante caída de servicios.

**Fase 6.** Migración **20261118000600_realtime.sql** publica únicamente `public.solicitudes` en `supabase_realtime`. Configuración Realtime y Edge activadas en config.toml; verify_jwt=true para la función. No se cambió ninguna política RLS. Los clientes escuchan Postgres Changes y reconsultan por SELECT autorizado; nunca toman el payload como sustituto de autorización. El filtro ADMIN por estado/material se ejecuta en PostgREST, conservando la lista completa de materiales mediante relación separada.

Observer con Streams: consulta inicial, cambios disponibles, SUBSCRIBED (también reconexión), sesión y señal explícita. Las mutaciones confirmadas disparan reconciliación local, al igual que conflictos de transición con estado autorizado. `SolicitudService.reconciliarVistas()` permite conectar foreground/reentrada sin importar infraestructura. Se agrupan consultas en vuelo y se descartan resultados si cambió la identidad. Al cerrar/cambiar sesión se emite lista vacía, se cierra el Stream y se cancela el canal; al cancelar el consumidor se liberan las suscripciones.

**Sin polling periódico.** Cuando una solicitud deja de estar ASIGNADA, el reciclador pierde acceso por RLS y no recibe el payload final. Una nueva consulta autorizada la retira. Se ejecuta al recuperar conexión, entrar/volver a la vista, señal disponible o tras operación propia. Si otro actor cancela mientras el reciclador permanece continuamente en la misma vista sin ningún disparador visible, puede conservar temporalmente la fila anterior. No se garantiza su retirada inmediata en ese caso. No se añadió Broadcast, tabla auxiliar de eventos ni acceso a estados finales para ocultar esta limitación.

**Fase 7.** Cada paquete incluye README, pubspec.yaml, lockfile, lib y test:

| Paquete | Contenido | Dependencias de producción |
|---|---|---|
| domain | Usuario, Reciclador, Solicitud, HistorialEstado; Ubicacion, Actor, ResultadoTransicion; enums y Fallo; State, Strategy y contratos | Dart puro |
| application | AuthService, SolicitudService, RecicladorService; historial y reconciliación por contratos | domain |
| infrastructure_supabase | Adaptadores Auth/Usuario/Solicitud/Reciclador/Historial, Gateway, mapeadores, errores y Observer | domain, supabase, http |
| infrastructure_mobile | GeolocalizacionStrategy inyectable | domain, Flutter, geolocator |

Aplicación no importa infraestructura, SQL, Supabase, widgets ni dispositivo. El Composition Root futuro ensamblará adaptadores → contratos y servicios → presentación.

State implementa PENDIENTE/ASIGNADA/RECOLECTADA/CANCELADA y rechaza transiciones inválidas; predicción inmutable, nunca autorización cliente. Strategy manual no geocodifica; GPS solicita permisos y obtiene coordenadas con límite de 15 segundos. Repository usa exclusivamente lecturas RLS, RPC o Edge. Observer usa Streams idiomáticos sin colección manual de observadores. Traducción distingue autorización, validación, conectividad, servicio y resultado no confirmado; el conflicto de estado se representa por ResultadoTransicion(confirmada=false, estadoActual), sin filtrar información a usuarios no autorizados.

## Pruebas efectivamente ejecutadas

Evidencias completas y saneadas: `docs/evidencias/fases-5-7/`. No se midió porcentaje de cobertura.

| Suite | Resultado final |
|---|---:|
| Edge Deno unitarias | 10 aprobadas, 0 fallos |
| Edge integración Auth/PostgREST/PostgreSQL reales | 7 aprobadas, 0 fallos (2.129 s) |
| Deno check entrypoint/backend/handler | aprobado |
| domain | 21 aprobadas |
| application | 4 aprobadas |
| infrastructure_supabase unitarias/contratos | 16 aprobadas; live omitida en esta invocación sin fixtures |
| infrastructure_supabase live con Realtime real | 1 recorrido integrado aprobado, 0 fallos (4 s) |
| infrastructure_mobile GPS simulado | 4 aprobadas |
| Análisis estático de los cuatro paquetes | No issues found en los cuatro |
| Regresión SQL/backend | 28 aprobadas (5.397 s) |
| Regresión Auth/HTTP | 5 aprobadas (0.795 s) |
| pgTAP | 12 aserciones aprobadas |

El recorrido live se ejecutó por separado con LIVE_FIXTURES; no se contabiliza su omisión como prueba aprobada. Las suites Dart suman 45 pruebas unitarias y 1 recorrido integrado real.

Edge integración verifica ADMIN, ausencia de token/no ADMIN, prohibición de rol/modalidad/estado elegibles, duplicado de correo sin borrar cuenta existente, duplicado de documento con compensación, fallo inducido mediante trigger en perfiles con rollback y eliminación Auth, ausencia de secretos en respuestas e inaccesibilidad cliente de la RPC interna. Unitarias añaden respuesta perdida tras commit, lectura incierta, eliminación fallida y RPC en vuelo sin eliminación insegura.

Realtime real verifica: alta visible para ADMIN; otro ciudadano sin evento; ASIGNADA visible para propietario y reciclador; filtro PENDIENTE de ADMIN pierde la fila; cancelación oculta al reciclador, retirada por reconciliación y SELECT vacío; corte real de WebSocket mediante proxy local, creación durante desconexión y recuperación por reconsulta; cierre/cambio de sesión y cancelación de consumidores. Las unitarias verifican además descarte de respuesta en vuelo, cierre de canal y ausencia de polling.

Las pruebas de concurrencia del backend se volvieron a ejecutar: doble asignación; asignación contra cancelación; transiciones finales competidoras; asignación e inactivación en ambos órdenes de bloqueo; recolección esperando inactivación. Permanecen las garantías de estado esperado, atomicidad e historial único.

GPS: coordenadas válidas sin dirección; servicio deshabilitado y alternativa manual; permiso denegado con solicitud; denegación permanente sin repetirla. **No ejecutadas:** diálogos/permisos Android/iOS reales, sensor físico, precisión, arranque en frío, timeout real y foreground/background de una aplicación. Requieren dispositivo/emulador y la integración móvil posterior; no se construyeron pantallas para simular su cumplimiento.

## Cambios sobre fases 1–4 y decisiones menores

Las cuatro migraciones originales son idénticas a dfec956. Las cinco tablas, constraints, índices, cinco políticas SELECT y ocho RPC de casos de uso permanecen intactos. Solo se agregaron las dos migraciones anteriores, activación de servicios en config, extensión de la prueba de superficie RPC para reconocer el noveno procedimiento exclusivo de servidor, documentación e ignores de artefactos.

Se fijaron dependencias con lockfiles; SDK probado Dart 3.10.1 / Flutter 3.38.3. No se agregaron frameworks de estado ni inyección. El Gateway permite pruebas sin servidor; la integración usa Supabase SDK real. Los catálogos y configuración específicos del runtime reducido no son migraciones de negocio.

## Desviaciones, limitaciones y pendientes antes de interfaces

1. **Supabase CLI completo sigue pendiente por espacio.** El entorno llegó a agotar un disco de 7.9 GB; se recuperó espacio de herramientas/artefactos temporales sin borrar código del proyecto. Se probó PostgreSQL, GoTrue, PostgREST, Realtime y Deno reales por separado, con proxy local; esto no valida el gateway/Edge Runtime completo, despliegue ni arranque/reset integral del CLI. Procedimiento y versiones en `scripts/test-runtime/README.md`.
2. **Creación incierta E-04:** el adaptador bloquea reintentos para la identidad afectada y permite reconsultar solicitudes autorizadas. No libera automáticamente el bloqueo ante una lista vacía porque no prueba que una transacción en vuelo haya abortado. El bloqueo es en memoria del repositorio, no un protocolo durable entre reinicios. Falta definir la resolución de ambigüedad y persistencia del intento al integrar la interfaz; si se desea reintento recuperable garantizado entre reinicios, debe aprobarse un protocolo idempotente. No se cambió silenciosamente la firma SQL ni se promete que este adaptador resuelva esa ambigüedad por sí solo.
3. **Retirada invisible por RLS:** limitación de disparadores indicada arriba. La interfaz deberá invocar reconciliación al foreground/reentrada. Una exigencia de retirada continua sin esos disparadores requeriría acordar un mecanismo servidor adicional; no se ha añadido polling.
4. `UsuarioRepository.obtenerPorUid` solo resuelve al usuario de la sesión: correo procede de Auth, no de usuarios ni de lectura privilegiada de terceros. Es una restricción explícita respecto de una interpretación genérica del contrato del diagrama. No se amplió el modelo ni la exposición de correo; si la futura interfaz necesita Usuario de terceros, hay que resolver ese contrato antes de utilizarlo.
5. Compensaciones pendientes y altas Auth de resultado incierto requieren revisión operativa segura. Hay código de estado y registro servidor; no se implementó una consola, cola de recuperación ni pantalla nueva.
6. GPS real y suscripciones asociadas al ciclo de vida de interfaces quedan pendientes de integración móvil; no son pruebas ejecutadas en esta entrega. El texto jurídico de la política sigue pendiente de suministro, desacoplado en configuración; no se inventó contenido.
7. Las versiones DOCX autoritativas mencionadas no constan entre los archivos accesibles del workspace. Se conservaron especificación y correcciones explícitas disponibles; la comparación documental de esos DOCX sigue pendiente, no se afirma haberla realizado.

Se conservan los cambios y evidencias en un nuevo commit local, sin remoto. Esta entrega se detiene aquí; las limitaciones anteriores no se convierten en requisitos nuevos ni autorizan iniciar fases 8/9.
