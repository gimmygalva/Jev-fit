# JEV FIT — Screen Map

> **Owner:** Agent 01 — Product & UX · **Fase:** 1 · **Stato:** Draft v1.0
> **Riferimenti:** requisiti `PS-*` (`PRODUCT_SPEC.md`), flussi `UF-*` (`USER_FLOWS.md`).

## 0. Convenzioni

**Presentazione**
| Tipo | Uso |
|---|---|
| `Tab` | Root di una delle 5 tab, dentro `NavigationStack` |
| `Push` | Navigazione gerarchica nello stack della tab |
| `Sheet` | Compito breve e interrompibile (detent medium/large) |
| `Cover` | `fullScreenCover`: compito immersivo che non deve essere chiuso per errore (onboarding, workout live, scanner, check-in) |
| `Alert` | Conferme distruttive o decisioni binarie |

**Fonti dati** (livello 2 = engine deterministici, livello 1 = servizi dati, livello 3 = JEV)
| Nome | Livello | Fornisce |
|---|---|---|
| `WorkoutEngine` | 2 | Programmazione, ExerciseScore, progressive overload, e1RM, volume, PR, plateau, deload |
| `NutritionEngine` | 2 | BMR/TDEE/expenditure + confidence, target calorie e macro, giorni allenamento/riposo, modulo **WeightTrend** |
| `RecoveryEngine` | 2 | Recovery 0–100 per gruppo, stima ore a recupero |
| `ReadinessEngine` | 2 | JEV READINESS 0–100, contributi fattori, confidence |
| `CheckInEngine` | 2 | Metriche settimanali, decisioni, limiti, **GoalProgress** |
| `FoodProvider` | 1 | Ricerca alimenti/barcode (DB locale, cache, Open Food Facts) |
| `HealthKitService` | 1 | Letture/scritture Salute, stato permessi dedotto |
| `JevCoach` | 3 | Testi JEV (AI online o template da reason code), chat |
| `DataStore` · `SyncService` · `NotificationService` · `ProfileStore` | 1 | Persistenza locale, sync cloud, notifiche locali, profilo/preferenze — *nomi proposti, da allineare con l'architettura del CTO* |

**Stati standard** (ogni schermata li dichiara se rilevanti): `Loading` · `Empty` · `Offline` · `Error` · `NoPermission`.
Regola: gli stati Loading sono quasi sempre assenti perché i dati sono locali; dove serve si usano placeholder `redacted` < 300 ms, mai spinner a pieno schermo.

**Deep link scheme:** `jevfit://`. Tutti i deep link funzionano offline.

---

## 1. Albero di navigazione

```
App
├── [Cover] Onboarding (solo primo avvio / nessun profilo)
│   └── SCR-ONB-01 … SCR-ONB-17
│
├── TabView
│   ├── Tab 1 · Oggi ─────────────── SCR-HOME-01
│   │   ├── [Push] SCR-HOME-02 Profilo
│   │   │   └── [Push] SCR-SET-01 Impostazioni
│   │   │       ├── [Push] SCR-SET-02 Unità
│   │   │       ├── [Push] SCR-SET-03 Salute (HealthKit)
│   │   │       ├── [Push] SCR-SET-04 Notifiche
│   │   │       ├── [Push] SCR-SET-05 Account & Sync ── [Sheet] SCR-AC-01 Accedi · [Sheet] SCR-AC-02 Unisci dati
│   │   │       ├── [Push] SCR-SET-06 Obiettivo & profilo ── [Sheet] SCR-SET-13 Anteprima cambio obiettivo
│   │   │       ├── [Push] SCR-SET-07 Preferenze allenamento
│   │   │       ├── [Push] SCR-SET-08 Limitazioni & dolore
│   │   │       ├── [Push] SCR-SET-09 Preferenze nutrizione → SCR-NU-10
│   │   │       ├── [Push] SCR-SET-10 Privacy & dati
│   │   │       ├── [Push] SCR-SET-11 Lingua, aspetto, accessibilità
│   │   │       └── [Push] SCR-SET-12 Info & disclaimer
│   │   ├── [Sheet] SCR-WT-01 Pesata
│   │   ├── [Cover] SCR-CI-01..04 Weekly check-in
│   │   └── (card) → Push verso dettagli delle altre tab
│   │
│   ├── Tab 2 · Allenamento ──────── SCR-WK-01
│   │   ├── [Push] SCR-WK-02 Programma ── [Push] SCR-WK-12 Generatore/Editor programma
│   │   ├── [Push] SCR-WK-03 Anteprima sessione
│   │   ├── [Sheet] SCR-WK-13 Workout rapido
│   │   ├── [Push] SCR-WK-08 Libreria esercizi ── [Push] SCR-WK-09 Dettaglio esercizio
│   │   │                                      └── [Sheet] SCR-WK-14 Esercizio custom
│   │   ├── [Push] SCR-WK-10 Storico ── [Push] SCR-WK-11 Dettaglio workout
│   │   └── [Cover] SCR-WK-04 Workout Live
│   │       ├── [Sheet] SCR-WK-05 Sostituisci esercizio
│   │       ├── [Sheet] SCR-WK-06 Opzioni set / dolore
│   │       ├── [Sheet] SCR-WK-08 Libreria (modalità selezione)
│   │       └── [Push in cover] SCR-WK-07 Summary
│   │   (SCR-WK-15 Workout interrotto: Sheet all'avvio, da qualsiasi tab)
│   │
│   ├── Tab 3 · Nutrizione ───────── SCR-NU-01
│   │   ├── [Sheet] SCR-NU-02 Logger
│   │   │   ├── [Push] SCR-NU-03 Porzione / dettaglio alimento
│   │   │   ├── [Cover] SCR-NU-04 Scanner barcode
│   │   │   ├── [Push] SCR-NU-05 Alimento custom
│   │   │   ├── [Push] SCR-NU-06 Quick add
│   │   │   ├── [Push] SCR-NU-07 Ricette ── [Push] SCR-NU-08 Editor ricetta
│   │   ├── [Sheet] SCR-NU-09 Copia pasto/giorno
│   │   ├── [Push] SCR-NU-10 Target & macro
│   │   ├── [Push] SCR-NU-11 Expenditure
│   │   └── [Sheet] SCR-NU-12 Calendario giorni
│   │
│   ├── Tab 4 · Corpo ────────────── SCR-BODY-01
│   │   ├── [Sheet] SCR-BODY-02 Dettaglio gruppo muscolare
│   │   ├── [Push] SCR-BODY-03 Dettaglio readiness ── [Sheet] SCR-BODY-04 Check rapido
│   │   └── [Push] SCR-PR-02 (metric=weight)
│   │
│   └── Tab 5 · Progressi ────────── SCR-PR-01
│       ├── [Push] SCR-PR-02 Dettaglio metrica
│       └── [Push] SCR-PR-03 Forza (lista esercizi) ── [Push] SCR-WK-09
│
└── Globali (da ogni tab)
    ├── [Sheet] SCR-JEV-01 JEV sheet (pulsante JEV in navigation bar)
    │   ├── [Push] SCR-JEV-02 Chat
    │   ├── [Push] SCR-JEV-03 Raccomandazione (WDC completo)
    │   ├── [Push] SCR-JEV-04 Storico check-in ── [Push] SCR-JEV-05 Check-in passato
    │   └── [Push] SCR-JEV-06 Avviso di sicurezza
    ├── ResumeWorkoutBanner (sopra la tab bar se workout InCorso e cover chiuso)
    └── OfflineChip (navigation bar, solo quando offline)
```

---

## 2. Onboarding (`Cover`) — UF-01

Componenti comuni: barra progresso a segmenti, `[Indietro]`, `[Continua]` (bottom, 56 pt), `[Salta]` (solo step opzionali), dati salvati a ogni step in `ProfileStore`.

