# Trazabilidad técnica de presentación — fases 8–9

Extiende la matriz histórica de fases 1–4. No constituye aceptación final ni resultados académicos. Se mantienen identificadores RF/HU de la documentación disponible y las correcciones explícitas del usuario.

| RF / HU | Pantalla o flujo | Servicio / pruebas ejecutadas |
|---|---|---|
| RF-01 / 01.1 | Móvil: registro, política/aceptación | AuthService; pruebas de registro, contraseña, política ausente y widgets |
| RF-01 / 01.2–01.3 | Login/logout en ambas apps | AuthService; controladores, widgets y Chromium ADMIN |
| RF-02 / 02.1 | Guards móvil CIUDADANO/RECICLADOR, web ADMIN | SessionController + AuthService; rechazo de roles, logout y cambio de usuario |
| RF-03 / 03.1 | Nueva solicitud, materiales, descripción, GPS/manual, ID, ambigüedad | SolicitudService + Strategy; límites 0/250/>250, unitarias/widgets y commit real con respuesta descartada |
| RF-04 / 04.1 | Mis solicitudes | observarMisSolicitudes; lista vacía, actualización por Stream y backend real |
| RF-05 / 05.1 | Mis recolecciones, dirección o marcador | observarMisAsignaciones + geolocator/flutter_map; widgets y RLS real; GPS físico pendiente |
| RF-06 / 06.1 | Marcar Recolectada | marcarRecolectada; confirmación, solicitud ajena e inactivación contra backend real |
| RF-07 / 07.1 | Registrar reciclador CON_APP/SIN_APP | RecicladorService; formulario, contrato Edge y 7 pruebas de integración Edge |
| RF-07 / 07.2–07.4 | Listar, editar, inactivar/reactivar | RecicladorService; controladores/widgets e inactivación real |
| RF-08 / 08.1 | Panel solicitudes, filtros combinados, mapa/lista | observarSolicitudes; filtros/materiales sin duplicados, responsive y navegación Chromium |
| RF-09 / 09.1 | Asignación manual | asignar; CON_APP/SIN_APP activos, widgets y dos controladores ADMIN compitiendo sobre RPC real |
| RF-10 / 10.1 | Cierre administrativo | cancelarComoAdmin y marcarRecolectada; estado observado, conflicto y no reintento automático |
| RF-11 / 11.1 | Historial ADMIN | consultarHistorial; campos de actor/rol/reciclador, orden y dos transiciones reales sin creación inicial |
| RF-12 / 12.1 | Cancelar solicitud propia PENDIENTE | cancelarPendientePropia; confirmación, precondición y conflicto |

QAW: E-01/E-02 control de acceso probado en UI y backend local; E-03 suscripción/reconexión probadas sin garantizar latencia; E-04 commit real con respuesta perdida, revisión previa al reintento y recuperación durable pendiente; E-05 rechazo de recolección ajena; E-06 filtros/ubicaciones probados, sin ensayo de rendimiento/carga; E-07 inactivación y rechazo operativo; E-08 carrera real entre dos controladores ADMIN. La validación integral RF/HU/QAW sigue pendiente de nueva aprobación.
