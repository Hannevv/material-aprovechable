# Ejecutar el proyecto localmente en Windows

Guía técnica de preparación, no aceptación integral RF/HU/QAW. No requiere servicios públicos ni el workspace de Codex. `127.0.0.1` siempre significa **el equipo donde se ejecuta el proceso**: ahora será tu PC. No se configura remoto ni se despliega a producción.

## 1. Requisitos y versiones

Usa Windows 10/11 **x64** compatible con Docker Desktop/WSL2; preferiblemente Windows 11 actualizado. Los comandos siguientes son **PowerShell**, ejecutados en Windows, no dentro de WSL. WSL2 se usa como backend de Docker Desktop. En Windows ARM, verifica primero compatibilidad/emulación y descarga binarios correspondientes; los ejemplos son x64.

| Herramienta | Versión / configuración |
|---|---|
| Git for Windows | 2.x; necesario para Flutter y para clonar el bundle suministrado |
| Flutter | **3.38.3 stable**, la versión usada en el checkpoint |
| Dart | **3.10.1**, incluido en Flutter; no instalar otro Dart separado |
| Supabase CLI | **2.75.0** para reproducir la configuración existente; binario Windows x64 |
| Docker Desktop | Edición estable compatible con tu Windows, WSL2 y **Linux containers**. El proyecto no fija versión Desktop; aquí se usó Docker Engine Linux 29.9.2, no Desktop Windows |
| Python | **3.12.x** con launcher `py`; preparación local y tests SQL/HTTP |
| Chrome o Edge | Navegador estable actualizado; `flutter devices` debe detectarlo |
| Android Studio | Versión estable compatible con API 36; solo necesario para Android |
| Android SDK | Platform **API 36**, Platform Tools (adb), Command-line Tools, Build-Tools de API 36; emulador API 36 recomendado, mínimo Android API 24 |
| Android NDK | **28.2.13676358**, solicitado por Flutter 3.38.3; instalar Side by side desde SDK Manager si Gradle lo solicita |
| Java/Gradle | JDK **17 o 21** compatible con AGP 8.11.1 (preferible JBR incluido en Android Studio); código Java/Kotlin target 17. Wrapper Gradle **8.14**, Kotlin **2.2.20**, ya fijados: no instalar Gradle global |
| Deno | **2.5.6**, solo para ejecutar unitarias de Edge con `deno test`; no hace falta para servir Edge mediante CLI/Docker |
| Node/Playwright | No necesarios para ejecutar las apps ni Supabase con el binario CLI. Solo para el harness Chromium histórico: Playwright 1.62.1 y navegador instalado |

Reserva varias decenas de GB para Docker, Android, Flutter y cachés (recomendación: **30–40 GB libres**, no un mínimo garantizado). El workspace de desarrollo no pudo arrancar la distribución completa de Supabase por espacio. **Esta guía y los helpers no han sido ejecutados en Windows ni certifican el arranque CLI completo**; se comprobó la generación de configuración y los límites de seguridad mediante pruebas unitarias.

## 2. Obtener el proyecto completo

La entrega incluye:

- `material-aprovechable-windows.zip`: todos los archivos versionados del checkpoint, incluidos apps, paquetes, migraciones, Edge, pruebas, documentación y licencias. No incluye SDK, node_modules, builds, bases Docker, usuarios de prueba, claves generadas ni archivos locales ignorados.
- `material-aprovechable.bundle`: historia Git completa hasta este checkpoint, sin remoto público. Permite clonar localmente sin GitHub.
- `SHA256SUMS.txt`: sumas SHA-256 de ambos archivos. Comprueba un archivo con `Get-FileHash -Algorithm SHA256` y compara con la suma entregada.

Descarga los archivos desde los enlaces de la entrega a tu carpeta Descargas. **No uses la ruta `/workspace/...` en tu PC**: esa ruta pertenece al entorno remoto.

Opción ZIP:

