# JEV FIT — Modello dati (M2 / Fase 3)

Autore: Agent 03 (Data Architect) · Revisione: Agent 00, Agent 12 (sicurezza), Agent 11 (QA) · Data: 2026-10-06
Riferimenti: `ARCHITECTURE_PLAN.md` §3, `SECURITY.md` §3, §6, §8, `DECISIONS.md` ADR-004, 005, 006, 009, 010, 012, 014.

Fonti di verità, in quest'ordine:
1. `Packages/JevKit/Sources/Persistence/Migrations/v001_initial.sql`: schema locale (SQLite/GRDB);
2. `backend/supabase/migrations/20261006120000_v001_initial.sql`: schema cloud (Postgres/Supabase);
3. questo documento, che spiega le scelte. Se diverge dal codice, vale il codice e il documento va corretto.

Le due migrazioni sono **speculari** per le tabelle sincronizzate. Lo verifica la CI (`scripts/ci/schema-parity.py`), che confronta nomi delle colonne e obbligatorietà. I record Swift si **generano** dallo schema locale (`tools/codegen/generate_records.py`), e la CI fallisce se il file generato non è aggiornato.

---

## 1. Classi di tabelle

| Classe | Dove | Sync | Esempi |
|---|---|---|---|
| **F**: fatto sincronizzato | locale + cloud | sì, via outbox | `weight_entry`, `workout_set`, `food_log_entry` |
| **L**: fatto solo locale | locale | no | `food_cache`, `ai_conversation`, `ai_message` |
| **D**: derivato | locale | **mai** (ADR-005) | `weight_trend_daily`, `muscle_recovery`, `energy_expenditure` |
| **S**: catalogo statico | bundle dell'app | no | esercizi (`exercises.json`), 17 gruppi muscolari (`MuscleGroup`), alimenti base (M9) |
| **H**: cache HealthKit | file separato, escluso dal backup | **mai** (ADR-012) | `health_metric_daily` |
| **Sistema** | locale | no | `outbox`, `sync_cursor`, `schema_meta` |
| **Solo server** | cloud | no | `user_consent`, `private.*` |

Il catalogo statico non sta nel database: gli esercizi del catalogo si riferiscono con la loro **chiave** (`exercise_key`, es. `bench_press`), quelli creati dall'utente con l'**id** del record (`custom_exercise_id`). Un vincolo `CHECK` impone che sia valorizzato esattamente uno dei due. Lo stesso vale per gli alimenti (`food_source` + `food_source_id`).

## 2. Tabelle

### 2.1 Fatti sincronizzati (31)

