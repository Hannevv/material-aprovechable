# Informe de cierre — fases 1 a 4

## Resultado y recuperación

Se conservó el proyecto existente en `/workspace/work/material-aprovechable`. No se reinició Git, no se descartó código y no se recreó la base al reanudar. Se inspeccionaron los archivos, el estado Git y las evidencias guardadas. Los contenedores estaban detenidos por la interrupción y se arrancaron conservando sus volúmenes.

La base del monorepo, modelo, RLS/permisos y ocho RPC están implementados. Las carpetas móviles/web y de paquetes Dart son solo reservas estructurales, sin código, manifests Flutter ni compilación de clientes. No se avanzó a Edge, Realtime o interfaces.

La comparación con los DOCX mencionados por el usuario continúa pendiente porque no se recibieron. La ejecución se basó en la especificación disponible y las decisiones explícitas posteriores que autorizaron continuar.

## Migraciones

1. `20261117000100_modelo.sql`: cinco ENUM, cinco tablas, PK/FK, UNIQUE/CHECK, seis índices de consulta y triggers de invariantes.
2. `20261117000200_seguridad.sql`: RLS en las cinco tablas, cinco políticas SELECT, revocación de DML y helper privado de rol.
3. `20261117000300_registro.sql`: perfil ciudadano, creación de solicitud y gestión de reciclador SIN_APP/edición/estado.
4. `20261117000400_transiciones.sql`: asignación, recolección, cancelación con precondición e historial transaccional.

Las cuatro se aplicaron satisfactoriamente a una base nueva en la ejecución anterior y nuevamente durante la comprobación de reconstrucción ya completada antes de la interrupción. Al reanudar no se modificaron ni reaplicaron.

## Modelo, claves y restricciones

| Tabla | Claves y restricciones principales |
|---|---|
| usuarios | PK uid; FK auth.users; rol ENUM; nombre obligatorio CIUDADANO/ADMIN; aceptación no nula CIUDADANO |
| recicladores | PK id; FK usuario_uid; UNIQUE documento y usuario_uid; CON_APP exige cuenta, SIN_APP exige null; nombre/documento no vacíos; modalidad/cuenta inmutables; cuenta vinculada de rol RECICLADOR; updated_at mantenido |
| solicitudes | PK id; FK ciudadano_uid y reciclador_id; propietario CIUDADANO; descripción ≤250; GPS completo y en rango o dirección manual no vacía, excluyentes; estado coherente con asociado/fecha |
| solicitud_materiales | PK compuesta solicitud_id/tipo_material; FK solicitud; catálogo ENUM; trigger diferible garantiza al menos un material al commit |
| historial_estados | PK id; FK solicitud/ejecutor/reciclador; CHECK transiciones válidas; ejecutor y rol derivados en las RPC; creación inicial sin historial |

ENUM: rol_usuario, modalidad_reciclador, estado_reciclador, estado_solicitud, tipo_material, con los valores canónicos aprobados. No se añadió tabla de materiales administrable ni organizaciones.

Se verificaron **13 índices**: cinco de PK, dos de unicidad en recicladores y seis explícitos:

- solicitudes(ciudadano_uid, fecha_creacion DESC)
- solicitudes(reciclador_id, estado)
- solicitudes(estado, fecha_creacion DESC)
- solicitud_materiales(tipo_material, solicitud_id)
- historial_estados(solicitud_id, fecha_hora)
- recicladores(estado)

E-06 y la optimización con la consulta final del panel permanecen fuera de esta iteración.

## RLS y privilegios

| Política | Lectura permitida |
|---|---|
| usuarios_lectura | Perfil propio o ADMIN |
| recicladores_lectura | Perfil operativo propio o ADMIN; permite conocer la propia inactividad |
| solicitudes_lectura | CIUDADANO propias; RECICLADOR solo ASIGNADA propia y ACTIVO; ADMIN todas |
| materiales_lectura | Solo cuando la solicitud padre es visible por RLS |
| historial_admin | Solo ADMIN |