```powershell
New-Item -ItemType Directory -Force C:\src | Out-Null
Expand-Archive "$env:USERPROFILE\Downloads\material-aprovechable-windows.zip" C:\src
Set-Location C:\src\material-aprovechable
```

Opción Git bundle, alternativa al ZIP (elige solo una):

```powershell
New-Item -ItemType Directory -Force C:\src | Out-Null
Set-Location C:\src
git clone "$env:USERPROFILE\Downloads\material-aprovechable.bundle" material-aprovechable
Set-Location .\material-aprovechable
# git clone crea origin apuntando al archivo local; es opcional eliminarlo:
git remote remove origin
git log -1 --oneline
```

No hay URL de repositorio remoto configurada por esta entrega. Si solo obtienes acceso al filesystem del workspace, la raíz del repo es `/workspace/work/material-aprovechable`; `git archive HEAD` o `git bundle create archivo.bundle --all` reproducen los exportables sin copiar archivos ignorados.

## 3. Instalar herramientas

Instala Git y Python 3.12 desde sus distribuciones oficiales, habilitando Git en PATH y el launcher Python. Verifica en una **terminal nueva**:

```powershell
git --version
py -3.12 --version
```

Flutter: descarga el ZIP Windows 3.38.3 stable desde el archivo oficial https://docs.flutter.dev/install/archive (selecciona Windows, stable, versión 3.38.3). Extrae el SDK en `C:\src\flutter`, fuera del repositorio y de Program Files/OneDrive. Añade `C:\src\flutter\bin` al PATH de usuario mediante Configuración de Windows. Para la terminal actual:

```powershell
$env:Path = "C:\src\flutter\bin;$env:Path"
flutter --version
dart --version
flutter config --enable-web
flutter doctor -v
```

Instala Docker Desktop desde https://docs.docker.com/desktop/setup/install/windows-install/. Activa virtualización, WSL2 y Linux containers. Si falta WSL, abre PowerShell como administrador, ejecuta `wsl --install` y reinicia cuando Windows lo solicite. Abre Docker Desktop y espera que el motor esté listo. Después, usa terminal normal:

```powershell
wsl --version
docker version
docker info
```

Supabase CLI nativo, sin instalación npm global:

```powershell
New-Item -ItemType Directory -Force C:\tools\supabase | Out-Null
Invoke-WebRequest https://github.com/supabase/cli/releases/download/v2.75.0/supabase_windows_amd64.tar.gz -OutFile "$env:TEMP\supabase_windows_amd64.tar.gz"
tar -xzf "$env:TEMP\supabase_windows_amd64.tar.gz" -C C:\tools\supabase
$env:Path = "C:\tools\supabase;$env:Path"
supabase --version
```

Añade también `C:\tools\supabase` al PATH de usuario para nuevas terminales. No hace falta `supabase login` para uso local. No ejecutes `supabase init`: el proyecto ya está inicializado. No uses `supabase link` ni comandos de despliegue remoto.

Android: instala Android Studio, usa SDK Manager para los componentes de la tabla, crea un emulador x64 API 36 y verifica:

```powershell
flutter doctor --android-licenses
flutter doctor -v
flutter emulators
flutter devices
```

Si Flutter no localiza el SDK/JDK, configura sus rutas reales con `flutter config --android-sdk "RUTA_SDK"` y `flutter config --jdk-dir "RUTA_JDK"`. No confundas target Java 17 con obligación de instalar un Gradle global. iOS **no se compila ni ejecuta desde Windows**; requiere macOS/Xcode y configuración separada.

## 4. Supabase local, migraciones y configuración pública

Desde `C:\src\material-aprovechable`, con Docker Desktop abierto:

```powershell
supabase start
supabase status
```

El primer arranque descarga imágenes y aplica `supabase/migrations/*.sql`. Mantén Realtime y Edge Runtime habilitados; no copies los comandos históricos que excluían estos servicios. Studio está deshabilitado en la configuración entregada y no es necesario para estos pasos.

Para aplicar migraciones nuevas a una instancia local ya existente:

