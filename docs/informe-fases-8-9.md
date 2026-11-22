# Checkpoint técnico de fases 8–9

Base aprobada: `ec1af906d995b934204f51a7a21677e86fc5ea08`. Se conservaron los archivos escritos antes de las interrupciones; no se regeneraron apps al reanudar. Esta entrega implementa presentación y cierra sus comprobaciones disponibles. **No declara terminado el proyecto ni constituye aceptación integral RF/HU/QAW.**

El hash de este checkpoint figura en la entrega y se obtiene con `git log -1 --format=%H`. El manifiesto completo de altas/modificaciones respecto de la base está en `archivos-fases-8-9.txt`. No se configuró remoto.

## Estructura y arquitectura

```text
apps/mobile_flutter/
  lib/main.dart
  lib/bootstrap/bootstrap.dart
  lib/presentation/{session_controller,mobile_controller,mobile_app,ui_common}.dart
  assets/config.json
  android/                 # proyecto y permisos de Internet/GPS de primer plano
  ios/                     # proyecto, Info.plist y Podfile de ubicación durante uso
  test/{controller_test,screens_test,live_controllers_test}.dart
  pubspec.yaml / pubspec.lock / analysis_options.yaml / README.md
apps/admin_flutter_web/
  lib/main.dart
  lib/bootstrap/bootstrap.dart
  lib/presentation/{session_controller,admin_controller,admin_app,ui_common}.dart
  assets/config.json
  assets/fonts/            # Roboto local y licencia
  web/                     # index, manifest, iconos y bootstrap CanvasKit local
  test/{controller_test,screens_test}.dart
  pubspec.yaml / pubspec.lock / analysis_options.yaml / README.md
test_support/fakes.dart
scripts/test-runtime/browser_admin.cjs
```

Cada Composition Root construye Gateway/repositories de infraestructura, servicios de Aplicación y controlador. Los widgets y controladores de presentación no importan Supabase ni infraestructura. Dominio conserva entidades, State, Strategy y contratos; no se duplican entidades/repositorios en las apps.

Estado: `ChangeNotifier` para sesión, formularios, carga/error/vacío, filtros y mensajes; Streams para listas. Se eligió por ser suficiente para el MVP, sin Redux/BLoC/event sourcing ni framework adicional. Los helpers visuales pequeños son locales a cada app; no se creó otra arquitectura compartida. Supabase y geolocator solo se ensamblan en bootstrap. Las reglas críticas permanecen en backend.

## Pantallas y flujos

- **CIUDADANO móvil:** registro nombre/correo/contraseña, mínimo 8, lectura y aceptación de política configurable; login/logout y resolución de rol; nueva solicitud con catálogo fijo, uno/varios materiales, descripción opcional hasta 250 caracteres, GPS o dirección manual; confirmación con identificador; lista reciente primero; cancelación propia PENDIENTE con diálogo; conflicto concurrente; resultado no confirmado y revisión previa al reintento.
- **RECICLADOR móvil:** login solo operativo si ACTIVO; asignaciones autorizadas; materiales, descripción, fecha de asignación y ubicación; dirección visible sin mapa, coordenadas con marcador; confirmación de recolección; reconciliación y rechazo autoritativo de solicitud ajena/inactivación.
- **ADMIN web:** login exclusivo; lista con filtro inicial PENDIENTE, estado/material combinables; múltiples materiales sin duplicados; mapa para coordenadas y dirección manual en lista; asignación manual a activos CON_APP/SIN_APP; cancelación PENDIENTE/ASIGNADA y recolección ASIGNADA; gestión de recicladores (alta, consulta, edición permitida, inactivación/reactivación); historial cronológico con actor/rol/reciclador.

No hay elección de rol al registrarse, cuentas ADMIN creadas por UI, cambio de modalidad, eliminación de recicladores, rutas, distancias, geocodificación ni asignación automática. Los estados finales no se reabren. La matriz técnica RF/HU → pantalla/servicio/pruebas está en `trazabilidad-fases-8-9.md`.

## Evidencia ejecutada

Logs completos en `docs/evidencias/fases-8-9/`. No se calculó cobertura porcentual. Se preservaron resultados confirmados y solo se repitieron comprobaciones afectadas por correcciones posteriores.

| Suite | Resultado exacto |
|---|---:|
| App móvil, ejecución con LIVE_FIXTURES | **26 aprobadas**, 0 fallos: 15 de controlador, 9 widgets, 2 recorridos de integración real |
| Panel web | **19 aprobadas**, 0 fallos: 12 de controlador y 7 widgets |
| domain | **21 aprobadas** |
| application | **4 aprobadas** |
| infrastructure_supabase | **18 aprobadas**; 1 live omitida explícitamente en esta invocación sin LIVE_FIXTURES |
| infrastructure_mobile | **4 aprobadas**, plataforma GPS simulada |
| Paquetes compartidos, total unitarias | **47 aprobadas** |
| Edge Function Deno | **10 aprobadas**, 0 fallos |
| Edge integración real | **7 aprobadas**, 0 fallos; 2.538 s |
| Análisis estático | **No issues found** en ambas apps y los cuatro paquetes |
| Flutter Web release | **Build aprobado**; resultado final en evidencia `web-build89-final.txt` |

