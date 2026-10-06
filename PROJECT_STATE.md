# PROJECT_STATE — JEV FIT

Memoria condivisa del team. Ogni agente la legge prima di iniziare e il CTO la aggiorna a ogni milestone.
Ultimo aggiornamento: 2026-10-06 (seconda sessione) · Agent 00 (CTO)

## Current phase
**M1 chiusa · M2 chiusa, compreso il progetto Supabase remoto.**
- M1: CI verde sul branch `claude/amazing-gauss-oo5oga`, run 37502690931 (4 job). Unica correzione necessaria: un'espressione di test che bloccava il type-checker.
- M2: CI verde, run 37508884578 (5 job, compreso il nuovo `db-tests`). 27 test Swift di Persistence; 486 asserzioni pgTAP eseguite sia su Postgres con shim sia su Supabase locale vero.
- Progetto Supabase `jev-fit` creato il 2026-10-06 (`eu-central-1`, piano Free, ref `xyseraszquglsfcffwny`) con `v001` applicata. Advisor di sicurezza senza segnalazioni; smoke test RLS sul remoto superato. Dettagli e impostazioni da fare nella dashboard in `docs/BACKEND.md`.

## Completed features / deliverable
| Deliverable | Autore | Stato |
|---|---|---|
| `docs/REQUIREMENTS_AUDIT.md`: audit requisiti, ambiguità, conflitti, blocchi ambiente | Agent 00 | ✔ |
| `docs/PRODUCT_SPEC.md`: requisiti numerati PS-*, MVP/V2, identità visiva, safety | Agent 01 | ✔ (riallineato dopo la review QA) |
| `docs/USER_FLOWS.md`: flussi UF-01…15 con edge case, offline, errori | Agent 01 | ✔ |
| `docs/SCREEN_MAP.md`: schermate SCR-*, stati, fonti dati, wireframe, componenti | Agent 01 | ✔ |
| `docs/ARCHITECTURE_PLAN.md`: i 10 punti per la revisione + esito della review QA | Agent 00 | ✔ in revisione |
| Review distruttiva del piano (21 finding, 2 blocker) | Agent 11 | ✔ tutti recepiti nel piano |
| `DECISIONS.md`: ADR-001 … ADR-015 | Agent 00 | ✔ (004, 006, 011, 015 accettate dall'utente) |
| `Packages/JevEngines`: 8 moduli puri + 8 target di test. Contratti JevCore (unità, DayKey, UUIDv7, statistiche robuste), JevDomain (tipi di dominio, `EngineConfig` v1), ExerciseCatalog (loader), CoachKit (`AIProvider`), decisioni del check-in | Agent 00 | scritto, **non compilato** |
| `Packages/JevKit`: Persistence (GRDB, bootstrap), Sync (contratto + DisabledSyncService), Health (contratto), Food (`FoodProvider`, query, barcode GS1), DesignSystem (token), Features (RootView a 5 tab) + test | Agent 00 / 13 | scritto, **non compilato** |
| `project.yml`, app shell, `AppTests`, `AppUITests`, `.github/workflows/ci.yml`, script CI (coverage gate, simulatore, secrets scan), `docs/SIGNING.md` | Agent 13 | scritto; YAML e script validati (actionlint, shellcheck, test con dati finti); **build non verificata** |
| `docs/SECURITY.md` (regole SEC-*), `App/PrivacyInfo.xcprivacy` | Agent 12 | ✔ (plist validato) |
| **M1 verificata in CI** (run 37502690931) + `Packages/JevKit/Package.resolved` (GRDB 7.11.1, supabase-swift 2.55.3), passato anche al progetto generato | Agent 13 | ✔ |
| `docs/DATA_MODEL.md`: classi di tabelle, convenzioni, integrità, contratto di sync (outbox, merge, singleton, pull) | Agent 03 | ✔ |
| Supabase `v001`: 31 tabelle "fatto" + `user_consent`, RLS per comando con consenso `cloud_sync`, nessun DELETE al client, trigger con clamp dell'orologio, tombstone che vince, last-writer-wins | Agent 03 / 12 | ✔ CI |
| pgTAP: `rls_facts` (15 casi × 31 tabelle), `rls_meta`, `rls_user_consent`; `scripts/ci/db-test.sh` + shim per Postgres senza Docker | Agent 03 / 11 | ✔ CI (shim + Supabase locale) |
| GRDB `v001_initial` (SQL come risorsa): fatti, locali, derivati, outbox con trigger e `revision`, FK differite; cache HealthKit `h001` in file separato escluso dal backup | Agent 03 | ✔ CI |
| Record Swift **generati** dallo schema (`tools/codegen/generate_records.py`), `FactRepository`, `OutboxRepository`, `HealthCacheStore` + 27 test | Agent 03 | ✔ CI |
| Controlli CI: parità schema locale/cloud (`schema-parity.py`), record generati aggiornati (`--check`) | Agent 13 | ✔ CI |

## Known bugs
Nessuno noto. Limiti verificati e accettati:
- la Data Protection dei file DB (SEC-LS-01) si verifica solo su dispositivo: sul simulatore il test controlla solo l'inclusione/esclusione dal backup;
- `markConflict` non conserva il codice d'errore nel DB (l'outbox ha solo un codice per le righe ancora in coda): lo registrerà la sync nel log tecnico (M12).