| ID | Titolo | Contenuto principale | Obblig. | Dati / engine | Rel. |
|---|---|---|---|---|---|
| SCR-ONB-01 | Benvenuto | Claim, 3 bullet, disclaimer breve, `[Inizia]`, `[Ho già un account]` | — | — | MVP |
| SCR-ONB-02 | Obiettivo | 6 card obiettivo con effetto atteso | Sì | ProfileStore | MVP |
| SCR-ONB-03 | Esperienza | 3 livelli con descrizione | Sì | ProfileStore | MVP |
| SCR-ONB-04 | Dati corpo | Peso (kg/lb inline), altezza, età, sesso opz. + `[Perché serve?]`, BF% opz. | Sì (peso, altezza, età) | ProfileStore | MVP |
| SCR-ONB-05 | Attività | 4 livelli con esempi | No (default Moderato) | ProfileStore | MVP |
| SCR-ONB-06 | Target & ritmo | Target weight, slider rate con limiti, data stimata | Condiz. | NutritionEngine | MVP |
| SCR-ONB-07 | Disponibilità | Giorni/sett., giorni preferiti, minuti | Sì | ProfileStore | MVP |
| SCR-ONB-08 | Attrezzatura | 4 preset + checklist, range manubri | Sì | ProfileStore | MVP |
| SCR-ONB-09 | Split | 6 split + "Lascia decidere a JEV" con motivo | No | WorkoutEngine | MVP |
| SCR-ONB-10 | Esercizi | Ricerca, preferiti/esclusi | No | WorkoutEngine (libreria) | MVP |
| SCR-ONB-11 | Limitazioni | Area, intensità, nota, copy "non è una diagnosi" | No | ProfileStore | MVP |
| SCR-ONB-12 | Priorità | MuscleMap selezionabile, max 3 | No | ProfileStore | MVP |
| SCR-ONB-13 | Macro | AUTO/ASSISTED/MANUAL con anteprima numeri | No (AUTO) | NutritionEngine | MVP |
| SCR-ONB-14 | Unità & check-in | kcal/kJ, conferma unità, giorno check-in | No | ProfileStore | MVP |
| SCR-ONB-15 | Salute | Lista tipi "→ a cosa serve", toggle scritture, `[Continua]`/`[Non ora]` | No | HealthKitService | MVP |
| SCR-ONB-16 | Notifiche | Categorie e default, `[Attiva]`/`[Non ora]` | No | NotificationService | MVP |
| SCR-ONB-17 | Il tuo piano | Split, prossima sessione, kcal allen./riposo, macro, TDEE + ConfidenceBadge, card JEV, `[Inizia]` | — | WorkoutEngine, NutritionEngine, JevCoach | MVP |

Stati: `Offline` → `[Ho già un account]` mostra nota; `Error` generazione → piano di base (UF-01 Errori).

---

## 3. Tab Oggi

### SCR-HOME-01 — Oggi `[MVP]`
- **Presentazione:** Tab root · **Deep link:** `jevfit://today`
- **Scopo:** in 3 secondi: quanto sono pronto, cosa alleno, quanto posso ancora mangiare, se sto andando verso l'obiettivo.
- **Componenti (priorità visiva):**
  1. Header: data, titolo "Oggi", OfflineChip (se offline), JevButton, avatar profilo (SyncStatusBadge se errore > 24 h).
  2. ContextCard (max 1): ResumeWorkout > SafetyNotice > Check-in pronto > Pesata di oggi (fino alle 12:00).
  3. Card Readiness: MetricRing (H0) + label fascia + glifo + ConfidenceBadge; dentro la stessa card, **JevTodayCard** con Ion Rail.
  4. Card Workout Today: nome sessione, durata, n. esercizi, RecoveryChip dei gruppi target, prime 2 righe target con esito overload, `[Inizia]`; opzione `[Versione ridotta]` se readiness < 40.
  5. Card Nutrizione: Calories Remaining (H1), tipo giorno, MacroBar P/C/F.
  6. Riga di due StatTile: Weight Trend (valore trend + kg/sett. + TrendSparkline) · Muscle Recovery (mini MuscleMap + gruppo meno recuperato).
  7. Card Goal Progress: GoalProgressBar, valore attuale → target, data stimata.
- **Azioni:** tap card → dettaglio (Readiness → SCR-BODY-03; Workout → SCR-WK-03; Nutrizione → tab Nutrizione; Peso → SCR-PR-02?metric=weight; Recovery → tab Corpo; Goal → SCR-SET-06); `[Inizia]` → SCR-WK-04; JevButton → SCR-JEV-01; pull-to-refresh = rilettura HealthKit.
- **Stati:**
  - `Empty` (giorno 1): Readiness "—" con "Completa il primo workout"; Weight Trend "Pesati per iniziare il trend"; Goal "Calibrazione".
  - `Offline`: OfflineChip; JEV TODAY con label "Spiegazione offline". Nessun'altra differenza.
  - `NoPermission` (HK): nessun callout in Home; Readiness con label "Stima parziale".
  - Nessun workout oggi (riposo): card Workout diventa "Giorno di riposo · Prossima: Lower A domani" + `[Allenati comunque]`.
- **Dati:** ReadinessEngine, JevCoach, WorkoutEngine (sessione + target), RecoveryEngine, NutritionEngine (target giorno, consumato, WeightTrend), CheckInEngine (GoalProgress, stato check-in), DataStore (workout in corso).

### SCR-HOME-02 — Profilo `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://profile`
- **Contenuto:** nome/avatar (locale), obiettivo e fase, statistiche totali (workout, giorni loggati, settimane di check-in), stato account/sync, `[Impostazioni]`.
- **Dati:** ProfileStore, DataStore, SyncService.

### SCR-WT-01 — Pesata `[MVP]`
- **Presentazione:** Sheet (medium) · **Deep link:** `jevfit://weight/new`
- **Componenti:** valore BigStepper (0,1 kg / 0,2 lb) + tastiera numerica, data/ora, BF% opz., anteprima "Trend dopo: 78,6 kg", `[Salva]`.
- **Stati:** conferma soft outlier (> 3% dal trend); `Error` validazione range.
- **Dati:** NutritionEngine/WeightTrend, DataStore, HealthKitService (scrittura opz.).

### Wireframe — SCR-HOME-01 Oggi
```
┌────────────────────────────────────────────┐
│ Lun 21 ottobre                 (JEV)  (GG) │
│ Oggi                                       │
├────────────────────────────────────────────┤
│ ┌ Check-in settimana pronto ───────── › ┐  │ ContextCard
│ └───────────────────────────────────────┘  │
│ ┌────────────────────────────────────────┐ │
│ │ JEV READINESS                          │ │
│ │    ╭─────╮                             │ │
│ │   │  82   │  Buono   ▮▮▮▯              │ │ MetricRing H0
│ │    ╰─────╯  CONF 76%  · SALUTE         │ │
│ │ ┃ JEV TODAY                            │ │ Ion Rail
│ │ ┃ Petto al 94%: panca pronta per 85 kg.│ │
│ │ ┃ Sonno 6 h 40: mantieni RIR 2.        │ │
│ │ ┃                          Dettagli ›  │ │
│ └────────────────────────────────────────┘ │
│ ┌ WORKOUT DI OGGI ───────────────────────┐ │
│ │ Upper A · 62 min · 6 esercizi          │ │
│ │ [Petto 94] [Dorsali 88] [Delt.lat 71]  │ │ RecoveryChip
│ │ Panca piana     85,0 kg × 6–8   ↑      │ │
│ │ Rematore        70,0 kg × 8–10  =      │ │
│ │                        [  Inizia  ▶ ]  │ │
│ └────────────────────────────────────────┘ │
│ ┌ CALORIE RIMASTE ─── Giorno allenamento ┐ │
│ │ 1.240 kcal           di 2.480          │ │
│ │ P ████████░░░  118 / 165 g             │ │ MacroBar
│ │ C █████░░░░░░  142 / 290 g             │ │
│ │ F ██████░░░░░   48 / 75 g              │ │
│ └────────────────────────────────────────┘ │
│ ┌ TREND PESO ────────┐ ┌ RECUPERO ───────┐ │
│ │ 78,6 kg            │ │  [mini mappa]   │ │ StatTile x2
│ │ −0,4 kg/sett  ╲_╱‾ │ │  Quadricipiti 41│ │
│ └────────────────────┘ └─────────────────┘ │
│ ┌ OBIETTIVO · Dimagrimento ──────────────┐ │
│ │ ███████████░░░░░  62%                  │ │ GoalProgressBar
│ │ 78,6 → 75,0 kg · arrivo stimato 2 dic  │ │
│ └────────────────────────────────────────┘ │
├────────────────────────────────────────────┤
│  Oggi   Allenamento  Nutrizione  Corpo  Progressi │
└────────────────────────────────────────────┘
```

