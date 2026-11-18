"""Integration tests on the disposable local Supabase instance only.
SQL sessions use SET LOCAL ROLE + verified JWT claims, as PostgREST does.
HTTP authentication tests are in auth_http_test.py.
"""
import concurrent.futures
import json
import os
import threading
import time
import unittest
import uuid
from contextlib import contextmanager

import psycopg

DSN = os.environ.get('TEST_DATABASE_URL', 'postgresql://postgres:postgres@127.0.0.1:54322/postgres')
C1, C2, A1, A2, R1, R2, NEW = [str(uuid.UUID(int=i)) for i in range(1, 8)]
RID1, RID2, RIDS = [str(uuid.UUID(int=i)) for i in range(11, 14)]
TABLES = ['usuarios', 'recicladores', 'solicitudes', 'solicitud_materiales', 'historial_estados']

@contextmanager
def db(uid=None, role='authenticated'):
    with psycopg.connect(DSN) as conn:
        if uid is not None or role == 'anon':
            conn.execute('set local role ' + role)
            conn.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid or '',))
            conn.execute("select set_config('request.jwt.claims', %s, true)",
                         (json.dumps({'sub': uid, 'role': role, 'user_metadata': {'rol': 'ADMIN'}}),))
        yield conn


def rpc(conn, name, args=()):
    return conn.execute('select public.' + name + '(' + ','.join(['%s'] * len(args)) + ')', args).fetchone()[0]


def scalar(sql, args=()):
    with db() as conn:
        return conn.execute(sql, args).fetchone()[0]


