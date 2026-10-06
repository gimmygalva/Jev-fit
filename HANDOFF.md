# HANDOFF — ripresa del lavoro in una nuova sessione

Data: 2026-10-06 · Da: Agent 00 (CTO), prima sessione

## Perché esiste questo file
La prima sessione ha completato **M0** (Fasi 0–1, piano approvato dall'utente) e ha scritto **M1** (scheletro, contratti core, XcodeGen, CI). Non ha potuto fare il push perché il repository `gimmygalva/Jev-fit` non era assegnato a quella sessione. **Nessuna riga Swift è mai stata compilata.**

## Procedura per la nuova sessione (in ordine)
1. Verifica l'accesso: `gh api repos/gimmygalva/Jev-fit --jq .permissions.push` deve dare `true`. Se non è così, fermati e avvisa l'utente.
2. Lo zip contiene la cartella `jev-fit/` con la directory `.git` e lo storico dei commit. Se il clone del repository è vuoto, copia il contenuto (inclusa `.git`) oppure aggiungi questa cartella come remote e porta lo storico su `main`. Non perdere i commit esistenti.
3. Remote: `https://github.com/gimmygalva/Jev-fit.git`, branch `main`. Fai il push.
4. Segui GitHub Actions (`.github/workflows/ci.yml`, 4 job: engines-linux, engines-macos, ios-build-test, secrets-scan). Correggi un problema alla volta, con commit piccoli, finché tutti i job sono verdi. Gli errori più probabili sono elencati in `PROJECT_STATE.md` → "Incertezze che solo la CI può risolvere".
5. Con la CI verde: versiona `Package.resolved`, valuta di attivare i warning come errori, aggiorna `PROJECT_STATE.md` (M1 chiusa) e passa a **M2** (Agent 03: DATA_MODEL, migrazioni GRDB e Supabase + RLS). Prima di creare il progetto Supabase (regione UE) chiedi conferma all'utente per i possibili costi.

## Cosa leggere prima di toccare codice
1. `docs/BRIEF.md`: il brief originale e completo dell'utente (requisiti, agenti, fasi, Definition of Done).
2. `PROJECT_STATE.md`: stato, blocchi, note di integrazione aperte.
3. `DECISIONS.md`: ADR-001…015 (004, 006, 011, 015 accettate dall'utente).
4. `docs/ARCHITECTURE_PLAN.md`: architettura e algoritmi, incluso l'esito della review QA (§11).
5. `docs/SECURITY.md`: regole SEC-* obbligatorie nel codice.

## Decisioni già prese dall'utente
- Verifica di build e test **solo tramite CI GitHub Actions**.
- Backend **Supabase, nuovo progetto in regione UE**.
- Persistenza locale **GRDB**.
- Interfaccia **solo in italiano** nell'MVP (String Catalog).

## Regole operative che restano valide
- Mai dichiarare "compila" o "test passati" senza un run CI verde come prova.
- Il CTO delega agli agenti specialistici e fa la review; Agent 11 rivede ogni milestone prima del merge.
- Ogni milestone aggiorna `PROJECT_STATE.md`.
