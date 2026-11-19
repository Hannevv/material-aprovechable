import json,sys,uuid
from pathlib import Path
import requests,psycopg
from local_tokens import token
s=requests.Session();s.trust_env=False
key=token('service_role'); base='http://127.0.0.1:54327'; headers={'Authorization':'Bearer '+key,'apikey':key}
fixtures={'url':base,'anon':token('anon')}
with psycopg.connect('postgresql://postgres:postgres@127.0.0.1:54322/postgres') as db:
 for name,role in [('admin','ADMIN'),('ciudadano','CIUDADANO'),('otro','CIUDADANO')]:
  email='phase567-'+uuid.uuid4().hex+'@example.com';password='Local-password-123'
  r=s.post(base+'/auth/v1/admin/users',headers=headers,json={'email':email,'password':password,'email_confirm':True});r.raise_for_status();uid=r.json()['id']
  db.execute('insert into public.usuarios(uid,nombre,rol,fecha_aceptacion_politica) values (%s,%s,%s,now())',(uid,name,role))
  fixtures[name]={'email':email,'password':password,'uid':uid}
 db.commit()
r=s.post(base+'/auth/v1/token?grant_type=password',headers={'apikey':fixtures['anon']},json={'email':fixtures['admin']['email'],'password':fixtures['admin']['password']});r.raise_for_status();admin=r.json()['access_token']
email='phase567-'+uuid.uuid4().hex+'@example.com';password='Local-password-123'
r=s.post(base+'/functions/v1/crear_reciclador_con_app',headers={'Authorization':'Bearer '+admin},json={'nombre':'Reciclador prueba','documento':uuid.uuid4().hex,'correo':email,'contrasena_inicial':password});r.raise_for_status();rec=r.json()['reciclador']
fixtures['reciclador']={'email':email,'password':password,'uid':rec['usuario_uid'],'id':rec['id']}
Path('.test-artifacts/phase567.json').write_text(json.dumps(fixtures))
print('Fixtures de integración creadas: ADMIN, dos CIUDADANO y RECICLADOR CON_APP')
