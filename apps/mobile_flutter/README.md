# Aplicación móvil — fases 8–9

`lib/bootstrap/bootstrap.dart` ensambla Supabase → repositorios → servicios → MobileController. Las pantallas solo usan el controlador y los servicios de Aplicación; no importan infraestructura. `ChangeNotifier` mantiene estado de UI y Streams mantienen las listas autorizadas.

CIUDADANO: registro, política configurable/aceptación, login/logout, solicitudes, formulario GPS/manual, confirmación con ID, cancelación confirmada y revisión de resultado ambiguo. RECICLADOR: asignaciones, ubicación/mapa y recolección; perfil activo verificado al acceder y reentrar. El backend decide permisos/transiciones.

## Configuración

- `assets/config.json`: la organización debe suministrar `politica`. Con null/vacío el registro permanece deshabilitado; no se inventó texto jurídico.
- `tiles_url`, `tiles_atribucion`, `tiles_user_agent`: proveedor de mapa y atribución visible. El valor inicial usa OpenStreetMap; revisar su política/capacidad antes de desplegar.
- Compilar/ejecutar con `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`. Usar exclusivamente clave pública anon/publishable; jamás service_role.
- No se persisten credenciales ni sesión entre reinicios: se solicita login. No hay cola ni almacenamiento offline de solicitudes.

Android declara INTERNET y ubicación fina/aproximada. iOS declara ubicación durante uso; Podfile excluye permiso Always de geolocator. Android requiere SDK y dispositivo/emulador; iOS requiere macOS/Xcode/CocoaPods y firma según destino. No se validaron estos builds en el workspace Linux.

Pruebas: `flutter test --concurrency=1`; `dart analyze`. La integración real en `test/live_controllers_test.dart` se activa con `LIVE_FIXTURES` apuntando al JSON local ignorado de scripts/test-runtime. Sin esa variable se omite explícitamente. GPS se inyecta en pruebas; eso no certifica el sensor real.

Al volver al foreground/reentrar se verifica el perfil y se reconsulta. No hay polling. La recuperación de un resultado ambiguo entre reinicios sigue pendiente; dentro de sesión se consulta y se exige revisión explícita antes de habilitar otro envío.