---

## 4. Tab Allenamento

### SCR-WK-01 — Allenamento `[MVP]`
- **Presentazione:** Tab root · **Deep link:** `jevfit://workout`
- **Componenti:** 1) Card prossima sessione (come Home, più dettagliata) con `[Inizia]`/`[Anteprima]`; 2) WeekStrip settimana (sessioni fatte/pianificate, deload marcato); 3) Azioni rapide: `[Workout rapido]`, `[Workout libero]`; 4) Programma attivo (nome, split, settimana X di Y) → SCR-WK-02; 5) Ultimi 3 workout → SCR-WK-11, `[Storico]`; 6) `[Libreria esercizi]`.
- **Stati:** `Empty` nessun programma → EmptyStateView `[Genera programma]` `[Workout libero]`; workout in corso → card sostituita da `[Riprendi workout]`.
- **Dati:** WorkoutEngine, RecoveryEngine, DataStore.

### SCR-WK-02 — Programma `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://workout/program`
- **Componenti:** nome, split + motivazione (reason code), mesociclo (settimana corrente, deload previsto/reattivo), lista sessioni con esercizi e set/rep range, volume settimanale per gruppo (barre), `[Modifica]`, `[Nuovo programma]`, `[Archivio programmi]`.
- **Dati:** WorkoutEngine, DataStore.

### SCR-WK-03 — Anteprima sessione `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://workout/today`, `jevfit://workout/session/{sessionId}`
- **Componenti:** header (nome, durata stimata, gruppi con RecoveryChip), banner readiness con `[Versione ridotta]` (se < 40), lista esercizi (nome, set × rep range, target kg, RIR, esito overload badge), `[Inizia workout]` (bottom, sticky).
- **Azioni:** riordina (drag), swap (→ SCR-WK-05), rimuovi, `[+ Esercizio]` (→ SCR-WK-08), tap esercizio → SCR-WK-09, JevButton ("Perché questi carichi?").
- **Stati:** gruppi < 40% → `[Scambia con sessione successiva]`; esercizio senza storico → "Primo set esplorativo".
- **Dati:** WorkoutEngine (target, overload, ExerciseScore), RecoveryEngine, ReadinessEngine.

### SCR-WK-04 — Workout Live `[MVP]`
- **Presentazione:** Cover · **Deep link:** `jevfit://workout/live`
- **Componenti (priorità):**
  1. Top bar: `[✕]` (riduce a ResumeWorkoutBanner, non termina), nome sessione, tempo trascorso (SF Mono), JevButton, `[•••]` (Aggiungi esercizio, Riordina, Salta esercizio, Termina workout).
  2. Progress bar esercizi.
  3. ExerciseHeader: nome (tap → swap), target, badge esito overload, riga **Precedente** (SF Mono).
  4. Tabella SetRow: n., SetTypeBadge, kg, reps, RIR, check. Set corrente evidenziato.
  5. `[+ Aggiungi set]`.
  6. RestTimerBar (quando attivo): countdown grande, `[−15s] [+15s] [Salta]`.
  7. Pannello input (zona pollice): BigStepper kg, BigStepper reps, RIRPicker (RPE se attivo), pulsante primario `[Completa set N]` 56+ pt.
  8. Banner Ion (eventuale) "regola primo set" con `[Applica]`/`[Ignora]`.
- **Azioni:** completa set (1 tap), modifica set completato (tap riga), swipe riga (Salta/Elimina), long-press riga → SCR-WK-06, swipe orizzontale tra esercizi, `[Termina workout]` → conferma → SCR-WK-07.
- **Stati:** `Empty` workout libero → "Aggiungi il primo esercizio"; `Offline` nessuna differenza (JEV sheet in template); `Error` scrittura → banner non bloccante; ripresa dopo crash → apertura diretta con timer ricalcolato.
- **Dati:** WorkoutEngine (target live, ricalcolo primo set, incrementi attrezzatura), DataStore (persistenza per azione), NotificationService (fine recupero), JevCoach.
- **Accessibilità:** BigStepper con azioni VoiceOver incrementa/decrementa; il timer annuncia 10 s e 0 s; layout verticale a Dynamic Type AX.

### Wireframe — SCR-WK-04 Workout Live
```
┌────────────────────────────────────────────┐
│ ✕          Upper A · 24:13      (JEV)  ••• │
│ ▰▰▰▱▱▱   Esercizio 3 di 6                   │
├────────────────────────────────────────────┤
│ Panca piana con bilanciere            ⇄    │ ExerciseHeader
│ Target 3 × 6–8 @ RIR 2       ↑ carico      │
│ PRECEDENTE  82,5×8  82,5×8  82,5×7         │ SF Mono
├────────────────────────────────────────────┤
│ SET  TIPO   KG      REPS   RIR             │
│  W   WU     60,0     8      —        ✓     │ SetRow
│  1   WRK    85,0     8      2        ✓     │
│▶ 2   WRK    85,0     8      ·              │ corrente
│  3   WRK    85,0    6–8     ·              │
│  + Aggiungi set                            │
├────────────────────────────────────────────┤
│ RECUPERO   ██████████████░░░░░   1:24      │ RestTimerBar
│            [−15s]    [+15s]    [Salta]     │
├────────────────────────────────────────────┤
│  KG    [  −  ]     85,0      [  +  ]       │ BigStepper
│  REPS  [  −  ]       8       [  +  ]       │ BigStepper
│  RIR   (0)  (1)  [2]  (3)  (4)  (5+)       │ RIRPicker
│ ┌────────────────────────────────────────┐ │
│ │            COMPLETA SET 2              │ │ 56 pt, Ion
│ └────────────────────────────────────────┘ │
└────────────────────────────────────────────┘
```

### SCR-WK-05 — Sostituisci esercizio `[MVP]`
- **Presentazione:** Sheet (large) dal live o dall'anteprima.
- **Componenti:** esercizio attuale; filtro "Solo attrezzatura disponibile"; lista SwapCandidateRow (nome, tag motivo, target calcolato, punteggio come barra non numerica); ricerca libreria; toggle `[Sostituisci anche nel programma]`.
- **Stati:** nessuna alternativa → "Nessuna alternativa compatibile" + `[Cerca in libreria]`.
- **Dati:** WorkoutEngine (ExerciseScore, target), RecoveryEngine.

### SCR-WK-06 — Opzioni set / dolore `[MVP]`
- **Presentazione:** Sheet (medium).
- **Componenti:** tipo set (SetTypeBadge picker), RPE (se attivo), nota, sezione **Segnala dolore** (area preselezionata, Lieve/Moderato/Forte, nota). Forte → SafetyNotice inline con `[Sostituisci esercizio]` `[Salta esercizio]` `[Continua comunque]`.
- **Dati:** DataStore, WorkoutEngine (penalità ExerciseScore), JevCoach (testo safety template).

### SCR-WK-07 — Summary `[MVP]`
- **Presentazione:** Push dentro il Cover del live · **Deep link:** `jevfit://workout/history/{workoutId}/summary`
- **Componenti:** header (sessione, data, durata, badge "Ridotta" se applicabile); hero Total Volume + DeltaBadge; PRBadge list (nascosta se vuota); mini MuscleMap + hard sets per gruppo; Performance vs Previous (righe esercizio con DeltaBadge); Estimated Recovery (RecoveryChip + ore); card JEV + `[Perché?]` → WhyDataConfidencePanel; rating fatica 1–5; nota; `[Salva]`.
- **Stati:** `Offline` JEV template; HK write error → nota in SCR-SET-03, non qui.
- **Dati:** WorkoutEngine (volume, PR, e1RM, delta), RecoveryEngine, JevCoach, HealthKitService (scrittura).