```powershell
supabase migration up --local
```

**Solo si quieres recrear una instancia desechable desde cero**, usa `supabase db reset --local`: borra los datos locales (incluidas cuentas/datos de demostración). No es parte del arranque normal ni debes ejecutarlo después de haber creado tu ADMIN si quieres conservarlo. Hay seis migraciones: modelo, RLS/permisos, gestión/registro, transiciones, alta interna CON_APP y publicación Realtime.

Crea el entorno Python y genera configuración:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r supabase\tests\requirements.txt
.\.venv\Scripts\python.exe scripts\local\preparar.py configurar
```

El helper ejecuta `supabase status -o json` en memoria y escribe solo:

| Archivo ignorado por Git | Uso |
|---|---|
| `config/local/web.json` | `SUPABASE_URL` del PC y `SUPABASE_ANON_KEY` local |
| `config/local/android-emulator.json` | Misma clave pública, host `10.0.2.2` para Android Emulator |

No escribe DB_URL, contraseña PostgreSQL, SERVICE_ROLE_KEY ni JWT secreto. La clave anon es pública, pero no es válida para tu backend hasta generarla allí. No copies las claves sintéticas del runtime antiguo. No publiques ni compartas la salida completa de `supabase status`, que incluye valores administrativos.

Alternativa manual: copia `config/supabase.example.json` a `config/local/web.json` y sustituye solo sus dos valores con `API_URL` y **ANON_KEY** de tu Supabase local. Se usa la clave anon JWT compatible con el CLI fijado; no una clave secreta. Las apps leen `String.fromEnvironment`, no cargan `.env` automáticamente. Un `$env:SUPABASE_URL` sin `--dart-define`/`--dart-define-from-file` no configura Flutter.

## 5. Crear un ADMIN local para entrar al panel

El producto no permite autorregistro ADMIN. El siguiente helper es una herramienta administrativa **exclusivamente local**, no una pantalla ni una RPC nueva:

```powershell
.\.venv\Scripts\python.exe scripts\local\preparar.py admin
```

Introduce un correo nuevo y una contraseña de al menos ocho caracteres (se solicita sin mostrarla). El helper usa temporalmente la clave service_role y DB_URL obtenidas del CLI, crea la cuenta mediante Auth y el perfil protegido ADMIN mediante conexión PostgreSQL local. No guarda credenciales, no convierte cuentas CIUDADANO/RECICLADOR existentes ni modifica la contraseña de un ADMIN ya existente. Rechaza endpoints que no sean loopback.

Si falla la conexión o la creación del perfil, no reintentes ciegamente: revisa el UID indicado y el estado de la cuenta. Solo se intenta compensación ante un rechazo SQL inequívoco; un commit incierto requiere revisión local. Para una instancia sin datos valiosos puedes optar explícitamente por resetearla y repetir el aprovisionamiento.

## 6. Edge Function

En una **segunda terminal**, desde la raíz y con Supabase iniciado:

```powershell
$env:Path = "C:\tools\supabase;C:\src\flutter\bin;$env:Path"
Set-Location C:\src\material-aprovechable
supabase functions serve crear_reciclador_con_app
```

Deja la terminal abierta. La ruta estándar es `http://127.0.0.1:54321/functions/v1/crear_reciclador_con_app`. El CLI suministra `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` dentro del runtime servidor; no copies esas variables al cliente ni añadas `.env` privilegiados al repo. `verify_jwt=true` permanece activo. **No uses `--no-verify-jwt`.** El ADMIN del panel envía su token de sesión, la Edge verifica el rol protegido y usa la operación SQL interna existente.

Si aparece 401/403, verifica sesión ADMIN, migración interna y runtime; no elimines validaciones JWT/RLS ni cambies CORS global para resolverlo. Si aparece conexión rechazada, comprueba Docker y la terminal `functions serve`.

## 7. Ver el panel Web en tu navegador

En la terminal principal:

