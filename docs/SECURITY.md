# JEV FIT — Security & Privacy

Autore: Agent 12 (Security & Privacy) · Data: 2026-10-05 · Fase 2 / M1
Stato: **Proposta**. Le regole `SEC-*` diventano vincolanti per tutti gli agenti quando il CTO le approva. Le scelte marcate *(da confermare con Agent 03/09)* toccano contratti di altri moduli.
Documenti collegati: `../DECISIONS.md` (ADR-005, 006, 007, 008, 012, 014), `ARCHITECTURE_PLAN.md` (§1.5, §3, §3.4, §5.11, §11), `PRODUCT_SPEC.md` (§6.17, §9, §10), `../App/PrivacyInfo.xcprivacy`.

> **Non sono un legale.** Le sezioni GDPR e Apple descrivono una postura tecnica conservativa e un elenco di cose da verificare. Prima di qualsiasi uso commerciale (utenti diversi dal titolare) serve la revisione di un professionista: vedi §15.
> Ciò che segue "**DA VERIFICARE sul testo ufficiale**" non va trattato come citazione: è il mio riassunto, da confrontare con la fonte.

Come si usa questo documento:
- ogni regola ha un ID `SEC-<area>-<n>` citabile nelle review e nei commit;
- §14 contiene le checklist che Agent 12 applica prima di ogni merge e prima di TestFlight;
- §16 elenca i rilievi aperti sul repository attuale.

---

## 1. Asset e confini di fiducia

| Asset | Dove | Perché conta |
|---|---|---|
| Dati sanitari e di fitness (peso, misure, allenamenti, dolore, limitazioni, alimentazione, gravidanza/allattamento, dati Salute) | SQLite sul dispositivo; Postgres Supabase (UE) se la sync è attiva | Categoria particolare art. 9 GDPR; dati HealthKit con regole Apple dedicate |
| Sessione utente (access token, refresh token Supabase) | Keychain | Chi la possiede legge e scrive tutti i dati cloud dell'utente |
| Segreti server (secret key Supabase, chiavi OpenAI/Anthropic/USDA, chiave Sign in with Apple `.p8`) | Secret delle Edge Functions | Bypass della RLS, costi, impersonificazione dell'app verso Apple |
| Budget AI | Provider AI + contatori nel DB | Costo diretto in denaro |
| Integrità delle decisioni (target calorici, carichi) | Engine sul dispositivo | Un numero sbagliato può fare danni fisici (PS-SAF) |

Confini di fiducia (tutto ciò che li attraversa va validato):
1. **Dispositivo ↔ rete**: TLS obbligatorio.
2. **Client ↔ PostgREST**: il client è **non fidato**. La RLS è l'unico controllo che conta; la logica del client non è una protezione.
3. **Client ↔ Edge Functions**: input non fidato (schema, dimensione, rate limit).
4. **Edge Function ↔ provider AI**: il provider è un responsabile del trattamento esterno, potenzialmente extra-UE; gli si invia il minimo.
5. **Testo di terzi ↔ modello AI**: nomi custom, note, nomi di prodotti Open Food Facts e messaggi chat sono **dati non fidati**, mai istruzioni.
6. **File importati e deep link `jevfit://`**: input non fidato.

---

## 2. Threat model (STRIDE sintetico)

Legenda: S spoofing · T tampering · R repudiation · I information disclosure · D denial of service · E elevation of privilege. "Residuo" = rischio accettato e motivato.

### 2.1 Dispositivo perso o rubato

| STRIDE | Minaccia | Mitigazione | Residuo |
|---|---|---|---|
| I | Lettura del DB da un dispositivo spento o riavviato e mai sbloccato | Data Protection sui file del DB (SEC-LS-01): chiavi non disponibili prima del primo sblocco | — |
| I | Dispositivo bloccato ma già sbloccato dopo l'avvio: estrazione forense | Nessuna mitigazione applicativa completa: la classe `completeUntilFirstUserAuthentication` lascia la chiave in memoria (scelta motivata in SEC-LS-01) | **Accettato**: serve un attacco forense sul dispositivo; è il livello di default di iOS per i file delle app |
| I | Dispositivo sbloccato in mano ad altri: l'app mostra tutto | Notifiche senza valori sanitari (SEC-LS-08); export protetto da autenticazione del proprietario (SEC-LS-06) | **Accettato** nell'MVP; in V2 blocco app opzionale con Face ID e oscuramento nello switcher |
| E/T | Dispositivo sbloccato: eliminazione account o export di tutti i dati | Eliminazione account richiede un nuovo Sign in with Apple (SEC-AU-06); export, eliminazione dati locali ed eliminazione account richiedono `LAContext` `.deviceOwnerAuthentication` | — |
| S | Furto della sessione dal Keychain | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non sincronizzabile (SEC-AU-03); rotazione del refresh token; logout globale da un altro dispositivo | — |
| I | Lock screen | Nessun valore di peso, calorie, HRV nel testo delle notifiche (SEC-LS-08) | — |

### 2.2 Backup iCloud e backup locali

| STRIDE | Minaccia | Mitigazione | Residuo |
|---|---|---|---|
| I | Il backup iCloud del dispositivo contiene il DB con dati sanitari | Decisione SEC-LS-03: DB principale **incluso** (unico modo di recuperare i dati senza account, coerente con PS-AC-06); cache HealthKit **esclusa**; token mai nel backup (ThisDeviceOnly); file di export temporanei esclusi e cancellati | Backup cifrato da Apple (end-to-end solo con Advanced Data Protection attiva). Compromissione dell'Apple ID ⇒ accesso al backup. Rapporto con la guideline 5.1.3: **DA VERIFICARE** (§13.1) |
| I | Backup locale cifrato su Mac (Finder) | Il token non migra (ThisDeviceOnly) | Contiene il DB: è un backup scelto dall'utente |
| T | Ripristino di un backup vecchio: record cancellati "risorgono" e vengono ripubblicati dalla sync | Tombstone lato server e regole di merge di §3.4 del piano; pgTAP dedicato (SEC-DB-10) | — |
| S | Ripristino del backup su un iPhone di un'altra persona | Nessuna sessione ripristinata (token ThisDeviceOnly); i dati locali appartengono comunque all'Apple ID che ha fatto il backup | — |

### 2.3 Attaccante sulla rete

| STRIDE | Minaccia | Mitigazione | Residuo |
|---|---|---|---|
| I/T | Man-in-the-middle | ATS di default, nessuna eccezione `NSAllowsArbitraryLoads`/`NSExceptionDomains` (SEC-NW-01); solo HTTPS | CA compromessa o profilo di configurazione installato dall'utente: niente pinning nell'MVP (motivazione in SEC-NW-02) |
| S | Replay di un identity token Apple intercettato | Nonce monouso: SHA-256 nell'autorizzazione Apple, valore grezzo a Supabase (SEC-AU-02) | — |
| I | Risposte HTTP con dati sanitari salvate in `Cache.db` | `URLCache` disattivata per Supabase e gateway (SEC-NW-03) | — |
| I | Metadati (DNS/SNI) rivelano l'uso di Supabase/Open Food Facts | — | **Accettato** |
| D | Rete assente o bloccata | Offline first: ogni funzione core funziona senza rete | — |

### 2.4 Utente autenticato malevolo che prova a leggere o scrivere dati altrui

| STRIDE | Minaccia | Mitigazione | Residuo |
|---|---|---|---|
| I | `GET /rest/v1/<tabella>` senza filtri con il proprio JWT | RLS `user_id = auth.uid()` su ogni tabella (SEC-DB-01…03); pgTAP | — |
| T | Insert/update con `user_id` altrui; update che "cede" una riga | `with check` su insert e update (SEC-DB-02) | — |
| T | Upsert su un `id` (UUID) di un altro utente | Nel ramo `on conflict do update` Postgres valuta la `using` della policy update sulla riga esistente e solleva errore: test dedicato | — |
| T | Orologio del client spostato in avanti per vincere sempre il last-writer-wins | Trigger server: `updated_at` limitato a `now() + 5 min`, `server_updated_at` assegnato dal server (SEC-DB-05, QA-12) | — |
| E | Funzione `security definer`, vista senza `security_invoker`, RPC esposta in `public` | Vietate salvo motivazione scritta (SEC-DB-06, 07); meta-test pgTAP | — |
| S | Sign-in anonimo di Supabase (crea utenti `authenticated` senza identità) | Disattivato (SEC-AU-07) | — |
| D | Scrittura massiva per riempire il DB | Vincoli di lunghezza sui testi, limiti PostgREST, rate limit Supabase | **Accettato** nell'MVP (uso personale); quote per utente prima del commerciale |

### 2.5 Abuso del gateway AI `jev-coach`

| STRIDE | Minaccia | Mitigazione | Residuo |
|---|---|---|---|
| D | Consumo di token per far salire la bolletta (utente legittimo, script, JWT rubato) | Rate limit per minuto e per giorno, budget token giornaliero per utente, tetto globale, kill switch, `max_output_tokens`, limiti di spesa sul provider (SEC-AI-03, SEC-SE-07) | Perdita massima = tetto globale giornaliero |
| S | Chiamata con la publishable key o con il JWT `anon` invece di un utente | Il gateway verifica il JWT dell'utente e richiede ruolo `authenticated` non anonimo (SEC-AI-01) | — |
| T | Prompt injection nei nomi di alimenti/esercizi custom, nelle note, nei nomi di prodotti Open Food Facts | Questi testi **non arrivano al modello**: il modello li cita con `{{label:<id>}}` e il client sostituisce il nome (SEC-AI-05) | — |
| T | Prompt injection nei messaggi chat | Messaggi solo nel ruolo `user`, delimitati, lunghezza limitata; il modello non ha tool né accesso web; nessuna azione deriva dal testo AI (le azioni passano dagli engine, PS-JEV-08); output a schema e validato (SEC-AI-05…08) | Il modello può rispondere male a una domanda: l'output passa comunque da grounding e filtro safety |
| I | Esfiltrazione di dati verso terzi tramite link o immagini nel testo generato | Il client mostra solo testo semplice: niente markdown, link, immagini, HTML; il validatore rifiuta URL (SEC-AI-07) | — |
| I | Esfiltrazione di dati di altri utenti | Il contesto contiene solo dati inviati dal chiamante; il gateway non legge tabelle utente con privilegi elevati (SEC-AI-11) | — |
| I | Contenuti dei prompt nei log | Solo metadati (SEC-AI-10, SEC-LG-05) | — |
| R | Contestazione di un addebito o di un abuso | Log di metadati con `request_id` e pseudonimo HMAC dell'utente | — |
| I | Rivelazione del system prompt | Si assume pubblico: non contiene segreti né dati | — |

### 2.6 Compromissione della chiave pubblicabile Supabase

La publishable key (`sb_publishable_…`, o la legacy `anon`) è **pubblica per progetto**: chiunque la estrae dall'IPA in pochi minuti. Il modello di sicurezza non dipende dalla sua segretezza.

| STRIDE | Cosa permette | Perché non basta | Residuo |
|---|---|---|---|
| I | PostgREST come `anon` | Grant revocati ad `anon` su tutte le tabelle + RLS (SEC-DB-03) | — |
| S | Creare account | Unico provider: Apple con identity token valido; email/password, magic link e anonimo disattivati (SEC-AU-07) | — |
| D | Chiamare le Edge Functions | Rifiutate senza JWT utente valido (SEC-AI-01) | — |
| D | Flood delle API Supabase | Rate limit della piattaforma | **Accettato**; rotazione della publishable key con release dell'app se abusata (SEC-SE-05) |

Contrasto: la compromissione della **secret key / service role** bypassa la RLS e legge tutto. È un incidente grave: procedura in SEC-SE-06.

### 2.7 Log e crash report

