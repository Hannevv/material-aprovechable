#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SUPABASE_BIN:=supabase}"
: "${PYTHON_BIN:=python3}"
# Requires a dedicated disposable local Supabase project. Python fixtures reset public data.
"$SUPABASE_BIN" test db
ALLOW_LOCAL_TEST_RESET=1 "$PYTHON_BIN" supabase/tests/backend_test.py
SUPABASE_BIN="$SUPABASE_BIN" "$PYTHON_BIN" supabase/tests/auth_http_test.py
