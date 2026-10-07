# PROJECT_STATE — JEV FIT

Memoria condivisa del team. Ogni agente la legge prima di iniziare e il CTO la aggiorna a ogni milestone.
Ultimo aggiornamento: 2026-10-07 (seconda sessione) · Agent 00 (CTO)

## Current phase
**M1–M8 chiuse con CI verde.** In verifica: M9 (food logger) e M10 (Oggi, Corpo, Progressi). Poi M11 (JEV), M12, M13.
- M1: CI verde, run 37502690931.
- M2: CI verde, run 37508884578; progetto Supabase `jev-fit` (UE) creato e migrato (`docs/BACKEND.md`).
- M3: CI verde, run 37550632510 (5 job). Onboarding completo che salva profilo, obiettivo, impostazioni, preferenze, limitazioni e prima pesata; deep link `jevfit://` verso le 5 tab; test UI del percorso completo.
- M4: CI verde, run 37559158163 (5 job). WorkoutEngine + catalogo di 149 esercizi; coverage gate 90% su WorkoutEngine ed ExerciseCatalog; generazione deterministica per tutti gli split (test di proprietà su molti profili).
- M5: CI verde, run 37560536651. NutritionEngine; Monte Carlo su 500 seed nei test (mediana e 90° percentile dell'errore TDEE entro le soglie del §5.2, anche con il 20% di giorni mancanti); coverage gate 90%.
- M6: CI verde, run 37560536651. Recupero muscolare e JEV READINESS; readiness valida con soli dati iPhone (test); coverage gate 90%.
- M7: CI verde, run 37560536651. HealthKit reale + sorgente simulata (permessi concessi/negati/parziali), cache esclusa dal backup, import idempotente delle pesate. **Resta la checklist su iPhone fisico (`docs/HEALTHKIT_CHECKLIST.md`), a cura dell'utente.**
- M8: CI verde, run 37560536651. Workout live salvato a ogni serie (sopravvive al kill, test con repository riaperto), riepilogo con record, storico, overload integrato (regola 2 verificata tra due sessioni).

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
| Progetto Supabase `jev-fit` (eu-central-1, Free) con `v001`; advisor di sicurezza senza segnalazioni; smoke test RLS sul remoto | Agent 03 / 12 | ✔ |
| **M3** DesignSystem: palette Instrument light/dark, tipografia, pulsante 56 pt, card, selection card, chip, avanzamento, avvisi | Agent 02 | ✔ CI |
| `GoalSafety` (JevDomain): gate età/gravidanza/BMI, limiti e default del ritmo, settimane all'obiettivo; soglie in `EngineConfig.safety` | Agent 06 / 00 | ✔ CI (coverage gate JevDomain) |
| `SplitSuggestion` (WorkoutEngine): split dai giorni con motivo | Agent 04 | ✔ CI |
| Onboarding: bozza salvata a ogni step (`schema_meta`), `OnboardingRepository.complete` transazionale, `OnboardingModel`, 14 step | Agent 02 / 03 | ✔ CI |
| Navigazione: `AppRouter`, `DeepLink` (in attesa durante l'onboarding), cover non chiudibile, `AppContainer` con DB su disco o in memoria (test UI) | Agent 02 | ✔ CI |
| String Catalog sincronizzato con le stringhe dei package (`tools/l10n/sync_strings.py`, controllo in CI) | Agent 13 | ✔ CI |
| **M4** catalogo (149 esercizi, generatore + controllo CI), filtro di Kalman livello+pendenza, e1RM, overload (regole 0–9), ExerciseScore, generatore di programma, plateau e record | Agent 04 | ✔ CI |
| **M5** BMR/prior, trend del peso, TDEE adattiva [M, E], target con floor e gate, calorie cycling, aggiustamento settimanale, macro AUTO/ASSISTED/MANUAL | Agent 06 | ✔ CI |
| **M6** fatica muscolare con tolleranza cronica e τ per taglia/età, tempo al pronto, adattamento di u_m; readiness con pesi rinormalizzati | Agent 05 | ✔ CI |
| **M7** `HealthKitDataSource`, `MockHealthDataSource`, `HealthAggregator`, `HealthImporter`, permessi dopo l'onboarding | Agent 08 | ✔ CI (device: checklist utente) |
| **M8** `WorkoutRepository`, `TrainingPlanService`, `WorkoutLiveModel`, tab Allenamento | Agent 02 / 04 | ✔ CI |

## Known bugs
Nessuno noto. Limiti verificati e accettati:
- onboarding M3, differenze dichiarate dalla spec: mancano SCR-ONB-10 (esercizi preferiti/esclusi, arriva con il catalogo in M4) e SCR-ONB-15/16 (permessi Salute e notifiche, M7); il riepilogo finale (SCR-ONB-17) mostra le scelte ma non ancora calorie, macro e sessioni (arrivano con M4/M5); altezza solo in cm (ft-in con le impostazioni unità); nessuna card JEV (M11);
- body map: per ora elenco per muscolo con barre di recupero (nessuna silhouette disegnata);
- camera per il barcode verificabile solo su iPhone fisico; in CI si testa il parsing di Open Food Facts con JSON di esempio;
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
- ~~M3: `DataStore` nell'`AppContainer` e onboarding salvato~~ (fatto). `HealthCacheStore` si collega in M7 con HealthKit.
- M12: motore di sync secondo DATA_MODEL §5 (push dall'outbox, pull con finestra di sovrapposizione, adozione dei singleton su 23505, regole di merge anche lato client).
- M11 (Agent 09): segnaposto `{{label:id}}` per i nomi scritti dall'utente o da terzi (estensione ADR-014). Nel CoachContext il peso entra solo come direzione e fascia, senza valore.
- Nuova Edge Function `account-delete`: richiede un nuovo Sign in with Apple e revoca i token Apple.
- AppIcon 1024×1024 originale prima di TestFlight.
- Incertezze che solo la CI può risolvere: nome dello scheme di JevKit, versione di Xcode sul runner, identificatore di accessibilità della TabView, prodotti `Auth`/`PostgREST`/`Functions` di supabase-swift, `DatabaseWriter` Sendable in GRDB 7.

## Next tasks
- Verifica CI di M9 e M10, poi **M11** (JEV: CoachKit, gateway Edge Function, check-in settimanale), **M12** (QA distruttivo, security, sync), **M13** (release candidate).
- Utente: checklist HealthKit su iPhone fisico (`docs/HEALTHKIT_CHECKLIST.md`); impostazioni manuali di Supabase in `docs/BACKEND.md`.
- Agent 13: aggiornare le action su Node 20; valutare `SWIFT_TREAT_WARNINGS_AS_ERRORS`.
- Nota di processo: la review (Agent 11) di M4–M10 l'ha fatta il CTO senza un agente separato; i bug trovati in CI (timeout del type-checker, reps fuori range, pavimento dello score, record di ripetizioni) sono stati corretti con test.