## Architecture decisions (sintesi, dettaglio in DECISIONS.md)
Tre livelli con "numeri solo dagli engine" · engine Swift puri in package locale · GRDB · fatti vs derivati (i derivati non si sincronizzano) · Supabase (UE) con RLS · AIProvider lato gateway, modelli configurabili · l'AI scrive segnaposto, non cifre · FoodProvider intercambiabili · unità canoniche e `day_key` locale · XcodeGen + CI macOS · dati fisiologici HealthKit solo sul dispositivo · un'unica `EngineConfig` versionata.

## Blocchi reali (ambiente)
1. **Nessun Xcode in questo ambiente**: build e test Swift solo tramite CI GitHub Actions (ADR-011). Le migrazioni e i test pgTAP invece si eseguono anche qui (Postgres 16 + pgTAP locali, `scripts/ci/db-test.sh`).
2. **HealthKit con autorizzazioni reali** è verificabile solo su iPhone fisico, a cura dell'utente con una checklist.

## Open questions (per l'utente)
1. ~~Verifica build~~ → **solo CI GitHub Actions** (ADR-011). Repository raggiungibile e CI attiva dal 2026-10-06.
2. ~~Supabase~~ → progetto `jev-fit` creato in UE (piano Free) e migrato. Restano le impostazioni manuali di `docs/BACKEND.md` (MFA sull'account, provider di login), nessuna urgente prima di M12.
3. ~~Persistenza~~ → **GRDB** (ADR-004).
4. ~~Lingua~~ → **solo italiano nell'MVP**, con String Catalog (ADR-015).
5. ID reali dei modelli richiesti ("GPT-5.6 Terra / Sol"): da verificare sulla documentazione OpenAI in Fase 10.
6. Superset e plate calculator: ora in V2. Da confermare.
7. Età minima: 16 anni per l'app, 18 per gli obiettivi in deficit. Serve una verifica legale prima di un uso commerciale.
8. Guideline Apple 5.1.3 per l'invio ad AI di informazioni derivate da HealthKit: verifica in Fase 12.

## Note di integrazione aperte (dalle review di Agent 12 e 13)
- ~~Versionare `Package.resolved`~~ (fatto). `SWIFT_TREAT_WARNINGS_AS_ERRORS`: rimandato a M3, dopo aver letto i warning attuali nei log CI (Agent 13).
- Le action `checkout@v4`, `cache@v4`, `upload-artifact@v4`, `setup-cli@v1` girano su Node 20, deprecato da GitHub: aggiornarle (Agent 13, M3).
- ~~M2 (Agent 03): `user_consent`, `health_metric_daily` separato, Data Protection~~ (fatto).
- M3: collegare `DataStore`/`HealthCacheStore` all'`AppContainer` (apertura su disco, schermata d'errore se il DB non si apre) e salvare l'onboarding con `FactRepository`.
- M12: motore di sync secondo DATA_MODEL §5 (push dall'outbox, pull con finestra di sovrapposizione, adozione dei singleton su 23505, regole di merge anche lato client).
- M11 (Agent 09): segnaposto `{{label:id}}` per i nomi scritti dall'utente o da terzi (estensione ADR-014). Nel CoachContext il peso entra solo come direzione e fascia, senza valore.
- Nuova Edge Function `account-delete`: richiede un nuovo Sign in with Apple e revoca i token Apple.
- AppIcon 1024×1024 originale prima di TestFlight.
- Incertezze che solo la CI può risolvere: nome dello scheme di JevKit, versione di Xcode sul runner, identificatore di accessibilità della TabView, prodotti `Auth`/`PostgREST`/`Functions` di supabase-swift, `DatabaseWriter` Sendable in GRDB 7.

## Next tasks
- **M3 / Fase 4**, Agent 02: design system, navigazione 5 tab, onboarding collegato al DB (`FactRepository`), deep link.
- In parallelo (piano §6): Agent 04 (WorkoutEngine + catalogo ~150 esercizi), Agent 06 (NutritionEngine + Monte Carlo), Agent 08 (HealthKit, scrive in `HealthCacheStore`).
- Nota di processo: in questa sessione la review di milestone (Agent 11) è stata fatta dal CTO senza un agente separato. È rimasta adversariale: ogni test pgTAP e il controllo di parità sono stati verificati introducendo difetti apposta.
