# PROJECT_STATE — JEV FIT

Memoria condivisa del team. Ogni agente la legge prima di iniziare e il CTO la aggiorna a ogni milestone.
Ultimo aggiornamento: 2026-10-06 · Agent 00 (CTO)

## Current phase
**M1 / Fase 2: codice scritto, IN ATTESA DELLA PRIMA CI.** M0 approvata dall'utente il 2026-10-05.
Nessuna riga Swift è stata compilata: in questo ambiente non c'è toolchain. M1 si chiude solo con la CI verde su GitHub Actions.

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

## Known bugs
Nessuno: non c'è ancora codice.

## Architecture decisions (sintesi, dettaglio in DECISIONS.md)
Tre livelli con "numeri solo dagli engine" · engine Swift puri in package locale · GRDB · fatti vs derivati (i derivati non si sincronizzano) · Supabase (UE) con RLS · AIProvider lato gateway, modelli configurabili · l'AI scrive segnaposto, non cifre · FoodProvider intercambiabili · unità canoniche e `day_key` locale · XcodeGen + CI macOS · dati fisiologici HealthKit solo sul dispositivo · un'unica `EngineConfig` versionata.

## Blocchi reali (ambiente)
1. **Nessun Xcode e nessun toolchain Swift in questo ambiente.** Il download da swift.org e dalle release di GitHub è bloccato dal proxy (403). Non posso dichiarare "compila" o "test passati" senza una CI macOS o una build sul Mac dell'utente.
2. **Repository remoto.** Il repository è `https://github.com/gimmygalva/Jev-fit` (creato dall'utente il 2026-10-06, vuoto). La prima sessione non poteva scriverci perché non le era stato assegnato; il lavoro prosegue in una nuova sessione con il repository selezionato all'avvio (vedi HANDOFF.md).
3. **HealthKit con autorizzazioni reali** è verificabile solo su iPhone fisico, a cura dell'utente con una checklist.

## Open questions (per l'utente)
1. ~~Verifica build~~ → **solo CI GitHub Actions** (ADR-011). Serve ancora un repository GitHub raggiungibile da questa sessione (oggi `gh` non è autenticato).
2. ~~Supabase~~ → **nuovo progetto `jev-fit` in regione UE** (ADR-006). Va creato in M2, quando le migrazioni sono pronte.
3. ~~Persistenza~~ → **GRDB** (ADR-004).
4. ~~Lingua~~ → **solo italiano nell'MVP**, con String Catalog (ADR-015).
5. ID reali dei modelli richiesti ("GPT-5.6 Terra / Sol"): da verificare sulla documentazione OpenAI in Fase 10.
6. Superset e plate calculator: ora in V2. Da confermare.
7. Età minima: 16 anni per l'app, 18 per gli obiettivi in deficit. Serve una verifica legale prima di un uso commerciale.
8. Guideline Apple 5.1.3 per l'invio ad AI di informazioni derivate da HealthKit: verifica in Fase 12.

## Note di integrazione aperte (dalle review di Agent 12 e 13)
- Dopo la prima CI verde: versionare `Package.resolved` (build riproducibili) e attivare `SWIFT_TREAT_WARNINGS_AS_ERRORS`.
- M2 (Agent 03): tabella `user_consent` (consensi separati per sync e AI), `health_metric_daily` in un file SQLite separato escluso dal backup, Data Protection `completeUntilFirstUserAuthentication`.
- M11 (Agent 09): segnaposto `{{label:id}}` per i nomi scritti dall'utente o da terzi (estensione ADR-014). Nel CoachContext il peso entra solo come direzione e fascia, senza valore.
- Nuova Edge Function `account-delete`: richiede un nuovo Sign in with Apple e revoca i token Apple.
- AppIcon 1024×1024 originale prima di TestFlight.
- Incertezze che solo la CI può risolvere: nome dello scheme di JevKit, versione di Xcode sul runner, identificatore di accessibilità della TabView, prodotti `Auth`/`PostgREST`/`Functions` di supabase-swift, `DatabaseWriter` Sendable in GRDB 7.

## Next tasks
- **Sbloccare la CI**: nella nuova sessione, push di `main` su `gimmygalva/Jev-fit` → seguire GitHub Actions → correggere fino al verde → chiudere M1 (procedura in HANDOFF.md).
- **M2 / Fase 3**, Agent 03: `DATA_MODEL.md`, migrazioni GRDB `v001`, migrazioni Supabase + RLS, repository, outbox, test.
- In parallelo dopo M2: Agent 04 (WorkoutEngine + catalogo), Agent 06 (NutritionEngine + Monte Carlo), Agent 08 (HealthKit).
