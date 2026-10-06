#!/usr/bin/env bash
# pick-simulator.sh — stampa su stdout l'UDID di un simulatore iPhone disponibile
# con runtime iOS >= MIN_IOS_VERSION (default 18.0).
#
# Perché uno script: i runner GitHub macOS cambiano spesso l'elenco di simulatori e
# runtime installati, quindi un nome fisso ("iPhone 16") prima o poi rompe la CI.
#
# Regole di scelta (deterministiche):
#   1. solo dispositivi "available" con nome che inizia per "iPhone";
#   2. runtime iOS >= MIN_IOS_VERSION e <= versione dell'SDK iphonesimulator dell'Xcode
#      selezionato (un runtime più nuovo dell'SDK non è utilizzabile da quell'Xcode);
#      se nessuno rispetta il limite superiore, si ripiega sul più recente >= minimo;
#   3. a parità: runtime più recente, poi modello con numero più alto, poi modello "base"
#      prima di "Pro", poi nome in ordine alfabetico.
#
# Uso:   UDID=$(scripts/ci/pick-simulator.sh)
# Env:   MIN_IOS_VERSION (es. "18.0"), SIMULATOR_UDID (override manuale, saltata la scelta).
# Diagnostica su stderr, solo l'UDID su stdout.

set -euo pipefail

if [[ -n "${SIMULATOR_UDID:-}" ]]; then
  echo "pick-simulator: uso SIMULATOR_UDID impostato a mano: ${SIMULATOR_UDID}" >&2
  echo "${SIMULATOR_UDID}"
  exit 0
fi

MIN_IOS_VERSION="${MIN_IOS_VERSION:-18.0}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "pick-simulator: xcrun non trovato (serve macOS con Xcode)." >&2
  exit 1
fi

SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || true)"
echo "pick-simulator: SDK iphonesimulator = ${SDK_VERSION:-sconosciuto}, minimo iOS = ${MIN_IOS_VERSION}" >&2

TMP_JSON="$(mktemp -t simctl-devices.XXXXXX)"
trap 'rm -f "${TMP_JSON}"' EXIT
xcrun simctl list devices available -j > "${TMP_JSON}"

python3 - "${TMP_JSON}" "${MIN_IOS_VERSION}" "${SDK_VERSION}" <<'PY'
import json
import re
import sys

path, min_version, sdk_version = sys.argv[1], sys.argv[2], sys.argv[3]


def parse_version(text):
    """'18.2' o '18' -> (18, 2). None se non interpretabile."""
    parts = re.findall(r"\d+", text or "")
    if not parts:
        return None
    nums = [int(p) for p in parts[:3]]
    while len(nums) < 3:
        nums.append(0)
    return tuple(nums)


def log(message):
    print(f"pick-simulator: {message}", file=sys.stderr)


min_v = parse_version(min_version)
if min_v is None:
    log(f"MIN_IOS_VERSION non valido: {min_version!r}")
    sys.exit(2)
sdk_v = parse_version(sdk_version)

with open(path, encoding="utf-8") as handle:
    devices_by_runtime = json.load(handle).get("devices", {})

runtime_re = re.compile(r"SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?$")
model_re = re.compile(r"^iPhone (\d+)")

candidates = []
for runtime_id, devices in devices_by_runtime.items():
    match = runtime_re.search(runtime_id)
    if not match:
        continue  # watchOS, tvOS, visionOS…
    runtime_v = tuple(int(g) if g else 0 for g in match.groups())
    if runtime_v < min_v:
        continue
    for device in devices:
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        if device.get("isAvailable") is False:
            continue
        model = model_re.match(name)
        model_number = int(model.group(1)) if model else 0
        suffix = name[model.end():].strip() if model else name
        # 0 = modello base ("iPhone 16"), 1 = "Pro", 2 = tutto il resto (Plus, Pro Max, e, Air…)
        variant_rank = 0 if suffix == "" else (1 if suffix == "Pro" else 2)
        candidates.append({
            "udid": device["udid"],
            "name": name,
            "runtime": runtime_id,
            "runtime_v": runtime_v,
            "model_number": model_number,
            "variant_rank": variant_rank,
        })

if not candidates:
    log(f"nessun simulatore iPhone con iOS >= {min_version}. Runtime visti:")
    for runtime_id, devices in sorted(devices_by_runtime.items()):
        log(f"  {runtime_id}: {', '.join(d.get('name', '?') for d in devices) or '(nessun dispositivo)'}")
    sys.exit(1)

usable = candidates
if sdk_v is not None:
    within_sdk = [c for c in candidates if c["runtime_v"][:2] <= sdk_v[:2]]
    if within_sdk:
        usable = within_sdk
    else:
        log("ATTENZIONE: nessun runtime <= SDK; uso comunque il più recente disponibile.")

usable.sort(key=lambda c: (
    tuple(-x for x in c["runtime_v"]),
    -c["model_number"],
    c["variant_rank"],
    c["name"],
))
chosen = usable[0]
version_text = ".".join(str(x) for x in chosen["runtime_v"])
log(f"scelto {chosen['name']} (iOS {version_text}) udid={chosen['udid']}")
print(chosen["udid"])
PY