| STRIDE | Minaccia | Mitigazione |
|---|---|---|
| I | Valori sanitari nel log unificato (leggibili con Console.app, sysdiagnose) | `os.Logger`, privacy esplicita, elenco di ciò che non si logga mai (SEC-LG-01…03). Attenzione: con `os.Logger` **gli interi, i double e i bool interpolati sono pubblici di default**; solo le stringhe dinamiche sono redatte |
| I | Dati nei messaggi di `fatalError`/`precondition`, che finiscono nei crash report | Vietato interpolare dati nei messaggi di crash (SEC-LG-04) |
| I | Corpi di richiesta/risposta nei log delle Edge Functions | Nessun `console.log` del body; solo la riga di metadati (SEC-LG-05) |
| I | Valori sanitari nelle query string (finiscono negli API log di Supabase) | Mai valori sanitari nei filtri GET; i filtri usano id, cursori, `day_key` (SEC-LG-06) |
| I | SDK di crash reporting terzi | Nessuno nell'MVP (SEC-LG-07) |

### 2.8 Supply chain

| STRIDE | Minaccia | Mitigazione |
|---|---|---|
| T | Release malevola o compromessa di GRDB / supabase-swift o di una dipendenza transitiva | Versioni esatte, `Package.resolved` versionato e verificato in CI, review del diff a ogni aggiornamento (SEC-SC-01…03) |
| T | GitHub Action di terze parti compromessa | Action fissate per SHA del commit, `permissions: contents: read` (SEC-SC-05) |
| T | Dipendenze Deno/npm delle Edge Functions | Versioni esatte, `deno.lock` versionato, chiamate ai provider AI con `fetch` invece degli SDK (SEC-SC-06) |
| I | Telemetria nascosta in un SDK | Solo due dipendenze; verifica a ogni aggiornamento del manifest privacy aggregato (SEC-SC-04) |

### 2.9 Altri vettori

