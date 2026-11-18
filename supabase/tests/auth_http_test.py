"""Tests of real GoTrue/PostgREST through the local Supabase gateway."""
import json
import os
import subprocess
import unittest
import uuid
import requests


class AuthHTTP(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get('LIGHTWEIGHT_TEST_RUNTIME') == '1':
            cls.url='http://127.0.0.1:54321'
            cls.auth_url='http://127.0.0.1:54324'
            cls.key=''
        else:
            cli=os.environ.get('SUPABASE_BIN','supabase')
            cfg=json.loads(subprocess.check_output([cli,'status','-o','json'],stderr=subprocess.DEVNULL))
            cls.url=cfg['API_URL']
            cls.auth_url=None
            cls.key=cfg['ANON_KEY']
        if cls.url not in ['http://127.0.0.1:54321','http://localhost:54321']:
            raise RuntimeError('Local isolated Supabase only')
        cls.session=requests.Session()
        cls.session.trust_env=False

    def request(self,method,path,token=None,body=None):
        headers={'apikey':self.key}
        if token: headers['Authorization']='Bearer '+token
        if self.auth_url:
            url=self.auth_url+path.removeprefix('/auth/v1') if path.startswith('/auth/v1') else self.url+path.removeprefix('/rest/v1')
        else:
            url=self.url+path
        return self.session.request(method,url,headers=headers,json=body,timeout=15)

    def signup(self):
        email='test-'+uuid.uuid4().hex+'@example.com'
        password='Local-test-123456'
        r=self.request('POST','/auth/v1/signup',body={'email':email,'password':password,'data':{'rol':'ADMIN'}})
        self.assertEqual(r.status_code,200,r.text)
        data=r.json()
        self.assertIn('access_token',data)
        return email,password,data

    def test_signup_profile_login_logout(self):
        email,password,data=self.signup(); token=data['access_token']
        r=self.request('POST','/rest/v1/rpc/crear_perfil_ciudadano',token,{'nombre':'Ciudadano','fecha_aceptacion_politica':'2026-11-17T00:00:00Z'})
        self.assertEqual(r.status_code,200,r.text)
        self.assertEqual(r.json()['rol'],'CIUDADANO')
        r=self.request('GET','/rest/v1/usuarios?select=uid,rol',token)
        self.assertEqual(r.status_code,200,r.text)
        self.assertEqual(len(r.json()),1)
        self.assertEqual(r.json()[0]['rol'],'CIUDADANO')
        r=self.request('POST','/auth/v1/token?grant_type=password',body={'email':email,'password':password})
        self.assertEqual(r.status_code,200,r.text)
        access=r.json()['access_token']; refresh=r.json()['refresh_token']
        r=self.request('POST','/auth/v1/logout',access)
        self.assertEqual(r.status_code,204,r.text)
        r=self.request('POST','/auth/v1/token?grant_type=refresh_token',body={'refresh_token':refresh})
        self.assertGreaterEqual(r.status_code,400)
        # Existing access JWTs can remain valid until expiry; no false revocation claim.

    def test_password_and_invalid_credentials(self):
        r=self.request('POST','/auth/v1/signup',body={'email':'test-'+uuid.uuid4().hex+'@example.com','password':'1234567'})
        self.assertEqual(r.status_code,422,r.text)
        self.assertEqual(r.json().get('error_code'),'weak_password',r.text)
        r=self.request('POST','/auth/v1/signup',body={'email':'invalid','password':'Local-test-123456'})
        self.assertEqual(r.status_code,400,r.text)
        self.assertEqual(r.json().get('error_code'),'validation_failed',r.text)
        r=self.request('POST','/auth/v1/token?grant_type=password',body={'email':'missing@example.com','password':'Incorrect-password'})
        self.assertEqual(r.status_code,400,r.text)
        self.assertEqual(r.json().get('error_code'),'invalid_credentials',r.text)

    def test_duplicate_email_rejected(self):
        email,password,_=self.signup()
        r=self.request('POST','/auth/v1/signup',body={'email':email,'password':password})
        self.assertIn(r.status_code,[400,422],r.text)
        self.assertEqual(r.json().get('error_code'),'user_already_exists',r.text)

    def test_api_no_profile_no_escalation_no_dml(self):
        _,_,data=self.signup(); token=data['access_token']
        r=self.request('POST','/rest/v1/rpc/crear_solicitud',token,{'materiales':['PAPEL'],'direccion':'Calle'})
        self.assertEqual(r.status_code,403,r.text)
        r=self.request('POST','/rest/v1/rpc/crear_perfil_ciudadano',token,{'nombre':'Ciudadano','fecha_aceptacion_politica':'2026-11-17T00:00:00Z'})
        self.assertEqual(r.status_code,200,r.text)
        r=self.request('POST','/rest/v1/rpc/crear_reciclador_sin_app',token,{'nombre':'X','documento':'X'})
        self.assertEqual(r.status_code,403,r.text)
        r=self.request('POST','/rest/v1/solicitudes',token,{'ciudadano_uid':data['user']['id'],'direccion':'Calle'})
        self.assertEqual(r.status_code,403,r.text)
        r=self.request('POST','/rest/v1/rpc/cancelar_solicitud',token,{'solicitud_id':str(uuid.uuid4()),'estado_esperado':'PENDIENTE'})
        self.assertEqual(r.status_code,403,r.text)
        self.assertEqual(r.json()['message'],'No autorizado')
        self.assertIsNone(r.json()['details'])
        r=self.request('GET','/rest/v1/solicitudes')
        self.assertGreaterEqual(r.status_code,400)

    def test_api_create_and_cancel_expected_state(self):
        _,_,data=self.signup(); token=data['access_token']
        r=self.request('POST','/rest/v1/rpc/crear_perfil_ciudadano',token,{'nombre':'Ciudadano','fecha_aceptacion_politica':'2026-11-17T00:00:00Z'})
        self.assertEqual(r.status_code,200,r.text)
        r=self.request('POST','/rest/v1/rpc/crear_solicitud',token,{'materiales':['PAPEL','METAL'],'direccion':'Calle'})
        self.assertEqual(r.status_code,200,r.text)
        sid=r.json()['id']
        r=self.request('POST','/rest/v1/rpc/cancelar_solicitud',token,{'solicitud_id':sid,'estado_esperado':'PENDIENTE'})
        self.assertEqual(r.status_code,200,r.text); self.assertTrue(r.json()['confirmada'])
        r=self.request('POST','/rest/v1/rpc/cancelar_solicitud',token,{'solicitud_id':sid,'estado_esperado':'PENDIENTE'})
        self.assertEqual(r.status_code,200,r.text); self.assertFalse(r.json()['confirmada'])

if __name__=='__main__': unittest.main(verbosity=2)