### SCR-WK-08 — Libreria esercizi `[MVP]`
- **Presentazione:** Push (navigazione) o Sheet (selezione da live/editor) · **Deep link:** `jevfit://exercises`
- **Componenti:** ricerca, filtri (gruppo, attrezzatura, pattern, preferiti, esclusi), lista con muscolo primario e icona attrezzatura, `[Nuovo esercizio]` → SCR-WK-14.
- **Stati:** `Empty` ricerca → "Nessun risultato · Crea esercizio".
- **Dati:** WorkoutEngine (catalogo), DataStore.

### SCR-WK-09 — Dettaglio esercizio `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://exercises/{exerciseId}`
- **Componenti:** nome IT/EN, muscoli primari/secondari (mini MuscleMap), attrezzatura, cue (max 3), e1RM stabile + ChartCard storico, PR (peso, reps, e1RM, volume), storico sessioni, toggle Preferito/Escluso, incremento personalizzato (macchine), `[Illustrazione/Video]` *(V2)*.
- **Stati:** `Empty` storico → "Ancora nessun set registrato".
- **Dati:** WorkoutEngine (e1RM, PR, plateau), DataStore.

### SCR-WK-10 — Storico workout `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://workout/history`
- **Componenti:** lista per settimana (nome, data, durata, volume, PR count), filtro per sessione/esercizio, workout esterni da Salute con SourceTag.
- **Dati:** DataStore, HealthKitService.

### SCR-WK-11 — Dettaglio workout `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://workout/history/{workoutId}`
- **Componenti:** come Summary in sola lettura + `[Modifica]` (set editabili, aggiunta/eliminazione) + `[Elimina workout]` (Alert).
- **Dati:** DataStore, WorkoutEngine/RecoveryEngine (ricalcolo al salvataggio).

### SCR-WK-12 — Generatore / Editor programma `[MVP]`
- **Presentazione:** Push.
- **Componenti:** input (giorni, minuti, split, attrezzatura, priorità; precompilati), `[Genera]`, anteprima con motivazioni, editor sessioni (drag, swap, set/rep range con avvisi fuori range), `[Salva programma]`, opzione `[Mantieni posizione nella rotazione]`.
- **Stati:** `Error` nessun esercizio compatibile → avviso con link SCR-SET-07.
- **Dati:** WorkoutEngine.

### SCR-WK-13 — Workout rapido `[MVP]`
- **Presentazione:** Sheet (medium).
- **Componenti:** slider tempo 20–90 min, focus (Auto / chip gruppi con RecoveryChip), attrezzatura del momento, `[Genera]` → SCR-WK-03.
- **Dati:** WorkoutEngine, RecoveryEngine.

### SCR-WK-14 — Esercizio custom `[MVP]`
- **Presentazione:** Sheet. Campi: nome, muscolo primario, secondari, attrezzatura, pattern, tipo (carico/corpo libero/tempo), incremento.

### SCR-WK-15 — Workout interrotto `[MVP]`
- **Presentazione:** Sheet non dismissibile all'avvio (ultimo input ≥ 4 h).
- **Contenuto:** "Workout di ieri interrotto alle 19:42 (12 set)"; `[Concludi e salva]` (primario), `[Riprendi]`, `[Scarta]` (Alert distruttivo).

---

## 5. Tab Nutrizione

### SCR-NU-01 — Nutrizione `[MVP]`
- **Presentazione:** Tab root · **Deep link:** `jevfit://nutrition`, `jevfit://nutrition/day/{yyyy-mm-dd}`
- **Componenti (priorità):**
  1. DayNavigator (‹ data ›, tipo giorno Allenamento/Riposo), `[Calendario]` → SCR-NU-12.
  2. Card Calorie: Calories Remaining (H0), consumate/target, MacroBar P, C, F, Fibra. Tap → SCR-NU-10.
  3. Card Expenditure: "TDEE 2.740 kcal · Confidence 91%" + ConfidenceBadge, trend 7g/21g, TrendSparkline. Tap → SCR-NU-11.
  4. MealSection × 4 (Colazione, Pranzo, Cena, Snack): totale kcal, FoodRow, `[+]`, menu `[•••]` (Copia da…, Salva come ricetta, Elimina tutto).
  5. Toggle "Giornata completa" / stato "Incompleta".
  6. Bottom toolbar: `[Barcode]` · `[+ Aggiungi]`.
- **Azioni:** `[+]` → SCR-NU-02 col pasto; swipe FoodRow → Elimina (con Annulla); tap FoodRow → SCR-NU-03 (modifica); `[Copia ieri]` in giorno vuoto → SCR-NU-09.
- **Stati:** `Empty` giorno → EmptyStateView per pasto + `[Copia ieri]`; `Offline` nessuna differenza; expenditure confidence < 50% → label "Stima iniziale".
- **Dati:** NutritionEngine (target giorno, tipo giorno, expenditure, confidence), DataStore (voci), JevCoach.

### Wireframe — SCR-NU-01 Nutrizione
```
┌────────────────────────────────────────────┐
│ Nutrizione                     (JEV) [cal] │
│   ‹   Lunedì 21 ott · Allenamento   ›      │ DayNavigator
├────────────────────────────────────────────┤
│ ┌────────────────────────────────────────┐ │
│ │ RIMASTE                                │ │
│ │ 1.240 kcal          1.240 / 2.480      │ │ H0
│ │ P   ████████░░░  118 / 165 g           │ │ MacroBar
│ │ C   █████░░░░░░  142 / 290 g           │ │
│ │ F   ██████░░░░░   48 / 75 g            │ │
│ │ Fib ████░░░░░░░   18 / 35 g            │ │
│ └────────────────────────────────────────┘ │
│ ┌ EXPENDITURE ───────────────────────────┐ │
│ │ TDEE 2.740 kcal     CONF 91% Affidabile│ │ ConfidenceBadge
│ │ 7g 2.712 · 21g 2.748        ‾╲_╱‾  ›   │ │ TrendSparkline
│ └────────────────────────────────────────┘ │
│ COLAZIONE                   512 kcal  [+]  │ MealSection
│   Yogurt greco 0% · 250 g          148     │ FoodRow
│   Fiocchi d'avena · 60 g           233     │
│   Mirtilli · 120 g                  68     │
│ PRANZO                      728 kcal  [+]  │
│   Riso basmati · 80 g              285     │
│   Petto di pollo · 180 g           297     │
│ CENA                          —       [+]  │
│   Copia da ieri ›                          │
│ SNACK                         —       [+]  │
│ [ ] Giornata completa                      │
├────────────────────────────────────────────┤
│  [Barcode]                  [ + Aggiungi ] │ toolbar
└────────────────────────────────────────────┘
```

### SCR-NU-02 — Logger `[MVP]`
- **Presentazione:** Sheet (large) · **Deep link:** `jevfit://nutrition/log?meal={breakfast|lunch|dinner|snack}&date=`
- **Componenti:** selettore pasto, campo ricerca (sempre in alto), segmenti Recenti (default) / Preferiti / Ricette / Miei, pulsanti `[Barcode]` `[Quick add]`, lista FoodRow con `[+]` rapido, sezione "Open Food Facts" sotto i risultati locali, barra inferiore "3 alimenti · 642 kcal" `[Fine]`, toggle "Aggiungi a ieri" (00:00–04:00).
- **Stati:** `Empty` recenti → suggerimenti + `[Scansiona barcode]`; `Offline` sezione OFF sostituita da "Risultati online non disponibili"; `Error` OFF → `[Riprova]` di sezione.
- **Dati:** FoodProvider (locale + OFF), DataStore (recenti, preferiti, custom, ricette), NutritionEngine (anteprima impatto).

