# JEV FIT — Fase 0: Audit dei requisiti

Autore: Agent 00 (Lead Architect / CTO) · Data: 2026-10-05 · Stato: in revisione utente

Scopo: leggere il brief come un revisore ostile prima di scrivere codice. Elenco cosa è chiaro, cosa è ambiguo, cosa è in conflitto, cosa non è verificabile nell'ambiente attuale, e come lo risolviamo.

---

## 1. Requisiti chiari (nessuna azione richiesta)

Architettura a 3 livelli con regola "numeri solo dagli engine"; iOS 18+, Swift 6, SwiftUI; offline-first per workout e food logging; HealthKit opzionale e mai dipendenza dall'Apple Watch; chiavi API mai nel client; i 13 agenti e le 14 fasi; la Definition of Done in 20 punti; divieto di copiare codice, testi, grafica, database e formule proprietarie di Fitbod / MacroFactor.

## 2. Ambiguità e come le risolvo

| # | Ambiguità | Risoluzione proposta | Dove documentata |
|---|---|---|---|
| A1 | "AIProvider con provider intercambiabili, OpenAIProvider iniziale, aggiungere Anthropic/Local **senza modificare l'app**" ma anche "chiavi non nell'app, chiamate via backend". | I provider cloud vivono **nel backend** (gateway `jev-coach`), dietro un'interfaccia `AIProvider` TypeScript. Cambiare provider/modello = cambiare config server, zero release app. Nel client esiste un protocollo Swift `AIProvider` con 3 implementazioni: `GatewayAIProvider` (backend), `TemplateAIProvider` (offline, deterministico), `OnDeviceAIProvider` (V2, Apple Foundation Models dove disponibile). | DECISIONS ADR-007 |
| A2 | Model routing "GPT-5.6 Terra / Sol". Non posso verificare ora che questi siano gli ID esatti dell'API OpenAI. | Gli ID modello sono **configurazione del gateway** (`ROUTINE_MODEL`, `ANALYSIS_MODEL`), non costanti nel codice. Verifico gli ID reali sulla documentazione OpenAI in Fase 10 prima del deploy. | ADR-007, Open questions |
| A3 | Entità come `WeightTrend`, `DailyNutrition`, `EnergyExpenditure`, `MuscleRecovery`, `ReadinessEntry` sono **derivate**: se sincronizzate creano conflitti su dati ricalcolabili. | Distinzione netta: **fatti** (input utente/HealthKit, sincronizzati) vs **derivati** (cache locali ricalcolabili in modo deterministico, mai sincronizzate). Eccezione: snapshot storici con valore legale/decisionale (`WeeklyCheckIn`, `AIRecommendation`, `NutritionTarget` applicati) sono fatti immutabili e si sincronizzano. | ADR-005, DATA_MODEL (Fase 3) |
| A4 | "Il recupero deve adattarsi all'utente nel tempo" — serve un segnale di verità. | Il segnale è la performance alla successiva esposizione del muscolo (residuo e1RM / reps-a-carico vs atteso). Aggiornamento bayesiano limitato di un moltiplicatore personale della costante di recupero, con cold-start su prior di popolazione. | Algoritmi §5.6 del piano |
| A5 | Sesso biologico opzionale ma richiesto da Mifflin-St Jeor. | Senza sesso: costante intermedia (−78 kcal, media di +5 e −161) e **prior più larga** (minor confidence iniziale). La stima converge comunque ai dati reali. Con % grasso disponibile si preferisce Katch-McArdle. | Piano §5.2 |
| A6 | "Torso/Limbs" e "Hybrid" non sono split standardizzati. | Torso/Limbs = sessione Torso (petto, dorso, spalle, core) / sessione Arti (gambe + braccia). Hybrid = Upper/Lower nei primi giorni + Push/Pull/Legs nei successivi (5-6 giorni), generato dal nostro engine, non un programma con nome commerciale. | Piano §5.5 |
| A7 | "Weekly check-in: JEV deve decidere" vs "decisione numerica dagli engine". | Decide il `CheckInEngine` (tabella di regole con priorità e isteresi). JEV **spiega** e contestualizza, non può alterare tipo né numeri della decisione. L'utente accetta/modifica (entro limiti)/rifiuta. | ADR-008 |
| A8 | "Calorie diverse per giorni allenamento/riposo" con programma a rotazione (decisione UX di Agent 01: il programma non è legato al calendario). | Il tipo di giorno si basa sui **giorni pianificati** a inizio settimana; se l'utente si allena in un giorno di riposo, il giorno diventa "training" e i giorni restanti si ribilanciano per tenere la media settimanale (vincolo: nessun giorno sotto il floor). | Piano §5.3 |
| A9 | Unità kg/lb e kcal/kJ, timezone, DST. | Storage canonico: kg, kcal, secondi, istanti UTC. Ogni log alimentare e pesata salva anche `dayKey` (data locale `yyyy-MM-dd` + identificativo timezone al momento del log): viaggiare non sposta i pasti tra giorni. Conversioni solo nel layer di presentazione. | ADR-010 |
| A10 | ">90% coverage per gli engine matematici" — come si misura. | Gli engine sono target Swift **puri** (Foundation only, niente UIKit/HealthKit/SwiftUI) → testabili con `swift test --enable-code-coverage` anche fuori da Xcode; il report di coverage è un gate della CI. | ADR-003 |
| A11 | Alimenti: "non vincolare a un database". Nessun DB scelto. | `FoodProvider` protocol. MVP: `LocalFoodProvider` (catalogo base generico incluso nell'app, da fonte pubblico dominio USDA FoodData Central, nomi tradotti in IT) + `OpenFoodFactsProvider` (barcode e ricerca prodotti confezionati, licenza ODbL → attribuzione obbligatoria). USDA online passa dal backend (chiave server-side). | ADR-009 |
| A12 | Superset/circuiti, plate calculator, età minima (domande di Agent 01). | Superset → V2 ma modello dati predisposto (`supersetGroup` nullable su WorkoutExercise). Plate calculator → V2. Età minima → onboarding blocca sotto i 16 anni (da confermare legalmente prima di qualsiasi uso commerciale). | Open questions |
| A13 | Workout di forza importati da Salute registrati da altre app. | Contano come carico generico (training load per readiness) senza set; non alimentano progressive overload né recovery per muscolo. | Piano §5.7 |

## 3. Conflitti / tensioni

**C1 — Offline-first vs JEV AI.** JEV online richiede rete e account. Risoluzione: ogni raccomandazione nasce come oggetto deterministico (`Recommendation` con reason code e fatti numerici); il testo di base è prodotto da template locali. L'AI arricchisce solo la prosa. Nessun flusso core dipende dall'AI.

**C2 — "Uso personale" vs "predisposto commerciale".** Rischio di overengineering. Risoluzione: multi-tenant e RLS fin dal giorno 1 (costano poco ora, moltissimo dopo); niente StoreKit, niente feature flag remote, niente analytics di prodotto nell'MVP.

**C3 — "Agenti in parallelo" vs dipendenze reali.** I tre engine dipendono da tipi condivisi (`JevCore`) e dallo schema dati. Risoluzione: Fasi 2-3 seriali (contratti), poi Workout / Nutrition / Recovery / HealthKit in parallelo su target separati, poi UI.

**C4 — Sicurezza alimentare vs autonomia.** "Nessuna modifica calorica estrema automatica" ma modalità MANUAL "target completamente manuali". Risoluzione: MANUAL permette qualsiasi target sopra un floor assoluto; sotto il floor (o rate di perdita oltre la soglia) l'app mostra un avviso persistente e JEV non avalla il target. Mai blocco silenzioso, mai approvazione silenziosa.

## 4. Requisiti NON verificabili nell'ambiente attuale (blocchi reali)

Lavoro in un container Linux cloud. Questo ha conseguenze dirette sulla Definition of Done, e preferisco dirlo ora:

| Requisito DoD | Stato | Mitigazione |
|---|---|---|
| "Compila con Xcode", "gira su iOS 18" | **Xcode non esiste su Linux.** Inoltre il download del toolchain Swift per Linux (download.swift.org) è bloccato dal proxy di questo ambiente (403), così come le pagine release di github.com; la CLI `gh` non è autenticata. | Serve **un Mac con Xcode** (tuo) oppure **CI GitHub Actions su runner macOS**. Il progetto Xcode è generato da `project.yml` (XcodeGen), riproducibile, niente `.pbxproj` scritto a mano. Senza una delle due opzioni non dichiaro mai "compila". |
| "Test degli engine passano" | Non eseguibili qui finché non ho un toolchain Swift. | Stessa CI (`swift test` sul package degli engine, macOS e Linux). In Fase 2 riprovo canali alternativi per il toolchain. |
| "HealthKit funziona con autorizzazioni reali" | Verificabile **solo su iPhone fisico** (il simulatore ha HealthKit ma con dati finti). | Test manuale su dispositivo guidato da una checklist (`docs/QA_DEVICE_CHECKLIST.md`, Fase 11). |
| Persistenza del lavoro | Il container è effimero: se resta inattivo viene distrutto. | Il codice deve stare in un **repository Git remoto** (GitHub) con push a ogni milestone. Finché non c'è, ti consegno archivi zip a ogni milestone. |
| Firma, entitlement HealthKit, TestFlight | Richiedono il tuo Apple Developer account. | `docs/SIGNING.md` con i passi; TestFlight richiede l'account a pagamento. |

## 5. Rischi di interpretazione scientifica

- **Densità energetica del tessuto** (kcal per kg di variazione di peso): il classico 7.700 kcal/kg è un'approssimazione; nelle prime 1-2 settimane di un cambio di dieta la variazione è dominata da acqua e glicogeno. Mitigazione: finestra di stima ≥ 14 giorni, peso ridotto alle prime settimane, densità configurabile e documentata.
- **Recupero muscolare**: non esiste un modello validato "per muscolo" con precisione clinica. Lo presentiamo come stima con confidence, non come misura.
- **Readiness**: HRV/RHR sono rumorosi e dipendono dal dispositivo; senza Apple Watch molti input mancano. Pesi rinormalizzati sui soli componenti disponibili e confidence che lo riflette.
- **Volume per muscolo**: conteggio frazionario (primario 1, secondario 0,5) è una convenzione della letteratura, non una legge.

## 6. Fonti pubbliche su cui baseremo gli algoritmi

Mifflin-St Jeor (1990), Katch-McArdle; Epley (1985), Brzycki (1993); modello fitness-fatigue di Banister (1975) e derivati; filtro di Kalman / modelli a livello+pendenza (statistica standard); bilancio energetico dinamico (Hall et al., 2011) per le assunzioni sulla densità energetica; dose-risposta del volume settimanale (Schoenfeld et al., 2017); position stand ISSN su proteine (Jäger et al., 2017) e meta-analisi di Morton et al. (2018); periodizzazione basata su RIR (Zourdos et al., 2016; Helms et al.); fibra 14 g / 1.000 kcal (Dietary Guidelines / IOM); rapporto acuto:cronico del carico (EWMA, Williams et al., 2017). Nessuna formula proprietaria.

## 7. Esito dell'audit

Il brief è implementabile. Tre decisioni dipendono da te (sezione "Open questions" di `PROJECT_STATE.md`): come compilare/verificare (Mac o CI), backend Supabase (progetto esistente o nuovo), repository Git remoto. Il resto è risolto con default documentati nelle ADR.