Las dos pruebas live de la app móvil ensamblan **ambos** controladores con servicios reales (Auth, PostgREST, PostgreSQL, Edge y Realtime). No son un simulacro de backend ni un E2E de dispositivo. GPS en esos recorridos sí está simulado. La prueba live histórica de infrastructure_supabase omitida en su suite unitaria no se cuenta como aprobada en esta iteración; sus comportamientos relevantes se verificaron a través de controladores reales.

**Móvil:** registro/política ausente/aceptación/contraseña; login/logout/rol incorrecto; GPS simulado y manual; uno/varios materiales; descripción vacía, 250 y >250; vacío y cambios de Stream; cancelación y conflicto; reciclador/inactividad; cambio de usuario; foreground/reentrada; consulta fallida y resultado ambiguo; respuesta tardía de validación tras destruir controlador. Widgets verifican formularios, confirmaciones, marcador/atribución, dirección sin mapa y cierre de diálogo al cambiar sesión.

**Web:** guards, estado inicial, filtros combinados, materiales sin duplicado, activos de ambas modalidades, carreras/conflictos, cierres permitidos/finales bloqueados, altas/duplicado saneado, edición/actividad, historial, Streams/logout/reentrada. Widgets verifican login/guards, filtros, asignación, cancelación/historial, gestión SIN_APP/edición/actividad, mapa y ancho de 390 px sin overflow.

**Integración real:** dos controladores ADMIN compiten por una solicitud (un cambio confirmado y un conflicto); cancelación con snapshot PENDIENTE obsoleto; recolección y dos transiciones de historial; alta CON_APP; reciclador no ve solicitud ajena y su RPC de cierre es rechazada; cancelación final desaparece mediante consulta autorizada; inactivación y rechazo de login; duplicado de documento; logout/relogin recrea suscripciones; corte real de WebSocket y reconsulta tras restaurarlo. Un segundo recorrido descarta intencionalmente la respuesta **después de un commit real**, verifica una sola solicitud persistida y exige revisión antes de permitir otro envío.

**Edge:** ADMIN/no ADMIN, falta de token, valores rol/modalidad/estado prohibidos, documento duplicado con compensación, correo duplicado sin borrar original, fallo de perfiles con rollback/compensación, privilegio exclusivo de la RPC interna y respuestas sin secretos. Unitarias cubren respuesta perdida, consulta incierta y compensación fallida. No se volvió a afirmar una transacción distribuida entre Auth y PostgreSQL.

## Build y Chromium

Se compiló Flutter Web release con Flutter 3.38.3 / Dart 3.10.1. El primer intento falló por disco; tras limpiar cachés generadas y comprimir temporalmente dos snapshots redundantes del SDK se logró compilar. Los snapshots fueron restaurados. El build inicial estándar también completó el dry run Wasm, pero **no se validó ejecución Wasm**. El build final usa JavaScript release con configuración pública del backend local; esos valores y el binario están ignorados por Git, no son credenciales de producción.

Chromium real headless ejecuta `scripts/test-runtime/browser_admin.cjs` sobre el build servido en 127.0.0.1:54328. **Resultado final: 6 comprobaciones aprobadas, 0 errores de runtime y 0 errores de consola.** El resultado exacto está en `docs/evidencias/fases-8-9/chromium89.txt`; comprueba arranque/login, rechazo CIUDADANO, acceso ADMIN, navegación de las dos secciones, logout/limpieza y ausencia de errores críticos en consola/runtime. No sustituye un recorrido exhaustivo de todos los formularios en navegador.

Se corrigieron dos impedimentos reproducibles: CanvasKit/Roboto remotos fallaban por la CA del entorno, por lo que ahora se sirven desde el propio build sin desactivar TLS; el proxy reducido no ofrecía CORS para el panel, por lo que se añadió una lista de origen **solo local** en el proxy de pruebas. No se modificó la configuración de seguridad del backend del producto. Dos preflight HTTP comprobaron el origen local autorizado y el rechazo de un origen distinto: sin wildcard y sin Access-Control-Allow-Credentials. No se usaron opciones para ignorar certificados TLS. La selección de navegación del harness se ajustó al rol accesible `radio` que Flutter expone para SegmentedButton; no requirió cambios funcionales de la app.

## Sesión, concurrencia y reconciliación

La sesión no se persiste entre reinicios: se requiere login. Al cerrar/cambiar usuario se vacían solicitudes, recicladores, historial, filtros y mensajes; se cancelan listeners y Streams. Una generación de sesión descarta respuestas tardías. El Navigator se reemplaza por identidad para cerrar también los diálogos y sus datos. Volver a iniciar sesión crea Streams nuevos. Una validación tardía no notifica controladores destruidos.

Cambiar filtros invalida la versión anterior, limpia resultados e inicia nueva suscripción sin esperar la retirada de un canal viejo; su cancelación se solicita y sus eventos tardíos se descartan. Los errores de conexión de Stream se separan de errores de operación y se limpian al recibir datos nuevamente.

