# PROJECT_STATE — JEV FIT

Memoria condivisa del team. Ogni agente la legge prima di iniziare e il CTO la aggiorna a ogni milestone.
Ultimo aggiornamento: 2026-10-05 · Agent 00 (CTO)

## Current phase
**M0: Fasi 0 e 1 completate.** Il piano architetturale è in attesa di approvazione dell'utente. Codice applicativo: nessuno (per scelta, finché il piano non è approvato).

## Completed features / deliverable
| Deliverable | Autore | Stato |
|---|---|---|
| `docs/REQUIREMENTS_AUDIT.md`: audit requisiti, ambiguità, conflitti, blocchi ambiente | Agent 00 | ✔ |
| `docs/PRODUCT_SPEC.md`: requisiti numerati PS-*, MVP/V2, identità visiva, safety | Agent 01 | ✔ (riallineato dopo la review QA) |
| `docs/USER_FLOWS.md`: flussi UF-01…15 con edge case, offline, errori | Agent 01 | ✔ |
| `docs/SCREEN_MAP.md`: schermate SCR-*, stati, fonti dati, wireframe, componenti | Agent 01 | ✔ |
| `docs/ARCHITECTURE_PLAN.md`: i 10 punti per la revisione + esito della review QA | Agent 00 | ✔ in revisione |
| Review distruttiva del piano (21 finding, 2 blocker) | Agent 11 | ✔ tutti recepiti nel piano |
| `DECISIONS.md`: ADR-001 … ADR-014 | Agent 00 | ✔ (in gran parte "Proposta") |

## Known bugs
Nessuno: non c'è ancora codice.

## Architecture decisions (sintesi, dettaglio in DECISIONS.md)
Tre livelli con "numeri solo dagli engine" · engine Swift puri in package locale · GRDB · fatti vs derivati (i derivati non si sincronizzano) · Supabase (UE) con RLS · AIProvider lato gateway, modelli configurabili · l'AI scrive segnaposto, non cifre · FoodProvider intercambiabili · unità canoniche e `day_key` locale · XcodeGen + CI macOS · dati fisiologici HealthKit solo sul dispositivo · un'unica `EngineConfig` versionata.

## Blocchi reali (ambiente)
1. **Nessun Xcode e nessun toolchain Swift in questo ambiente.** Il download da swift.org e dalle release di GitHub è bloccato dal proxy (403). Non posso dichiarare "compila" o "test passati" senza una CI macOS o una build sul Mac dell'utente.
2. **Container effimero.** Il lavoro va salvato su un repository Git remoto. Ora la CLI `gh` non è autenticata: finché non c'è un remote, consegno uno zip a ogni milestone.
3. **HealthKit con autorizzazioni reali** è verificabile solo su iPhone fisico, a cura dell'utente con una checklist.

## Open questions (per l'utente)
1. Verifica build: CI GitHub Actions su macOS (serve un repo e un token), Mac dell'utente, o entrambi.
2. Supabase: nuovo progetto `jev-fit` in regione UE creato da qui, oppure un progetto esistente.
3. Persistenza: GRDB (consigliato) o SwiftData.
4. Lingua UI: IT + EN (consigliato) o solo IT.
5. ID reali dei modelli richiesti ("GPT-5.6 Terra / Sol"): da verificare sulla documentazione OpenAI in Fase 10.
6. Superset e plate calculator: ora in V2. Da confermare.
7. Età minima: 16 anni per l'app, 18 per gli obiettivi in deficit. Serve una verifica legale prima di un uso commerciale.
8. Guideline Apple 5.1.3 per l'invio ad AI di informazioni derivate da HealthKit: verifica in Fase 12.

## Next tasks (dopo l'approvazione)
- **M1 / Fase 2**, Agent 00 + 13: scheletro repo, `Package.swift` con tutti i moduli, `project.yml`, CI, `README` di build, `SECURITY.md` (Agent 12), `EngineConfig` iniziale.
- **M2 / Fase 3**, Agent 03: `DATA_MODEL.md`, migrazioni GRDB `v001`, migrazioni Supabase + RLS, repository, outbox, test.
- In parallelo dopo M2: Agent 04 (WorkoutEngine + catalogo), Agent 06 (NutritionEngine + Monte Carlo), Agent 08 (HealthKit).