```powershell
Set-Location C:\src\material-aprovechable\apps\admin_flutter_web
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 3000 --dart-define-from-file=../../config/local/web.json
```

Abre `http://localhost:3000` **en tu PC** e ingresa con el ADMIN creado. Para Edge usa `-d edge` si aparece en `flutter devices`. No se necesita Node, el proxy 54327, un servidor de Codex ni túneles. Supabase CLI proporciona su gateway local en 54321.

Opcional: build release y servidor estático local (detén primero `flutter run` si ocupaba 3000):

```powershell
flutter build web --release --dart-define-from-file=../../config/local/web.json
py -3.12 -m http.server 3000 --bind 127.0.0.1 --directory build/web
```

CanvasKit y Roboto están incluidos localmente; no se debe desactivar TLS del navegador. La visualización de tiles sí necesita conexión con el proveedor configurado. Las claves/URL se incorporan en compilación: después de cambiarlas, detén y vuelve a ejecutar/compilar, no solo hot reload.

## 8. Ejecutar móvil Android

Inicia tu emulador desde Android Studio Device Manager. Desde la raíz:

```powershell
Set-Location C:\src\material-aprovechable\apps\mobile_flutter
flutter pub get
flutter devices
# Sustituye emulator-5554 si flutter devices muestra otro identificador:
flutter run --debug -d emulator-5554 --dart-define-from-file=../../config/local/android-emulator.json
```

`10.0.2.2` es la dirección especial del host Windows desde el **Android Emulator**, no una dirección de Codex ni de un teléfono físico. `127.0.0.1` dentro del emulador apunta al emulador, por eso hay un archivo separado.

Teléfono Android físico por USB, con depuración USB autorizada: usa `adb reverse` para no abrir la API/BD a la LAN. Añade Android SDK `platform-tools` al PATH o usa la ruta completa de adb:

```powershell
adb devices
# Sustituye SERIAL por el identificador del teléfono:
adb -s SERIAL reverse tcp:54321 tcp:54321
flutter run --debug -d SERIAL --dart-define-from-file=../../config/local/web.json
```

El archivo web usa 127.0.0.1; con `adb reverse` ese puerto se redirige al PC. Si cambias el puerto del API, modifica ambos números. Para retirar el túnel: `adb -s SERIAL reverse --remove tcp:54321`.

Solo el manifest **debug** permite HTTP a `localhost`, `127.0.0.1` y `10.0.2.2`; el resto de destinos cleartext se deniega. No se cambió release ni la validación de certificados. No se habilita tráfico HTTP global ni se abre un firewall a Internet. No uses estos comandos para generar una distribución pública.

`apps/mobile_flutter/assets/config.json` contiene `politica:null`. Debes suministrar ahí el texto aprobado por la organización para habilitar registro ciudadano; no se inventó contenido. Usa el ADMIN web para dar de alta RECICLADOR CON_APP y luego inicia sesión móvil con esa cuenta. GPS real/permisos se comprobarán en tu dispositivo; dirección manual no requiere GPS ni genera coordenadas.

## 9. Pruebas disponibles en Windows

Desde raíz, unitarias/widgets y análisis (sin backend para las suites ordinarias):

```powershell
$root = (Get-Location).Path
foreach ($p in @('domain','application','infrastructure_supabase')) {
    Push-Location (Join-Path $root "packages\$p")
    dart pub get
    dart test
    dart analyze
    Pop-Location
}
foreach ($p in @('packages\infrastructure_mobile','apps\mobile_flutter','apps\admin_flutter_web')) {
    Push-Location (Join-Path $root $p)
    flutter pub get
    flutter test --concurrency=1
    dart analyze
    Pop-Location
}
py -3.12 scripts\local\test_preparar.py
```

Sin `LIVE_FIXTURES`, los tests live se **omiten**: no equivalen a integraciones aprobadas. La suite móvil ordinaria incluye 24 pruebas de controlador/widget y omite dos recorridos reales; core Supabase omite uno. Los fakes GPS/mapas no certifican hardware ni proveedor de tiles.