### SCR-NU-03 — Porzione / dettaglio alimento `[MVP]`
- **Presentazione:** Push nel logger (o Sheet da FoodRow in modifica).
- **Componenti:** nome, marca, SourceTag (DATABASE / OFF / PERSONALE), badge "Dati community — verifica l'etichetta" o "Dati incoerenti", PortionPicker (g/ml, porzione, unità naturali, moltiplicatori), valori per porzione (kcal, P/C/F, fibra) in SF Mono, anteprima impatto sul giorno (MacroBar), pasto, `[Aggiungi a Pranzo]`/`[Salva modifiche]`, stella preferito, `[Salva come personale]`.
- **Dati:** FoodProvider, NutritionEngine, DataStore.

### SCR-NU-04 — Scanner barcode `[MVP]`
- **Presentazione:** Cover · **Deep link:** `jevfit://nutrition/scan?meal=`
- **Componenti:** camera con ScannerOverlay, torcia, `[Inserisci codice]`, stato "Cerco…" non bloccante.
- **Stati:** `NoPermission` camera → spiegazione + `[Apri Impostazioni]` + `[Inserisci codice]`; non trovato → SCR-NU-05 con barcode; `Offline` non in cache → `[Crea alimento]` / `[Quick add]`.
- **Dati:** FoodProvider (cache locale → OFF).

### SCR-NU-05 — Alimento custom `[MVP]`
- **Presentazione:** Push. Campi: nome, marca, base (100 g / porzione con grammi), kcal, P, C, F, fibra, barcode (precompilato se da scanner). Validazione coerenza kcal vs macro (soft).
- **Dati:** DataStore.

### SCR-NU-06 — Quick add `[MVP]`
- **Presentazione:** Push (o Sheet medium). Campi: kcal, P, C, F, nome opz., pasto. Calcolo 4/4/9 se kcal vuote.

### SCR-NU-07 — Ricette `[MVP]`
- **Presentazione:** segmento del logger + Push da SCR-NU-01 `[•••]` · **Deep link:** `jevfit://nutrition/recipes`
- **Componenti:** lista ricette (kcal/porzione, macro), `[Nuova ricetta]`.

### SCR-NU-08 — Editor ricetta `[MVP]`
- **Presentazione:** Push. Nome, ingredienti (ricerca come logger, grammi), porzioni totali o peso finale cotto, totali e per porzione, `[Salva]`. Avviso: modifiche non alterano i log passati.

### SCR-NU-09 — Copia pasto/giorno `[MVP]`
- **Presentazione:** Sheet (medium). Data sorgente (default ieri), pasto sorgente o "Giorno intero", checkbox voci, totale kcal, pasto destinazione, `[Copia]`.
- **Stati:** sorgente vuota → "Nessuna voce in questo pasto".

### SCR-NU-10 — Target & macro `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://nutrition/targets`
- **Componenti:** modalità AUTO/ASSISTED/MANUAL (segmented), target medio settimanale, giorni allenamento/riposo (toggle + delta), tabella 7 giorni, macro (g e % kcal), proteine g/kg, fibra, limiti di sicurezza spiegati (ⓘ), WhyDataConfidencePanel per i target AUTO.
- **Stati:** MANUAL sotto 1.200 kcal → SafetyNotice di conferma.
- **Dati:** NutritionEngine, ProfileStore.

### SCR-NU-11 — Expenditure `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://nutrition/expenditure`
- **Componenti:** TDEE (H0) + ConfidenceBadge + label (Stima iniziale / In calibrazione / Affidabile), ChartCard TDEE con trend 7g e 21g, giorni usati vs esclusi (incompleti), dati usati (n. pesate, n. giorni loggati, periodo), spiegazione metodo in linguaggio semplice, cosa aumenta la confidence.
- **Stati:** `Empty` < 7 giorni → stima formula + "Servono ancora N giorni".
- **Dati:** NutritionEngine (expenditure, WeightTrend), DataStore.

### SCR-NU-12 — Calendario giorni `[MVP]`
- **Presentazione:** Sheet. Calendario mensile con stato giorno (completo / incompleto / vuoto) e kcal vs target; tap → SCR-NU-01 sul giorno.

---

## 6. Tab Corpo

### SCR-BODY-01 — Corpo `[MVP]`
- **Presentazione:** Tab root · **Deep link:** `jevfit://body`
- **Componenti (priorità):**
  1. Riga Readiness compatta (valore, fascia, glifo, `Dettagli ›` → SCR-BODY-03).
  2. Toggle Fronte / Retro.
  3. **MuscleMap** sfaccettata, colori scala Ember→Mint, gruppi senza dati in neutro, badge limitazione sulle aree dichiarate.
  4. Legenda 4 fasce con label.
  5. Lista gruppi in due sezioni: "Da recuperare" (< 65) e "Pronti" — RecoveryChip + ore stimate.
  6. Card Peso & composizione (trend, BF% con SourceTag) → SCR-PR-02?metric=weight.
- **Azioni:** tap area o riga → SCR-BODY-02; JevButton.
- **Stati:** `Empty` nessun workout → mappa neutra "Allena un gruppo per vedere il recupero"; storico < 2 settimane → ConfidenceBadge bassa sulla mappa; `NoPermission` HK → nessun impatto sulla mappa (dati da workout loggati).
- **Dati:** RecoveryEngine, ReadinessEngine, NutritionEngine/WeightTrend, ProfileStore (limitazioni), HealthKitService (BF%).
- **Accessibilità:** la mappa è un elemento con rotore "Gruppi"; ogni gruppo legge "Petto, 94 percento, pronto".

### Wireframe — SCR-BODY-01 Corpo
```
┌────────────────────────────────────────────┐
│ Corpo                                (JEV) │
├────────────────────────────────────────────┤
│ READINESS  82 · Buono  ▮▮▮▯      Dettagli ›│
│          [ Fronte |  Retro ]               │
│                  ◢◣                        │
│               ◢▓▓▓▓▓▓◣      ▓ Mint         │ MuscleMap
│              ▓▓▓░░░░▓▓▓     ░ Citrine      │ sfaccettata
│              ▓▓ ░░░░ ▓▓     ▒ Amber        │
│              ▒   ▓▓   ▒     █ Ember        │
│                 ▒▒ ▒▒                      │
│                 ██ ██   (!) ginocchio dx   │ badge limitazione
│                 ▒▒ ▒▒                      │
│ ▮ Affaticato ▮ In recupero ▮ Quasi ▮ Pronto│ legenda
├────────────────────────────────────────────┤
│ DA RECUPERARE                              │
│ Quadricipiti    41  ▮▮▯▯   pronto ~30 h  › │ RecoveryChip
│ Glutei          48  ▮▮▯▯   pronto ~26 h  › │
│ Femorali        58  ▮▮▯▯   pronto ~18 h  › │
│ PRONTI                                     │
│ Petto           94  ▮▮▮▮                 › │
│ Dorsali         88  ▮▮▮▮                 › │
│ Deltoidi lat.   71  ▮▮▮▯                 › │
├────────────────────────────────────────────┤
│ ┌ PESO & COMPOSIZIONE ───────────────────┐ │
│ │ Trend 78,6 kg · BF 16,8 %  SALUTE    › │ │
│ └────────────────────────────────────────┘ │
└────────────────────────────────────────────┘
```

### SCR-BODY-02 — Dettaglio gruppo muscolare `[MVP]`
- **Presentazione:** Sheet (medium/large) · **Deep link:** `jevfit://body/muscle/{groupId}`
- **Componenti:** nome + recovery (H1) + fascia + ConfidenceBadge; **Last trained** (data, sessione → SCR-WK-11); **Sets** hard sets ultimi 7 giorni; **Volume** 7 giorni vs media 4 settimane (barra); **Recovery estimate** ore a ≥ 90%; **Next recommended training** (sessione + data stimata); esercizi principali per il gruppo; nota limitazione se presente; contributo da workout esterni (SourceTag SALUTE).
- **Stati:** `Empty` gruppo mai allenato → "Nessun dato" + esercizi suggeriti.
- **Dati:** RecoveryEngine, WorkoutEngine, DataStore.

