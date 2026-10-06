# JEV FIT

App iPhone nativa (iOS 18+, Swift 6, SwiftUI) per allenamento e nutrizione, con coach AI **JEV** che interpreta i dati prodotti da engine deterministici e testabili.

**Stato:** M1 (scheletro). Piano approvato; package, contratti core, progetto XcodeGen e CI scritti. La CI non è ancora stata eseguita: nessuna build è verificata (vedi `PROJECT_STATE.md`).

## Da dove iniziare a leggere
0. `HANDOFF.md`: come riprendere il lavoro in una nuova sessione.
1. `PROJECT_STATE.md`: stato attuale, blocchi, prossimi passi.
2. `docs/ARCHITECTURE_PLAN.md`: architettura, cartelle, schema DB, schermate, algoritmi, agenti, roadmap, rischi, MVP/V2.
3. `docs/REQUIREMENTS_AUDIT.md`: Fase 0.
4. `docs/PRODUCT_SPEC.md`, `docs/USER_FLOWS.md`, `docs/SCREEN_MAP.md`: Fase 1.
5. `DECISIONS.md`: Architecture Decision Records.
6. `docs/BRIEF.md`: brief originale completo.

## Build & test

> Nessuna build è stata verificata in questo repository finché la CI non è verde: lo stato reale
> è quello dell'ultimo run di GitHub Actions (ADR-011).

### Prerequisiti
- macOS con **Xcode 16 o successivo** (SDK iOS 18). Il `.xcodeproj` non è versionato.
- **XcodeGen** 2.38+: `brew install xcodegen`.
- Per l'iPhone fisico e la firma: `docs/SIGNING.md`.
- Per i soli engine basta un toolchain Swift 6 (anche su Linux).

### Comandi
```bash
# 1. Genera il progetto da project.yml e aprilo
xcodegen generate
open JevFit.xcodeproj

# 2. Engine (Swift puro, gira anche su Linux)
cd Packages/JevEngines
swift test
swift test --enable-code-coverage && ../../scripts/ci/coverage-gate.sh   # gate di coverage
cd ../..

# 3. App: unit test + UI test sul simulatore (stesso comando della CI)
UDID=$(scripts/ci/pick-simulator.sh)
xcodebuild -project JevFit.xcodeproj -scheme JevFit \
  -destination "id=$UDID" CODE_SIGNING_ALLOWED=NO test

# 4. Package JevKit (lo scheme "JevKit-Package" è generato da Xcode: verifica con `xcodebuild -list`)
cd Packages/JevKit
xcodebuild -scheme JevKit-Package -destination "id=$UDID" CODE_SIGNING_ALLOWED=NO test
cd ../..

# 5. Controllo segreti sui file tracciati da git
scripts/ci/check-secrets.sh
```

Soglie di coverage per modulo: `scripts/ci/coverage-targets.txt` (gli engine si aggiungono al 90%
quando vengono implementati).

### CI (GitHub Actions, `.github/workflows/ci.yml`)
Parte a ogni push su qualsiasi branch e a ogni pull request; un nuovo push annulla il run precedente
sullo stesso ref.

| Job | Runner | Cosa fa |
|---|---|---|
| `engines-linux` | ubuntu-latest, container `swift:6.1` | `swift build`, `swift test --enable-code-coverage`, gate di coverage |
| `engines-macos` | macos-15, Xcode stabile più recente | `swift test` di JevEngines |
| `ios-build-test` | macos-15, Xcode stabile più recente | `xcodegen generate`, scelta dinamica del simulatore, test dell'app e di JevKit |
| `secrets-scan` | ubuntu-latest | `scripts/ci/check-secrets.sh` (esclusa `docs/`) |

### Dove trovare i log
- GitHub → scheda **Actions** → run → job → step: log completo di ogni comando.
- La tabella di coverage compare nel **riepilogo del run** (job `engines-linux`).
- Se `ios-build-test` fallisce, in fondo alla pagina del run c'è l'artifact
  `ios-test-results-…` con gli `.xcresult` (apribili con Xcode) e i log di `xcodebuild`.
- In locale `xcodebuild` scrive in DerivedData; gli `.xcresult` della CI finiscono in `build/results/`
  (ignorata da git).