Backend con Supabase CLI, en instancia local **dedicada a pruebas**:

```powershell
supabase test db
.\.venv\Scripts\python.exe supabase\tests\auth_http_test.py
# ATENCIÓN: backend_test.py TRUNCA las cinco tablas públicas.
# Ejecutar solo si aceptas perder perfiles/solicitudes del entorno de prueba:
$localStatus = supabase status -o json | ConvertFrom-Json
$env:TEST_DATABASE_URL = $localStatus.DB_URL
$env:ALLOW_LOCAL_TEST_RESET = '1'
.\.venv\Scripts\python.exe supabase\tests\backend_test.py
Remove-Item Env:ALLOW_LOCAL_TEST_RESET
Remove-Item Env:TEST_DATABASE_URL
$localStatus = $null
```

Las guardas de esas pruebas exigen los puertos locales predeterminados (54321/54322). Si los cambias, las apps pueden configurarse, pero **no elimines las guardas de pruebas** para forzarlas. La suite SQL elimina perfiles del ADMIN de demostración; no la ejecutes sobre datos que quieres conservar. Después de una prueba destructiva puedes recrear explícitamente la instancia con `supabase db reset --local` y volver a crear ADMIN/configuración.

Para instalar Deno opcionalmente, descarga el binario oficial fijado y añádelo al PATH de esta terminal:

```powershell
Invoke-WebRequest https://github.com/denoland/deno/releases/download/v2.5.6/deno-x86_64-pc-windows-msvc.zip -OutFile "$env:TEMP\deno.zip"
Expand-Archive "$env:TEMP\deno.zip" C:\tools\deno
$env:Path = "C:\tools\deno;$env:Path"
```

Unitarias de Edge:

```powershell
deno --version
deno test supabase/functions/crear_reciclador_con_app/tests
deno check supabase/functions/crear_reciclador_con_app/index.ts
```

**Harness histórico, no portable directamente al CLI estándar:** `scripts/test-runtime/*`, `supabase/tests/edge_integration_test.py`, `browser_admin.cjs` y los recorridos LIVE_FIXTURES asumen servicios separados, JWT sintético, fixtures y proxy/puertos 54324–54328. No los apuntes sin adaptación a tu Supabase CLI ni copies sus claves. Su documentación conserva cómo se ejecutaron en el entorno ligero. La adaptación integral de ese harness al CLI Windows sigue pendiente; no se presentan sus resultados anteriores como pruebas ejecutadas en tu PC. Para comprobar manualmente la integración existente, inicia `functions serve`, crea un reciclador CON_APP desde el panel y úsalo en móvil; eso es una comprobación local, no aceptación final automatizada.

## 10. Auditoría de direcciones, CORS y mapas

| Referencia | Ámbito y decisión |
|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` en ambos bootstraps | Producto: argumentos de compilación externos, sin host/clave de Codex incrustados en fuentes |
| `config/supabase.example.json` | Ejemplo sin clave real; archivos generados en config/local ignorados |
| Puertos 54321 API, 54322 DB, 54320 shadow | Defaults del CLI en supabase/config.toml, modificables antes de arrancar; regenerar JSON después |
| Auth `site_url=http://localhost:3000` | Coincide con esta guía. Flujos actuales usan contraseña, sin confirmación de correo. No habilita acceso público ni sustituye CORS |
| 54324 Auth, 54325 Realtime, 54326 Edge, 54327 proxy, 54328 panel | Solo runtime/harness anterior. **No se usan** en el arranque estándar de esta guía |
| CORS de scripts/test-runtime/proxy.cjs | Exclusivo de prueba, origen exacto 127.0.0.1:54328, sin wildcard de credenciales; no se copia a configuración desplegable |
| Edge CORS existente | Ya usa `Access-Control-Allow-Origin: *`, sin `Allow-Credentials`, para peticiones con token Bearer explícito. No procede del proxy Chromium y no se amplió en esta entrega. JWT y verificación ADMIN siguen obligatorios; el cliente no recibe service_role |
| `tiles_url`, `tiles_atribucion`, `tiles_user_agent` | Producto: configurables en assets/config.json de cada app; valor inicial OpenStreetMap, atribución visible, sin geocodificación |
| Política de tratamiento | Configurable y pendiente de contenido jurídico; sin contenido no hay registro ciudadano |
| `.test-artifacts`, env locales, caches, builds | Ignorados y excluidos del ZIP/bundle de fuentes |

