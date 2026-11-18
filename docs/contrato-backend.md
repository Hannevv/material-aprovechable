# Contrato del backend

## RPC públicas

Todas requieren sesión `authenticated`; además cada función comprueba internamente rol y propiedad. No admiten rol, Actor o usuario ejecutor del cliente.

| RPC | Argumentos | Resultado | Autorización |
|---|---|---|---|
| crear_perfil_ciudadano | nombre text, fecha_aceptacion_politica timestamptz | usuarios | auth.uid(); crea solo CIUDADANO; idempotente; no sobrescribe perfil existente |
| crear_solicitud | materiales tipo_material[], descripcion text = null, direccion text = null, latitud double = null, longitud double = null | solicitudes | CIUDADANO |
| crear_reciclador_sin_app | nombre text, documento text, telefono text = null | recicladores | ADMIN |
| actualizar_reciclador | reciclador_id uuid, nombre text, documento text, telefono text = null | recicladores | ADMIN; no recibe modalidad, correo ni cuenta |
| cambiar_estado_reciclador | reciclador_id uuid, estado estado_reciclador | recicladores | ADMIN |
| asignar_solicitud | solicitud_id uuid, reciclador_id uuid | jsonb | ADMIN; PENDIENTE, destino ACTIVO |
| marcar_recolectada | solicitud_id uuid | jsonb | ADMIN o reciclador ACTIVO asociado a solicitud ASIGNADA |
| cancelar_solicitud | solicitud_id uuid, estado_esperado estado_solicitud | jsonb | CIUDADANO propietario/PENDIENTE; ADMIN/PENDIENTE o ASIGNADA |

Una transición confirmada devuelve `confirmada: true` y `estado_actual`. Un conflicto de estado para alguien autorizado devuelve `confirmada: false`, `codigo: CONFLICTO_ESTADO` y estado actual. La cancelación siempre tiene destino CANCELADA; no hay RPC genérica ni sobrecarga antigua de un argumento.

Falta de autorización: SQLSTATE 42501, mensaje `No autorizado`, sin detalles del recurso. Un ID inexistente produce el mismo rechazo. Datos inválidos: 22023 o restricciones PostgreSQL 23xxx. Las autorizaciones se comprueban antes de información de estado. El reciclador que ya no puede leer una solicitud final recibe rechazo sin estado; debe reconciliar su listado autorizado. La confirmación de su propia recolección sí informa el resultado de la operación que acaba de ejecutar.

## Atomicidad y concurrencia

- Creación de solicitud y materiales en una transacción. Trigger diferible exige al menos un material al commit. No se genera historial inicial.
- La asignación bloquea el reciclador con FOR SHARE y la solicitud con FOR UPDATE; verifica ACTIVO/PENDIENTE y hace UPDATE condicionado al estado. Dos asignaciones de una solicitud se serializan y solo una confirma.
- La recolección por RECICLADOR bloquea primero su perfil activo con FOR SHARE y luego la solicitud. La inactivación usa UPDATE sobre el perfil y debe esperar; si la inactivación ganó, la operación se rechaza.
- Cancelación y cierre ADMIN bloquean la solicitud. El estado esperado de cancelación se compara después de adquirir el bloqueo.
- El orden reciclador → solicitud evita inversión de bloqueos entre asignación y recolección. Inactivación no necesita bloquear solicitudes.
- Cambio de estado e INSERT de historial pertenecen a la misma transacción. Ante fallo de historial no queda cambio parcial. El asociado de cierre siempre se toma de la fila persistida.
- Una asignación confirmada antes de una inactivación conserva su asociación; después solo ADMIN puede cerrar mientras el reciclador esté inactivo. No existe reasignación.

## E-04 corregido

| Momento del fallo | Resultado persistente esperado | Conducta futura del cliente |
|---|---|---|
| Antes de enviar | No se ejecuta RPC; cero solicitud nueva | Informar que no se envió |
| Dentro de la transacción | Rollback completo; cero solicitud/materiales parciales | Informar fallo confirmado |
| Respuesta perdida tras commit | Puede existir solicitud completa | Resultado no confirmado; consultar las solicitudes autorizadas antes de cualquier reintento |

La prueba de respuesta perdida descarta deliberadamente el resultado después del commit y comprueba la reconsulta autorizada. No simula transporte móvil ni prueba una interfaz inexistente. Si la reconsulta no permite distinguir un envío de otro similar, se conserva el estado no confirmado; no se inventa una confirmación ni se reintenta automáticamente. La firma aprobada no incorpora una clave de idempotencia por solicitud, por lo que esta entrega no promete deduplicación de llamadas repetidas a `crear_solicitud`.

## Auth

Auth valida correo y longitud mínima 8, genera hashes y entrega sesión sin exigir confirmación de correo. El autorregistro Auth y el perfil son dos operaciones: si el segundo falla, se reintenta exclusivamente el perfil idempotente. Una cuenta Auth sin perfil no tiene permisos de negocio. Cierre de sesión invalida la sesión de refresco; no se afirma que el JWT de acceso emitido desaparezca antes de su expiración. La comprobación de ACTIVO se hace en RLS/RPC incluso con JWT vigente.
