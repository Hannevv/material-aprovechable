"""Preparación local Windows/Linux; no despliega ni escribe secretos privilegiados."""
import argparse
import getpass
import json
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]


def local_url(url, schemes):
    parsed = urlsplit(url)
    if parsed.scheme not in schemes or parsed.hostname not in {'localhost', '127.0.0.1', '::1'}:
        raise ValueError('Solo se admite Supabase local en loopback.')
    return parsed


def status(binary):
    executable = shutil.which(binary)
    if not executable:
        raise ValueError('No se encontró Supabase CLI. Añade supabase.exe al PATH.')
    result = subprocess.run([executable, 'status', '-o', 'json'], cwd=ROOT,
                            capture_output=True, text=True, check=False)
    if result.returncode:
        raise ValueError('Supabase local no está listo. Ejecuta supabase start y comprueba Docker.')
    cfg = json.loads(result.stdout)
    local_url(cfg['API_URL'], {'http', 'https'})
    local_url(cfg['DB_URL'], {'postgres', 'postgresql'})
    if not cfg.get('ANON_KEY'):
        raise ValueError('El CLI no devolvió ANON_KEY; usa la versión documentada.')
    return cfg


def configurar(cfg):
    parsed = local_url(cfg['API_URL'], {'http', 'https'})
    folder = ROOT / 'config' / 'local'
    folder.mkdir(parents=True, exist_ok=True)
    # Solo estos dos campos llegan a Flutter. Jamás exportar status completo.
    public = {'SUPABASE_URL': cfg['API_URL'], 'SUPABASE_ANON_KEY': cfg['ANON_KEY']}
    (folder / 'web.json').write_text(json.dumps(public, indent=2) + '\n', encoding='utf-8')
    port = f':{parsed.port}' if parsed.port else ''
    public['SUPABASE_URL'] = f'{parsed.scheme}://10.0.2.2{port}{parsed.path}'
    (folder / 'android-emulator.json').write_text(json.dumps(public, indent=2) + '\n', encoding='utf-8')
    print('Creados config/local/web.json y android-emulator.json (solo URL/clave pública).')


def auth_request(cfg, method, suffix, body=None):
    local_url(cfg['API_URL'], {'http', 'https'})
    key = cfg['SERVICE_ROLE_KEY']
    request = urllib.request.Request(cfg['API_URL'].rstrip('/') + '/auth/v1/admin/users' + suffix,
        method=method, headers={'apikey': key, 'Authorization': 'Bearer ' + key,
                               'Content-Type': 'application/json'},
        data=None if body is None else json.dumps(body).encode())
    # Evita enviar la petición local a un proxy corporativo. TLS se verifica normalmente.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=20) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def admin(cfg):
    import psycopg
    local_url(cfg['DB_URL'], {'postgres', 'postgresql'})
    email = input('Correo del ADMIN local: ').strip()
    if '@' not in email:
        raise ValueError('Correo inválido.')
    with psycopg.connect(cfg['DB_URL']) as db:
        existing = db.execute('select a.id,u.rol from auth.users a left join public.usuarios u on u.uid=a.id where lower(a.email)=lower(%s)', (email,)).fetchone()
        if existing:
            if existing[1] == 'ADMIN':
                print('El ADMIN local ya existe. No se cambió su contraseña.'); return
            raise ValueError('Ese correo ya existe sin perfil ADMIN. Usa otro correo; no se eleva el rol de una cuenta existente.')
        password = getpass.getpass('Contraseña local (mínimo 8 caracteres): ')
        if len(password) < 8 or password != getpass.getpass('Repite la contraseña: '):
            raise ValueError('Contraseña corta o confirmación diferente.')
        # Si la respuesta Auth se pierde antes de conocer UID no repetir ciegamente.
        created = auth_request(cfg, 'POST', '', {'email': email, 'password': password, 'email_confirm': True})
        uid = created['id']
        try:
            db.execute("insert into public.usuarios(uid,nombre,rol) values (%s,'Administrador local','ADMIN')", (uid,))
            db.commit()
        except Exception as error:
            # Solo compensar un rechazo SQL inequívoco, no un commit incierto.
            definitive = str(getattr(error, 'sqlstate', '') or '').startswith(('22', '23', '40'))
            try:
                db.rollback()
                if not definitive:
                    raise RuntimeError('Resultado no confirmado')
                auth_request(cfg, 'DELETE', '/' + str(uid))
            except Exception:
                print('Revisar cuenta local pendiente, UID: ' + str(uid), file=sys.stderr)
            raise ValueError('No se creó el perfil. Revisa las migraciones y la cuenta local antes de reintentar.') from None
    print('ADMIN local creado. Inicia sesión con el correo y contraseña elegidos.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('accion', choices=['configurar', 'admin'])
    parser.add_argument('--supabase-bin', default='supabase', help='Ruta de supabase.exe o binario disponible en PATH')
    args = parser.parse_args()
    try:
        cfg = status(args.supabase_bin)
        if args.accion == 'configurar':
            configurar(cfg)
        else:
            admin(cfg)
        return 0
    except (urllib.error.URLError, TimeoutError):
        print('Respuesta Auth no confirmada o rechazada. Revisa la cuenta local antes de repetir; no se muestran datos del servidor.', file=sys.stderr)
    except Exception as error:
        # No imprimir conexiones, tokens, contraseñas ni respuestas internas.
        print(str(error) if isinstance(error, ValueError) else 'No se completó la preparación local. Comprueba Docker, CLI, migraciones y dependencias.', file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
