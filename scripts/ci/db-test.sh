#!/usr/bin/env bash
# Esegue le migrazioni Supabase e i test pgTAP su un Postgres "nudo" con lo shim di
# backend/tools/supabase_shim.sql. Usato in sviluppo (senza Docker) e in CI come
# controllo rapido; la CI esegue gli stessi test anche con `supabase test db` su Supabase vero.
#
# Variabili: PGHOST, PGPORT, PGUSER (superuser), PGPASSWORD come per psql. DB_NAME (default jevfit_test).
# Esce con codice != 0 se una migrazione fallisce o se un test pgTAP non passa.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
supa="${root}/backend/supabase"
db="${DB_NAME:-jevfit_test}"

psql_db() { psql -X -v ON_ERROR_STOP=1 -q -d "${db}" "$@"; }

psql -X -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists ${db}" -c "create database ${db}"

echo "== shim Supabase"
psql_db -f "${root}/backend/tools/supabase_shim.sql"

echo "== migrazioni"
shopt -s nullglob
migrations=("${supa}"/migrations/*.sql)
if [[ ${#migrations[@]} -eq 0 ]]; then
  echo "Nessuna migrazione trovata" >&2
  exit 1
fi
for f in "${migrations[@]}"; do
  echo "   $(basename "${f}")"
  psql_db -f "${f}"
done

echo "== test pgTAP"
failed=0
tests=("${supa}"/tests/*.test.sql)
if [[ ${#tests[@]} -eq 0 ]]; then
  echo "Nessun test pgTAP trovato" >&2
  exit 1
fi
for f in "${tests[@]}"; do
  name="$(basename "${f}")"
  # Ogni file è begin; ... rollback; e termina con finish(), che segnala piano non rispettato.
  if ! out="$(psql_db -At -f "${f}" 2>&1)"; then
    echo "FAIL ${name} (errore SQL)"
    echo "${out}"
    failed=1
    continue
  fi
  if grep -Eq '^not ok|# Looks like|^# Failed' <<<"${out}"; then
    echo "FAIL ${name}"
    grep -E '^not ok|^#' <<<"${out}" || true
    failed=1
  else
    count="$(grep -c '^ok' <<<"${out}" || true)"
    echo "ok   ${name} (${count} asserzioni)"
  fi
done

exit "${failed}"