No pongas SERVICE_ROLE_KEY, DB_URL o JWT_SECRET en un archivo usado por `--dart-define-from-file`. Esos valores pertenecen al servidor/administración. No compartas la clave administrativa en capturas o chats.

## 11. Parar y resolver problemas frecuentes

- Para Flutter/servidor/Edge en primer plano: Ctrl+C. Para detener la pila local: `supabase stop` (conserva el flujo normal de datos locales del CLI); evita `--no-backup` si quieres conservar datos.
- Docker no responde: abre Desktop, verifica WSL2/Linux containers y `docker info`. No mezcles el Compose histórico con el CLI: sus puertos colisionan.
- CLI fuera de PATH: abre nueva terminal o vuelve a establecer PATH; el helper admite `--supabase-bin C:\tools\supabase\supabase.exe`.
- Puerto ocupado: detén el proceso que lo usa o ajusta config.toml para una nueva instancia, después regenera JSON. No uses reset para solucionar un proceso externo.
- Panel carga pero no permite login: crea el perfil ADMIN con el helper, no solo Auth. CIUDADANO/RECICLADOR no tienen acceso al panel.
- Android sin conexión: confirma emulador 10.0.2.2 o USB con adb reverse, modo debug y mismo puerto del API. No uses la IP del workspace remoto ni desactives TLS.
- Edge falla: comprueba la segunda terminal, JWT del ADMIN y migración 005. No cambies roles/RLS ni uses una clave administrativa en Flutter.
- Mapas vacíos: comprueba proveedor/URL/atribución/conexión; una dirección manual no debe mostrar mapa.
- Espacio insuficiente: libera cachés e imágenes de prueba que no necesites, sin borrar datos valiosos. Este fue un bloqueo real del entorno de desarrollo.

Pendientes externos: ejecución real Windows de esta guía, stack completo CLI, builds/ejecución Android/iOS, GPS real, recuperación durable de creación ambigua, compensaciones de resultado incierto y validación integral RF/HU/QAW. Preparar ejecución local no los declara aprobados.


## 12. Comprobaciones de esta preparación

- **9/9 pruebas unitarias nuevas aprobadas** del helper: loopback, exportación solo pública, puerto configurable, rechazo remoto, alta ADMIN, protección de roles existentes, idempotencia ADMIN, compensación SQL inequívoca y ausencia de borrado Auth con commit incierto. Usan dobles de Auth/BD: no constituyen integración con Supabase CLI.
- JSON, TOML y XML válidos; excepción HTTP únicamente debug y tres hosts locales; archivos generados ignorados por Git. `git diff --check` sin errores.
- Enlaces oficiales de binarios Windows Supabase CLI/Deno respondieron HTTP 200 sin excepciones TLS.
- SQL, RPC, RLS, Edge, contratos/core, código Dart de apps y proxy de pruebas **sin cambios**. No se repitieron suites funcionales ni build web: no hubo cambios en ellos.
- Cambio de plataforma: manifest y recurso Android **debug** para conexión HTTP a Supabase local. Compilación y prueba de esa configuración quedan pendientes de Android SDK/dispositivo; la validación XML no sustituye esa prueba.
- Evidencias: [helper-tests.txt](evidencias/ejecucion-local-windows/helper-tests.txt) y [config-checks.txt](evidencias/ejecucion-local-windows/config-checks.txt).

No se añadió funcionalidad de negocio ni se cambió la arquitectura. Se detiene aquí la preparación local; no se inicia aceptación integral.