### SCR-BODY-03 — Dettaglio readiness `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://body/readiness`
- **Componenti:** MetricRing H0 + fascia + ConfidenceBadge; contributi fattori (barre +/−: recovery gruppi prossima sessione, carico acuto/cronico, sonno, HRV, RHR, check soggettivo) con SourceTag; ChartCard 30 giorni; card JEV; `[Check rapido]` → SCR-BODY-04.
- **Stati:** `NoPermission` HK → PermissionCallout "Sonno/HRV non disponibili" + `[Collega Salute]`; label "Stima parziale".
- **Dati:** ReadinessEngine, HealthKitService, JevCoach.

### SCR-BODY-04 — Check rapido `[MVP]`
- **Presentazione:** Sheet (medium). 3 domande a chip (Sonno: Male/Ok/Bene; Energia: Bassa/Ok/Alta; Indolenzimento: Nessuno/Lieve/Forte), `[Salva]`. Una volta al giorno; facoltativo.
- **Dati:** DataStore → ReadinessEngine.

---

## 7. Tab Progressi

### SCR-PR-01 — Progressi `[MVP]`
- **Presentazione:** Tab root · **Deep link:** `jevfit://progress?range={7d|30d|3m|6m|1y|all}`
- **Componenti:** RangeSegmentedControl (7g, 30g, 3m, 6m, 1a, Tutto); sezioni con ChartCard compatte (valore corrente, delta, mini-grafico):
  - **Corpo:** Weight + Weight Trend (un grafico).
  - **Energia:** Calories, TDEE, Energy Balance.
  - **Macro:** Protein, Carbs, Fat.
  - **Forza:** Strength (indice), Estimated 1RM (top 3 esercizi) → SCR-PR-03.
  - **Allenamento:** Training Volume, Workout Frequency.
  - **Recupero:** Recovery (media), Readiness.
  - Marker di fase (cambio obiettivo) e check-in sugli assi temporali.
- **Stati:** `Empty` per ChartCard → "Ancora 3 pesate per mostrare il trend"; range senza dati → "Nessun dato in questo periodo".
- **Dati:** NutritionEngine (WeightTrend, expenditure, energy balance), WorkoutEngine (volume, frequenza, e1RM, Strength), RecoveryEngine, ReadinessEngine, DataStore.

### SCR-PR-02 — Dettaglio metrica `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://progress/metric/{metricId}?range=`
- **Componenti:** grafico grande con scrub (tap-and-hold), statistiche periodo (media, min, max, delta), lista valori per giorno/settimana con SourceTag, `[+]` per metriche inseribili (peso → SCR-WT-01), descrizione metrica (glossario), Audio Graph.
- **Varianti `metricId`:** `weight`, `calories`, `tdee`, `energyBalance`, `protein`, `carbs`, `fat`, `strength`, `volume`, `frequency`, `recovery`, `readiness`.

### SCR-PR-03 — Forza `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://progress/strength`
- **Componenti:** indice Strength, lista esercizi principali (e1RM stabile, delta periodo, TrendSparkline, badge plateau) → SCR-WK-09.
- **Dati:** WorkoutEngine.

---

## 8. JEV (globale)

### SCR-JEV-01 — JEV sheet `[MVP]`
- **Presentazione:** Sheet (medium → large) da JevButton in ogni tab · **Deep link:** `jevfit://jev?context={today|workout|nutrition|body|progress|live}`
- **Componenti (priorità):**
  1. Header: "JEV", stato (AI online / Spiegazione offline), contesto.
  2. **Consiglio di oggi** (Ion Rail, 2–5 frasi, ConfidenceBadge, `[Perché?]`).
  3. **Raccomandazioni attive**: RecommendationRow (titolo, numeri prima→dopo, ConfidenceBadge, `[Applica]`/`[Ignora]`, `[Perché?]` → SCR-JEV-03), ordinate per contesto.
  4. **Chiedi a JEV**: campo testo + 3 domande suggerite contestuali → SCR-JEV-02.
  5. **Storico check-in** → SCR-JEV-04.
- **Stati:** `Offline`/no account → template; chat disabilitata con motivo e CTA; `Empty` → "Nessuna raccomandazione attiva: il piano è in linea."
- **Dati:** JevCoach, tutti gli engine (payload), CheckInEngine.

### SCR-JEV-02 — Chat `[MVP]`
- **Presentazione:** Push nello sheet.
- **Componenti:** messaggi (JEV con Ion Rail; numeri tappabili → metrica + fonte), card azionabili inline, chip suggerimenti, campo input. Disclaimer breve una volta per conversazione.
- **Stati:** `Offline` → input disabilitato "Torna online per la chat"; no account → `[Accedi con Apple]`; `Error` invio → bolla con `[Riprova]`.
- **Dati:** JevCoach (con payload engine), SyncService (account).

### SCR-JEV-03 — Raccomandazione `[MVP]`
- **Presentazione:** Push nello sheet · **Deep link:** `jevfit://jev/recommendation/{id}`
- **Componenti:** titolo, valori prima→dopo, **WhyDataConfidencePanel** esteso (WHY: reason code in linguaggio umano; DATA USED: metriche, periodo, fonti con SourceTag; CONFIDENCE: % + cosa la limita), testo JEV, `[Applica]`/`[Ignora]`.

### SCR-JEV-04 — Storico check-in `[MVP]`
- **Presentazione:** Push · lista settimane con esito (Accettato / Modificato / Rifiutato / Saltato / Parziale) e decisioni principali.

### SCR-JEV-05 — Check-in passato `[MVP]`
- **Presentazione:** Push · **Deep link:** `jevfit://checkin/{weekId}` (se passato). Metriche della settimana, decisioni proposte vs finali, testo JEV.

### SCR-JEV-06 — Avviso di sicurezza `[MVP]`
- **Presentazione:** Push nello sheet o Sheet da SafetyNotice · **Deep link:** `jevfit://jev/safety/{id}`
- **Componenti:** testo chiaro (cosa è stato rilevato, con dati), cosa fare (medico/professionista; 112 per sintomi acuti), cosa ha fatto l'app (es. "nessun aumento carico su spalla"), `[Ho letto]`, `[Aggiungi come limitazione]` (se dolore).
- **Dati:** CheckInEngine / WorkoutEngine (trigger), JevCoach (template deterministico).

---

## 9. Weekly check-in (`Cover`) — UF-08

### SCR-CI-01 — Panoramica `[MVP]`
- **Deep link:** `jevfit://checkin/current`
- **Componenti:** periodo, pagina 1/3; griglia StatTile (10 metriche: Weight Trend, Expenditure, Average Calories, Protein adherence, Workout adherence, Strength trend, Training volume, Recovery, Readiness, Goal progress) con DeltaBadge vs settimana precedente e ConfidenceBadge dove pertinente; card JEV sintetica; `[Più tardi]`, `[Continua]`.
- **Stati:** parziale → banner "Dati insufficienti per le decisioni nutrizionali" + cosa serve.
- **Dati:** CheckInEngine, JevCoach.

### SCR-CI-02 — Decisioni `[MVP]`
- **Componenti:** pagina 2/3; DecisionCard per decisione (tipo, valori prima→dopo con dettaglio allenamento/riposo, testo JEV con Ion Rail, WhyDataConfidencePanel collassato, `[Rifiuta]` `[Modifica]` `[Accetta]`), `[Accetta tutto]`, `[Continua]` (abilitato quando ogni decisione ha uno stato).
- **Stati:** solo KEEP/NO ACTION → card unica "Piano confermato"; safety attivo → riduzioni sostituite da NO ACTION + SafetyNotice; MANUAL → `[Applica]` al posto di `[Accetta]`.

### SCR-CI-03 — Modifica decisione `[MVP]`
- **Presentazione:** Sheet (medium). BigStepper limitato (es. calorie ±250, floor), anteprima effetti (giorni allenamento/riposo, macro), messaggio ai limiti, `[Salva modifica]`.
- **Dati:** CheckInEngine (limiti, validazione), NutritionEngine/WorkoutEngine (anteprima).

