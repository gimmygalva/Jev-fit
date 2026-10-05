#!/usr/bin/env bash
# check-secrets.sh — fallisce se nei file TRACCIATI da git compaiono pattern di chiavi segrete.
#
# Esclusi: docs/ (la documentazione cita i nomi delle chiavi per spiegare cosa NON fare)
# e questo stesso script (contiene i pattern).
#
# Falsi positivi legittimi (es. il NOME di una variabile d'ambiente letta da una Edge Function,
# mai il valore): aggiungere sulla stessa riga il commento  secrets-scan: allow
# Ogni eccezione va motivata in review.
#
# L'output riporta solo file:riga e il tipo di pattern, MAI il contenuto della riga,
# per non ripubblicare un eventuale segreto nei log della CI.
#
# Compatibile con bash 3.2 (macOS) e GNU/BSD grep.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null)"; then
  echo "check-secrets: non è un repository git." >&2
  exit 2
fi
cd "${REPO_ROOT}"

SELF_PATH="scripts/ci/check-secrets.sh"
ALLOW_MARKER="secrets-scan: allow"

# Elenco file tracciati (NUL-separati), esclusioni tramite pathspec di git.
FILE_LIST="$(mktemp)"
trap 'rm -f "${FILE_LIST}"' EXIT
git ls-files -z -- . ":(exclude)docs" ":(exclude)${SELF_PATH}" > "${FILE_LIST}"

if [[ ! -s "${FILE_LIST}" ]]; then
  echo "check-secrets: nessun file tracciato da controllare."
  exit 0
fi

# Formato: etichetta|opzioni grep|regex ERE.
# Il prefisso (^|[^A-Za-z0-9]) evita match dentro parole più lunghe (es. "disk-…").
PATTERNS=(
  "Chiave API stile OpenAI/Anthropic (sk-…)||(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}"
  "Chiave Anthropic (sk-ant-…)||(^|[^A-Za-z0-9])sk-ant-[A-Za-z0-9_-]{10,}"
  "Riferimento a service role Supabase|-i|service_role"
  "Variabile service key Supabase||SUPABASE_SERVICE"
  "Secret key Supabase (sb_secret_…)||sb_secret_[A-Za-z0-9_-]{10,}"
  "JWT lungo (eyJhbGciOi…)||eyJhbGciOi[A-Za-z0-9_=-]{10,}\.[A-Za-z0-9_=-]{20,}\.[A-Za-z0-9_=-]{16,}"
  "Access key AWS (AKIA…)||(^|[^A-Z0-9])AKIA[0-9A-Z]{16}"
  "Chiave privata PEM||-----BEGIN ([A-Z]+ )?PRIVATE KEY-----"
)

found=0
for spec in "${PATTERNS[@]}"; do
  label="${spec%%|*}"
  rest="${spec#*|}"
  flags="${rest%%|*}"
  regex="${rest#*|}"

  # grep esce con 1 se non trova nulla: non è un errore. xargs propaga 123 in quel caso.
  # shellcheck disable=SC2086
  matches="$(xargs -0 grep -I -n -H -E ${flags} -e "${regex}" -- < "${FILE_LIST}" 2>/dev/null \
    | grep -v -F "${ALLOW_MARKER}" || true)"

  if [[ -n "${matches}" ]]; then
    found=1
    echo "::error::check-secrets: trovato pattern \"${label}\""
    # Solo file:riga, senza contenuto.
    printf '%s\n' "${matches}" | cut -d: -f1,2 | sed 's/^/  - /'
  fi
done

if [[ "${found}" -ne 0 ]]; then
  echo
  echo "check-secrets: FALLITO. Rimuovi il segreto, ruotalo se è stato pubblicato,"
  echo "e se si tratta di un falso positivo aggiungi '${ALLOW_MARKER}' sulla riga."
  exit 1
fi

echo "check-secrets: OK — nessun pattern di segreti nei file tracciati (docs/ esclusa)."
