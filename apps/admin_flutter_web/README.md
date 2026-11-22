# Panel ADMIN — fases 8–9

Bootstrap propio en `lib/bootstrap/bootstrap.dart`; `AdminController` usa exclusivamente servicios de Aplicación. Presentación con ChangeNotifier y Streams, sin acceso directo a Supabase desde widgets. No hay un framework de estado adicional.

Login solo ADMIN; solicitudes con filtro inicial PENDIENTE y material combinable; ubicación manual/mapa; asignación manual de recicladores activos CON_APP/SIN_APP; cierres con confirmación y precondición observada; historial cronológico; alta, edición de campos permitidos e inactivación/reactivación de recicladores. No hay cambio de modalidad, borrado, autorregistro ADMIN, rutas ni sugerencias.

## Ejecutar

```sh
flutter pub get
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter build web --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Solo clave pública. La configuración de pruebas se guardó en `.test-artifacts/web-config.json` (ignorado); no contiene secretos administrativos. `assets/config.json` configura tiles/atribución. CanvasKit y Roboto se sirven localmente con el build para no depender de un CDN durante el arranque. Licencia Roboto en `assets/fonts/Roboto_LICENSE.txt`.

`flutter test --concurrency=1` ejecuta controladores y widgets; `dart analyze` verifica tipos/imports. `scripts/test-runtime/browser_admin.cjs` comprueba el build release en Chromium contra el backend local. Requiere Playwright (probado 1.62.1), Chromium y fixtures vigentes. No sustituye pruebas exhaustivas de navegador/dispositivos, HTTPS ni Supabase CLI completo.

No se persiste la sesión. Al cambiar/cerrar sesión se limpia el estado y se reemplaza el Navigator, incluidos diálogos abiertos. Reconsulta por Realtime, reconexión, foreground/reentrada y operaciones; sin polling.
