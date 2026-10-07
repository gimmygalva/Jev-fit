# JEV FIT — Progetto Supabase

Aggiornato: 2026-10-06 · Agent 03 / Agent 12

## Progetto

| Voce | Valore |
|---|---|
| Nome | `jev-fit` |
| Project ref | `xyseraszquglsfcffwny` |
| URL API | `https://xyseraszquglsfcffwny.supabase.co` |
| Regione | `eu-central-1` (Francoforte, UE: ADR-006, SECURITY §12) |
| Postgres | 17 |
| Piano | Free (organizzazione personale) |

Nessun segreto in questo file né nel repository. La **publishable key** (non segreta per design, protetta dalla RLS) entrerà nella configurazione dell'app in M12. Le chiavi segrete (secret key, chiavi AI, chiave Apple `.p8`) vivono solo come secret delle Edge Functions (SECURITY §4).

## Migrazioni applicate

| Versione remota | File | Applicata |
|---|---|---|
| `20261006190920` | `backend/supabase/migrations/20261006190920_v001_initial.sql` | 2026-10-06 |

Il nome del file coincide con la versione registrata dal progetto remoto, così `supabase db push` non tenterà di riapplicarla. Le migrazioni applicate sono **immutabili**: ogni modifica va in un nuovo file.

## Verifiche sul progetto remoto (2026-10-06)

- Advisor di sicurezza Supabase: **nessuna segnalazione**.
- Advisor di performance: solo "indice non usato" (livello INFO) sugli indici di sync. È atteso con il database vuoto; da ricontrollare dopo M12.
- 32 tabelle in `public`, tutte con RLS; 96 policy; nessun privilegio ad `anon`; nessun DELETE concesso al client; 31 trigger di sync.
- Smoke test RLS eseguito in un blocco annullato (nessun dato residuo): l'utente A vede solo la propria riga; insert per conto di B, delete e accesso `anon` rifiutati con `42501`.
- Nessuna tabella nella publication Realtime, `pg_graphql` non installata, nessun bucket Storage (SEC-DB-09).
- I test pgTAP completi (486 asserzioni) girano in CI su Supabase locale con la stessa migrazione.

## Da fare nella dashboard (solo il proprietario dell'account)

Questi punti non si possono configurare dagli strumenti a disposizione di Claude. Nessuno blocca lo sviluppo fino a M12.

1. **Account supabase.com**: attivare l'autenticazione a due fattori (SECURITY §14.2).
2. **Authentication → Sign In / Providers**:
   - lasciare **disattivati** gli accessi anonimi;
   - disattivare le registrazioni via email: l'MVP usa solo Sign in with Apple (SECURITY §5);
   - attivare **Apple** quando sarà disponibile l'Apple Developer Program (Services ID, Team ID, Key ID e chiave `.p8`). Serve in M12, prima di TestFlight.
3. **Piano Free**: un progetto inattivo per circa una settimana viene messo in pausa e si riattiva dalla dashboard; i backup del piano Free sono limitati. Va bene per lo sviluppo. Prima di un uso con dati reali va valutato il piano Pro (backup, nessuna pausa) e vanno riportati nell'informativa i tempi di conservazione reali dei backup (SECURITY §12.6).
4. **Prima di un uso commerciale**: DPA con Supabase e restrizioni di rete sul database (SEC-DB-11).

## Gateway di JEV (Edge Function `coach`, M11)

Codice in `backend/supabase/functions/coach/` (type check e test Deno in CI). Verifica il JWT dell'utente, richiede il consenso `ai_online` attivo, sceglie il modello per tier e valida la risposta con le stesse regole di grounding del client. Senza configurazione risponde `503` e l'app usa i testi template offline: JEV funziona comunque, solo senza AI online.

Segreti da impostare nella dashboard (**Edge Functions → Secrets**), mai nel repository né nell'app:

| Variabile | Valore |
|---|---|
| `COACH_PROVIDER` | `anthropic` (default) oppure `openai` |
| `COACH_MODEL_ROUTINE` | ID del modello rapido (JEV TODAY) |
| `COACH_MODEL_ANALYSIS` | ID del modello di reasoning (check-in settimanale) |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | chiave del provider scelto |

`SUPABASE_URL` e `SUPABASE_ANON_KEY` sono fornite automaticamente da Supabase alle funzioni. Deploy: `supabase functions deploy coach --project-ref xyseraszquglsfcffwny` (o dalla dashboard).

## Eliminazione dell'account (Edge Function `account-delete`)

Codice in `backend/supabase/functions/account-delete/` (type check e test Deno in CI). Verifica il JWT, richiede `{"confirm":"DELETE"}` ed elimina l'utente Auth con la chiave amministrativa che Supabase fornisce automaticamente alle funzioni: tutte le tabelle hanno `on delete cascade`, quindi i dati nel cloud spariscono con l'utente. Deploy: `supabase functions deploy account-delete --project-ref xyseraszquglsfcffwny`. Da aggiungere prima di un uso commerciale: revoca del token Sign in with Apple.

## App: configurazione pubblica (M12)

`project.yml` scrive in Info.plist `JEVSupabaseURL` e `JEVSupabasePublishableKey` (chiave `sb_publishable_…`, pubblica per definizione). L'account si attiva solo con Sign in with Apple configurato nel punto 2 qui sopra; senza, il pulsante di accesso restituisce un errore gestito e l'app resta interamente locale.