### SCR-CI-04 — Conferma `[MVP]`
- **Componenti:** pagina 3/3; riepilogo prima→dopo (calorie, macro, volume per gruppo, esercizi cambiati, deload), data efficacia, `[Conferma piano]`.
- **Stati:** `Error` applicazione → decisione marcata "Non applicata" con motivo.

### Wireframe — SCR-CI-02 Decisioni
```
┌────────────────────────────────────────────┐
│ ✕   Check-in 14–20 ott          2 di 3     │
│ ▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱                        │
├────────────────────────────────────────────┤
│ Decisioni                                  │
│ ┌ DIMINUISCI CALORIE ─────── CONF 88% ───┐ │ DecisionCard
│ │ Media giornaliera                      │ │
│ │ 2.250  →  2.150 kcal      −100         │ │ H1 + DeltaBadge
│ │ Allenamento 2.480 → 2.380              │ │
│ │ Riposo      2.030 → 1.930              │ │
│ │ ┃ Trend −0,25 kg/sett. contro target   │ │ Ion Rail
│ │ ┃ −0,40. Taglio piccolo, proteine      │ │
│ │ ┃ invariate a 165 g.                   │ │
│ │ WHY · DATA USED · CONFIDENCE       ⌄   │ │ WDC panel
│ │ [Rifiuta]    [Modifica]   [ Accetta ]  │ │
│ └────────────────────────────────────────┘ │
│ ┌ AUMENTA CARICO ALLENAMENTO ─ CONF 74% ─┐ │
│ │ Dorsali   10 → 12 set/settimana        │ │
│ │ ┃ Recupero dorsali medio 91%, rematore │ │
│ │ ┃ +3,2% in 3 settimane.                │ │
│ │ WHY · DATA USED · CONFIDENCE       ⌄   │ │
│ │ [Rifiuta]    [Modifica]   [ Accetta ]  │ │
│ └────────────────────────────────────────┘ │
├────────────────────────────────────────────┤
│ [ Accetta tutto ]            [ Continua › ]│
└────────────────────────────────────────────┘
```
Nota: le etichette decisione sono localizzate in UI (DIMINUISCI CALORIE ↔ `DECREASE_CALORIES`); i codici inglesi restano negli engine e nei log.

---

## 10. Impostazioni & account

| ID | Schermata | Contenuto | Stati notevoli | Dati | Deep link | Rel. |
|---|---|---|---|---|---|---|
| SCR-SET-01 | Impostazioni | Sezioni: Profilo & obiettivo, Allenamento, Nutrizione, Unità, Salute, Notifiche, Account & Sync, Privacy & dati, Lingua & aspetto, Info. Avviso "dati solo su questo iPhone" se no account | — | ProfileStore | `jevfit://settings` | MVP |
| SCR-SET-02 | Unità | Peso kg/lb, energia kcal/kJ, altezza cm/ft-in; anteprima conversione target | Disabilitato durante workout live | ProfileStore, WorkoutEngine (arrotondamenti) | `jevfit://settings/units` | MVP |
| SCR-SET-03 | Salute | Stato per tipo (Collegato / Nessun dato recente / Non collegato), toggle scritture, ultimo import, `[Collega Salute]`, `[Apri Salute]` | NoPermission, revoca, errore scrittura con retry | HealthKitService | `jevfit://settings/health` | MVP |
| SCR-SET-04 | Notifiche | Toggle e orari per categoria, quiet hours, limite giornaliero | Permesso negato → `[Apri Impostazioni]` | NotificationService | `jevfit://settings/notifications` | MVP |
| SCR-SET-05 | Account & Sync | Stato account, ultima sync, progress, errori + `[Riprova]`, `[Accedi con Apple]`, `[Esci]` | Offline: login disabilitato | SyncService | `jevfit://settings/account` | MVP |
| SCR-SET-06 | Obiettivo & profilo | Obiettivo, fase (data inizio), target weight, rate, dati corpo, `[Cambia obiettivo]` | — | ProfileStore, CheckInEngine (GoalProgress) | `jevfit://settings/goal` | MVP |
| SCR-SET-07 | Preferenze allenamento | Giorni/minuti, split, attrezzatura, preferiti/esclusi, RPE on/off, warm-up suggeriti, durata recupero default, incrementi | — | ProfileStore, WorkoutEngine | `jevfit://settings/training` | MVP |
| SCR-SET-08 | Limitazioni & dolore | Aree dichiarate, intensità, note, storico segnalazioni | — | ProfileStore, DataStore | `jevfit://settings/limitations` | MVP |
| SCR-SET-09 | Preferenze nutrizione | Modalità macro (→ SCR-NU-10), split calorie allen./riposo, giorno check-in, valore giornaliero peso (prima/media), soglia giorno incompleto | — | ProfileStore, NutritionEngine | `jevfit://settings/nutrition` | MVP |
| SCR-SET-10 | Privacy & dati | Spiegazione privacy (6 punti), toggle JEV AI online, export JSON/CSV, importa backup, elimina dati locali, elimina account | Conferme distruttive (Alert) | DataStore, SyncService | `jevfit://settings/privacy` | MVP |
| SCR-SET-11 | Lingua, aspetto, accessibilità | Lingua (Sistema/IT/EN), aspetto (Sistema/Chiaro/Scuro), haptics on/off | — | ProfileStore | `jevfit://settings/appearance` | MVP |
| SCR-SET-12 | Info & disclaimer | Versione, disclaimer completo, licenze (OFF ODbL), contatti | — | — | `jevfit://settings/about` | MVP |
| SCR-SET-13 | Anteprima cambio obiettivo | Diff prima→dopo, `[Applica da oggi]` / `[Al prossimo check-in]` | — | NutritionEngine, WorkoutEngine | — | MVP |
| SCR-AC-01 | Accedi | Cosa abilita l'account, Sign in with Apple | Offline: disabilitato | SyncService | `jevfit://account/signin` | MVP |
| SCR-AC-02 | Unisci dati | Conteggi locali vs cloud, `[Unisci]` (default), `[Usa solo cloud]` (distruttivo), `[Annulla]`; scelta programma attivo | Error merge → retry | SyncService | — | MVP |
| SCR-SET-14 | Abbonamento | Piani StoreKit | — | StoreKit | `jevfit://settings/subscription` | V2 |

---

## 11. Deep link (riepilogo)

| Deep link | Destinazione | Usato da |
|---|---|---|
| `jevfit://today` | SCR-HOME-01 | default |
| `jevfit://weight/new` | SCR-WT-01 | Notifica pesata |
| `jevfit://workout/today` | SCR-WK-03 | Notifica workout |
| `jevfit://workout/live` | SCR-WK-04 | Notifica fine recupero, ResumeWorkoutBanner |
| `jevfit://workout/history/{id}` | SCR-WK-11 | Storico, JEV |
| `jevfit://exercises/{id}` | SCR-WK-09 | Progressi, JEV |
| `jevfit://nutrition/log?meal=&date=` | SCR-NU-02 | Notifica pasti |
| `jevfit://nutrition/scan?meal=` | SCR-NU-04 | Quick action icona app (V2: App Intent) |
| `jevfit://nutrition/expenditure` | SCR-NU-11 | Home, JEV |
| `jevfit://body/muscle/{groupId}` | SCR-BODY-02 | Summary, JEV |
| `jevfit://body/readiness` | SCR-BODY-03 | Home |
| `jevfit://progress/metric/{metricId}` | SCR-PR-02 | Home, JEV |
| `jevfit://checkin/current` | SCR-CI-01 | Notifica check-in |
| `jevfit://checkin/{weekId}` | SCR-JEV-05 | Storico |
| `jevfit://jev?context=` | SCR-JEV-01 | JevButton |
| `jevfit://jev/recommendation/{id}` | SCR-JEV-03 | Card JEV |
| `jevfit://settings/...` | SCR-SET-* | Callout permessi |

