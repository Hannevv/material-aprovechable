# Trazabilidad de esta iteración

La cobertura indicada corresponde al backend. No equivale a aceptación completa de las HU de interfaz.

| RF/HU | Componentes de fases 1–4 | Pruebas concretas |
|---|---|---|
| RF-01 / 01.1 | Auth, usuarios, crear_perfil_ciudadano | profile_idempotent_and_protected; profile_requires_acceptance; signup_profile_login_logout; password_and_invalid_credentials; duplicate_email_rejected |
| RF-01 / 01.2–01.3 | Auth y rol protegido | signup_profile_login_logout; password_and_invalid_credentials; recycler_management_and_inactivation. Navegación y limpieza de cliente pendientes |
| RF-02 / 02.1 | RLS, grants, autorización de RPC | rls_isolation_and_materials; no_direct_dml_for_any_client; direct_dml_rejected_on_every_table; metadata_cannot_escalate_role; api_no_profile_no_escalation_no_dml; public_rpc_surface_and_search_path |
| RF-03 / 03.1 | solicitudes, solicitud_materiales, crear_solicitud | creation_atomic_and_no_initial_history; invalid_creation_cases; deferred_nonempty_materials_constraint; e04_before_send_and_transaction_failure; e04_lost_response_after_commit_requery |
| RF-04 / 04.1 | SELECT propio y materiales | rls_isolation_and_materials. Orden/vista/Streams pendientes |
| RF-05 / 05.1 | SELECT ASIGNADA propia y ACTIVO | recycler_visible_only_active_assigned; recycler_management_and_inactivation. Mapa/suscripción pendientes |
| RF-06 / 06.1 | marcar_recolectada, historial | recycler_recollection_and_history; final_states_no_reopen; recollection_waits_for_inactivation |
| RF-07 / 07.1 | crear_reciclador_sin_app, constraints | sin_app_and_uniqueness; modality_and_account_constraints. CON_APP/Edge pendiente |
| RF-07 / 07.2–07.4 | actualizar_reciclador, cambiar_estado_reciclador, SELECT ADMIN | recycler_management_and_inactivation; sin_app_and_uniqueness; assignment_waits_for_inactivation; inactivation_waits_for_assignment |
| RF-08 / 08.1 | SELECT ADMIN, índices previstos | rls_isolation_and_materials. Filtros finales, mapa, Realtime y E-06 pendientes |
| RF-09 / 09.1 | asignar_solicitud, historial | concurrent_assignment_e08 (10 carreras); concurrent_assignment_cancel (10 carreras); rollback_when_history_insert_fails |
| RF-10 / 10.1 | cancelar_solicitud con precondición, marcar_recolectada | cancel_owner_and_expected_state; concurrent_final_transitions; final_states_no_reopen |
| RF-11 / 11.1 | historial_estados, RLS ADMIN | recycler_recollection_and_history; pending_cancel_history_without_recycler; no_direct_dml_for_any_client |
| RF-12 / 12.1 | cancelar_solicitud propietario/PENDIENTE | cancel_owner_and_expected_state; pending_cancel_history_without_recycler; concurrent_assignment_cancel |

## QAW

- E-01: permisos ADMIN comprobados por SQL/API; ingreso a panel no probado porque no hay interfaz.
- E-02: consultas sin filtro y por ID ajeno comprobadas bajo RLS.
- E-03: pendiente; no se habilita Realtime en esta fase.
- E-04: tres escenarios distinguidos en contrato; rollback y reconsulta probados en backend, transporte/interfaz pendientes.
- E-05: intento de recolección ajena rechazado sin datos ni historial.
- E-06: pendiente hasta panel y consulta final.
- E-07: inactivación, referencias y rechazo con identidad existente probados en SQL; cierre/interacción móvil pendiente.
- E-08: carreras reales entre dos conexiones con identidades ADMIN distintas.

RN-01 se aplica en perfil; RN-02–03 en creación y constraints; RN-04–07 en transiciones, bloqueos e historial; RN-08–09 en recicladores, RLS y RPC de gestión.
