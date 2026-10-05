# DECISIONS — Architecture Decision Records (semplificati)

Formato: contesto → decisione → conseguenze. Stato: **Proposta** (in attesa di approvazione utente) · **Accettata** · **Superata da ADR-xxx**.
Un ADR accettato non si modifica: si scrive un nuovo ADR che lo supera.

---

## ADR-001 — Architettura a tre livelli con regola "numeri solo dagli engine"
**Stato:** Accettata (requisito del brief) · 2026-10-05
**Contesto:** il brief vieta un chatbot che inventa consigli; l'AI deve interpretare dati prodotti da algoritmi deterministici.
**Decisione:** Data (L1) → Deterministic engines (L2) → JEV AI (L3). Ogni numero mostrato all'utente proviene da L1/L2. Il testo AI passa da un validatore di number grounding (ADR-008).
**Conseguenze:** l'app è pienamente utile senza AI e offline; l'AI è sostituibile; serve un contratto `CoachContext` stabile.

## ADR-002 — Feature-based + MVVM leggero, niente framework architetturali
**Stato:** Proposta · 2026-10-05
**Contesto:** il brief chiede architettura moderna ma senza overengineering.
**Decisione:** SwiftUI + Observation. ViewModel `@MainActor @Observable` solo per schermate con logica; le viste semplici leggono direttamente dai repository osservabili. Niente TCA, VIPER, Coordinator a classi.
**Conseguenze:** meno boilerplate; la logica complessa sta negli engine (testati), non nei ViewModel.

## ADR-003 — Engine come target Swift puri in un package locale
**Stato:** Proposta · 2026-10-05
**Contesto:** coverage > 90% sugli engine, Swift 6 strict concurrency, determinismo.
**Decisione:** `WorkoutEngine`, `NutritionEngine`, `RecoveryEngine`, `CheckInEngine`, `CoachKit` dipendono solo da Foundation, `JevCore`, `JevDomain`. Il tempo è un parametro (niente `Date()` interno). Parametri in struct `Config` versionate.
**Conseguenze:** testabili con `swift test` anche fuori da Xcode e su Linux; nessun accesso a DB/HealthKit dagli engine; serve un layer (`InsightsPipeline`) che prepara gli input.

