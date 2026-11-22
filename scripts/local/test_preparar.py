import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('preparar', Path(__file__).with_name('preparar.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class LocalConfig(unittest.TestCase):
    def test_loopback_only(self):
        for url in ['http://127.0.0.1:54321', 'http://localhost:54321']:
            self.assertIsNotNone(m.local_url(url, {'http'}))
        for url in ['https://example.com', 'http://127.0.0.1.evil.test', 'file:///tmp/config']:
            with self.assertRaises(ValueError):
                m.local_url(url, {'http', 'https'})

    def test_exports_only_public_config_and_respects_port(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(m, 'ROOT', Path(folder)):
            cfg = {'API_URL': 'http://127.0.0.1:55421', 'ANON_KEY': 'PUBLIC_TEST',
                   'SERVICE_ROLE_KEY': 'PRIVATE_TEST', 'DB_URL': 'postgresql://hidden:password@localhost/db'}
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                m.configurar(cfg)
            web = json.loads((Path(folder)/'config/local/web.json').read_text())
            android = json.loads((Path(folder)/'config/local/android-emulator.json').read_text())
            self.assertEqual(web, {'SUPABASE_URL': cfg['API_URL'], 'SUPABASE_ANON_KEY': 'PUBLIC_TEST'})
            self.assertEqual(android['SUPABASE_URL'], 'http://10.0.2.2:55421')
            self.assertNotIn('PRIVATE_TEST', output.getvalue())
            self.assertNotIn('password', json.dumps([web, android]))

    def test_remote_config_not_written(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(m, 'ROOT', Path(folder)):
            with self.assertRaises(ValueError):
                m.configurar({'API_URL': 'https://example.com', 'ANON_KEY': 'PUBLIC_TEST'})
            self.assertFalse((Path(folder)/'config').exists())

class LocalAdmin(unittest.TestCase):
    def setUp(self):
        self.cfg = {'API_URL': 'http://127.0.0.1:54321',
                    'DB_URL': 'postgresql://postgres:private@127.0.0.1:54322/postgres',
                    'SERVICE_ROLE_KEY': 'PRIVATE_TEST'}
        self.db = MagicMock()
        self.db.execute.return_value.fetchone.return_value = None
        self.connect = MagicMock()
        self.connect.return_value.__enter__.return_value = self.db
        self.patches = [patch.dict('sys.modules', {'psycopg': SimpleNamespace(connect=self.connect)}),
                        patch('builtins.input', return_value='admin@example.test'),
                        patch.object(m.getpass, 'getpass', return_value='local-password'),
                        patch.object(m, 'auth_request', return_value={'id': 'new-local-uid'})]
        for item in self.patches:
            result = item.start()
            self.addCleanup(item.stop)
        self.auth = result
        self.stdout, self.stderr = io.StringIO(), io.StringIO()
        self.enterContext(contextlib.redirect_stdout(self.stdout))
        self.enterContext(contextlib.redirect_stderr(self.stderr))

    def test_new_admin_profile_and_no_secrets_in_output(self):
        m.admin(self.cfg)
        self.db.commit.assert_called_once()
        self.assertEqual(self.db.execute.call_args.args[1], ('new-local-uid',))
        self.assertEqual(self.auth.call_args.args[1], 'POST')
        for secret in ['PRIVATE_TEST', 'local-password', self.cfg['DB_URL']]:
            self.assertNotIn(secret, self.stdout.getvalue() + self.stderr.getvalue())

    def test_existing_non_admin_cannot_be_promoted(self):
        self.db.execute.return_value.fetchone.return_value = ('existing', 'CIUDADANO')
        with self.assertRaises(ValueError):
            m.admin(self.cfg)
        self.auth.assert_not_called()
        self.db.commit.assert_not_called()

    def test_existing_admin_is_not_changed(self):
        self.db.execute.return_value.fetchone.return_value = ('existing', 'ADMIN')
        m.admin(self.cfg)
        self.auth.assert_not_called()
        self.assertEqual(self.db.execute.call_count, 1)

    def test_definitive_sql_rejection_compensates_exact_account(self):
        error = Exception('SQL rejected')
        error.sqlstate = '23505'
        self.db.commit.side_effect = error
        with self.assertRaises(ValueError):
            m.admin(self.cfg)
        self.db.rollback.assert_called_once()
        self.assertEqual(self.auth.call_args.args, (self.cfg, 'DELETE', '/new-local-uid'))

    def test_uncertain_commit_does_not_delete_auth_account(self):
        self.db.commit.side_effect = ConnectionError('lost response')
        with self.assertRaises(ValueError):
            m.admin(self.cfg)
        self.assertEqual(self.auth.call_count, 1)
        self.assertIn('new-local-uid', self.stderr.getvalue())

    def test_remote_db_is_rejected_before_connect(self):
        self.cfg['DB_URL'] = 'postgresql://user:secret@example.com/db'
        with self.assertRaises(ValueError):
            m.admin(self.cfg)
        self.connect.assert_not_called()
        self.auth.assert_not_called()

if __name__ == '__main__':
    unittest.main(verbosity=2)