No hay políticas de escritura. PUBLIC/anon/authenticated pierden privilegios directos sobre las tablas; authenticated recibe SELECT sujeto a RLS. Se concede EXECUTE únicamente sobre las ocho RPC públicas y el helper privado que necesita RLS. Las funciones de trigger no se conceden a clientes. `private` no forma parte de los esquemas expuestos por PostgREST.

Todas las RPC privilegiadas usan SECURITY DEFINER, search_path vacío y referencias de esquema explícitas; comprueban autorización internamente. El rol procede de usuarios, la identidad de auth.uid(), nunca de user_metadata. Las pruebas incluyen metadata con rol ADMIN sin que produzca escalamiento.

## RPC

- crear_perfil_ciudadano(nombre, fecha_aceptacion_politica): idempotente, rol fijo CIUDADANO; preserva perfil y aceptación existentes.
- crear_solicitud(materiales, descripcion, direccion, latitud, longitud): solicitud y materiales atómicos, sin historial inicial.
- crear_reciclador_sin_app(nombre, documento, telefono): solo ADMIN; no crea cuenta Auth.
- actualizar_reciclador(reciclador_id, nombre, documento, telefono): solo ADMIN; sin parámetros modalidad/correo/cuenta.
- cambiar_estado_reciclador(reciclador_id, estado): solo ADMIN, conserva solicitudes e historial.
- asignar_solicitud(solicitud_id, reciclador_id): ADMIN, PENDIENTE y reciclador ACTIVO.
- marcar_recolectada(solicitud_id): ADMIN o reciclador ACTIVO asociado a solicitud ASIGNADA.
- cancelar_solicitud(solicitud_id, estado_esperado): destino fijo CANCELADA; propietario/PENDIENTE o ADMIN/PENDIENTE-ASIGNADA; comprobación del estado esperado después del bloqueo.

No existe la firma antigua de cancelación ni una RPC genérica de transición. Un rechazo de autorización no devuelve datos del recurso; un conflicto para usuario autorizado puede incluir el estado actual. El reciclador que perdió acceso a una solicitud final recibe rechazo sin ese estado.

## Concurrencia

Se usan transacciones, comparación de estado esperado y bloqueos FOR SHARE/FOR UPDATE. Orden: perfil del reciclador antes de solicitud cuando intervienen ambos. La inactivación actualiza el mismo perfil y se serializa con asignación/recolección. El historial se inserta en la misma transacción que el estado; el asociado se obtiene de la fila persistida para cierres.

Pruebas completadas:

- 10 carreras entre dos ADMIN asignando una misma solicitud: exactamente una confirmación y un historial por solicitud.
- 10 carreras asignación contra cancelación esperada PENDIENTE: exactamente una operación confirma.
- Carrera recolección contra cancelación ADMIN: un único cierre.
- Asignación esperando una inactivación: rechazada tras confirmarse INACTIVO.
- Inactivación esperando una asignación: conserva la asignación ya confirmada y bloquea operaciones posteriores del reciclador.
- Recolección esperando una inactivación: rechazada, conservando ASIGNADA e historial previo.

## Pruebas y resultados

| Suite | Resultado final | Evidencia |
|---|---|---|
| Integración SQL/backend | 28/28 aprobadas, 4.788 s en la reconstrucción previa | evidencias/backend.txt |
| pgTAP | 12/12 aserciones aprobadas | evidencias/pgtap.txt |
| HTTP Auth/PostgREST | 5/5 aprobadas, 0.676 s en la reanudación | evidencias/http.txt |
| Inventario de catálogo | 13 índices, 5 políticas, 8 RPC; hashes de migraciones | evidencias/catalogo.json |

En la reanudación se corrigieron expectativas del test HTTP: el identificador de error de GoTrue se llama `error_code`, mientras que `code` es numérico; el correo inválido produce HTTP 400. Estas correcciones no cambian reglas de negocio ni código de producto. Los cinco casos HTTP se ejecutaron de nuevo y pasaron. Las suites SQL/pgTAP y las migraciones permanecieron sin cambios, por lo que se conservaron sus evidencias sin repetirlas.

