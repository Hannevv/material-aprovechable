import json,sys,unittest,uuid
from pathlib import Path
import requests,psycopg
sys.path.insert(0,str(Path('scripts/test-runtime').resolve()))
from local_tokens import token

class Edge(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.f=json.loads(Path('.test-artifacts/phase567.json').read_text());cls.s=requests.Session();cls.s.trust_env=False
  cls.key=token('service_role');cls.dsn='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
  cls.tokens={}
  for role in ['admin','ciudadano']:
   r=cls.s.post('http://127.0.0.1:54324/token?grant_type=password',json={'email':cls.f[role]['email'],'password':cls.f[role]['password']});r.raise_for_status();cls.tokens[role]=r.json()['access_token']
 def datos(self):return {'nombre':'Edge test','documento':uuid.uuid4().hex,'correo':uuid.uuid4().hex+'@example.com','contrasena_inicial':'Password1234'}
 def call(self,d,role='admin'):
  return self.s.post('http://127.0.0.1:54326',headers={} if role is None else {'Authorization':'Bearer '+self.tokens[role]},json=d,timeout=30)
 def count(self,email,table='auth.users'):
  with psycopg.connect(self.dsn) as c:return c.execute('select count(*) from '+table+' where '+('email' if table=='auth.users' else 'documento')+'=%s',(email,)).fetchone()[0]
 def test_admin_creates_fixed_profiles_no_secrets(self):
  d=self.datos();r=self.call(d);self.assertEqual(r.status_code,201,r.text);p=r.json()['reciclador']
  self.assertEqual((p['modalidad'],p['estado']),('CON_APP','ACTIVO'));self.assertNotIn(self.key,r.text);self.assertNotIn(d['contrasena_inicial'],r.text)
  with psycopg.connect(self.dsn) as c:self.assertEqual(c.execute('select rol from public.usuarios where uid=%s',(p['usuario_uid'],)).fetchone()[0],'RECICLADOR')
 def test_missing_and_non_admin(self):
  for role,status in [(None,401),('ciudadano',403)]:
   d=self.datos();r=self.call(d,role);self.assertEqual(r.status_code,status,r.text);self.assertEqual(self.count(d['correo']),0)
 def test_forbidden_role_modality_state(self):
  for k in ['rol','modalidad','estado']:
   d={**self.datos(),k:'ADMIN'};r=self.call(d);self.assertEqual(r.status_code,400,r.text);self.assertEqual(self.count(d['correo']),0)
 def test_duplicate_email_does_not_delete_original(self):
  d=self.datos();self.assertEqual(self.call(d).status_code,201);d['documento']=uuid.uuid4().hex;r=self.call(d);self.assertEqual(r.status_code,409,r.text);self.assertEqual(self.count(d['correo']),1)
 def test_duplicate_document_compensates_new_auth(self):
  d=self.datos();self.assertEqual(self.call(d).status_code,201);original=d['correo'];d['correo']=uuid.uuid4().hex+'@example.com'
  r=self.call(d);self.assertEqual(r.status_code,409,r.text);self.assertEqual(self.count(d['correo']),0);self.assertEqual(self.count(original),1)
 def test_partial_profile_failure_rolls_back_and_compensates(self):
  with psycopg.connect(self.dsn) as c:
   c.execute("create function private.edge_test_fail() returns trigger language plpgsql as $$ begin if new.nombre='FAIL_EDGE_TEST' then raise exception 'injected'; end if; return new; end $$")
   c.execute('create trigger edge_test_fail before insert on public.recicladores for each row execute function private.edge_test_fail()')
  try:
   d=self.datos();d['nombre']='FAIL_EDGE_TEST';r=self.call(d);self.assertEqual(r.status_code,400,r.text);self.assertEqual(self.count(d['correo']),0);self.assertEqual(self.count(d['documento'],'public.recicladores'),0)
   with psycopg.connect(self.dsn) as c:self.assertEqual(c.execute('select count(*) from public.usuarios u left join auth.users a on a.id=u.uid where a.id is null').fetchone()[0],0)
  finally:
   with psycopg.connect(self.dsn) as c:c.execute('drop trigger edge_test_fail on public.recicladores');c.execute('drop function private.edge_test_fail()')
 def test_internal_rpc_not_callable_by_admin_client(self):
  r=self.s.post('http://127.0.0.1:54321/rpc/_crear_perfil_reciclador_con_app',headers={'Authorization':'Bearer '+self.tokens['admin']},json={'ejecutor_uid':self.f['admin']['uid'],'cuenta_uid':str(uuid.uuid4()),'nombre':'X','documento':'X'})
  self.assertEqual(r.status_code,403,r.text)

if __name__=='__main__':unittest.main(verbosity=2)