| Dominio | Tabella | Note |
|---|---|---|
| Profilo | `user_profile` | **una riga viva** per utente (indice unico parziale). Anno di nascita, altezza, sesso (opzionale), esperienza, attività, unità, gravidanza/allattamento (gate di sicurezza QA-14) |
| | `goal` | storico degli obiettivi (`ended_at` chiude il precedente) |
| | `app_settings` | una riga viva. `notifications` e `display` sono oggetti JSON ≤ 4 KB |
| | `training_preferences` | una riga viva. Giorni, minuti, split, attrezzatura, priorità muscolari (liste JSON / `text[]`) |
| | `exercise_preference` | preferito / escluso / non gradito, per chiave di catalogo o esercizio custom |
| | `limitation` | area, gravità, nota libera ≤ 1000 caratteri. **SAN**: la nota non va mai all'AI |
| Corpo | `weight_entry` | `day_key` + `tz` (ADR-010), `hk_uuid` unico (niente doppioni da Salute) |
| | `body_measurement` | % grasso o circonferenze in cm, `hk_uuid` unico |
| | `subjective_check` | una per giorno: sonno, energia, indolenzimento 1–5 |
| Esercizi custom | `custom_exercise`, `custom_exercise_muscle` | tipo di carico, attrezzatura, controindicazioni, muscoli con contributo |
| | `recovery_calibration` | moltiplicatore τ appreso per muscolo (sopravvive a una reinstallazione) |
| Allenamento | `training_program` | split, mesociclo, settimana, schema JSON, `engine_version` |
| | `workout_template`, `workout_template_exercise` | sessioni del programma e loro esercizi |
| | `workout_session` | **al massimo una `in_progress`** sul dispositivo (ripresa dopo kill dell'app) |
| | `workout_exercise` | esercizio eseguito, con eventuale sostituzione (`replaced_from_*`) |
| | `workout_set` | carico canonico in kg + valore digitato (`entered_value`/`entered_unit`, niente falsi PR da conversione), zavorra/assistenza (`added_load_kg`), reps, RIR, RPE, durata, dolore |
| | `pain_report` | dolore segnalato; `acknowledged_at` sblocca gli aumenti di carico (QA-02) |
| Nutrizione | `custom_food`, `custom_food_serving` | nutrienti per 100 g, porzioni |
| | `recipe`, `recipe_ingredient` | ingredienti con **snapshot** dei nutrienti per 100 g |
| | `saved_meal`, `saved_meal_item` | pasti salvati riutilizzabili, stesso schema degli ingredienti |
| | `food_log_entry` | **snapshot dei totali** della porzione (ADR-009); `quick_add` senza alimento |
| | `nutrition_day` | uno per giorno: stato (aperto/completo/incompleto) e tipo (allenamento/riposo) |
| | `nutrition_target`, `macro_target` | target in vigore da `effective_from`, macro per tipo di giorno |
| JEV | `weekly_check_in` | uno per settimana: snapshot `metrics`, `decisions`, `responses` (JSON versionati dall'engine) |
| | `ai_recommendation` | testo, provider, modello, `confidence`, stato |

Rispetto alla sintesi del piano (§3.2) cambiano solo i nomi: `exercise` (custom) è diventata `custom_exercise`, `food` (custom) è diventata `custom_food`, e `meal` è diventata `saved_meal` con la nuova `saved_meal_item` (un pasto salvato senza voci non serviva a niente). La cache degli alimenti remoti è `food_cache` (L).

### 2.2 Solo locali, derivati, sistema

- `food_cache`: prodotti Open Food Facts / USDA già visti, unici per `(source, source_id)`. È contenuto di terzi non fidato (nomi solo come `{{label:id}}` verso l'AI).
- `ai_conversation`, `ai_message`: chat con JEV, solo sul dispositivo nell'MVP.
- Derivati (`weight_trend_daily`, `performance_record`, `exercise_trend`, `personal_record`, `muscle_recovery`, `readiness_entry`, `daily_nutrition`, `energy_expenditure`): ogni riga ha `engine_version` e `computed_at`. Quando cambia `EngineConfig.version` le tabelle si svuotano e si ricalcolano (ADR-005, ADR-013). Gli esercizi sono identificati da `exercise_ref`, che vale la chiave del catalogo oppure `custom:<uuid>`.
- `outbox` (§5.2), `sync_cursor` (ultimo `server_updated_at` letto per tabella), `schema_meta` (`device_id`, `engine_version`, `local_owner_user_id`).
- `health_metric_daily`: in `HealthCache/health-cache.sqlite`, cartella esclusa dal backup (SEC-LS-04).

## 3. Convenzioni

| Aspetto | Locale (SQLite) | Cloud (Postgres) |
|---|---|---|
| id | `BLOB` 16 byte (formato GRDB di `UUID`) | `uuid` |
| Generazione id | UUIDv7 sul dispositivo (`JevCore.UUIDv7`) | mai sul server (eccetto `user_consent`) |
| Proprietario | nessuna colonna (un solo proprietario per dispositivo) | `user_id uuid not null default auth.uid()` |
| Istanti | `TEXT` `yyyy-MM-dd HH:mm:ss.SSS` UTC | `timestamptz` |
| Giorno locale | `TEXT` `yyyy-MM-dd` (`DayKey`) | `date` |
| Decimali | `REAL` | `numeric(p,s)` con range |
| Booleani | `INTEGER` 0/1 con `CHECK` | `boolean` |
| Liste | `TEXT` JSON array | `text[]` / `smallint[]` con `<@` sui valori ammessi |
| Oggetti | `TEXT` JSON con limite di lunghezza | `jsonb` con `jsonb_typeof` e limite di dimensione |
| Enum | `TEXT` + `CHECK (x IN (...))` | `text` + stesso `CHECK` |

Unità canoniche (ADR-010): kg, kcal, grammi, secondi, centimetri. Le conversioni (lb, kJ) avvengono solo nella presentazione, tranne il valore digitato di un set, salvato a parte.

**Colonne di sync** (tutte le tabelle F): `created_at`, `updated_at`, `deleted_at` (tombstone), `origin_device_id`, `server_updated_at`; solo in locale `sync_state` (`pending` | `synced` | `conflict`).

**Vincoli di dominio** (SEC-DB-08): gli stessi range in locale e nel cloud. Il client li verifica prima nella UI, il DB locale è la seconda linea, il server la terza. Esempi: peso 20–400 kg, reps 0–200, RIR 0–10, kcal per 100 g ≤ 900, macro per 100 g con somma ≤ 100, testi liberi ≤ 1000 caratteri, nomi ≤ 120.

## 4. Integrità referenziale

### 4.1 Locale
Chiavi esterne tra fatti, `DEFERRABLE INITIALLY DEFERRED` e senza `ON DELETE CASCADE`: il controllo avviene al commit, quindi una transazione può salvare figli e genitori in qualsiasi ordine. Una serie che punta a un esercizio inesistente fa fallire l'intera transazione (test `workoutGraph`).

### 4.2 Cloud
Nessuna FK tra tabelle "fatto", solo `user_id → auth.users(id) on delete cascade`. Motivi:
- durante la sync l'ordine di arrivo non è garantito (un push interrotto può consegnare la serie prima della sessione);
- una FK tra righe di utenti diversi è comunque impossibile da sfruttare, perché la RLS nasconde le righe altrui;
- l'eliminazione dell'account cancella tutto tramite il cascade su `auth.users`.

### 4.3 Unicità
Indici unici **parziali** su `deleted_at is null`: le righe cancellate non bloccano una nuova riga con la stessa chiave naturale. Casi: profilo, impostazioni e preferenze (una riga viva), un `subjective_check`/`nutrition_day` per giorno, un `weekly_check_in` per settimana, una calibrazione per muscolo, un muscolo per esercizio custom, un macro target per tipo di giorno. `hk_uuid` è unico (non parziale) in locale e per `(user_id, hk_uuid)` nel cloud.

## 5. Sync (contratto; implementazione in M12)

### 5.1 Scritture locali
Tutte passano da `FactRepository`:
- `save` imposta `updated_at = max(now, precedente + 1 ms)`, `origin_device_id`, `sync_state = 'pending'` e conserva `created_at`;
- `delete` scrive solo il tombstone (`deleted_at = updated_at`), mai una `DELETE`;
- un record cancellato non si modifica più (`FactRepositoryError.recordDeleted`).

### 5.2 Outbox
Trigger `AFTER INSERT/UPDATE ... WHEN NEW.sync_state = 'pending'` su ogni tabella F: la coda è aggiornata nella **stessa transazione** della modifica, senza disciplina richiesta al codice. Una riga per record (`UNIQUE (table_name, record_id)`), con `revision` incrementata a ogni nuova modifica.

Push, per ogni riga in ordine di `seq`:
1. leggere il record **attuale** (più modifiche diventano un solo upsert);
2. `upsert on conflict (id)` sul server;
3. esito:
   - successo → `markPushed(entry, serverUpdatedAt:)`. Se la revisione è cambiata nel frattempo, il record resta `pending` e in coda;
   - errore temporaneo (rete, 5xx, 429) → `markFailed` con backoff;
   - errore permanente (`42501` RLS, `23514` check, `23505` unicità non risolvibile) → `markConflict`: record `conflict`, fuori dalla coda, mai ritentato in automatico (SECURITY §6.5).

I record applicati dal server sono scritti con `sync_state = 'synced'` e non rientrano nell'outbox.

### 5.3 Regole di merge (applicate dal trigger server `private.tg_fact_sync_columns`)
1. `updated_at` e `created_at` del client limitati a `now() + 5 min` (orologio avanti, QA-12).
2. `server_updated_at` lo decide sempre il server (cursore di pull).
3. `created_at` immutabile.
4. **Il tombstone vince**: una riga con `deleted_at` non torna viva e non cambia più.
5. **Last-writer-wins** su `updated_at`: una scrittura più vecchia della riga salvata non la sovrascrive.

Nei casi 4 e 5 la scrittura non viene scartata in silenzio: il server mantiene i propri valori e aggiorna comunque `server_updated_at`. Il client che ha scritto riceve la versione del server al pull successivo. Il client applica le stesse regole quando integra i record ricevuti.

### 5.4 Tabelle "una riga per utente"
Due dispositivi offline possono creare ciascuno il proprio profilo con id diversi. Il secondo push viola l'indice unico (`23505`): il client scarica la riga del server, la adotta (stesso id) applicando last-writer-wins sui campi e marca la propria riga come tombstone locale senza inviarla. È l'unico caso in cui un `23505` non è un `conflict`.

### 5.5 Pull
Per ogni tabella, nell'ordine di `SyncedTables.all` (genitori prima dei figli): `server_updated_at > cursore − 2 min` (finestra di sovrapposizione per transazioni lunghe, SECURITY §6.2), paginato. Applicazione idempotente: lo stesso record ricevuto due volte non cambia nulla. Una pagina si applica in una transazione; le FK locali differite tollerano l'ordine all'interno della pagina.

### 5.6 Consenso
Le policy insert/update del cloud richiedono il consenso `cloud_sync` attivo (`private.has_active_consent`, SECURITY §6.6). Senza consenso il push fallisce con `42501`: la sync parte solo dopo il consenso esplicito, mai in automatico.

## 6. Migrazioni

- **Locali**: `DatabaseMigrator` GRDB. `v000_bootstrap` (M1) crea `schema_meta`; `v001_initial` (M2) carica `Migrations/v001_initial.sql` dal bundle del modulo. La cache HealthKit ha un migratore proprio (`h001_initial`).
- **Cloud**: file in `backend/supabase/migrations/` con prefisso timestamp, stessa versione logica (`v001`).
- Le migrazioni sono **immutabili** una volta rilasciate (TestFlight o progetto remoto). Ogni modifica è una nuova versione `v002_…`, in entrambi gli schemi se tocca una tabella F. Poi si rigenerano i record (`tools/codegen/generate_records.py`).
- Compatibilità tra versioni dell'app durante la sync: colonne nuove sempre nullable o con default; il client ignora le colonne che non conosce.
- Test: migrazione da DB vuoto, da un DB della versione precedente (`upgradeFromPreviousVersion`), idempotenza della riapertura.

## 7. Test (M2)

| Area | Dove | Cosa |
|---|---|---|
| RLS e sync cloud | `backend/supabase/tests/rls_facts.test.sql` | 15 asserzioni × 31 tabelle: casi 1–11 di SECURITY §6.4, tombstone, LWW, `user_id` di default, riga di B invariata |
| Meta RLS | `rls_meta.test.sql` | RLS ovunque, nessuna `security definer`, nessuna policy `true`/`for all`, `anon` senza privilegi, nessun DELETE al client, viste sicure |
| Consensi | `rls_user_consent.test.sql` | concedere, revocare, non ripristinare, non toccare i consensi altrui |
| Parità degli schemi | `scripts/ci/schema-parity.py` | stesse tabelle, colonne e NOT NULL tra locale e cloud |
| Record generati | `generate_records.py --check` + `SchemaTests` | colonne dei record = colonne delle tabelle, trigger outbox presenti |
| Repository | `FactRepositoryTests` | round trip di tutti i tipi, tombstone, `updated_at` monotono, unicità, vincoli, FK differite, workout completo |
| Outbox | `OutboxTests` | coalescing, push confermato, modifica durante il push, errori temporanei e permanenti |
| HealthKit cache | `HealthCacheStoreTests` | file separato escluso dal backup |

I test pgTAP girano in CI due volte: su un Postgres con lo shim di Supabase (`scripts/ci/db-test.sh`, eseguibile anche senza Docker) e su Supabase locale vero (`supabase test db`).