Seguridad comprobada: rechazo anónimo, aislamiento por propietario/asignación, metadata no confiable, ausencia de DML directo para los tres roles en las cinco tablas, RPC restringidas, historial solo ADMIN, inactividad con identidad existente y no divulgación de estado ajeno.

Atomicidad comprobada: fallo inyectado en materiales revierte la solicitud; fallo inyectado en historial revierte asignación/recolección/cancelación. E-04 distingue no envío, fallo transaccional y respuesta descartada tras commit con reconsulta autorizada. Esta última es simulación controlada del resultado perdido en backend, no una prueba de transporte móvil ni de una interfaz inexistente.

HTTP comprobado: autorregistro con sesión sin confirmación de correo, perfil fijo CIUDADANO, rechazo de contraseña corta/correo inválido/correo duplicado/credenciales erróneas, inicio/cierre de sesión y rechazo del refresh revocado, RPC y permisos a través de PostgREST.

## Decisiones, diferencias y pendientes

Se eligieron ENUM, UUID, JSONB para resultados de transición, helpers privados, normalización de materiales duplicados y triggers diferibles. No se añadieron funcionalidades fuera de alcance. La política jurídica queda sin contenido y desacoplada; la persistencia de aceptación está implementada, su visualización futura no.

La diferencia material está en el entorno de pruebas: las imágenes completas Supabase PostgreSQL 17 y 15 fallaron por espacio de Docker. Se usó PostgreSQL 17.12 ligero con GoTrue 2.186.0 y PostgREST 14.3 reales. El script reproducible de ese runtime está separado de las migraciones. No se validaron Kong ni el arranque completo `supabase start`/`db reset` del CLI. Esa validación continúa pendiente en un entorno con espacio suficiente; no se presenta como aprobada.

No hubo despliegue remoto ni aprovisionamiento de cuentas reales. La integración con clientes, Edge CON_APP, Streams, Postgres Changes, GPS/mapa y E-06 quedan detenidos por el alcance aprobado.

Los DOCX autoritativos siguen sin estar disponibles para comparación. La carpeta externa de salida prevista por la conversación no pudo crearse por permisos del entorno; el código y este informe permanecen íntegros en el workspace, sin enlace de descarga externo.

## Archivos

Todos los archivos de producto son nuevos respecto del workspace inicial, que solo contenía adjuntos. En esta reanudación se modificó el test HTTP, README y trazabilidad, y se agregaron este informe y las evidencias persistentes. No se modificaron documentos adjuntos. Git permanece sin commits ni remoto.

Inventario completo a continuación (excluye metadatos Git, cachés y artefactos temporales):

```text
.gitignore
README.md
apps/admin_flutter_web/README.md
apps/admin_flutter_web/lib/bootstrap/.gitkeep
apps/admin_flutter_web/lib/presentation/.gitkeep
apps/mobile_flutter/README.md
apps/mobile_flutter/lib/bootstrap/.gitkeep
apps/mobile_flutter/lib/presentation/.gitkeep
config/politica_tratamiento.example.json
docs/contrato-backend.md
docs/decisiones.md
docs/evidencias/backend.txt
docs/evidencias/catalogo.json
docs/evidencias/http.txt
docs/evidencias/pgtap.txt
docs/informe-fases-1-4.md
docs/trazabilidad.md
packages/application/README.md
packages/domain/README.md
packages/infrastructure_mobile/README.md
packages/infrastructure_supabase/README.md
scripts/test-backend.sh
scripts/test-runtime/auth-context.sql
scripts/test-runtime/bootstrap.sql
scripts/test-runtime/compose.yml
scripts/test-runtime/run.sh
supabase/config.toml
supabase/functions/.gitkeep
supabase/migrations/20261117000100_modelo.sql
supabase/migrations/20261117000200_seguridad.sql
supabase/migrations/20261117000300_registro.sql
supabase/migrations/20261117000400_transiciones.sql
supabase/tests/001_schema.test.sql
supabase/tests/auth_http_test.py
supabase/tests/backend_test.py
supabase/tests/requirements.txt
```