## ADR-004 — GRDB (SQLite) invece di SwiftData
**Stato:** Proposta (da confermare con l'utente) · 2026-10-05
**Contesto:** servono migrazioni prevedibili, record `Sendable` per Swift 6, sync con Postgres, query di aggregazione per i grafici.
**Decisione:** GRDB 7 con `DatabasePool`, record come `struct`, migrazioni SQL nominate e immutabili, `ValueObservation` per la UI.
**Alternative considerate:** SwiftData (nativo ma con attriti noti su strict concurrency, migrazioni e query aggregate; controllo meno esplicito per la sync); Core Data (verboso, stesse questioni di concurrency).
**Conseguenze:** una dipendenza esterna matura; SQL esplicito speculare alle migrazioni Supabase.

## ADR-005 — Fatti vs derivati; i derivati non si sincronizzano
**Stato:** Proposta · 2026-10-05
**Contesto:** trend, expenditure, recovery, readiness, PR sono ricalcolabili; sincronizzarli genera conflitti e propaga bug.
**Decisione:** solo i fatti si sincronizzano. I derivati sono cache locali invalidate al cambio di `engine_version`. Snapshot decisionali (`weekly_check_in`, `ai_recommendation`, `nutrition_target`) sono fatti immutabili.
**Conseguenze:** sync più semplice e sicura; ogni dispositivo ricalcola (costo trascurabile).

## ADR-006 — Supabase come backend (Postgres + RLS + Auth + Edge Functions)
**Stato:** Proposta (progetto da creare o indicare) · 2026-10-05
**Contesto:** il brief cita Supabase RLS; serve backend per sync, auth e proxy AI senza chiavi nel client.
**Decisione:** Supabase; Sign in with Apple; RLS `user_id = auth.uid()` su ogni tabella; Edge Functions `jev-coach` e `food-search`.
**Alternative:** CloudKit (sync gratuita ma nessun luogo sicuro per le chiavi AI, meno portabile per un prodotto multipiattaforma); backend custom su Railway (più lavoro operativo).
**Conseguenze:** l'app funziona anche senza account; account necessario solo per sync e JEV online.

## ADR-007 — AIProvider lato server, provider client per offline/on-device
**Stato:** Proposta · 2026-10-05
**Contesto:** "provider intercambiabili senza modificare l'app" + "chiavi mai nel client".
**Decisione:** nel gateway `jev-coach` un'interfaccia TypeScript `AIProvider` con `OpenAIProvider` (iniziale) e `AnthropicProvider`; il modello per tier (`routine`, `analysis`) è una variabile d'ambiente. Nel client un protocollo Swift `AIProvider` con `GatewayAIProvider`, `TemplateAIProvider` (offline) e in V2 `OnDeviceAIProvider`.
**Conseguenze:** cambiare provider o modello non richiede una release; gli ID modello ("GPT-5.6 Terra/Sol" del brief) vanno verificati sulla documentazione ufficiale in Fase 10.

## ADR-008 — Number grounding e decisioni non modificabili dall'AI
**Stato:** Proposta · 2026-10-05
**Contesto:** l'AI non deve inventare numeri né cambiare decisioni.
**Decisione:** il `CheckInEngine` produce decisioni tipizzate con delta numerici; la UI renderizza decisione e numeri dall'oggetto dell'engine. Il testo AI è validato: ogni numero deve corrispondere a un fatto del `CoachContext`, altrimenti retry e poi fallback a template.
**Conseguenze:** testo AI a volte meno "libero", ma verificabile; il fallback garantisce sempre una spiegazione.

## ADR-009 — Provider alimentari intercambiabili
**Stato:** Proposta · 2026-10-05
**Decisione:** protocollo `FoodProvider` (search, lookup barcode, dettagli). MVP: `LocalFoodProvider` (catalogo generico incluso, derivato da USDA FoodData Central, pubblico dominio), `OpenFoodFactsProvider` (ODbL: attribuzione obbligatoria), `GatewayFoodProvider` (USDA online via backend). Ogni alimento loggato salva uno snapshot dei nutrienti.
**Conseguenze:** nessun lock-in; lo storico non cambia se un provider modifica un prodotto.

## ADR-010 — Unità canoniche, giorno locale e timezone
**Stato:** Proposta · 2026-10-05
**Decisione:** storage in kg, kcal, secondi, istanti UTC; conversioni kg/lb e kcal/kJ solo in presentazione. Pesate, log alimentari e sessioni salvano `day_key` locale + identificativo timezone al momento della registrazione.
**Conseguenze:** viaggi e cambi DST non spostano i dati tra giorni; i test coprono DST e cambio fuso.

## ADR-011 — Progetto Xcode generato con XcodeGen; CI su macOS
**Stato:** Proposta (dipende dalla scelta utente su repo/CI) · 2026-10-05
**Contesto:** l'ambiente di sviluppo non ha Xcode; un `.pbxproj` scritto a mano è fragile.
**Decisione:** `project.yml` versionato, `.xcodeproj` generato. CI GitHub Actions: build + test su simulatore iOS 18 e `swift test` del package con gate di coverage 90% sugli engine.
**Conseguenze:** "compila" è dimostrato da un log di CI o da una build sul Mac dell'utente, mai dichiarato senza prova.

## ADR-012 — Dati fisiologici HealthKit solo sul dispositivo
**Stato:** Proposta · 2026-10-05
**Decisione:** HRV, FC a riposo, FC, sonno, passi, energia attiva sono salvati solo localmente come aggregati giornalieri e mai inviati al cloud né all'AI in forma grezza (all'AI arrivano solo sottopunteggi già calcolati). Le pesate si sincronizzano (servono all'expenditure su ogni dispositivo), deduplicate per `hk_uuid`.
**Conseguenze:** minore superficie di rischio privacy; su un nuovo dispositivo i dati fisiologici tornano da Salute. Peso, misure, allenamenti e alimentazione sincronizzati restano dati sanitari ai sensi del GDPR art. 9: consenso esplicito separato per la sync e per JEV AI online, progetto Supabase in regione UE.

## ADR-013 — Un'unica `EngineConfig` versionata per tutte le soglie
**Stato:** Proposta · 2026-10-05
**Contesto:** la review QA (QA-10) ha trovato soglie diverse tra piano e product spec (fasce readiness, etichette confidence, sufficienza dati, plateau, soglia "pronto").
**Decisione:** tutte le soglie numeriche vivono in `EngineConfig` (in `JevDomain`) con un `version`. La UI legge da lì, gli engine leggono da lì, i documenti citano i nomi dei parametri. Cambiare `version` invalida le cache derivate (ADR-005). Valori iniziali allineati a PRODUCT_SPEC.
**Conseguenze:** una sola fonte di verità; taratura sui dati reali senza cercare numeri sparsi.

## ADR-014 — L'AI scrive segnaposto, non cifre
**Stato:** Proposta · 2026-10-05
**Contesto:** QA-13: un validatore che confronta i numeri non rileva un numero corretto attribuito al dato sbagliato, né i numeri scritti in lettere.
**Decisione:** il testo AI può citare valori solo come `{{fact:<id>}}`; il client sostituisce il valore formattato dal fatto dell'engine. Qualsiasi cifra letterale o numero in lettere → validazione fallita → retry → template deterministico. Filtro di sicurezza anche sull'output.
**Conseguenze:** impossibile per l'AI "inventare" o spostare numeri; prompt e test del gateway devono coprire questo contratto.
