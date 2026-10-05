#!/usr/bin/env bash
# coverage-gate.sh — gate di coverage delle LINEE per i moduli di Packages/JevEngines (ADR-011).
#
# Prerequisito: `swift test --enable-code-coverage` già eseguito in Packages/JevEngines.
#
# Uso:
#   scripts/ci/coverage-gate.sh                 # trova da solo il JSON di llvm-cov
#   scripts/ci/coverage-gate.sh path/al/file.json
#
# Variabili d'ambiente opzionali:
#   COVERAGE_TARGETS_FILE  default: scripts/ci/coverage-targets.txt
#   COVERAGE_SOURCES_ROOT  default: Packages/JevEngines/Sources
#                          (si contano solo i file in <root>/<Modulo>/)
#
# Esce con 0 se tutti i moduli rispettano la soglia, 1 se almeno uno è sotto soglia
# o non ha file misurati, 2 per errori di configurazione/input.
# Se esiste $GITHUB_STEP_SUMMARY, vi aggiunge la tabella in Markdown.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PACKAGE_DIR="${REPO_ROOT}/Packages/JevEngines"
TARGETS_FILE="${COVERAGE_TARGETS_FILE:-${SCRIPT_DIR}/coverage-targets.txt}"
SOURCES_ROOT="${COVERAGE_SOURCES_ROOT:-Packages/JevEngines/Sources}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "coverage-gate: python3 non trovato." >&2
  exit 2
fi

JSON_PATH="${1:-}"
if [[ -z "${JSON_PATH}" ]]; then
  # 1) chiediamo a SwiftPM dove ha scritto l'export JSON di llvm-cov.
  if command -v swift >/dev/null 2>&1; then
    JSON_PATH="$(cd "${PACKAGE_DIR}" && swift test --show-codecov-path 2>/dev/null | tail -n 1 || true)"
  fi
  # 2) ripiego: il JSON più recente sotto .build/*/codecov/ (il nome dell'opzione di
  #    SwiftPM è cambiato tra versioni; così il gate non dipende da quel dettaglio).
  if [[ -z "${JSON_PATH}" || ! -f "${JSON_PATH}" ]]; then
    JSON_PATH="$(python3 - "${PACKAGE_DIR}/.build" <<'PY'
import glob, os, sys
found = glob.glob(os.path.join(sys.argv[1], "**", "codecov", "*.json"), recursive=True)
if found:
    print(max(found, key=os.path.getmtime))
PY
)"
  fi
fi

if [[ -z "${JSON_PATH}" || ! -f "${JSON_PATH}" ]]; then
  echo "coverage-gate: JSON di coverage non trovato. Hai eseguito 'swift test --enable-code-coverage'?" >&2
  exit 2
fi
if [[ ! -f "${TARGETS_FILE}" ]]; then
  echo "coverage-gate: file soglie non trovato: ${TARGETS_FILE}" >&2
  exit 2
fi

echo "coverage-gate: profilo = ${JSON_PATH}"
echo "coverage-gate: soglie  = ${TARGETS_FILE}"

python3 - "${JSON_PATH}" "${TARGETS_FILE}" "${SOURCES_ROOT}" <<'PY'
import json
import os
import sys

json_path, targets_path, sources_root = sys.argv[1], sys.argv[2], sys.argv[3]
sources_root = sources_root.strip("/").replace("\\", "/")


def fail_config(message):
    print(f"coverage-gate: {message}", file=sys.stderr)
    sys.exit(2)


# --- soglie -----------------------------------------------------------------
targets = []
with open(targets_path, encoding="utf-8") as handle:
    for number, raw in enumerate(handle, start=1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            fail_config(f"{targets_path}:{number}: atteso '<Modulo> <soglia>', trovato {raw.strip()!r}")
        module, threshold_text = parts
        try:
            threshold = float(threshold_text)
        except ValueError:
            fail_config(f"{targets_path}:{number}: soglia non numerica {threshold_text!r}")
        if not 0 <= threshold <= 100:
            fail_config(f"{targets_path}:{number}: soglia fuori da 0–100: {threshold}")
        targets.append((module, threshold))

if not targets:
    fail_config("nessun modulo nel file delle soglie")

# --- profilo llvm-cov (formato "llvm.coverage.json.export") --------------------
try:
    with open(json_path, encoding="utf-8") as handle:
        report = json.load(handle)
    files = [f for block in report["data"] for f in block.get("files", [])]
except (OSError, ValueError, KeyError, TypeError) as error:
    fail_config(f"JSON di coverage non leggibile ({error})")

totals = {module: {"files": 0, "count": 0, "covered": 0} for module, _ in targets}
for entry in files:
    filename = entry.get("filename", "").replace("\\", "/")
    lines = entry.get("summary", {}).get("lines", {})
    for module in totals:
        # Confronto sul percorso relativo alla radice della repo: funziona sia sul runner
        # sia dentro il container, qualunque sia la cartella di checkout. Esclude da sé
        # i sorgenti generati in .build/ (es. resource_bundle_accessor.swift).
        marker = f"/{sources_root}/{module}/"
        if marker in filename:
            totals[module]["files"] += 1
            totals[module]["count"] += int(lines.get("count", 0))
            totals[module]["covered"] += int(lines.get("covered", 0))
            break

# --- tabella ed esito -----------------------------------------------------------
rows = []
failed = False
for module, threshold in targets:
    data = totals[module]
    if data["files"] == 0 or data["count"] == 0:
        percent = None
        status = "FAIL (nessuna linea misurata)"
        failed = True
    else:
        percent = 100.0 * data["covered"] / data["count"]
        ok = percent + 1e-9 >= threshold
        status = "OK" if ok else "FAIL"
        failed = failed or not ok
    rows.append((module, data["files"], data["count"], data["covered"], percent, threshold, status))

header = ("Modulo", "File", "Linee", "Coperte", "Coverage", "Soglia", "Esito")
table = [header] + [
    (m, str(f), str(c), str(cv), "—" if p is None else f"{p:.2f}%", f"{t:g}%", s)
    for (m, f, c, cv, p, t, s) in rows
]
widths = [max(len(row[i]) for row in table) for i in range(len(header))]
separator = "  ".join("-" * w for w in widths)
print()
for index, row in enumerate(table):
    print("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)))
    if index == 0:
        print(separator)
print()

summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if summary_path:
    with open(summary_path, "a", encoding="utf-8") as summary:
        summary.write("### Coverage JevEngines (linee)\n\n")
        summary.write("| " + " | ".join(header) + " |\n")
        summary.write("|" + "---|" * len(header) + "\n")
        for row in table[1:]:
            summary.write("| " + " | ".join(row) + " |\n")
        summary.write("\n")

if failed:
    print("coverage-gate: FALLITO — almeno un modulo è sotto soglia o non è stato misurato.")
    sys.exit(1)
print("coverage-gate: OK")
PY
