#!/usr/bin/env bash
# Isolated test runtime: real PostgreSQL, GoTrue and PostgREST; not a replacement production backend.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "${1:-}" != '--reset-local' ]]; then
  echo 'Usage: scripts/test-runtime/run.sh --reset-local (destroys only material-backend-tests containers/volumes)' >&2
  exit 2
fi
: "${PYTHON_BIN:=python3}"
compose=(docker compose -f scripts/test-runtime/compose.yml)
"${compose[@]}" down --volumes
"${compose[@]}" up -d db
ready=false
for attempt in {1..30}; do
  if "${compose[@]}" exec -T db pg_isready -U postgres >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
if [[ "$ready" != true ]]; then echo 'Database not ready' >&2; exit 1; fi
"${compose[@]}" exec -T db psql -X -U postgres -v ON_ERROR_STOP=1 < scripts/test-runtime/bootstrap.sql
"${compose[@]}" up -d auth rest
ready=false
for attempt in {1..30}; do
  if curl --noproxy '*' -fsS http://127.0.0.1:54324/health >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
if [[ "$ready" != true ]]; then echo 'Auth not ready' >&2; exit 1; fi
"${compose[@]}" exec -T db psql -X -U postgres -v ON_ERROR_STOP=1 < scripts/test-runtime/auth-context.sql
mkdir -p .test-artifacts
for migration in supabase/migrations/*.sql; do
  echo "Applying $migration"
  "${compose[@]}" exec -T db psql -X -U postgres -v ON_ERROR_STOP=1 -1 < "$migration"
done
"${compose[@]}" exec -T db psql -X -U postgres -v ON_ERROR_STOP=1 -c "create schema extensions; notify pgrst, 'reload schema';"
# pgTAP 1.3.4: official release, checksum pinned; PostgreSQL >= 10 needs only template substitutions.
curl -fsSL https://github.com/theory/pgtap/releases/download/v1.3.4/pgTAP-1.3.4.zip -o .test-artifacts/pgtap.zip
"$PYTHON_BIN" - <<'PY'
import hashlib
import pathlib
import zipfile
p=pathlib.Path('.test-artifacts')
assert hashlib.sha256((p/'pgtap.zip').read_bytes()).hexdigest() == '5de16455e3e29898813f05cc9f396a31f878309a94d8adb34e80f423a5841736'
with zipfile.ZipFile(p/'pgtap.zip') as z:
    (p/'pgtap.control').write_bytes(z.read('pgTAP-1.3.4/pgtap.control'))
    sql=z.read('pgTAP-1.3.4/sql/pgtap.sql.in').decode().replace('__OS__','linux').replace('__VERSION__','1.3')
    (p/'pgtap--1.3.4.sql').write_text(sql)
PY
"${compose[@]}" cp .test-artifacts/pgtap.control db:/usr/local/share/postgresql/extension/pgtap.control
"${compose[@]}" cp .test-artifacts/pgtap--1.3.4.sql db:/usr/local/share/postgresql/extension/pgtap--1.3.4.sql
"${compose[@]}" exec -T db chmod 644 /usr/local/share/postgresql/extension/pgtap.control /usr/local/share/postgresql/extension/pgtap--1.3.4.sql
"${compose[@]}" exec -T db psql -X -U postgres -v ON_ERROR_STOP=1 -At < supabase/tests/001_schema.test.sql | tee .test-artifacts/pgtap.txt
"$PYTHON_BIN" - <<'PY'
from pathlib import Path
lines=Path('.test-artifacts/pgtap.txt').read_text().splitlines()
assert '1..12' in lines and sum(s.startswith('ok ') for s in lines)==12
assert not any(s.startswith('not ok') for s in lines)
PY
ALLOW_LOCAL_TEST_RESET=1 "$PYTHON_BIN" supabase/tests/backend_test.py 2>&1 | tee .test-artifacts/backend.txt
LIGHTWEIGHT_TEST_RUNTIME=1 "$PYTHON_BIN" supabase/tests/auth_http_test.py 2>&1 | tee .test-artifacts/http.txt