class Backend(unittest.TestCase):
    def setUp(self):
        # Explicit opt-in; this fixture is destructive and must never target a shared database.
        if os.environ.get('ALLOW_LOCAL_TEST_RESET') != '1' or '127.0.0.1:54322/' not in DSN:
            raise RuntimeError('Requires ALLOW_LOCAL_TEST_RESET=1 and isolated localhost:54322')
        with db() as c:
            c.execute('truncate public.historial_estados, public.solicitud_materiales, public.solicitudes, public.recicladores, public.usuarios')
            for uid in [C1,C2,A1,A2,R1,R2,NEW]:
                c.execute('insert into auth.users(id,email) values (%s,%s) on conflict(id) do nothing', (uid, uid+'@example.test'))
            for uid, role in [(C1,'CIUDADANO'),(C2,'CIUDADANO'),(A1,'ADMIN'),(A2,'ADMIN'),(R1,'RECICLADOR'),(R2,'RECICLADOR')]:
                c.execute('insert into public.usuarios(uid,nombre,rol,fecha_aceptacion_politica) values (%s,%s,%s,now())', (uid,role,role))
            for rid,uid in [(RID1,R1),(RID2,R2)]:
                c.execute("insert into public.recicladores(id,usuario_uid,nombre,documento,modalidad) values (%s,%s,'Reciclador',%s,'CON_APP')", (rid,uid,rid))
            c.execute("insert into public.recicladores(id,nombre,documento,modalidad) values (%s,'Sin app','SIN-1','SIN_APP')", (RIDS,))

    def create(self, uid=C1, materials=None, description=None, address='Calle 1', lat=None, lon=None):
        with db(uid) as c:
            return c.execute('select id from public.crear_solicitud(%s,%s,%s,%s,%s)',
                             (materials if materials is not None else ['PAPEL','VIDRIO'],description,address,lat,lon)).fetchone()[0]

    def assign(self, sid, rid=RID1):
        with db(A1) as c:
            return rpc(c,'asignar_solicitud',(sid,rid))

    def denied(self, uid, name, args):
        with self.assertRaises(psycopg.errors.InsufficientPrivilege) as err:
            with db(uid) as c: rpc(c,name,args)
        self.assertEqual(err.exception.diag.message_primary, 'No autorizado')
        self.assertIsNone(err.exception.diag.message_detail)

    def test_profile_idempotent_and_protected(self):
        with db(NEW) as c:
            c.execute("select public.crear_perfil_ciudadano('Nombre',now())")
            c.execute("select public.crear_perfil_ciudadano('Otro nombre',now())")
        self.assertEqual(scalar('select nombre from public.usuarios where uid=%s',(NEW,)), 'Nombre')
        self.denied(A1,'crear_perfil_ciudadano',('Cambio','2026-01-01'))
        self.assertEqual(scalar('select rol from public.usuarios where uid=%s',(A1,)), 'ADMIN')

    def test_profile_requires_acceptance(self):
        with self.assertRaises(psycopg.errors.InvalidParameterValue):
            with db(NEW) as c: rpc(c,'crear_perfil_ciudadano',('Nombre',None))
        self.assertEqual(scalar('select count(*) from public.usuarios where uid=%s',(NEW,)),0)

    def test_rls_isolation_and_materials(self):
        mine=self.create(); other=self.create(C2)
        with db(C1) as c:
            self.assertEqual(c.execute('select id from public.solicitudes').fetchall(),[(mine,)])
            self.assertEqual(c.execute('select count(*) from public.solicitudes where id=%s',(other,)).fetchone()[0],0)
            self.assertEqual(c.execute('select count(*) from public.solicitud_materiales').fetchone()[0],2)
            self.assertEqual(c.execute('select count(*) from public.recicladores').fetchone()[0],0)
            self.assertEqual(c.execute('select count(*) from public.usuarios').fetchone()[0],1)
        with db(A1) as c: self.assertEqual(c.execute('select count(*) from public.solicitudes').fetchone()[0],2)

    def test_no_direct_dml_for_any_client(self):
        for uid in [C1,R1,A1]:
            for table in TABLES:
                for operation in ['insert','update','delete']:
                    with self.subTest(uid=uid,table=table,operation=operation):
                        with db(uid) as c:
                            self.assertFalse(c.execute('select has_table_privilege(current_user,%s,%s)',('public.'+table,operation)).fetchone()[0])
            with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                with db(uid) as c: c.execute("update public.usuarios set rol='ADMIN'")
        with self.assertRaises(psycopg.errors.InsufficientPrivilege):
            with db(role='anon') as c: c.execute('select * from public.solicitudes')
        with self.assertRaises(psycopg.errors.InsufficientPrivilege):
            with db(role='anon') as c: rpc(c,'crear_perfil_ciudadano',('N','2026-01-01'))

    def test_direct_dml_rejected_on_every_table(self):
        for uid in [C1,R1,A1]:
            for table,column in [('usuarios','nombre'),('recicladores','nombre'),('solicitudes','estado'),('solicitud_materiales','tipo_material'),('historial_estados','estado_nuevo')]:
                statements=[f'insert into public.{table} default values',f'update public.{table} set {column}={column}',f'delete from public.{table}']
                for statement in statements:
                    with self.subTest(uid=uid,statement=statement):
                        with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                            with db(uid) as c: c.execute(statement)

    def test_recollection_waits_for_inactivation(self):
        sid=self.create(); self.assign(sid)
        def collect():
            with db(R1) as c: return rpc(c,'marcar_recolectada',(sid,))
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            with db(A1) as c:
                rpc(c,'cambiar_estado_reciclador',(RID1,'INACTIVO'))
                future=pool.submit(collect)
                time.sleep(.15)
                self.assertFalse(future.done())
            with self.assertRaises(psycopg.errors.InsufficientPrivilege): future.result(timeout=5)
        self.assertEqual(scalar('select estado from public.solicitudes where id=%s',(sid,)),'ASIGNADA')
        self.assertEqual(scalar('select count(*) from public.historial_estados'),1)

    def test_metadata_cannot_escalate_role(self):
        sid=self.create()
        self.denied(C1,'asignar_solicitud',(sid,RID1))
        self.denied(R1,'crear_reciclador_sin_app',('X','X',None))
        self.denied(A1,'crear_solicitud',(['PAPEL'],None,'Calle',None,None))

    def test_creation_atomic_and_no_initial_history(self):
        sid=self.create(materials=['PAPEL','PAPEL','VIDRIO'])
        self.assertEqual(scalar('select count(*) from public.solicitud_materiales where solicitud_id=%s',(sid,)),2)
        self.assertEqual(scalar('select count(*) from public.historial_estados'),0)
        self.assertEqual(scalar('select estado from public.solicitudes where id=%s',(sid,)),'PENDIENTE')

    def test_invalid_creation_cases(self):
        cases=[dict(materials=[]),dict(materials=[None]),dict(materials=['OTRO']),dict(description='x'*251),
               dict(description='x'*250+' '),dict(address=None),dict(address='  '),dict(address=None,lat=1),
               dict(address=None,lon=1),dict(lat=1,lon=1),dict(address=None,lat=91,lon=0),
               dict(address=None,lat=0,lon=-181),dict(address=None,lat=float('nan'),lon=1)]
        for args in cases:
            with self.subTest(args=args):
                with self.assertRaises(psycopg.Error): self.create(**args)
        self.assertEqual(scalar('select count(*) from public.solicitudes'),0)
        self.assertEqual(scalar('select count(*) from public.solicitud_materiales'),0)
        self.create(description='x'*250,address=None,lat=-90,lon=180)

    def test_deferred_nonempty_materials_constraint(self):
        with self.assertRaises(psycopg.errors.CheckViolation):
            with db() as c: c.execute("insert into public.solicitudes(ciudadano_uid,direccion) values (%s,'Calle')",(C1,))
        sid=self.create()
        with self.assertRaises(psycopg.errors.CheckViolation):
            with db() as c: c.execute('delete from public.solicitud_materiales where solicitud_id=%s',(sid,))
        self.assertEqual(scalar('select count(*) from public.solicitud_materiales'),2)

    def test_recycler_visible_only_active_assigned(self):
        sid=self.create(); self.assign(sid)
        other=self.create(C2); self.assign(other,RID2)
        with db(R1) as c: self.assertEqual(c.execute('select id from public.solicitudes').fetchall(),[(sid,)])
        with db(A1) as c: rpc(c,'cancelar_solicitud',(sid,'ASIGNADA'))
        with db(R1) as c:
            self.assertEqual(c.execute('select count(*) from public.solicitudes').fetchone()[0],0)
            self.assertEqual(c.execute('select count(*) from public.solicitud_materiales').fetchone()[0],0)
        self.denied(R1,'marcar_recolectada',(sid,))

    def test_recycler_recollection_and_history(self):
        sid=self.create(); self.assign(sid)
        self.denied(R2,'marcar_recolectada',(sid,))
        with db(R1) as c: self.assertTrue(rpc(c,'marcar_recolectada',(sid,))['confirmada'])
        with db(A1) as c:
            row=c.execute("select usuario_ejecutor_uid,rol_ejecutor,reciclador_id from public.historial_estados where estado_nuevo='RECOLECTADA'").fetchone()
            self.assertEqual(tuple(map(str,row)),(R1,'RECICLADOR',RID1))
        for uid in [C1,R1]:
            with db(uid) as c: self.assertEqual(c.execute('select count(*) from public.historial_estados').fetchone()[0],0)

    def test_cancel_owner_and_expected_state(self):
        sid=self.create()
        self.denied(C2,'cancelar_solicitud',(sid,'PENDIENTE'))
        self.denied(C2,'cancelar_solicitud',(uuid.uuid4(),'PENDIENTE'))
        self.assign(sid)
        with db(C1) as c:
            result=rpc(c,'cancelar_solicitud',(sid,'PENDIENTE'))
            self.assertEqual(result,{'confirmada':False,'estado_actual':'ASIGNADA','codigo':'CONFLICTO_ESTADO'})
        with self.assertRaises(psycopg.errors.InvalidParameterValue):
            with db(C1) as c: rpc(c,'cancelar_solicitud',(sid,'ASIGNADA'))
        with db(A1) as c: self.assertFalse(rpc(c,'cancelar_solicitud',(sid,'PENDIENTE'))['confirmada'])
        self.assertEqual(scalar('select count(*) from public.historial_estados'),1)
        with db(A1) as c: self.assertTrue(rpc(c,'cancelar_solicitud',(sid,'ASIGNADA'))['confirmada'])
        self.assertEqual(str(scalar("select reciclador_id from public.historial_estados where estado_nuevo='CANCELADA'")),RID1)

    def test_pending_cancel_history_without_recycler(self):
        sid=self.create()
        with db(C1) as c: self.assertTrue(rpc(c,'cancelar_solicitud',(sid,'PENDIENTE'))['confirmada'])
        self.assertIsNone(scalar('select reciclador_id from public.historial_estados'))
        self.assertEqual(str(scalar('select usuario_ejecutor_uid from public.historial_estados')),C1)

    def test_final_states_no_reopen(self):
        for target in ['CANCELADA','RECOLECTADA']:
            sid=self.create(); self.assign(sid)
            with db(A1) as c:
                if target=='CANCELADA': rpc(c,'cancelar_solicitud',(sid,'ASIGNADA'))
                else: rpc(c,'marcar_recolectada',(sid,))
                for name,args in [('asignar_solicitud',(sid,RID2)),('marcar_recolectada',(sid,)),('cancelar_solicitud',(sid,'ASIGNADA'))]:
                    self.assertFalse(rpc(c,name,args)['confirmada'])
        self.assertEqual(scalar('select count(*) from public.historial_estados'),4)

    def test_recycler_management_and_inactivation(self):
        sid=self.create(); self.assign(sid)
        with db(A1) as c:
            rpc(c,'actualizar_reciclador',(RID1,'Nuevo','NUEVO',None))
            rpc(c,'cambiar_estado_reciclador',(RID1,'INACTIVO'))
        with db(R1) as c: self.assertEqual(c.execute('select count(*) from public.solicitudes').fetchone()[0],0)
        self.denied(R1,'marcar_recolectada',(sid,))
        with self.assertRaises(psycopg.errors.InvalidParameterValue): self.assign(self.create(),RID1)
        with db(A1) as c:
            self.assertTrue(rpc(c,'marcar_recolectada',(sid,))['confirmada'])
            rpc(c,'cambiar_estado_reciclador',(RID1,'ACTIVO'))
        self.assign(self.create(),RID1)
        with db(R1) as c: self.assertEqual(c.execute('select count(*) from public.solicitudes').fetchone()[0],1)

    def test_sin_app_and_uniqueness(self):
        with db(A1) as c:
            rid=c.execute("select id from public.crear_reciclador_sin_app('Nombre','DOC',null)").fetchone()[0]
        self.assertIsNone(scalar('select usuario_uid from public.recicladores where id=%s',(rid,)))
        with self.assertRaises(psycopg.errors.UniqueViolation):
            with db(A1) as c: rpc(c,'crear_reciclador_sin_app',('Otro','DOC',None))
        with self.assertRaises(psycopg.errors.UniqueViolation):
            with db(A1) as c: rpc(c,'actualizar_reciclador',(RID1,'Otro','DOC',None))
        sid=self.create(); self.assign(sid,rid)
        with db(A1) as c: self.assertTrue(rpc(c,'marcar_recolectada',(sid,))['confirmada'])

    def test_modality_and_account_constraints(self):
        with self.assertRaises(psycopg.errors.CheckViolation):
            with db() as c: c.execute("update public.recicladores set modalidad='SIN_APP',usuario_uid=null where id=%s",(RID1,))
        with self.assertRaises(psycopg.errors.CheckViolation):
            with db() as c: c.execute("insert into public.recicladores(nombre,documento,modalidad,usuario_uid) values ('X','X','CON_APP',%s)",(C1,))

    def test_rollback_when_history_insert_fails(self):
        sid=self.create()
        with db() as c:
            c.execute("create function private.test_fail_history() returns trigger language plpgsql as $$ begin raise exception 'injected'; end $$")
            c.execute('create trigger test_fail_history before insert on public.historial_estados for each row execute function private.test_fail_history()')
        try:
            with self.assertRaises(psycopg.errors.RaiseException): self.assign(sid)
            self.assertEqual(scalar('select estado from public.solicitudes where id=%s',(sid,)),'PENDIENTE')
            self.assertIsNone(scalar('select reciclador_id from public.solicitudes where id=%s',(sid,)))
            self.assertEqual(scalar('select count(*) from public.historial_estados'),0)
        finally:
            with db() as c:
                c.execute('drop trigger test_fail_history on public.historial_estados')
                c.execute('drop function private.test_fail_history()')

    def test_rollback_on_failed_history_for_closures(self):
        sid=self.create(); self.assign(sid)
        with db() as c:
            c.execute("create function private.test_fail_history() returns trigger language plpgsql as $$ begin raise exception 'injected'; end $$")
            c.execute('create trigger test_fail_history before insert on public.historial_estados for each row execute function private.test_fail_history()')
        try:
            for name,args in [('marcar_recolectada',(sid,)),('cancelar_solicitud',(sid,'ASIGNADA'))]:
                with self.assertRaises(psycopg.errors.RaiseException):
                    with db(A1) as c: rpc(c,name,args)
                self.assertEqual(scalar('select estado from public.solicitudes where id=%s',(sid,)),'ASIGNADA')
                self.assertEqual(scalar('select count(*) from public.historial_estados'),1)
        finally:
            with db() as c:
                c.execute('drop trigger test_fail_history on public.historial_estados')
                c.execute('drop function private.test_fail_history()')

    def test_e04_before_send_and_transaction_failure(self):
        # Before send: no RPC is dispatched; DB remains empty.
        self.assertEqual(scalar('select count(*) from public.solicitudes'),0)
        with db() as c:
            c.execute("create function private.test_fail_material() returns trigger language plpgsql as $$ begin raise exception 'injected'; end $$")
            c.execute('create trigger test_fail_material before insert on public.solicitud_materiales for each row execute function private.test_fail_material()')
        try:
            with self.assertRaises(psycopg.errors.RaiseException): self.create()
            self.assertEqual(scalar('select count(*) from public.solicitudes'),0)
            self.assertEqual(scalar('select count(*) from public.solicitud_materiales'),0)
        finally:
            with db() as c:
                c.execute('drop trigger test_fail_material on public.solicitud_materiales')
                c.execute('drop function private.test_fail_material()')

    def test_e04_lost_response_after_commit_requery(self):
        # Discard RPC response intentionally; verify authorized reconciliation, no retry.
        self.create()
        with db(C1) as c:
            rows=c.execute('select id from public.solicitudes').fetchall()
            self.assertEqual(len(rows),1)
            self.assertEqual(c.execute('select count(*) from public.solicitud_materiales').fetchone()[0],2)
        with db(C2) as c: self.assertEqual(c.execute('select count(*) from public.solicitudes').fetchone()[0],0)

    def race(self, actions):
        barrier=threading.Barrier(len(actions))
        def run(action):
            uid,name,args=action
            with db(uid) as c:
                c.execute("set local lock_timeout='5s'")
                barrier.wait(timeout=5)
                return rpc(c,name,args)
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(actions)) as pool:
            return list(pool.map(run,actions))

    def test_concurrent_assignment_e08(self):
        for _ in range(10):
            sid=self.create()
            results=self.race([(A1,'asignar_solicitud',(sid,RID1)),(A2,'asignar_solicitud',(sid,RID2))])
            self.assertEqual(sum(r['confirmada'] for r in results),1)
            self.assertEqual(scalar('select count(*) from public.historial_estados where solicitud_id=%s',(sid,)),1)

    def test_concurrent_assignment_cancel(self):
        for _ in range(10):
            sid=self.create()
            results=self.race([(A1,'asignar_solicitud',(sid,RID1)),(A2,'cancelar_solicitud',(sid,'PENDIENTE'))])
            self.assertEqual(sum(r['confirmada'] for r in results),1)
            self.assertEqual(scalar('select count(*) from public.historial_estados where solicitud_id=%s',(sid,)),1)

    def test_concurrent_final_transitions(self):
        sid=self.create(); self.assign(sid)
        results=self.race([(A1,'marcar_recolectada',(sid,)),(A2,'cancelar_solicitud',(sid,'ASIGNADA'))])
        self.assertEqual(sum(r['confirmada'] for r in results),1)
        self.assertEqual(scalar('select count(*) from public.historial_estados where solicitud_id=%s',(sid,)),2)

    def test_assignment_waits_for_inactivation(self):
        sid=self.create()
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            with db(A1) as c:
                rpc(c,'cambiar_estado_reciclador',(RID1,'INACTIVO'))
                future=pool.submit(self.assign,sid)
                time.sleep(.15)
                self.assertFalse(future.done())
            with self.assertRaises(psycopg.errors.InvalidParameterValue): future.result(timeout=5)
        self.assertEqual(scalar('select estado from public.solicitudes where id=%s',(sid,)),'PENDIENTE')

    def test_inactivation_waits_for_assignment(self):
        sid=self.create()
        def deactivate():
            with db(A2) as c: rpc(c,'cambiar_estado_reciclador',(RID1,'INACTIVO'))
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            with db(A1) as c:
                rpc(c,'asignar_solicitud',(sid,RID1))
                future=pool.submit(deactivate)
                time.sleep(.15)
                self.assertFalse(future.done())
            future.result(timeout=5)
        self.denied(R1,'marcar_recolectada',(sid,))
        self.assertEqual(scalar('select estado from public.solicitudes where id=%s',(sid,)),'ASIGNADA')

    def test_public_rpc_surface_and_search_path(self):
        with db() as c:
            names=c.execute("select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef order by 1").fetchall()
            self.assertEqual([n[0] for n in names],sorted(['crear_perfil_ciudadano','crear_solicitud','crear_reciclador_sin_app','actualizar_reciclador','cambiar_estado_reciclador','asignar_solicitud','marcar_recolectada','cancelar_solicitud']))
            for name,oid,config in c.execute("select p.proname,p.oid,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef"):
                self.assertIn('search_path=""',config)
                self.assertFalse(c.execute("select has_function_privilege('anon',%s,'execute')",(oid,)).fetchone()[0])
                self.assertTrue(c.execute("select has_function_privilege('authenticated',%s,'execute')",(oid,)).fetchone()[0])

if __name__=='__main__': unittest.main(verbosity=2)