Cancelación ciudadana usa PENDIENTE; ADMIN conserva el estado del objeto observado antes de abrir confirmación. Un conflicto informa el estado autorizado actual, reconsulta y **no repite** ni elige otra transición automáticamente. State local no sustituye RPC/locks/RLS.

Realtime es el mecanismo principal. Se reconsulta por evento disponible, SUBSCRIBED/reconexión, foreground, reentrada/actualización explícita y operación confirmada/conflicto. **No hay polling periódico.** Si RLS oculta un evento final del reciclador, la fila se retira en la siguiente consulta autorizada; sin evento visible ni disparador de ciclo de vida puede quedar temporalmente en pantalla. No se amplió RLS para leer estados finales.

## Resultado ambiguo y cambios internos

Tras una creación incierta: bloquear otro envío, explicar “resultado no confirmado”, consultar las solicitudes autorizadas y exigir que el usuario revise el resultado. Si la consulta falla, no se habilita la revisión/reintento. La revisión no crea otra solicitud por sí sola. Si la solicitud aparece, no corresponde reenviarla. Una lista vacía **no demuestra por sí sola** que una operación aún en vuelo abortó; no se ofrece garantía de idempotencia distribuida.

Cambios de integración sobre los paquetes existentes:

1. `AuthService.sesiones` expone el Stream del contrato Auth para que UI no importe infraestructura.
2. El adaptador libera su bloqueo en memoria solo después de completar una consulta autorizada de reconciliación; la UI mantiene su propio bloqueo hasta revisión explícita. Una consulta con cambio de identidad en vuelo se rechaza. Se añadieron dos pruebas de regresión del adaptador.

**SQL, tablas, constraints, índices, RPC, políticas RLS, privilegios y Edge Function no cambiaron respecto de ec1af90.** Se conserva el checkpoint anterior y sus garantías. El CORS añadido está solo en `scripts/test-runtime/proxy.cjs`, para el servidor auxiliar local.

## Defectos corregidos

- Overflow del selector web de material: expansión al ancho disponible, verificado en 390 px.
- Resultados viejos durante cambio de filtros: limpieza inmediata/versionado y cancelación independiente del canal anterior.
- Posible notificación tardía tras destruir controlador: guardas de sesión/disposición y prueba específica.
- Diálogos de otra sesión: Navigator por identidad, probado con diálogo abierto.
- Recursos CDN que impedían arranque en Chromium: CanvasKit y fuente locales, con licencia incluida.
- CORS faltante del runtime auxiliar: habilitado exclusivamente para el origen local del panel.
- Las fallas de pruebas por falta de espacio y por automatización de foco/semántica se corrigieron en el entorno/harness; no se contabilizan como aprobadas hasta la ejecución final.

## Pendientes y desviaciones explícitas

- **Android build/ejecución:** no hay Android SDK ni dispositivo/emulador. Se entregan fuentes/permisos y análisis; no APK certificado.
- **iOS build/ejecución:** workspace Linux, sin macOS/Xcode/CocoaPods/dispositivo. Podfile/permisos no fueron ejecutados en iOS.
- **GPS real:** faltan dispositivo/emulador, permisos nativos y sensor. No se certificaron precisión, arranque en frío, diálogos reales o comportamiento de background.
- **Supabase CLI completo:** sigue pendiente por espacio. Los servicios ligeros reales no sustituyen arranque/reset/despliegue y gateway completo del CLI.
- **Creación ambigua durable:** el bloqueo/revisión es en memoria; reinicio mata ese contexto. No se implementó almacenamiento offline, cola ni clave idempotente nueva. Requiere decisión y validación externa antes de prometer recuperación durable.
- **Compensaciones CON_APP inciertas:** continúan requiriendo revisión administrativa segura. No hay nueva consola/cola de recuperación ni garantía de ausencia de huérfanos ante caída prolongada o respuesta Auth perdida sin UID; no se detectó una vulnerabilidad nueva en las pruebas ejecutadas.
- **Política jurídica:** `politica:null` deshabilita el registro en configuración entregada hasta que la organización suministre el texto. Solo se usó contenido explícitamente ficticio en tests.
- **Mapas:** marcador y atribución probados con tiles de memoria; no se certificó disponibilidad/cuota del proveedor externo. Configurar proveedor y verificar sus condiciones antes de desplegar.
- **E2E externos:** no se ejecutaron recorridos completos móviles, Safari/Firefox, despliegue HTTPS, dispositivos reales, carga/latencia, accesibilidad integral ni aceptación RF/HU/QAW.
- **Documentos autoritativos DOCX:** no constan entre los archivos accesibles; la comparación con esas versiones sigue pendiente. Esta fase siguió la especificación disponible y las instrucciones explícitas aprobadas.
- Se conservan las restricciones documentadas anteriormente sobre consulta de correo de terceros y retirada por RLS. No se agregaron funcionalidades para ocultarlas.

El proyecto queda detenido en el checkpoint de fases 8–9, sin remoto, sin iniciar aceptación final ni documentación académica.