| Vettore | Mitigazione |
|---|---|
| File di import (`[Importa backup]`, UF-13) | Dimensione massima 50 MB; schema JSON con versione; ogni valore passa dai validatori di dominio (stessi range dell'input manuale); `user_id` del file ignorato; import in una transazione, tutto o niente |
| Deep link `jevfit://` | Solo navigazione: nessun deep link esegue scritture o azioni distruttive senza conferma in UI; parametri validati (id = UUID, enum noti) |
| Dati Open Food Facts | Contenuto di terzi non fidato: mostrato come testo; i nutrienti passano dai controlli di plausibilità; i nomi non arrivano all'AI (SEC-AI-05) |
| Account condiviso sullo stesso iPhone (logout di A, login di B) | I dati locali hanno un proprietario (`local_owner_user_id`); al login di un altro account non vengono mai caricati né riassegnati: si chiede di eliminarli o di annullare (SEC-AU-05) |
| Reinstallazione: gli item del Keychain sopravvivono alla disinstallazione | Al primo avvio dopo l'installazione (flag assente in `UserDefaults`) il client cancella gli item del Keychain di JEV FIT (SEC-AU-04) |

---

## 3. Classificazione dei dati

Classi:
- **SAN**: dato relativo alla salute, art. 9 GDPR. Per prudenza il progetto tratta come SAN anche allenamenti e alimentazione (ARCHITECTURE_PLAN §1.5).
- **PERS**: dato personale non sanitario (preferenze, contenuti dell'utente, identificativi).
- **TEC**: dato tecnico necessario al funzionamento.
- **PUB**: catalogo statico incluso nell'app, nessun dato personale.

Colonne "CoachContext":
- **no**: mai inviato all'AI;
- **valore**: fatto `{id, labelKey, unit, value}` prodotto da un engine;
- **qualitativo**: fatto senza `value`, solo `direction` / `band` calcolati dall'engine; il numero lo inserisce il client al posto del segnaposto (ADR-014);
- **enum**: solo codici chiusi (aree corporee, livelli, reason code);
- **label**: l'entità entra solo come `{id, kind}`; il nome è sostituito dal client con `{{label:<id>}}`.

| Tabella (§3.2) | Tipo | Classe | Dove vive | CoachContext |
|---|---|---|---|---|
| `user_profile` | F | SAN (altezza, gravidanza/allattamento) + PERS | device + cloud | no per anno di nascita, sesso, altezza, gravidanza. Il gate di sicurezza arriva solo come reason code generico (es. `GOAL_DEFICIT_BLOCKED_SAFETY`), mai la causa |
| `goal` | F | SAN | device + cloud | enum per il tipo; target weight e ritmo: qualitativo |
| `app_settings` | F | PERS | device + cloud | enum (`macro_mode`), nient'altro |
| `training_preferences` | F | PERS | device + cloud | valore (giorni/settimana, minuti), enum (split, attrezzatura) |
| `exercise_preference` | F | PERS | device + cloud | label (o chiave di catalogo se l'esercizio è statico) |
| `limitation` | F | SAN | device + cloud | enum (area, gravità). **La nota libera mai** |
| `weight_entry` | F | SAN (anche HealthKit) | device + cloud | no come serie; i fatti di trend (livello, pendenza, variazione 7/21 g) solo qualitativi |
| `body_measurement` | F | SAN (anche HealthKit) | device + cloud | qualitativo |
| `health_metric_daily` | L | SAN, origine HealthKit | **solo device**, file separato escluso dal backup (SEC-LS-04) | **mai i valori**. Solo i sottopunteggi readiness 0–100 calcolati dal RecoveryEngine (ADR-012) |
| `weight_trend_daily` | D | SAN | solo device | qualitativo |
| `muscle_group` | S | PUB | app bundle | sì (chiave e nome) |
| `exercise` (catalogo) | S | PUB | app bundle | sì (chiave di catalogo) |
| `custom_exercise`, `custom_exercise_muscle` | F | PERS (contenuto dell'utente) | device + cloud | label |
| `exercise_muscle` / `exercise_alternative` (catalogo) | S | PUB | bundle | chiavi di catalogo |
| `training_program`, `workout_template`, `workout_template_exercise` | F | PERS (fitness) | device + cloud | valore (serie, rep range, RIR target) |
| `workout_session` | F | SAN | device + cloud | valore aggregato (durata, n. sessioni); **`notes` mai** |
| `workout_exercise` | F | SAN | device + cloud | label o chiave di catalogo |
| `workout_set` | F | SAN | device + cloud | no come singoli set; aggregati dell'engine (e1RM, delta %, volume) come valore |
| `pain_report` | F | SAN | device + cloud | enum (area, livello, conteggio come valore) |
| `performance_record`, `exercise_trend`, `personal_record` | D | SAN | solo device | valore |
| `muscle_recovery` | D | SAN (derivato dagli allenamenti) | solo device | valore (recovery %) |
| `recovery_calibration` | F | PERS (parametro appreso) | device + cloud | no |
| `readiness_entry` | D | SAN (include componenti HealthKit) | solo device | punteggio totale e sottopunteggi 0–100; confidence |
| `subjective_check` | F | SAN | device + cloud | sottopunteggio 0–100 |
| alimenti di catalogo / `food_cache` / `custom_food` | S / L / F | PUB / TEC / PERS | bundle / device / device + cloud | label per cache e custom (i nomi OFF sono contenuto di terzi non fidato) |
| porzioni di catalogo / `custom_food_serving` | S / F | PUB / PERS | bundle / device + cloud | no |
| `recipe`, `recipe_ingredient`, `saved_meal`, `saved_meal_item` | F | PERS | device + cloud | label |
| `food_log_entry` | F | SAN | device + cloud | no come singole voci; solo aggregati giornalieri e settimanali dell'engine |
| `nutrition_day` | F | SAN | device + cloud | valore (giorni completi) |
| `daily_nutrition`, `energy_expenditure` | D | SAN | solo device | valore (totali, TDEE, confidence) |
| `nutrition_target`, `macro_target` | F | SAN | device + cloud | valore |
| `weekly_check_in` | F | SAN | device + cloud | decisioni, delta e reason code dell'engine (valore); lo snapshot `metrics` segue le regole delle tabelle d'origine |
| `ai_recommendation` | F | SAN | device + cloud | no (storico; al più lo stato delle ultime decisioni come enum) |
| `ai_conversation` / `ai_message` | L | SAN (testo libero) | solo device | ultimi ≤ 10 messaggi della conversazione corrente, solo per la chat, delimitati (SEC-AI-05) |
| `outbox` | L | TEC | solo device | no. `last_error` contiene un codice, mai payload o messaggi del server |
| `sync_cursor`, `schema_meta` | L | TEC | solo device | no |
| **Solo server** `user_consent` *(proposta, §6.6)* | cloud | PERS (prova del consenso) | cloud | no |
| **Solo server** `private.ai_usage` *(proposta, §7.3)* | cloud | TEC (pseudonimo + contatori) | cloud, schema non esposto | no |
| `auth.users` (Supabase) | cloud | PERS (Apple `sub`, eventuale email relay) | cloud | no. **Nessun identificativo** nel CoachContext |

Regola generale (SEC-DC-01): una colonna nuova eredita la classe più alta della sua tabella. Chi aggiunge una tabella aggiorna questa sezione nello stesso PR, altrimenti la review fallisce.

Regola HealthKit (SEC-DC-02): nessun **valore** che provenga da HealthKit, grezzo o aggregato giornaliero (peso da Salute, % grasso, HRV, FC, FC a riposo, sonno, passi, energia attiva), entra nel CoachContext. Per il peso, che mescola fonti manuali e Salute, i fatti di trend sono sempre **qualitativi**. Vedi §13.1.

---

## 4. Segreti

### 4.1 Cosa può stare nel client e cosa mai

| Valore | Nel client | Dove sta |
|---|---|---|
| URL del progetto Supabase | sì | `xcconfig` → build setting → `Info.plist`, letto all'avvio |
| Publishable key (`sb_publishable_…`), o anon key legacy | sì (pubblica per design) | come sopra. Preferire le nuove publishable key: si ruotano senza cambiare il JWT secret |
| Secret key (`sb_secret_…`) / `service_role` | **mai** | secret delle Edge Functions (Supabase la inietta come variabile d'ambiente) |
| Password del DB, JWT secret, connection string | **mai** | solo dashboard Supabase / secret CI per le migrazioni |
| Chiavi OpenAI, Anthropic, USDA | **mai** | `supabase secrets set` (OPENAI_API_KEY, ANTHROPIC_API_KEY, USDA_API_KEY) |
| Chiave Sign in with Apple `.p8`, Key ID, Team ID, Services ID (per revocare i token) | **mai** | secret dell'Edge Function `account-delete` |
| Salt HMAC per pseudonimizzare l'utente nei log | **mai** | secret delle Edge Functions (`LOG_HMAC_SALT`) |
| Chiave API App Store Connect, certificati di firma | **mai nel repo** | secret di GitHub Actions (Agent 13, `SIGNING.md`) |
| ID modello AI, limiti di rate | non segreti, ma non nel client | variabili d'ambiente del gateway (ADR-007) |

### 4.2 Regole

- **SEC-SE-01** Nessun segreto nel repository, in nessun branch, nemmeno "temporaneo" o in un file di esempio. `.env.example` contiene solo nomi di variabili con valori vuoti.
- **SEC-SE-02** Nel client c'è un solo client Supabase, creato con la publishable key. Nessun codice Swift contiene le stringhe `service_role`, `sb_secret_`, `sk-`, `sk-ant-`.
- **SEC-SE-03** Le Edge Functions leggono i segreti solo da `Deno.env.get(...)` e falliscono all'avvio (500 generico, log `CONFIG_MISSING`) se mancano. Mai fallback a valori hard-coded.
- **SEC-SE-04** Scan in CI: `scripts/ci/check-secrets.sh` (Agent 13, già presente) gira a ogni push e PR sui file tracciati, esclusa `docs/`, e stampa solo file:riga. Oggi copre `sk-…`, `sk-ant-…`, `service_role`, `SUPABASE_SERVICE*`, `sb_secret_…`, JWT lunghi, chiavi AWS e PEM. Il pattern JWT colpirebbe anche l'anon key legacy: un motivo in più per usare nel client la publishable key `sb_publishable_…`. **Da aggiungere** (Agent 13): assegnazioni non vuote a `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `USDA_API_KEY`, `APPLE_SIGNIN_PRIVATE_KEY`, `LOG_HMAC_SALT`; file `*.p8`, `*.p12`, `*.mobileprovision` tracciati; scan del bundle `.app`. Insieme completo dei controlli richiesti:
  - `sb_secret_[A-Za-z0-9_-]{10,}`;
  - JWT (`eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.`) il cui payload decodificato contiene `"role":"service_role"`; per prudenza, qualsiasi JWT fuori da `xcconfig` va segnalato;
  - `sk-[A-Za-z0-9_-]{20,}` (OpenAI, incluso `sk-proj-`), `sk-ant-[A-Za-z0-9_-]{20,}` (Anthropic);
  - assegnazioni non vuote a `USDA_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_SECRET_KEY`, `APPLE_SIGNIN_PRIVATE_KEY`, `LOG_HMAC_SALT`;
  - `-----BEGIN (EC |RSA )?PRIVATE KEY-----` e file `*.p8`, `*.p12`, `*.mobileprovision` versionati.

  In più: GitHub secret scanning con push protection attivo sul repository; lo stesso script gira sul bundle `.app` prodotto dalla CI (`strings` sull'eseguibile e sui plist) per dimostrare il criterio di uscita di M12 ("nessun segreto nel client").
- **SEC-SE-05** Rotazione:
  - **subito** se una chiave compare in un log, in un commit, in uno screenshot o se un dispositivo/account con accesso è compromesso;
  - **ogni 12 mesi** per le chiavi dei provider e la secret key Supabase; quando una persona con accesso lascia il progetto;
  - procedura: crea la nuova chiave → `supabase secrets set` → deploy → verifica con una chiamata di prova → revoca la vecchia → annota data e motivo in `docs/SECURITY_LOG.md` (senza la chiave);
  - publishable key: si ruota solo se abusata, perché richiede una release dell'app; la vecchia si disattiva quando la nuova versione è adottata.
- **SEC-SE-06** Incidente "secret key esposta": ruotare subito, rivedere gli API log Supabase dall'ultima rotazione per accessi anomali, valutare la notifica di data breach (art. 33 GDPR: 72 ore dal momento in cui se ne viene a conoscenza, se c'è rischio per gli interessati). Con il solo titolare come utente il rischio è limitato, ma la procedura va provata prima del commerciale.
- **SEC-SE-07** Account degli strumenti: MFA obbligatoria su GitHub, Supabase, Apple Developer, OpenAI, Anthropic. Limiti di spesa mensili impostati sui provider AI (budget di progetto lato provider) come seconda barriera dopo il budget del gateway.

---

## 5. Autenticazione e sessione

- **SEC-AU-01** Unico metodo: **Sign in with Apple** nativo (`AuthenticationServices`) → `supabase.auth.signInWithIdToken(provider: .apple, idToken:, nonce:)`. Nessun web flow, nessun email/password. L'account resta opzionale (PS-AC-01).
- **SEC-AU-02** Nonce: 32 byte da `SecRandomCopyBytes` (mai `UUID()` o `random()` non crittografico), codificati; nella `ASAuthorizationAppleIDRequest.nonce` va lo **SHA-256 esadecimale**, a Supabase il valore **grezzo**. Il nonce vale per una sola richiesta e si scarta subito dopo. Scope richiesti: **nessuno** (né nome né email): l'app non ne ha bisogno (minimizzazione). *DA VERIFICARE in M2: che Supabase accetti un id token senza email e cosa salva in `auth.users.email`; se salva l'email relay va dichiarata (vedi §13.3).*
- **SEC-AU-03** Token nel Keychain con `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` e `kSecAttrSynchronizable = false`, tramite un'implementazione di `AuthLocalStorage` del progetto (non affidarsi al default della libreria, che va comunque verificato). Motivazione:
  - *AfterFirstUnlock*: la sync in background (task in background, consegna in background di HealthKit) deve poter rinnovare l'access token a dispositivo bloccato; `WhenUnlocked` la romperebbe in modo silenzioso;
  - *ThisDeviceOnly*: il token non entra nei backup e non migra su un nuovo iPhone, quindi un backup rubato non contiene una sessione; sul nuovo dispositivo si rifà il login (UF-13 lo prevede già);
  - scartato `WhenPasscodeSetThisDeviceOnly`: renderebbe l'account inutilizzabile senza codice e cancellerebbe gli item se l'utente rimuove il codice.
- **SEC-AU-04** Reinstallazione: gli item del Keychain sopravvivono alla disinstallazione. Al primo avvio, se il flag `didCompleteFirstLaunch` in `UserDefaults` manca, il client cancella tutti gli item Keychain del proprio service prima di inizializzare Supabase.
- **SEC-AU-05** Logout (`[Esci]`, SCR-SET-05):
  1. `auth.signOut()` (revoca del refresh token lato server; offrire "Esci da tutti i dispositivi" = scope globale);
  2. cancellazione degli item Keychain;
  3. stop della sync; l'outbox resta (i record restano del proprietario locale);
  4. scelta UF-12: mantenere i dati sul dispositivo (default) o rimuoverli.

  I dati locali restano marcati con `local_owner_user_id`. Se poi accede **un altro** account, i record di A non vengono mai caricati né riassegnati a B: l'app chiede di eliminarli o di annullare il login. La RLS li rifiuterebbe comunque (`with check`), ma il client non deve provare a "correggere" `user_id`.
- **SEC-AU-06** Eliminazione account in app (requisito App Store, §13.2), SCR-SET-10:
  1. conferma con testo esplicito + `LAContext` `.deviceOwnerAuthentication`;
  2. nuovo Sign in with Apple per ottenere un `authorizationCode` fresco (ri-autenticazione);
  3. chiamata all'Edge Function `account-delete` con JWT + `authorizationCode`;
  4. il server: verifica il JWT → scambia il codice con Apple e **revoca i token Sign in with Apple** tramite l'API REST di Apple → cancella i dati applicativi (cascade da `auth.users`) → `auth.admin.deleteUser(uid)` → risponde 200 solo a cancellazione completata;
  5. il client cancella Keychain, flag di sync, consensi locali e, se l'utente l'ha scelto, i dati locali.

  Se la revoca Apple fallisce dopo la cancellazione dei dati, l'errore si registra (solo metadati) e si riprova; non si lascia l'account a metà.
- **SEC-AU-07** Configurazione Supabase Auth: solo provider Apple attivo; email/password, magic link, telefono e **anonymous sign-ins disattivati**; rotazione del refresh token attiva; durata dell'access token di default (1 h) o inferiore. Verifica con l'advisor di sicurezza Supabase (`get_advisors`) a ogni milestone backend.
- **SEC-AU-08** Il client non decide mai l'autorizzazione: `user_id` nelle richieste è solo un dato che la RLS verifica. Nessuna logica "se l'utente è X allora…" lato client per proteggere dati.

---

## 6. Database e RLS

### 6.1 Regole

- **SEC-DB-01** **Default deny**: ogni tabella in uno schema esposto (`public`) ha RLS attiva **nella stessa migrazione che la crea**. Nessuna tabella senza RLS, nemmeno "temporanea". Le tabelle che il client non deve vedere stanno nello schema `private`, non esposto da PostgREST.
- **SEC-DB-02** Ogni tabella "fatto" ha `user_id uuid not null default auth.uid() references auth.users(id) on delete cascade` e quattro policy separate per comando, tutte `to authenticated`, con `(select auth.uid()) = user_id` in `using` e in `with check` (insert e update). Mai una policy `for all`, mai `using (true)`.
- **SEC-DB-03** Grant minimi: `revoke all ... from anon, authenticated`, poi `grant select, insert, update, delete ... to authenticated` (oppure senza `delete`, vedi §6.2). Il ruolo `anon` non ha alcun privilegio su tabelle con dati utente.
- **SEC-DB-04** Indice `(user_id, server_updated_at)` su ogni tabella sincronizzata (prestazioni della RLS e del pull).
- **SEC-DB-05** Trigger server su ogni tabella sincronizzata: `server_updated_at := now()`, `updated_at` limitato a `now() + 5 min` (QA-12), `created_at` immutabile.
- **SEC-DB-06** Funzioni `security definer` **vietate**. Eccezione solo con: motivazione scritta nel commento della migrazione e in questo documento, schema `private`, `set search_path = ''`, `revoke execute ... from public, anon, authenticated` e grant esplicito al solo ruolo che serve, test pgTAP dedicato. Oggi non ne serve nessuna.
- **SEC-DB-07** Viste in `public` solo con `with (security_invoker = true)`; niente viste materializzate in `public` (non applicano la RLS).
- **SEC-DB-08** Vincoli di dominio nel DB come seconda linea dopo il client: `check` su range plausibili (es. `weight_kg between 20 and 400`, `reps between 0 and 200`), lunghezza dei testi liberi (`char_length(note) <= 1000`, nomi `<= 120`), enum come `check (x in (...))`.
- **SEC-DB-09** Niente Realtime, Storage, GraphQL nell'MVP: nessuna tabella nella publication `supabase_realtime`; nessun bucket; `pg_graphql` non installata sul progetto (verificato il 2026-10-06, docs/BACKEND.md). Se in V2 serve Storage (foto progressi), le policy su `storage.objects` limitano la cartella a `auth.uid()`.
- **SEC-DB-10** Test pgTAP obbligatori per ogni tabella sincronizzata (casi in §6.4), eseguiti in CI con `supabase test db` su un DB locale.
- **SEC-DB-11** Restrizioni di rete sul DB (connessioni Postgres dirette solo dagli IP necessari, SSL obbligatorio) attive prima del commerciale.

### 6.2 Template di migrazione per una tabella "fatto"

Esempio su `weight_entry`. Agent 03 lo applica a ogni tabella F, adattando le colonne.

```sql
-- Una sola volta (migrazione iniziale) -------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;   -- solo per has_active_consent()

-- Trigger comune alle tabelle sincronizzate (SEC-DB-05, QA-12)
create or replace function private.tg_fact_sync_columns()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- L'orologio del client non può superare now() + 5 min.
  new.updated_at := least(coalesce(new.updated_at, now()), now() + interval '5 minutes');
  -- Cursore di pull: lo decide il server, il valore del client è ignorato.
  new.server_updated_at := now();
  if tg_op = 'UPDATE' then
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

-- Tabella -------------------------------------------------------------------
create table public.weight_entry (
  id                uuid primary key,                  -- UUIDv7 generato dal client
  user_id           uuid not null default auth.uid()
                    references auth.users(id) on delete cascade,
  measured_at       timestamptz not null,
  day_key           date not null,
  tz                text not null check (char_length(tz) <= 64),
  weight_kg         numeric(5,2) not null check (weight_kg between 20 and 400),
  source            text not null check (source in ('manual','healthkit')),
  hk_uuid           uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted_at        timestamptz,
  origin_device_id  uuid,
  unique (user_id, hk_uuid)
);

create index weight_entry_user_sync_idx on public.weight_entry (user_id, server_updated_at);

create trigger weight_entry_sync_columns
  before insert or update on public.weight_entry
  for each row execute function private.tg_fact_sync_columns();

-- RLS: default deny, poi solo le proprie righe (SEC-DB-01..03)
alter table public.weight_entry enable row level security;

revoke all on table public.weight_entry from anon, authenticated;
grant select, insert, update, delete on table public.weight_entry to authenticated;

create policy weight_entry_select on public.weight_entry
  for select to authenticated
  using ( (select auth.uid()) = user_id );

create policy weight_entry_insert on public.weight_entry
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and (select private.has_active_consent('cloud_sync'))   -- §6.6, proposta
  );

create policy weight_entry_update on public.weight_entry
  for update to authenticated
  using ( (select auth.uid()) = user_id )
  with check (
    (select auth.uid()) = user_id
    and (select private.has_active_consent('cloud_sync'))
  );

create policy weight_entry_delete on public.weight_entry
  for delete to authenticated
  using ( (select auth.uid()) = user_id );
```

Note al template:
- `(select auth.uid())` invece di `auth.uid()` è la forma raccomandata da Supabase: la funzione viene valutata una volta per query, non per riga.
- **Delete**: il protocollo di sync usa tombstone (`deleted_at`), quindi il client non ha bisogno di cancellazioni fisiche. Se Agent 03 conferma che il client non fa mai `DELETE`, **si omettono grant e policy delete** (preferito, privilegio minimo). La purga dei tombstone e le cancellazioni per revoca del consenso/eliminazione account avvengono lato server (§6.6, SEC-AU-06).
- **Last-writer-wins e "il tombstone vince"** (§3.4 del piano) sono regole di sync di Agent 03. Se le si applica nel trigger, **non** si scarta in silenzio la scrittura (`return null`): il client segnerebbe il record come sincronizzato con una versione che il server non ha. Si ripristinano i valori di `old` e si aggiorna comunque `server_updated_at`, così il client riceve la versione del server al pull successivo. *(da allineare con DATA_MODEL.md)*
- `server_updated_at = now()` è l'istante di inizio transazione: una transazione lunga può fare commit dopo un'altra con timestamp maggiore. Il pull deve usare una finestra di sovrapposizione (es. cursore − 2 min) e applicare i record in modo idempotente. *(Agent 03)*
- Il trigger è `security invoker` e non legge altre tabelle: non serve `security definer`.

### 6.3 Tabelle non "fatto"

- **Catalogo statico** (`muscle_group`, catalogo `exercise`, `food` di base): non sta nel cloud, è nel bundle dell'app. Gli elementi custom stanno in tabelle F con `user_id` (o nella stessa tabella con `user_id not null` per le sole righe custom: niente righe condivise tra utenti nel cloud).
- **Tabelle solo server** (`private.ai_usage`): schema `private`, RLS attiva comunque, nessun grant ad `anon`/`authenticated`, accesso solo dal ruolo service delle Edge Functions tramite funzioni con grant esplicito.

### 6.4 Test RLS con pgTAP

File in `backend/supabase/tests/rls_<tabella>.test.sql`, uno per tabella sincronizzata, più un meta-test globale. Ogni file: `begin; ... rollback;` (nessun residuo). Casi minimi **obbligatori** per ogni tabella:

| # | Caso | Atteso |
|---|---|---|
| 1 | Utente A legge la tabella | vede solo le proprie righe (conteggio esatto) |
| 2 | A cerca le righe di B filtrando per `user_id` di B | insieme vuoto |
| 3 | A fa `update` sulle righe di B | nessun errore, 0 righe toccate; verificato come `postgres` che la riga di B è invariata |
| 4 | A fa `delete` sulle righe di B (se la policy esiste) | 0 righe; riga di B presente |
| 5 | A inserisce una riga con `user_id` di B | errore `42501` (violazione RLS) |
| 6 | A aggiorna una propria riga impostando `user_id` = B | errore `42501` |
| 7 | A fa upsert `on conflict (id) do update` usando l'`id` di una riga di B | errore `42501`; riga di B invariata |
| 8 | Ruolo `anon` (nessun JWT utente) legge la tabella | errore `42501` (privilegi revocati) |
| 9 | Insert con `updated_at = now() + 3 days` | salvato `updated_at <= now() + 5 min` |
| 10 | Insert con `server_updated_at` nel passato | salvato `server_updated_at = now()` |
| 11 | Insert senza consenso `cloud_sync` attivo (se §6.6 approvato) | errore `42501` |

Meta-test (`rls_meta.test.sql`), eseguito sullo schema intero:
- nessuna tabella in `public` con `relrowsecurity = false`;
- nessuna funzione `prosecdef = true` in `public`;
- ogni tabella in `public` con colonna `user_id` ha almeno una policy per `select`, `insert` e `update`;
- nessuna policy con espressione `true`;
- `anon` non ha privilegi su nessuna tabella di `public`;
- nessuna vista in `public` senza `security_invoker`.

Scheletro (da adattare alle colonne reali; le colonne minime di `auth.users` vanno verificate sulla versione di Supabase in uso):

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

-- Fixture, come postgres (bypassa la RLS)
insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@test.invalid'),
  ('00000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@test.invalid');
insert into public.user_consent (user_id, kind, policy_version) values
  ('00000000-0000-0000-0000-00000000000a', 'cloud_sync', 'test'),
  ('00000000-0000-0000-0000-00000000000b', 'cloud_sync', 'test');
insert into public.weight_entry (id, user_id, measured_at, day_key, tz, weight_kg, source) values
  ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', now(), current_date, 'Europe/Rome', 80.00, 'manual'),
  ('10000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', now(), current_date, 'Europe/Rome', 70.00, 'manual');

-- Come utente A
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

select results_eq($$ select count(*) from public.weight_entry $$, $$ values (1::bigint) $$,
  'A vede solo la propria riga');
select is_empty($$ select 1 from public.weight_entry
                   where user_id = '00000000-0000-0000-0000-00000000000b' $$,
  'A non legge le righe di B');
select lives_ok($$ update public.weight_entry set weight_kg = 50
                   where id = '10000000-0000-0000-0000-00000000000b' $$,
  'update sulle righe di B non fallisce ma non tocca nulla');
select throws_ok($$ insert into public.weight_entry (id, user_id, measured_at, day_key, tz, weight_kg, source)
                    values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000b',
                            now(), current_date, 'Europe/Rome', 60, 'manual') $$,
  '42501', null, 'insert con user_id di B rifiutato');
select throws_ok($$ update public.weight_entry set user_id = '00000000-0000-0000-0000-00000000000b'
                    where id = '10000000-0000-0000-0000-00000000000a' $$,
  '42501', null, 'A non può cedere una riga a B');
select throws_ok($$ insert into public.weight_entry (id, user_id, measured_at, day_key, tz, weight_kg, source)
                    values ('10000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000a',
                            now(), current_date, 'Europe/Rome', 60, 'manual')
                    on conflict (id) do update set weight_kg = excluded.weight_kg $$,
  '42501', null, 'upsert sull''id di una riga di B rifiutato');
select lives_ok($$ insert into public.weight_entry (id, user_id, measured_at, day_key, tz, weight_kg, source, updated_at, server_updated_at)
                   values ('10000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000000a',
                           now(), current_date, 'Europe/Rome', 80.5, 'manual',
                           now() + interval '3 days', now() - interval '30 days') $$,
  'insert con orologio sbagliato accettato ma corretto');

-- Come anon
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok($$ select * from public.weight_entry $$, '42501', null, 'anon: permesso negato');

-- Verifiche finali come postgres
reset role;
select is((select weight_kg from public.weight_entry where id = '10000000-0000-0000-0000-00000000000b'),
  70.00::numeric(5,2), 'la riga di B è invariata');
select ok((select updated_at <= now() + interval '5 minutes'
           from public.weight_entry where id = '10000000-0000-0000-0000-0000000000a2'),
  'updated_at limitato a now() + 5 min');
select ok((select server_updated_at = now()
           from public.weight_entry where id = '10000000-0000-0000-0000-0000000000a2'),
  'server_updated_at assegnato dal server');

select * from finish();
rollback;
```

### 6.5 Rilievo per Agent 03

Il piano usa `upsert on conflict (id)`. Con RLS, un conflitto su un `id` di un altro utente produce un errore 42501 che il client deve trattare come **errore permanente del record** (marcato `conflict`, mai ritentato all'infinito, mai "risolto" generando un nuovo id in automatico senza log). Con UUIDv7 generati dal client la collisione accidentale è trascurabile; il caso esiste solo se un client è manomesso.

### 6.6 Consensi lato server *(proposta, da confermare con Agent 03)*

Il consenso esplicito (art. 9) deve essere **dimostrabile** (art. 7(1)) e la regola "niente dati sanitari nel cloud senza consenso" è troppo importante per affidarla solo al client.

```sql
create table public.user_consent (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind           text not null check (kind in ('cloud_sync','ai_online')),
  policy_version text not null check (char_length(policy_version) <= 32),
  app_version    text check (char_length(app_version) <= 32),
  granted_at     timestamptz not null default now(),
  revoked_at     timestamptz
);
alter table public.user_consent enable row level security;
revoke all on table public.user_consent from anon, authenticated;
grant select, insert on table public.user_consent to authenticated;
grant update (revoked_at) on table public.user_consent to authenticated;  -- si può solo revocare

create policy user_consent_select on public.user_consent
  for select to authenticated using ( (select auth.uid()) = user_id );
create policy user_consent_insert on public.user_consent
  for insert to authenticated with check ( (select auth.uid()) = user_id and revoked_at is null );
create policy user_consent_update on public.user_consent
  for update to authenticated
  using ( (select auth.uid()) = user_id and revoked_at is null )
  with check ( (select auth.uid()) = user_id and revoked_at is not null );

create or replace function private.has_active_consent(p_kind text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from public.user_consent c
    where c.user_id = (select auth.uid())
      and c.kind = p_kind
      and c.revoked_at is null
  );
$$;
revoke execute on function private.has_active_consent(text) from public, anon;
grant execute on function private.has_active_consent(text) to authenticated;
```

Effetti: le policy insert/update delle tabelle F richiedono `cloud_sync` attivo; il gateway AI richiede `ai_online` attivo (SEC-AI-02). Le righe di consenso esistono solo se l'utente ha un account. La revoca di `cloud_sync` avvia la cancellazione dei dati cloud lato server (§12.4).

---

## 7. Gateway AI `jev-coach` (e altre Edge Functions)

### 7.1 Pipeline obbligatoria, in quest'ordine

1. Solo `POST`, `Content-Type: application/json`; corpo letto con un limite di **32 KiB**, oltre → `413 PAYLOAD_TOO_LARGE`.
2. **Autenticazione** (SEC-AI-01).
3. Kill switch `AI_ENABLED` → `503 AI_UNAVAILABLE`.
4. **Consenso** `ai_online` attivo (SEC-AI-02) → altrimenti `403 CONSENT_REQUIRED`.
5. **Validazione dello schema** di input (SEC-AI-04) → `422 INVALID_INPUT`.
6. **Safety in ingresso**: segnali di allarme nella chat (lessico condiviso con CoachKit: dolore toracico, svenimento, ecc.) → risposta `{ "fallback": "safety_template", "code": "SAF_SYMPTOMS" }` **senza chiamare il provider**.
7. **Rate limit e prenotazione budget** atomica (SEC-AI-03) → `429 RATE_LIMITED` con `Retry-After`.
8. Costruzione del prompt (SEC-AI-05).
9. Chiamata al provider con timeout, `max_output_tokens`, output a schema JSON, nessun tool (SEC-AI-06).
10. **Validazione dell'output** (SEC-AI-07); se fallisce, **un solo** retry con feedback generico; se fallisce ancora → `{ "fallback": "template", "code": "VALIDATION_FAILED" }`.
11. Consuntivo dei token reali nel budget.
12. Una riga di log di metadati (SEC-AI-10).

### 7.2 Regole

- **SEC-AI-01** Verifica JWT nel codice della funzione, **sempre**, indipendentemente dal flag `verify_jwt` della piattaforma: `Authorization: Bearer <access token utente>` → validazione con Supabase Auth (`auth.getUser(token)`, oppure verifica locale firma/`exp`/`aud` con le JWKS se il progetto usa chiavi di firma asimmetriche). Requisiti: `role = authenticated`, `sub` presente, `is_anonymous` non vero. La publishable key o l'anon key legacy (che è un JWT con ruolo `anon`) **non** bastano. *DA VERIFICARE sulla documentazione Supabase corrente: con le nuove publishable/secret key la verifica JWT della piattaforma va disattivata e fatta nel codice.*
- **SEC-AI-02** Il gateway legge il consenso `ai_online` con un client Supabase creato **con il JWT dell'utente** (la RLS si applica). Revoca del consenso ⇒ richiesta rifiutata anche se il client è vecchio o manomesso.
- **SEC-AI-03** Rate limit e budget (valori iniziali in variabili d'ambiente, da tarare):

  | Limite | Default |
  |---|---|
  | richieste/minuto/utente | 6 |
  | richieste `routine`/giorno/utente | 60 |
  | messaggi chat/giorno/utente | 30 |
  | richieste `analysis`/giorno/utente | 3 |
  | token (input + output) /giorno/utente | 150.000 |
  | token /giorno globali (tutti gli utenti) | `AI_GLOBAL_TOKENS_PER_DAY`, dimensionato sul budget mensile |
  | `max_output_tokens` | routine 400 · analysis 1.200 |

  Implementazione: tabella `private.ai_usage(user_hash, day, tier, requests, tokens)` + funzione `private.ai_budget_reserve(...)` con `insert ... on conflict do update ... returning` atomico, eseguibile **solo** dal ruolo service (grant esplicito, revoca a `public`/`anon`/`authenticated`). Si prenota una stima (input stimato + `max_output_tokens`) prima della chiamata e si corregge col consuntivo dopo. Il retry di validazione consuma budget. Il giorno è quello UTC. Contatori conservati 90 giorni.
- **SEC-AI-04** Schema di input (`schemaVersion: 1`), `additionalProperties: false` a ogni livello, validato con una libreria di schema prima di qualsiasi altra elaborazione:

  ```jsonc
  {
    "schemaVersion": 1,
    "tier": "routine | analysis",
    "kind": "today_card | recommendation | workout_summary | checkin_narrative | chat",
    "locale": "it",
    "facts": [                       // max 200
      { "id": "^[a-z0-9_]{1,64}$",
        "labelKey": "^[a-z0-9_.]{1,64}$",          // chiave di un catalogo di etichette, mai testo libero
        "unit": "kg | kcal | pct | g | reps | sets | days | score | none",
        "value": "number | null",                   // null per i fatti qualitativi (SEC-DC-02)
        "direction": "up | down | flat | null",
        "band": "low | moderate | good | high | below_target | on_target | above_target | null",
        "provenance": "engine | user_entered | hk_derived" }
    ],
    "entities": [                    // max 100
      { "id": "^[a-z0-9_-]{1,64}$",
        "kind": "exercise | food | recipe | meal | muscle | body_area",
        "catalogKey": "^[a-z0-9_.]{1,64}$ | null" }  // presente solo per elementi del catalogo statico
    ],
    "decisions": [                   // max 20
      { "type": "INCREASE_CALORIES | DECREASE_CALORIES | KEEP | NO_ACTION | CHANGE_MACROS | DELOAD | REDUCE_TRAINING_LOAD | INCREASE_TRAINING_LOAD | CHANGE_EXERCISE",
        "reasonCodes": ["^[A-Z0-9_]{1,64}$"],      // max 10
        "factIds": ["<id di facts>"],
        "confidence": "number 0...1" }
    ],
    "safetyFlags": ["^[A-Z0-9_]{1,64}$"],          // max 10
    "chat": {                        // solo se kind = chat
      "messages": [ { "role": "user | assistant", "text": "string, max 1000 caratteri" } ]  // max 10
    }
  }
  ```

  Nessun campo per nome, email, età, sesso, `user_id`, note, limitazioni in testo libero, nomi custom. I `fact.id` e gli `entity.id` sono identificativi locali alla richiesta (non gli UUID del DB). La lista dei tipi di decisione è quella del CheckInEngine (§5.10 del piano): l'elenco definitivo lo fissa Agent 09.
- **SEC-AI-05** Separazione istruzioni/dati (difesa dalla prompt injection):
  - il system prompt è statico, versionato nel repository, senza segreti e senza dati;
  - il CoachContext entra come **un blocco JSON delimitato** (es. tra `<coach_context>` e `</coach_context>`, con la regola esplicita che il contenuto è solo dato);
  - i messaggi chat entrano **solo** come messaggi di ruolo `user`/`assistant`, mai concatenati nel system prompt;
  - **nessun testo scritto da utenti o da terzi** (nomi custom di alimenti/esercizi/ricette/pasti, note, nomi e marche di prodotti Open Food Facts, testo delle limitazioni) entra nel contesto: il modello cita le entità con `{{label:<id>}}`, il client sostituisce il nome. I nomi del catalogo statico (scritti da noi) possono entrare come `catalogKey`;
  - il modello non ha tool, function calling, web search, né accesso ad altri dati. *(estensione di ADR-014 da confermare con Agent 09)*
- **SEC-AI-06** Chiamata al provider:
  - timeout del gateway: `routine` 12 s, `analysis` 40 s (`AbortController`); il client mostra il template dopo 8 s (UF-09) e chiude la richiesta a 15 s / 45 s;
  - output a schema JSON (structured output del provider);
  - **nessuna memorizzazione lato provider** dove l'API lo consente (es. `store: false` nella Responses API di OpenAI; *DA VERIFICARE sui parametri correnti di ciascun provider*);
  - nessun identificativo dell'utente nella richiesta; se il provider chiede un identificativo per l'abuse monitoring si usa l'HMAC dell'utente, mai lo `user_id`.
- **SEC-AI-07** Validazione dell'output (nel gateway **e di nuovo nel client** prima del rendering, difesa in profondità):
  - JSON conforme a `{ headline ≤ 120 caratteri, body ≤ 900, why[] ≤ 5 × 200, dataUsed[] ≤ 20 factId }`, `additionalProperties: false`;
  - **number grounding ADR-014**: nessuna cifra `[0-9]` nel testo; nessun numerale in lettere (lessico italiano di Agent 09 con test, attenzione agli articoli "un/uno/una"); ogni `{{fact:id}}` e `{{label:id}}` esiste nell'input; `dataUsed` ⊆ `facts.id`;
  - niente URL (`http`, `www.`, domini), markdown (`](`, `![`), HTML (`<`), indirizzi email;
  - filtro safety in uscita (PS-SAF-01): farmaci, integratori con dosaggi, digiuni prolungati, diagnosi o nomi di patologie come ipotesi, linguaggio colpevolizzante (PS-SAF-07) → fallback al template;
  - il client mostra solo testo semplice (`Text(verbatim:)`/`AttributedString` senza markdown): un link nel testo non è mai cliccabile.
- **SEC-AI-08** Il testo AI non cambia mai i dati né il piano: le azioni passano dagli engine (PS-JEV-08). Il gateway non scrive su tabelle utente.
- **SEC-AI-09** **Nessuna persistenza dei contenuti nel gateway**: niente tabelle, file, cache o code con contesto, prompt o risposte. Le conversazioni restano sul dispositivo (`ai_message` L).
- **SEC-AI-10** Log: una riga JSON per richiesta con soli metadati: `request_id`, `user_hash` (HMAC-SHA256 di `user_id` con `LOG_HMAC_SALT`), `tier`, `kind`, `provider`, `model`, `latency_ms`, `tokens_in`, `tokens_out`, `validation` (`ok | retry_ok | fallback`), `error_code`. Mai: body, prompt, risposta, fatti, testo chat, header `Authorization`, messaggi d'errore del provider (possono contenere frammenti del prompt).
- **SEC-AI-11** Due client nel gateway: `userClient` (JWT dell'utente, RLS attiva) per tutto ciò che riguarda l'utente; `serviceClient` (secret key) **solo** per `private.ai_budget_reserve` / `ai_budget_commit`. In review: `serviceClient` non può comparire accanto a un nome di tabella di `public`.
- **SEC-AI-12** Errori al client: solo `{ "error": { "code": "<CODICE>" }, "requestId": "<id>" }` con codici chiusi (`UNAUTHORIZED` 401, `CONSENT_REQUIRED` 403, `PAYLOAD_TOO_LARGE` 413, `INVALID_INPUT` 422, `RATE_LIMITED` 429, `AI_UNAVAILABLE` 503, `INTERNAL` 500). Mai stack trace, messaggi del provider, nomi di modelli o di variabili d'ambiente, dettagli di validazione oltre il codice.
- **SEC-AI-13** Nessun header CORS permissivo: il client è un'app nativa; nessun `Access-Control-Allow-Origin: *`.

### 7.3 `food-search` (proxy USDA)

- JWT utente obbligatorio con le stesse regole di SEC-AI-01: senza, la funzione sarebbe un proxy aperto sulla nostra chiave USDA. Senza account l'app usa solo il catalogo locale e Open Food Facts (PS §10).
- Query ≤ 100 caratteri, barcode solo cifre (8–14); rate limit 120 richieste/ora/utente.
- Nei log nessun testo di ricerca né barcode: solo metadati come in SEC-AI-10.
- La risposta USDA è un dato non fidato: il client la valida come i dati Open Food Facts.

### 7.4 `account-delete`

- JWT obbligatorio + `authorizationCode` Apple fresco (SEC-AU-06). Usa il `serviceClient` (unico caso legittimo oltre al budget AI), per cancellare l'utente e i suoi dati.
- Modalità `cloud_data` (revoca del consenso alla sync: cancella le righe delle tabelle F dell'utente, mantiene account e consensi) e `account` (cancellazione completa).
- Idempotente: una seconda chiamata dopo un successo parziale completa il lavoro.

---

## 8. Storage locale

- **SEC-LS-01 Data Protection del DB SQLite: `NSFileProtectionCompleteUntilFirstUserAuthentication`.**
  - Perché non `complete`: dopo circa 10 s dal blocco i file diventano illeggibili e GRDB riceve errori di I/O. Questo romperebbe: la consegna in background di HealthKit (nuove pesate a telefono bloccato), i task di sync in background, la riprogrammazione delle notifiche locali dopo un'azione da notifica, la persistenza di un set registrato mentre il telefono si blocca durante il workout. Un errore di I/O in mezzo a un workout viola "Workout in corso persi = 0" (PS §11.2).
  - Perché non `completeUnlessOpen`: con SQLite in WAL i file `-wal` e `-shm` vengono creati e riaperti di continuo; il comportamento è difficile da garantire e da testare.
  - Applicazione: il DB vive in `Application Support/JevFit/` (mai in `Documents`, che con `UIFileSharingEnabled` sarebbe esposto); la protezione si imposta sulla **cartella** prima di creare il DB, così `-wal` e `-shm` la ereditano; un test d'integrazione legge l'attributo `FileAttributeKey.protectionKey` dei tre file.
  - `UIFileSharingEnabled` e `LSSupportsOpeningDocumentsInPlace` assenti o `false`.
- **SEC-LS-02** Niente SQLCipher nell'MVP. La cifratura a riposo è quella di iOS (Data Protection, chiave legata al codice del dispositivo). SQLCipher aggiungerebbe una dipendenza e una chiave da conservare comunque nel Keychain con la stessa accessibilità: nessun guadagno reale contro le minacce di §2.1.
- **SEC-LS-03 Backup: DB principale incluso nel backup del dispositivo.** Trade-off:
  - *incluso*: senza account il backup è l'unico modo di non perdere mesi di allenamenti e alimentazione; PS-AC-06 lo promette già all'utente; Apple cifra il backup;
  - *escluso*: meno copie dei dati sanitari, ma perdita totale dei dati per chi non usa l'account, in contrasto con la promessa di prodotto;
  - **decisione**: incluso, con due eccezioni: la cache HealthKit (SEC-LS-04) e i file temporanei. Se la verifica di §13.1 concludesse che i dati derivati da HealthKit non possono stare nel backup iCloud, anche le `weight_entry` con `source = healthkit` vanno spostate nel file escluso (sono reimportabili da Salute tramite `hk_uuid`).
- **SEC-LS-04** `health_metric_daily` (aggregati da HealthKit, solo locali per ADR-012) sta in un **file SQLite separato** (`health-cache.sqlite`) con `isExcludedFromBackup = true`, protezione come SEC-LS-01. È ricostruibile da Salute (UF-13); così nessun dato fisiologico di HealthKit finisce nel backup iCloud. *(da confermare con Agent 03/08: secondo `DatabaseQueue` dietro lo stesso `DataStore`.)*
- **SEC-LS-05** Cache derivate (tabelle D): restano nel DB principale (ricalcolabili, invalidate da `engine_version`). Non c'è motivo di gestirle a parte: contengono informazioni già deducibili dai fatti nello stesso file.
- **SEC-LS-06** Export (PS-AC-05): file JSON/CSV creati in `tmp/` con `NSFileProtectionComplete`, condivisi con `ShareLink`/share sheet, cancellati a fine condivisione e a ogni avvio (pulizia di `tmp/`). Prima dell'export, autenticazione del proprietario (`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`; senza codice impostato sul dispositivo basta la conferma). Testo in UI: "Il file contiene i tuoi dati di salute. Una volta condiviso non è più protetto da JEV FIT."
- **SEC-LS-07** Rete e cache: vedi SEC-NW-03. Nessun dato sanitario in `UserDefaults` (plist caricato per intero in memoria, fuori dal DB e quindi fuori da export, eliminazione e controlli di questo documento): lì solo preferenze di UI (filtro grafici, tab), flag tecnici e lo stato dei consensi come booleano.
- **SEC-LS-08** Notifiche locali: il testo non contiene valori sanitari né nomi di limitazioni. Sì: "È il momento della pesata", "Check-in settimanale pronto", "Recupero terminato". No: "Ieri 82,4 kg", "Ti mancano 650 kcal".
- **SEC-LS-09** Nessuna donazione di contenuti sanitari a Spotlight, `NSUserActivity` indicizzabili, Siri o widget nell'MVP. In V2 (widget/App Intents) i dati condivisi tramite App Group seguono SEC-LS-01 e questa sezione si aggiorna prima del merge.
- **SEC-LS-10** Nessun dato nel pasteboard generale da parte dell'app (salvo copia esplicita dell'utente, es. codice errore di sync).

## 9. Rete

- **SEC-NW-01** ATS di default; vietati `NSAllowsArbitraryLoads`, `NSAllowsArbitraryLoadsInWebContent`, `NSExceptionDomains`. Domini attesi: `<progetto>.supabase.co` e i domini HTTPS di Open Food Facts. Qualsiasi nuovo dominio passa dalla review di Agent 12.
- **SEC-NW-02** Niente certificate pinning nell'MVP: i certificati della piattaforma Supabase ruotano fuori dal nostro controllo e un pin sbagliato bloccherebbe tutti i client fino a una nuova release; la minaccia residua (CA compromessa, profilo installato dall'utente) è bassa per un'app personale. Da rivalutare prima del commerciale.
- **SEC-NW-03** Le sessioni verso Supabase, gateway e Open Food Facts usano una `URLSessionConfiguration` senza `URLCache` (`urlCache = nil`, `requestCachePolicy = .reloadIgnoringLocalCacheData`) e senza cookie; per supabase-swift si passa la sessione configurata nelle opzioni globali del client (*da verificare sull'API della versione fissata*).
- **SEC-NW-04** Open Food Facts: solo testo cercato o barcode, nessun identificativo; `User-Agent` con nome app, versione e un contatto dello **sviluppatore** (come chiede OFF), mai dati dell'utente.

---

## 10. Logging e crash report

- **SEC-LG-01** Solo `os.Logger` (subsystem `app.jevfit`, categorie per modulo). Vietati `print`, `debugPrint`, `dump`, `NSLog` nel codice di produzione (`Sources/`, `App/`); la CI li cerca con `grep` e fallisce.
- **SEC-LG-02** Privacy esplicita a ogni interpolazione. Default di progetto: `privacy: .private`. `.public` solo per valori tecnici a cardinalità chiusa (nomi di enum, codici errore, conteggi tecnici come "3 record in outbox", durate di operazioni), con il commento `// log-public: <motivo>` sulla stessa riga; la CI segnala ogni `.public` senza quel commento. Per correlare eventi senza rivelare valori: `privacy: .private(mask: .hash)`.
  Attenzione: **numeri e booleani interpolati in `os.Logger` sono pubblici di default**. Un `logger.debug("peso \(kg)")` scrive il peso in chiaro. Per questo i valori sanitari non si loggano proprio (SEC-LG-03), nemmeno come `.private`.
- **SEC-LG-03** Non si logga **mai**, a nessun livello, nemmeno in debug:
  - peso, misure, % grasso, trend, pendenze;
  - calorie, macro, alimenti, nomi di alimenti/ricette/pasti, barcode, testi di ricerca;
  - HRV, FC, FC a riposo, sonno, passi, energia attiva, readiness e sottopunteggi;
  - carichi, ripetizioni, RIR, e1RM, PR;
  - note, limitazioni, segnalazioni di dolore, gravidanza/allattamento, anno di nascita, sesso, altezza;
  - contenuti chat, CoachContext, prompt, risposte AI;
  - token, nonce, authorization code, header `Authorization`, chiavi;
  - `user_id`, Apple `sub`, email;
  - payload e messaggi d'errore del server (possono riportare valori).

  Si possono loggare: eventi ("sync completata"), conteggi tecnici, durate, codici d'errore, id di richiesta, versioni.
- **SEC-LG-04** Nessun dato nei messaggi di `fatalError`, `precondition`, `assert` e nelle `description` degli errori che possono finire in un crash report o in un alert.
- **SEC-LG-05** Edge Functions: solo la riga di metadati di SEC-AI-10; nessun `console.log` di oggetti richiesta/risposta; gli errori si loggano come codice + nome della classe d'errore, non `error.message` del provider.
- **SEC-LG-06** Nessun valore sanitario nelle URL (query string di PostgREST), che finiscono negli API log di Supabase: i filtri usano id, cursori `server_updated_at`, `day_key`.
- **SEC-LG-07** **Nessun SDK di crash reporting o analytics di terze parti nell'MVP.** Fonti di diagnostica ammesse: crash report di Apple (Xcode Organizer / TestFlight, condivisi solo dagli utenti che hanno acconsentito nelle impostazioni di sistema) e, se utile, `MetricKit` letto sul dispositivo senza invio automatico. Un SDK terzo richiede: ADR, aggiornamento del manifest privacy e della Privacy Nutrition Label, DPA con il fornitore.
- **SEC-LG-08** Errori di sync mostrati all'utente (UF-12: "codice errore copiabile"): solo un codice, mai il messaggio del server.

---

## 11. Supply chain

- **SEC-SC-01** Dipendenze consentite nell'app: **GRDB** e **supabase-swift**. Una nuova dipendenza richiede un ADR con alternative considerate e il parere di Agent 12.
- **SEC-SC-02** Versioni **esatte** (`exact:` in `Package.swift`, `exactVersion` in `project.yml`). Oggi non è così: vedi §16.
- **SEC-SC-03** `Package.resolved` versionato e verificato in CI. Il `.xcodeproj` è generato e ignorato da Git, quindi il suo `Package.resolved` non viene versionato: la CI risolve le dipendenze e confronta il risultato con un `Package.resolved` di riferimento nel repository (fallisce se diverso). Ogni aggiornamento è un PR dedicato con changelog e diff della dipendenza letti.
- **SEC-SC-04** Di supabase-swift si usano solo i prodotti necessari (Auth, PostgREST, Functions), non l'ombrello `Supabase` che include Realtime e Storage (*nomi dei prodotti da verificare sulla versione fissata*). A ogni aggiornamento si controlla l'elenco delle dipendenze transitive e il **Privacy Report** aggregato generato dall'archivio Xcode.
- **SEC-SC-05** GitHub Actions: action di terze parti fissate per SHA completo del commit (non per tag); `permissions: contents: read` di default, permessi in scrittura solo nel job che li richiede; segreti disponibili solo ai job su `main`/tag, mai ai PR da fork.
- **SEC-SC-06** Edge Functions: import con versione esatta (`npm:`/`jsr:` con `@x.y.z`), `deno.lock` versionato; chiamate a OpenAI/Anthropic con `fetch` sulle API HTTP invece degli SDK (meno codice di terzi nel processo che vede le chiavi).
- **SEC-SC-07** Dati di terzi inclusi nell'app (catalogo alimenti derivato da USDA, pubblico dominio): generati da script in `tools/catalog/` versionati, mai scaricati a runtime da URL non fissati. Attribuzione ODbL per Open Food Facts in Impostazioni → Licenze.

---

## 12. GDPR

> Contesto: oggi l'unico utente è il titolare stesso; per l'uso puramente personale vale probabilmente l'esenzione domestica (art. 2(2)(c)). Il progetto si progetta comunque per l'uso commerciale, dove il GDPR si applica in pieno. **Tutta questa sezione va validata da un legale** (§15).

### 12.1 Ruoli

- **Titolare**: chi pubblica l'app (oggi lo sviluppatore come persona fisica; in futuro la società che la commercializza).
- **Responsabili (art. 28)**: Supabase (DB, Auth, Edge Functions, log); il provider AI attivo (OpenAI e/o Anthropic); Apple non è responsabile per i dati dell'app, salvo i servizi che l'utente usa direttamente (backup iCloud, Salute).
- **Terzi autonomi**: Open Food Facts riceve dal dispositivo testo cercato, barcode e indirizzo IP.
- **Dati solo locali**: senza account i dati restano sul dispositivo e il titolare non vi accede. *DA VERIFICARE con il legale come inquadrarli nell'informativa (il trattamento avviene sul dispositivo dell'utente tramite il software del titolare).*

### 12.2 Basi giuridiche e consensi

| Trattamento | Base giuridica | Consenso nell'app |
|---|---|---|
| Account (Apple `sub`, eventuale email relay) | art. 6(1)(b) esecuzione del servizio richiesto | creazione dell'account |
| **Sync cloud** dei dati sanitari e di fitness | art. 9(2)(a) consenso esplicito + art. 6(1)(a) | **Consenso A**, schermata dedicata in SCR-AC-01 prima del primo upload |
| **JEV AI online** (CoachContext e chat al provider AI) | art. 9(2)(a) consenso esplicito + art. 6(1)(a) | **Consenso B**, schermata dedicata al primo uso di JEV online; toggle in SCR-SET-10 |
| Sicurezza e prevenzione abusi (log di metadati, contatori di rate limit) | art. 6(1)(f) legittimo interesse | informativa |
| Prova del consenso (`user_consent`) | art. 6(1)(c) / art. 7(1) | — |
| Ricerca alimenti online | art. 6(1)(b); nessun dato sanitario inviato | informativa |

Requisiti dei consensi A e B:
- **separati**, non preselezionati, non condizione per usare l'app (tutto funziona offline e con i template);
- **specifici e informati**: ogni schermata dice cosa viene inviato, a chi (nome del fornitore e paese), per quale scopo, per quanto tempo, come revocare;
- **revocabili** con la stessa facilità con cui si danno (toggle in SCR-SET-10);
- registrati con versione dell'informativa e data (§6.6); un cambio sostanziale dell'informativa richiede un nuovo consenso.

Effetti della revoca:
- **A (sync)**: la sync si ferma; i dati cloud vengono cancellati (`account-delete` modalità `cloud_data`) dopo una conferma che spiega che quelli locali restano; l'account può restare per JEV AI.
- **B (AI)**: il gateway rifiuta subito (SEC-AI-02); JEV torna ai template; lato gateway non c'è nulla da cancellare (SEC-AI-09); lato provider vale la sua retention (§12.6).

### 12.3 Informativa (art. 13)

Testo in italiano, raggiungibile da onboarding, SCR-AC-01, schermate di consenso, Impostazioni → Privacy e dalla pagina dell'App Store (Apple richiede un link alla privacy policy). Contenuti minimi: titolare e contatti; categorie di dati (§3); finalità e basi giuridiche (§12.2); destinatari e responsabili con sede; trasferimenti extra-UE e garanzie; tempi di conservazione (§12.6); diritti e come esercitarli; diritto di revocare il consenso; diritto di reclamo al Garante; che i dati Salute non sono usati per pubblicità né venduti; natura non medica dell'app (PS-SAF-05) e uso di un sistema di AI (§12.8).

### 12.4 Diritti dell'interessato

| Diritto | Come lo si soddisfa nell'app |
|---|---|
| Accesso (art. 15) e portabilità (art. 20) | Export JSON + CSV (PS-AC-05). Con sync attiva l'export parte dopo un pull completo, così include anche ciò che è solo nel cloud. Formato documentato in `DATA_MODEL.md` |
| Rettifica (art. 16) | Modifica in app di ogni dato inserito |
| Cancellazione (art. 17) | Eliminazione dati locali; eliminazione dati cloud (revoca A); eliminazione account (SEC-AU-06) |
| Revoca del consenso (art. 7(3)) | Toggle A e B |
| Opposizione / limitazione | Contatto del titolare (informativa); per i trattamenti basati sul consenso coincide con la revoca |

Tempi: le funzioni in app sono immediate; per richieste via email il termine di legge è un mese (art. 12(3)).

### 12.5 Registro dei trattamenti (art. 30), versione minima

| # | Trattamento | Interessati | Dati | Finalità | Base | Destinatari | Extra-UE | Conservazione | Misure |
|---|---|---|---|---|---|---|---|---|---|
| T1 | Account | utenti con account | Apple `sub`, email relay se presente | autenticazione | 6(1)(b) | Supabase | *da verificare* (§12.7) | fino all'eliminazione dell'account | §5 |
| T2 | Sync cloud | utenti con consenso A | dati di §3 marcati "cloud" | backup e multi-dispositivo | 9(2)(a) | Supabase (regione UE) | *da verificare* | fino a revoca o eliminazione; backup del fornitore secondo il piano | §6, RLS, cifratura in transito e a riposo |
| T3 | JEV AI online | utenti con consenso B | CoachContext (§7), chat | spiegazioni e coaching | 9(2)(a) | Supabase (gateway), provider AI | **probabile** | gateway: nessuna; provider: §12.6 | §7, minimizzazione, pseudonimizzazione |
| T4 | Sicurezza e abusi | utenti con account | metadati richieste, HMAC utente, contatori | prevenzione abusi e costi | 6(1)(f) | Supabase | *da verificare* | contatori 90 giorni; log secondo la retention della piattaforma | §7.2 |
| T5 | Consensi | utenti con account | tipo, versione, date | prova del consenso | 6(1)(c) | Supabase | *da verificare* | per la durata dell'account (*periodo successivo da verificare con il legale*) | §6.6 |

### 12.6 Conservazione

- **Dispositivo**: finché l'utente non elimina i dati o l'app.
- **Cloud**: finché c'è il consenso A e l'account. I tombstone vengono purgati dopo 90 giorni (abbastanza per propagare la cancellazione agli altri dispositivi; *da allineare con Agent 03*).
- **Backup della piattaforma Supabase**: i dati cancellati restano nei backup automatici fino alla loro scadenza (dipende dal piano Supabase): va scritto nell'informativa con il valore reale.
- **Gateway**: nessun contenuto. Contatori di budget 90 giorni. Log della piattaforma secondo la retention del piano Supabase (contengono solo metadati).
- **Provider AI**: dipende dal contratto. Obiettivo: zero data retention o la retention minima disponibile, nessun uso per addestramento. *Da verificare per ogni provider (§12.7).*

### 12.7 Trasferimenti extra-UE e fornitori: cosa va verificato

Per **Supabase** (progetto in regione UE, ADR-006):
- DPA firmato (Supabase ne offre uno standard: *verificare versione e modalità di accettazione*);
- elenco dei sub-responsabili e loro sede; accessi dal supporto o dalla società madre fuori UE e relative garanzie (SCC e/o adesione all'EU-US Data Privacy Framework);
- cifratura a riposo, durata dei backup, retention dei log per il piano scelto, così l'informativa riporta valori reali.

Per il **provider AI** (OpenAI iniziale, Anthropic alternativo, ADR-007), prima di attivare il consenso B per utenti diversi dal titolare:
- **entità contraente** per i clienti UE e sede del trattamento; opzioni di **residenza dei dati in UE**, se esistono per il tipo di account e i modelli usati;
- **DPA** e meccanismo di trasferimento (**SCC** del 2021 e/o **DPF**), con transfer impact assessment;
- **zero data retention**: se è disponibile, a quali condizioni (spesso richiede approvazione), su quali endpoint/funzionalità; in alternativa la retention standard per abuse monitoring e come si disattiva la memorizzazione (es. `store: false`);
- conferma contrattuale che i dati inviati via API **non sono usati per addestrare** i modelli;
- che le funzioni usate (structured output) siano compatibili con la ZDR.

Il cambio di provider o di modello si fa con una variabile d'ambiente (ADR-007), ma **cambiare provider è un cambio di destinatario**: aggiornare informativa, registro e, se il nuovo provider non era indicato nel consenso B, chiedere di nuovo il consenso.

### 12.8 Altri obblighi da valutare con il legale

- **DPIA (art. 35)**: con molti utenti, il trattamento su larga scala di dati sanitari con un sistema AI è un caso tipico in cui è richiesta. Da fare prima del lancio commerciale.
- **DPO (art. 37)**: potrebbe servire se il trattamento su larga scala di dati sanitari diventa attività principale.
- **Minori**: età minima dell'app **16 anni**, obiettivi in deficit solo da **18** (PS-ON-03, §5.3 del piano). Il gate usa l'anno di nascita con calcolo conservativo (limite inferiore dell'età). In Italia la soglia per il consenso ai servizi della società dell'informazione è fissata dall'art. 2-quinquies del Codice privacy (*secondo me 14 anni: verificare*); il progetto sceglie 16 per prudenza, perché si tratta di dati sanitari e di consigli nutrizionali. La fascia d'età dell'App Store va scelta di conseguenza (*verificare le fasce attuali del questionario Apple*).
- **AI Act (Reg. UE 2024/1689)**: obblighi di trasparenza per i sistemi che interagiscono con persone (dire che JEV è un'AI): *verificare la data di applicazione e se il caso rientra*. La UI dice già "JEV" come assistente AI e "Spiegazione offline" per i template; aggiungere "Risposta generata da AI" sui testi del gateway.
- **Dispositivi medici (Reg. UE 2017/745)**: l'app non diagnostica e non tratta (PS-SAF-01); la *destinazione d'uso* dichiarata (descrizione App Store, onboarding, informativa) deve restare "benessere e fitness". Da far confermare.
- **Notifica di violazione** (art. 33–34): procedura in SEC-SE-06.

---

## 13. Apple

### 13.1 HealthKit e guideline 5.1.3

Cosa ritengo **ragionevolmente sicuro** (riassunto, non citazione):
- le App Review Guidelines, sezione **5.1.3 (Health and Health Research)**, vietano di usare o comunicare a terzi i dati raccolti nel contesto salute/fitness (inclusi quelli da HealthKit) per **pubblicità, marketing o data mining basato sull'uso**; l'uso è ammesso per migliorare la gestione della salute o per la ricerca, **e solo con il permesso dell'utente**;
- la stessa sezione vieta di scrivere in HealthKit dati falsi o inesatti e di **memorizzare informazioni sanitarie personali in iCloud**;
- un'app che usa HealthKit deve avere una **privacy policy** e deve spiegare l'uso di ogni tipo di dato (stringhe `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`); va richiesto solo ciò che serve (PS-HK-01/02 lo fanno già);
- l'integrazione con HealthKit va indicata chiaramente nell'interfaccia e nella descrizione dell'app (guideline 2.5.1);
- i dati HealthKit non si vendono (Apple Developer Program License Agreement).

**DA VERIFICARE sul testo ufficiale corrente** (Fase 12 e prima di TestFlight esterno):
1. se l'invio a un provider AI (responsabile del trattamento, per fornire il coaching richiesto dall'utente, con consenso esplicito) di **informazioni derivate** da HealthKit (sottopunteggi readiness) è ammesso;
2. se "non memorizzare informazioni sanitarie in iCloud" si applica anche al **backup del dispositivo** che contiene il container dell'app (decisione SEC-LS-03/04);
3. eventuali clausole del Developer Program License Agreement sull'uso dei dati HealthKit verso terzi, oltre a quanto sopra;
4. la guideline **5.1.2(i)**: a quanto mi risulta, un aggiornamento recente richiede di indicare chiaramente quando dati personali vengono condivisi con **AI di terze parti** e di ottenere un permesso esplicito prima di farlo. Il consenso B è progettato per soddisfarla, ma il testo va letto.

**Regola operativa conservativa del progetto (vincolante fino all'esito delle verifiche):**
- **SEC-HK-01** Nel CoachContext entrano solo **sottopunteggi 0–100** già calcolati dal RecoveryEngine per le componenti HealthKit; **mai valori HealthKit** (grezzi o aggregati) né serie temporali. I fatti sul peso sono qualitativi (SEC-DC-02).
- **SEC-HK-02** Dati fisiologici HealthKit (HRV, FC, FC a riposo, sonno, passi, energia attiva) mai nel cloud (ADR-012) e mai nel backup (SEC-LS-04).
- **SEC-HK-03** Nessun uso pubblicitario o di marketing, nessuna profilazione commerciale, nessuna vendita o cessione, nessun SDK di analytics/ads che possa vederli.
- **SEC-HK-04** Nessun uso di CloudKit / iCloud Drive / `NSUbiquitousKeyValueStore` per dati sanitari.
- **SEC-HK-05** Se la verifica del punto 1 è negativa: l'AI non riceve nulla di derivato da HealthKit; la readiness viene spiegata solo dal template (il sottopunteggio "recupero muscolare", derivato dagli allenamenti, può restare).
- **SEC-HK-06** Le scritture in Salute (PS-HK-05) contengono solo ciò che l'utente ha inserito o completato davvero (nessun dato stimato scritto come misurato).

### 13.2 Account, login, eliminazione

- **Eliminazione dell'account dall'app** (guideline 5.1.1(v)): obbligatoria per le app che consentono di creare un account; deve essere avviabile in app, non solo via email o sito. SEC-AU-06 la implementa.
- Con Sign in with Apple, all'eliminazione dell'account vanno **revocati i token** tramite l'API REST di Sign in with Apple (indicazione Apple del 2022; *verificare il testo corrente*).
- Sign in with Apple come unico login soddisfa la guideline 4.8.
- Disclaimer non medico e invito a consultare un professionista (guideline 1.4.1 per le app che possono influire sulla salute): PS-SAF-05.

### 13.3 Privacy manifest (`App/PrivacyInfo.xcprivacy`)

Contenuto e motivazioni:
- `NSPrivacyTracking = false`, `NSPrivacyTrackingDomains` vuoto: nessun tracking nel senso di Apple (nessun collegamento con dati di terzi per pubblicità, nessun data broker).
- `NSPrivacyCollectedDataTypes`: il manifest è **statico** e descrive ciò che l'app **può** raccogliere, cioè trasmettere fuori dal dispositivo e conservare. Non può dire "solo se l'utente attiva la sync o JEV AI". Per questo dichiara i tipi raccolti **quando** sync o AI sono attivi; la condizione (account + consenso) si spiega nell'informativa e nelle schermate di consenso. Dichiarare meno di ciò che il binario può fare sarebbe inesatto. Tutti i tipi: `Linked = true` (associati all'account), `Tracking = false`, scopo solo `NSPrivacyCollectedDataTypePurposeAppFunctionality`.

  | Tipo | Perché |
  |---|---|
  | `NSPrivacyCollectedDataTypeHealth` | peso, misure, alimentazione, limitazioni, dolore, sottopunteggi readiness (sync e AI) |
  | `NSPrivacyCollectedDataTypeFitness` | allenamenti, set, programma (sync e AI) |
  | `NSPrivacyCollectedDataTypeSensitiveInfo` | il flag gravidanza/allattamento (Apple lo elenca tra le "Sensitive Info") viene sincronizzato perché il gate di sicurezza deve valere su ogni dispositivo. Se Agent 03 lo rendesse solo locale, va tolto |
  | `NSPrivacyCollectedDataTypeUserID` | id dell'account Supabase / Apple `sub` |
  | `NSPrivacyCollectedDataTypeEmailAddress` | **prudenziale**: Supabase può salvare l'email (anche relay) contenuta nell'identity token. Da togliere se la verifica di SEC-AU-02 conferma che nessuna email viene salvata |
  | `NSPrivacyCollectedDataTypeOtherUserContent` | messaggi chat a JEV (al provider AI), nomi custom e note sincronizzati |
  | `NSPrivacyCollectedDataTypeOtherDataTypes` | anno di nascita, preferenze di allenamento e impostazioni sincronizzate |

  Non dichiarati: Crash Data e Performance Data (nessun SDK; i crash report di Apple sono raccolti da Apple con il consenso dell'utente: *verificare se Apple chiede comunque di dichiararli*); Search History (le ricerche di alimenti sono servite in tempo reale e non conservate da noi: *verificare la definizione di "raccolta" di Apple per le query inviate a Open Food Facts e al proxy USDA*); Location, Contacts, Purchases, Usage Data, Identifiers pubblicitari: non usati.
- `NSPrivacyAccessedAPITypes`: solo **UserDefaults** con reason **`CA92.1`** (leggere e scrivere dati accessibili solo all'app stessa: preferenze UI, flag di primo avvio). Valutati e **non** inclusi oggi:
  - *File Timestamp* (`C617.1` per file nel container dell'app, `DDA9.1` per mostrare date all'utente): servono solo se il codice legge date di creazione/modifica dei file (es. pulizia di `tmp/` per data). La pulizia di SEC-LS-06 cancella tutto senza leggere date, quindi non serve;
  - *Disk Space* (`E174.1` per verificare lo spazio prima di scrivere): non previsto; da aggiungere se l'export controlla lo spazio libero;
  - *System Boot Time* (`35F9.1` per misurare il tempo tra eventi nell'app): il timer di recupero deve usare un istante di fine in tempo reale (`Date`), necessario comunque per la notifica in background, e non `ProcessInfo.systemUptime` / `mach_absolute_time()`. *Da verificare se `ContinuousClock`/`SuspendingClock` rientrino nelle API dichiarabili.*
  - App Group (`1C8F.1` per UserDefaults condivisi) servirà in V2 con i widget.

  Regola **SEC-PM-01**: chi usa una Required Reason API aggiunge il tipo e il reason code nel manifest nello stesso PR; la CI cerca con `grep` i simboli noti (`UserDefaults`, `@AppStorage`, `creationDate`, `contentModificationDate`, `attributesOfItem`, `volumeAvailableCapacity`, `systemUptime`, `mach_absolute_time`, `activeInputModes`) e la review confronta. Le dipendenze (GRDB, supabase-swift) dichiarano le proprie API nei loro manifest, se li includono: *verificare a M1 se le versioni fissate li includono*; il Privacy Report dell'archivio Xcode è la prova finale.

### 13.4 Privacy Nutrition Label App Store (proposta)

**Data Used to Track You**: nessuno.
**Data Linked to You** (tutti per *App Functionality*):

| Categoria Apple | Tipo | Quando |
|---|---|---|
| Health & Fitness | Health | sync attiva o JEV AI online |
| Health & Fitness | Fitness | sync attiva o JEV AI online |
| Sensitive Info | Sensitive Info | sync attiva (flag gravidanza/allattamento) |
| Identifiers | User ID | con account |
| Contact Info | Email Address | con account, se Supabase la salva (vedi §13.3) |
| User Content | Other User Content | chat JEV; nomi custom e note con sync attiva |
| Other Data | Other Data Types | profilo e preferenze con sync attiva |

**Data Not Linked to You**: nessuno. Testo per la descrizione dell'App Store: "Senza account i tuoi dati restano sul tuo iPhone. La raccolta indicata avviene solo se attivi la sincronizzazione o JEV AI online."

La label deve corrispondere al manifest, all'informativa e al comportamento reale: Agent 12 li confronta prima di ogni invio in review (§14.2).

---

## 14. Checklist

### 14.1 Security review per milestone (Agent 12, prima del merge)

**Sempre:**
- [ ] `scripts/ci/check-secrets.sh` verde; nessun file `.env`, `.p8`, `.p12` versionato.
- [ ] Nessun `print`/`NSLog`/`dump`/`debugPrint` in `Sources/` e `App/`; ogni `privacy: .public` ha il commento `// log-public:`; nessun valore di SEC-LG-03 nei log (lettura del diff).
- [ ] Nessuna nuova dipendenza senza ADR; versioni esatte; `Package.resolved` di riferimento aggiornato solo in PR dedicati.
- [ ] Tabelle e colonne nuove classificate in §3; Required Reason API nuove nel manifest (SEC-PM-01).
- [ ] Nessuna eccezione ATS; nessun nuovo dominio di rete non approvato.
- [ ] Nessun dato sanitario in `UserDefaults`, notifiche, URL, messaggi di crash.

**Per milestone:**

| Milestone | Controlli aggiuntivi |
|---|---|
| M1 (scheletro) | `PrivacyInfo.xcprivacy` incluso nel target app (`project.yml`); nessuna eccezione ATS in `Info.plist`; `UIFileSharingEnabled` assente; CI con action fissate per SHA e permessi minimi; scan dei segreti attivo; dipendenze esatte (§16) |
| M2 (dati) | Template §6.2 applicato a **ogni** tabella F; meta-test RLS verde; casi 1–11 di §6.4 per ogni tabella; trigger `server_updated_at`/clamp; nessuna `security definer`; `anon` senza grant; advisor di sicurezza Supabase senza errori; protezione dei file DB verificata da test (SEC-LS-01); file `health-cache.sqlite` escluso dal backup |
| M3 (onboarding) | Gate età 16/18; schermate dei consensi A e B separate e non preselezionate; disclaimer; nessun dato sanitario in `UserDefaults` |
| M7 (HealthKit) | Solo i tipi di PS-HK-01; stringhe d'uso presenti e specifiche; dati fisiologici solo nel file escluso; nessun valore HealthKit verso rete (ricerca nel codice di `Sync`/`Food`/gateway); scritture solo con toggle attivi |
| M8–M9 (workout, food) | Notifiche senza valori; Open Food Facts senza identificativi e con `User-Agent` corretto; import JSON validato e limitato; export in `tmp/` protetto e cancellato |
| M11 (JEV) | Pipeline §7.1 completa; test del gateway: JWT mancante/`anon`/scaduto → 401, consenso revocato → 403, body > 32 KiB → 413, schema errato → 422, oltre i limiti → 429; injection nei nomi custom (non arrivano al modello), output con cifre/URL/markdown → fallback; log senza contenuti (lettura dei log di una sessione di test); `store: false` o equivalente; validazione ripetuta nel client |
| M12 (QA e sync) | Test multi-utente sulla sync (logout A → login B senza upload dei dati di A); eliminazione account end-to-end con revoca Apple; revoca A con cancellazione cloud; scan dei segreti sul bundle `.app`; rotazione delle chiavi provata una volta |

### 14.2 Checklist pre-TestFlight

- [ ] Tutti i controlli di §14.1 fino alla milestone corrente.
- [ ] Privacy policy pubblicata a un URL stabile e inserita in App Store Connect e nell'app.
- [ ] Privacy Nutrition Label compilata come §13.4 e coerente con `PrivacyInfo.xcprivacy` e con l'informativa.
- [ ] Privacy Report dell'archivio Xcode letto: nessuna API o tipo di dato inatteso dalle dipendenze.
- [ ] Entitlement: solo HealthKit (e background delivery se usata) e Sign in with Apple; nessun entitlement iCloud/CloudKit.
- [ ] Stringhe `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` in italiano, specifiche.
- [ ] Eliminazione account in app funzionante su build di release, con revoca dei token Apple verificata.
- [ ] Supabase: solo provider Apple, anonymous sign-in disattivato, RLS su tutte le tabelle (meta-test sul progetto remoto), advisor senza errori, MFA sull'account, restrizioni di rete del DB.
- [ ] Gateway: limiti e tetto globale configurati, kill switch provato, limiti di spesa sul provider attivi.
- [ ] Verifiche di §13.1 (5.1.3, 5.1.2(i)) fatte sul testo corrente e annotate in `PROJECT_STATE.md`. **TestFlight esterno (altri tester) solo dopo le verifiche legali di §15** e con i DPA attivi; TestFlight interno solo per il titolare.
- [ ] Build di release senza log di debug con dati, senza menu di debug che espongano il DB, senza endpoint di staging.

---

## 15. Punti che richiedono verifica di un professionista o sul testo ufficiale

**Legale (prima di qualsiasi utente diverso dal titolare):**
1. Basi giuridiche, testo dei consensi A e B, informativa completa.
2. Inquadramento dei dati solo locali (il titolare non vi accede).
3. Età minima (16 anni, 18 per i deficit) rispetto all'art. 2-quinquies del Codice privacy e al tipo di dati.
4. DPIA e necessità di un DPO.
5. DPA con Supabase e con il provider AI; meccanismo di trasferimento extra-UE (SCC/DPF), transfer impact assessment.
6. Conservazione della prova del consenso dopo l'eliminazione dell'account.
7. AI Act (obblighi di trasparenza e date di applicazione) e qualificazione rispetto al regolamento sui dispositivi medici.
8. Procedura di data breach.

**Apple (testo ufficiale corrente):**
1. Guideline 5.1.3: invio di informazioni derivate da HealthKit a un provider AI; "niente dati sanitari in iCloud" rispetto al backup del dispositivo.
2. Guideline 5.1.2(i): condivisione con AI di terze parti e permesso esplicito.
3. Guideline 5.1.1(v) e revoca dei token Sign in with Apple all'eliminazione dell'account.
4. Developer Program License Agreement: clausole HealthKit.
5. Definizione di "raccolta" per la Privacy Nutrition Label (ricerche alimenti, crash report Apple).
6. Reason code di File Timestamp, Disk Space, System Boot Time se in futuro servono; `ContinuousClock`.

**Fornitori (documentazione e contratti):**
1. Provider AI: entità UE, residenza dei dati, ZDR, `store: false` o equivalente, nessun addestramento.
2. Supabase: DPA, sub-responsabili, cifratura a riposo, retention di backup e log, verifica JWT con le nuove API key, dati salvati da Sign in with Apple senza scope.

---

## 16. Rilievi aperti sul repository (2026-10-05)

| # | Dove | Rilievo | Azione proposta | Owner |
|---|---|---|---|---|
| R-01 | `Packages/JevKit/Package.swift` | GRDB `from: "7.0.0"` e supabase-swift `from: "2.0.0"`: intervalli aperti, non versioni esatte (SEC-SC-02) | `exact:` sulle versioni verificate in M1 | Agent 00 / 13 |
| R-02 | `.gitignore` + XcodeGen | Il `.xcodeproj` è ignorato, quindi il `Package.resolved` dell'app non è versionato: build non riproducibili | `Package.resolved` di riferimento versionato e confrontato in CI (SEC-SC-03) | Agent 13 |
| R-03 | `Packages/JevKit/Package.swift`, target `Sync` | Dipende dal prodotto ombrello `Supabase` (include Realtime e Storage) | Solo i prodotti necessari (SEC-SC-04) | Agent 00 / 03 |
| R-04 | `.gitignore` | Non esclude `*.p8`, `*.p12`, `*.mobileprovision`, `*.cer` | Aggiungerli (lo scan di SEC-SE-04 resta la protezione principale) | Agent 13 |
| R-05 | ARCHITECTURE_PLAN §5.11 / ADR-014 | Il segnaposto copre i numeri ma non i nomi scritti dall'utente o da terzi (vettore di prompt injection) | Estendere con `{{label:<id>}}` (SEC-AI-05) | Agent 09 + CTO |
| R-06 | ARCHITECTURE_PLAN §3.2 | Mancano `user_consent` e `private.ai_usage`, e l'Edge Function `account-delete` | Aggiungerli al modello dati (§6.6, §7.3, §7.4) | Agent 03 / 09 |
| R-07 | ARCHITECTURE_PLAN §3.2 | `health_metric_daily` nello stesso file del DB principale finirebbe nel backup iCloud | File separato escluso dal backup (SEC-LS-04) | Agent 03 / 08 |