Regola: se un deep link punta a un workout live inesistente, apre SCR-WK-01; se il check-in è già completato, apre SCR-JEV-05 della settimana.

---

## 12. V2 — schermate e superfici previste

| ID | Superficie | Note |
|---|---|---|
| SCR-V2-01 | Live Activity / Dynamic Island workout | Timer recupero, set corrente, `[Completa set]` interattivo |
| SCR-V2-02 | Widget (Readiness, Calorie rimaste, Prossimo workout) | Small/medium, Lock Screen |
| SCR-V2-03 | Food da foto (AI) | Cover camera → proposta voci → conferma |
| SCR-V2-04 | Misure corporee & foto progressi | In tab Corpo |
| SCR-V2-05 | Apple Watch app | Logging set da polso |
| SCR-V2-06 | App Intents / Siri / Shortcuts | "Registra pesata", "Chiedi a JEV" |
| SCR-V2-07 | Condivisione summary | Immagine generata, nessun social interno |
| SCR-V2-08 | Illustrazioni/video esercizi | In SCR-WK-09 |
| SCR-SET-14 | Abbonamento StoreKit | Vedi §10 |

---

## 13. Componenti del design system

Token: vedi PRODUCT_SPEC §8 (palette, tipografia, forme). Ogni componente supporta light/dark, Dynamic Type fino ad AX3, VoiceOver label con valore + unità + fascia.

| Componente | Descrizione | Varianti / props principali | Usato in |
|---|---|---|---|
| **MetricRing** | Anello 0–100 o 0–target con numero H0 al centro; colore da scala semantica o macro | `value`, `scale` (readiness/recovery/calories), `size` (hero/compact), `confidence` | HOME-01, BODY-03, NU-01 |
| **MacroBar** | Barra orizzontale consumato/target con label e grammi in SF Mono; overflow mostrato oltre il 100% con tratteggio | `macro` (P/C/F/Fib), `consumed`, `target`, `preview` (impatto futuro) | HOME-01, NU-01, NU-03 |
| **RecoveryChip** | Chip con nome gruppo, %, glifo 4 tacche, colore fascia | `group`, `value`, `compact` | HOME-01, WK-03, BODY-01/02, WK-07 |
| **ConfidenceBadge** | "CONF 91%" SF Mono + label (Stima iniziale / In calibrazione / Affidabile); tap → spiegazione | `value`, `style` (inline/pill) | ovunque ci sia una stima |
| **WhyDataConfidencePanel** (WDC) | Pannello collassabile 3 sezioni: WHY (reason code umanizzato), DATA USED (metriche, periodo, SourceTag), CONFIDENCE (valore + limiti) | `collapsed`, `reasonCodes`, `dataRefs`, `confidence` | JEV-01/03, CI-02, WK-07, NU-10 |
| **IonRail** | Contenitore testo JEV con barra Ion 3 pt; label "Spiegazione offline" opzionale | `source` (ai/template) | tutte le superfici JEV |
| **JevButton** | Pulsante navigation bar (SF Symbol dedicato + "JEV"), badge punto se raccomandazioni nuove | `hasNew` | tutte le tab, WK-04 |
| **JevTodayCard** | Card JEV TODAY in Home con IonRail, ConfidenceBadge, `[Dettagli]` | — | HOME-01 |
| **BigStepper** | Stepper grande (min 56×56 pt) con valore SF Mono, step configurabile, long-press accelera, tap sul valore → tastiera | `value`, `step`, `allowedValues` (attrezzatura), `bounds` | WK-04, WT-01, CI-03 |
| **RIRPicker** | 6 chip 0…5+, modalità RPE opzionale 6–10 | `mode` (rir/rpe), `target` evidenziato | WK-04, WK-06 |
| **SetRow** | Riga set: indice, SetTypeBadge, kg, reps, RIR, check; stati pending/current/done/skipped/edited | `state`, `isPR` | WK-04, WK-11 |
| **SetTypeBadge** | Badge abbreviato WU/WRK/TOP/BO/DROP/FAIL/AMRAP | `type` | WK-04, WK-06 |
| **ExerciseHeader** | Nome, target, badge esito overload, riga Precedente | `outcome` (up-load/up-reps/hold/regress/deload) | WK-04, WK-03 |
| **RestTimerBar** | Countdown con barra, `[−15s] [+15s] [Salta]`; basato su timestamp | `endsAt` | WK-04 |
| **SwapCandidateRow** | Alternativa con tag motivo e target calcolato | `reasons[]`, `target` | WK-05 |
| **TrendSparkline** | Mini linea trend senza assi con punto finale evidenziato | `series`, `direction` | HOME-01, NU-01, PR-03 |
| **ChartCard** | Card grafico (Swift Charts) con valore, delta, range, scrub, Audio Graph | `metric`, `range`, `markers` (fasi, check-in) | PR-01/02, NU-11, BODY-03, WK-09 |
| **StatTile** | Tile metrica: label, valore H1, DeltaBadge, SourceTag | `size` (half/full) | HOME-01, CI-01 |
| **DeltaBadge** | Delta con segno, freccia SF Symbol, unità; neutro salvo PR | `value`, `unit`, `isPR` | WK-07, CI-01/02, PR-* |
| **PRBadge** | Badge Gold "PR" + tipo (peso/reps/e1RM/volume) | `kind` | WK-07, WK-09 |
| **SourceTag** | Micro label maiuscola SF Mono: SALUTE · MANUALE · STIMA · OFF · DATABASE · PERSONALE | `source` | ovunque |
| **MuscleMap** | Mappa sfaccettata fronte/retro, 17 aree tappabili, colore per fascia, badge limitazione, modalità selezione | `values`, `side`, `mode` (display/select/mini) | BODY-01, HOME-01, WK-07, ONB-12 |
| **GoalProgressBar** | Barra progresso fase con valore attuale → target e data stimata | `progress`, `eta` | HOME-01, SET-06 |
| **MealSection** | Sezione pasto con totale, FoodRow, `[+]`, menu | `meal` | NU-01 |
| **FoodRow** | Nome, porzione, kcal, `[+]` rapido, swipe azioni, stella | `mode` (log/search) | NU-01/02 |
| **PortionPicker** | Selettore unità + quantità + moltiplicatori | `units[]` | NU-03 |
| **ScannerOverlay** | Mirino barcode, torcia, stato ricerca | — | NU-04 |
| **DayNavigator** | ‹ data › con tipo giorno | `date`, `dayType` | NU-01 |
| **WeekStrip** | 7 giorni con stato sessione (fatto/pianificato/deload/saltato) | — | WK-01 |
| **DecisionCard** | Decisione check-in: tipo, prima→dopo, IonRail, WDC, 3 azioni, stato | `decision`, `state` | CI-02 |
| **RecommendationRow** | Raccomandazione JEV compatta con azione | `actionable` | JEV-01 |
| **ContextCard** | Card temporanea in cima a Home (resume, safety, check-in, pesata) | `kind` | HOME-01 |
| **SafetyNotice** | Card/banner safety con testo deterministico, `[Ho letto]` | `trigger` | HOME-01, WK-06, CI-02, JEV-06 |
| **ResumeWorkoutBanner** | Banner persistente sopra tab bar per workout in corso | — | globale |
| **OfflineChip** | Chip discreto "Offline" in navigation bar; mai modale | — | globale |
| **SyncStatusBadge** | Punto su avatar per errore sync > 24 h | — | HOME-01 |
| **PermissionCallout** | Callout contestuale per permesso mancante con beneficio + CTA | `permission` | BODY-03, NU-04, SET-03 |
| **EmptyStateView** | SF Symbol, una riga di spiegazione, quanti dati mancano, CTA | `requirement` | ovunque |
| **RangeSegmentedControl** | 7g/30g/3m/6m/1a/Tutto | — | PR-01/02 |
| **UnitText** | Formatter numero + unità (Unit-light), locale, kg/lb, kcal/kJ | `value`, `unit`, `style` (hero/key/data) | ovunque |
