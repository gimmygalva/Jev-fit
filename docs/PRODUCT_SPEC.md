# JEV FIT — Product Spec

> **Owner:** Agent 01 — Product & UX · **Fase:** 1 (Discovery & Spec) · **Stato:** Draft v1.0 per review CTO
> **Documenti collegati:** `USER_FLOWS.md` (flussi `UF-xx`), `SCREEN_MAP.md` (schermate `SCR-xx`, componenti design system)
> **Piattaforma:** iPhone, iOS 18+, Swift 6, SwiftUI. Nessuna dipendenza da Apple Watch.
> **Lingua UI:** italiano (primaria), inglese (secondaria).

Convenzioni:
- Requisiti: `PS-<AREA>-<NN>` + tag `[MVP]` o `[V2]`. Ogni requisito MVP ha almeno un criterio di accettazione (**AC**) verificabile.
- Valori numerici marcati *(proposta)* sono default di prodotto da validare con le spec degli engine del CTO; la UI non dipende dal valore esatto.
- "Engine" = livello 2 deterministico. "JEV" = livello 3 (JevCoach). "Data engine" = livello 1.

---

## 1. Visione

JEV FIT è il coach di allenamento e nutrizione che ragiona sui tuoi dati, non su frasi motivazionali. Ogni numero che vedi viene da un algoritmo deterministico, testabile e funzionante offline; JEV, il coach AI, li legge e ti dice cosa fare domani e perché.

**In una frase:** "Un'app che sa quanto hai recuperato, quanto stai davvero consumando e quanto caricare sul bilanciere — e te lo dimostra."

Tre promesse all'utente:
1. **Precisione onesta:** ogni stima mostra quanto è affidabile (confidence) e su quali dati si basa.
2. **Zero attrito in palestra e a tavola:** loggare un set o un alimento recente richiede ≤ 2 tap, anche senza rete.
3. **Un unico cervello:** allenamento, nutrizione, peso e recupero si influenzano a vicenda nel check-in settimanale.

---

## 2. Principi di prodotto

| ID | Principio | Implicazione concreta |
|---|---|---|
| P1 | **Architettura a 3 livelli** | (1) Data engine: dati reali, storico, HealthKit, workout, nutrizione, peso. (2) Deterministic engines: calcolano ogni numero. (3) JEV AI: interpreta, spiega, motiva. |
| P2 | **Numeri solo dagli engine** | JEV non produce numeri propri. Ogni numero in un testo JEV deve esistere nel payload strutturato fornito dagli engine (vedi PS-JEV-04). Se la validazione fallisce, si mostra il testo template deterministico. |
| P3 | **Spiegabilità: WHY / DATA USED / CONFIDENCE** | Ogni raccomandazione ha, quando possibile, un pannello con motivo, dati usati (con periodo) e confidence. |
| P4 | **Offline first** | Workout logging, food logging (locale/recenti/custom), pesata, check-in deterministico funzionano senza rete. La rete arricchisce, non abilita. Nessun flusso core bloccato dalla rete. |
| P5 | **Local first, account opzionale** | Tutto funziona senza account. Sign in with Apple serve solo per sync cloud e JEV AI online. |
| P6 | **iPhone-only, HealthKit opzionale** | Nessuna feature assume Apple Watch. Se HealthKit è negato, ogni feature ha un input manuale equivalente. |
| P7 | **Proporre, mai imporre** | Gli engine propongono; l'utente accetta/modifica/rifiuta. Nessuna modifica calorica o di carico estrema è automatica; le modifiche manuali restano entro limiti di sicurezza. |
| P8 | **Stabilità percepita** | Il peso del giorno non sposta il trend in modo brusco; i target non oscillano ogni giorno. I cambi di piano avvengono al check-in settimanale, salvo azioni esplicite dell'utente. |
| P9 | **Densità senza rumore** | Molti dati, pochi elementi per schermata: un numero eroe per card, il resto è contesto. |

---

## 3. Persone

### 3.1 Persona primaria — P-01 "L'intermedio data-driven" (uso personale)
- 25–45 anni, si allena in palestra da 2–6 anni, 3–5 sessioni/settimana, 50–80 min.
- Conosce RIR/RPE, double progression, ha già usato fogli Excel o app di logging.
- Traccia la nutrizione a periodi; vuole sapere il suo TDEE reale, non quello di una formula.
- Solo iPhone (niente Watch), a volte senza rete in palestra (seminterrato).
- Obiettivi tipici: ipertrofia, ricomposizione, dimagrimento preservando massa.
- **Frustrazioni:** app di logging lente tra un set e l'altro; target calorici che non si adattano; consigli AI generici non verificabili.
- **Job to be done:** "Quando entro in palestra voglio sapere cosa fare e con che carico, loggarlo in 2 secondi, e a fine settimana sapere se il piano funziona."

### 3.2 Persone future (commerciali, non guidano l'MVP)
| ID | Persona | Bisogno chiave | Impatto su design |
|---|---|---|---|
| P-02 | Principiante motivato | Programma pronto, spiegazioni semplici | Default intelligenti, glossario inline, RIR spiegato |
| P-03 | Lifter orientato alla forza | Top set, back-off, e1RM, peaking | Set types avanzati, grafici e1RM, deload controllabile |
| P-04 | Over 40, dimagrimento, poco tempo | Sessioni 30–40 min, preservare massa | Generazione per tempo disponibile, safety su rate of change |
| P-05 | Ibrido (palestra + corsa/bici da HealthKit) | Readiness che tiene conto del cardio | Import workout HK nel carico, split Hybrid |

---

## 4. Obiettivi e non-obiettivi

### 4.1 Obiettivi (MVP)
- O1. Completare onboarding in < 4 minuti (mediana) con un programma generato e target nutrizionali pronti.
- O2. Loggare un workout intero offline, con progressive overload suggerito per ogni esercizio.
- O3. Stimare l'expenditure adattiva con confidence crescente nelle prime 3–4 settimane.
- O4. Check-in settimanale che chiude il loop allenamento + nutrizione + peso con decisioni accettabili in < 2 minuti.
- O5. JEV che spiega il piano con dati tracciabili; zero numeri inventati.
- O6. Nessuna perdita di dati: workout in corso sopravvive a crash; sync senza duplicati.

### 4.2 Non-obiettivi
- NO1. Non è un dispositivo medico: nessuna diagnosi, nessuna prescrizione clinica.
- NO2. Nessun social network, feed o classifiche (condivisione semplice solo V2).
- NO3. Nessun tracking GPS di corsa/bici nativo: il cardio arriva solo da HealthKit o inserimento manuale.
- NO4. Nessun meal plan generato con ricette (si traccia, non si prescrive il menù).
- NO5. Nessuna app Android/web.
- NO6. Nessun micronutriente oltre la fibra nell'MVP (zuccheri, sodio, grassi saturi visualizzati se presenti, non tracciati come target).

---

## 5. Scope MVP vs V2 (sintesi)

| Area | MVP | V2 |
|---|---|---|
| Onboarding | Completo, con skip e default | Import da altre app (CSV) |
| Allenamento | Programmi, generazione, live mode, overload, summary, storico, libreria testuale | Live Activity, widget, illustrazioni/video, superset strutturati (vedi domande), plate calculator |
| Recovery/Readiness | Mappa muscolare, score 0–100, dettaglio gruppo | Input soggettivi avanzati, stress/ciclo |
| Nutrizione | Target, macro AUTO/ASSISTED/MANUAL, expenditure, logger completo con barcode e ricette base | Food da foto con AI, micronutrienti, acqua |
| Peso/corpo | Pesata, trend, body fat da HK/manuale | Misure circonferenze, foto progressi |
| JEV | Card, sheet, chat online, template offline, WDC | Provider AI on-device, App Intents/Siri |
| Piattaforma | HealthKit, notifiche locali, sync, account | Apple Watch app, StoreKit, condivisione social |

---

## 6. Requisiti funzionali

### 6.1 Onboarding (`PS-ON`) — flusso `UF-01`, schermate `SCR-ONB-*`

- **PS-ON-01** [MVP] L'onboarding raccoglie, in quest'ordine: obiettivo, esperienza, dati corpo, livello attività, target weight + rate of change, disponibilità (giorni e minuti), attrezzatura, split, esercizi preferiti/esclusi, limitazioni/dolore, muscle priority, modalità macro, unità, HealthKit, notifiche.
  - AC: tutti i 15 step sono raggiungibili; i dati inseriti sono persistiti localmente a ogni step (kill app a metà → riapertura sullo stesso step).
- **PS-ON-02** [MVP] Step obbligatori: obiettivo, esperienza, peso, altezza, età, giorni disponibili, attrezzatura. Tutti gli altri hanno default e pulsante "Salta".
  - AC: un utente che tocca "Continua" accettando i default e "Salta" dove possibile completa l'onboarding in ≤ 20 tap dopo aver inserito i dati obbligatori.
- **PS-ON-03** [MVP] Obiettivi selezionabili: Forza, Ipertrofia, Mantenimento, Ricomposizione, Dimagrimento (preservando massa), Fitness generale. Ognuno con una riga di descrizione e l'effetto previsto su calorie e allenamento. Gate di sicurezza: Dimagrimento non selezionabile con BMI attuale < 18,5; nessun obiettivo in deficit sotto i 18 anni o con gravidanza/allattamento dichiarati (ARCHITECTURE_PLAN §5.3).
  - AC: la selezione determina default di rate of change, rep range e modalità macro mostrati negli step successivi.
- **PS-ON-04** [MVP] Sesso biologico opzionale con spiegazione: "Serve solo per stimare il metabolismo basale iniziale. Se preferisci non indicarlo usiamo una formula neutra e la stima si corregge con i tuoi dati in 2–3 settimane."
  - AC: con sesso non indicato, la confidence iniziale dell'expenditure è inferiore (visibile) e nessuna schermata richiede di nuovo il dato.
- **PS-ON-05** [MVP] Target weight e desired rate of change con limiti di sicurezza *(proposta)*: perdita 0,25–1,0% del peso/settimana (default 0,5%), aumento 0,1–0,5%/settimana (default 0,25%). Valori fuori range non selezionabili; il picker mostra la data stimata di arrivo.
  - AC: lo slider non consente valori fuori limite; con perdita > 0,75%/sett. compare la nota "Ritmo aggressivo: più difficile preservare massa muscolare".
- **PS-ON-06** [MVP] Attrezzatura: preset Palestra completa, Home gym, Solo manubri, Corpo libero; ogni preset apre una checklist modificabile (bilanciere, rack, panca, cavi, macchine, manubri con range, kettlebell, elastici, sbarra).
  - AC: il WorkoutEngine non propone mai esercizi che richiedono attrezzatura non selezionata.
- **PS-ON-07** [MVP] Split: Full Body, Upper/Lower, Push Pull Legs, Torso/Limbs, Hybrid, Custom, oppure "Lascia decidere a JEV" (default). Lo split suggerito mostra il motivo ("4 giorni, 60 min, ipertrofia → Upper/Lower").
  - AC: con "Lascia decidere a JEV" lo split è scelto dal WorkoutEngine e la motivazione deriva dal suo reason code.
- **PS-ON-08** [MVP] Limitazioni/dolore dichiarati: selezione area (spalla, gomito, polso, lombare, anca, ginocchio, caviglia, collo, altro) + intensità (lieve/moderato) + nota libera. Nessuna domanda diagnostica. Copy: "Non è una diagnosi: ci serve per evitare esercizi che potrebbero darti fastidio."
  - AC: un'area dichiarata riduce l'ExerciseScore degli esercizi che la caricano; il Body screen mostra un'icona sull'area.
- **PS-ON-09** [MVP] Muscle priority: fino a 3 gruppi prioritari (volume +), opzionale.
- **PS-ON-10** [MVP] Permessi HealthKit con schermata di pre-permesso che spiega ogni tipo (vedi PS-HK-02) prima del prompt di sistema.
- **PS-ON-11** [MVP] Al termine: schermata "Il tuo piano" con split, prossima sessione, calorie (giorni allenamento/riposo), macro, TDEE stimato con confidence, prima card JEV.
  - AC: tutti i numeri mostrati provengono da WorkoutEngine/NutritionEngine; il pulsante "Inizia" porta a Oggi.

### 6.2 Oggi / Home (`PS-HOME`) — `SCR-HOME-01`

- **PS-HOME-01** [MVP] Above the fold (iPhone 15/16, Dynamic Type default): JEV READINESS, card JEV TODAY, Workout Today. Sotto: Calories Remaining + Protein/Carbs/Fat, Weight Trend, Muscle Recovery, Goal Progress.
  - AC: tutti i 10 elementi richiesti sono presenti in Home senza tap aggiuntivi; ordine come in SCREEN_MAP.
- **PS-HOME-02** [MVP] Calories Remaining = target del giorno − calorie loggate. Le calorie dell'attività **non** vengono aggiunte (sono già nel TDEE adattivo). Il tipo di giorno (allenamento/riposo) è visibile.
  - AC: loggare 500 kcal riduce Remaining di esattamente 500; un workout completato non cambia Remaining salvo cambio del tipo di giorno (PS-NU-07).
- **PS-HOME-03** [MVP] Card contestuali temporanee (max 1 visibile alla volta, sopra Workout Today): workout da riprendere, check-in pronto, pesata di oggi mancante (fino alle 12:00), safety notice.
  - AC: priorità: ResumeWorkout > SafetyNotice > Check-in > Pesata.
- **PS-HOME-04** [MVP] Header: data, avatar profilo (→ Profilo/Impostazioni), pulsante JEV, OfflineChip quando offline.
- **PS-HOME-05** [MVP] Ogni card è tappabile e porta al dettaglio della sua area (deep link interno).
- **PS-HOME-06** [V2] Widget Home Screen e Lock Screen (readiness, calorie rimaste, prossimo workout).

### 6.3 Programmazione (`PS-PG`) — `UF-03`, `SCR-WK-01..03, 12, 13`

- **PS-PG-01** [MVP] Il WorkoutEngine genera un programma = split + template settimanale (sessioni con esercizi, set, rep range, RIR target) + regole di progressione + politica di deload.
  - AC: dato lo stesso input (profilo, attrezzatura, esclusioni, seed), la generazione è deterministica.
- **PS-PG-02** [MVP] Split supportati: Full Body, Upper/Lower, Push Pull Legs, Torso/Limbs, Hybrid, Custom.
- **PS-PG-03** [MVP] Il programma è a **rotazione**: "Prossima sessione" è la successiva nella sequenza, non legata al giorno della settimana. I giorni preferiti servono a promemoria e a calcolare giorni allenamento/riposo per le calorie.
  - AC: saltare un giorno non fa "perdere" una sessione; la prossima resta la stessa.
- **PS-PG-04** [MVP] Selezione esercizi tramite ExerciseScore (pattern, attrezzatura, preferenze, esclusioni, limitazioni, recupero muscolare, storico). Esercizi esclusi mai proposti.
  - AC: un esercizio escluso non compare in generazione, swap o workout rapido.
- **PS-PG-05** [MVP] "Workout rapido": generazione one-off da tempo disponibile (20–90 min), focus (auto/gruppi muscolari) e attrezzatura del momento. Priorità ai gruppi con recovery più alta.
  - AC: la durata stimata del workout generato è entro ±10% del tempo richiesto.
- **PS-PG-06** [MVP] Workout libero (vuoto) e template custom: l'utente aggiunge esercizi dalla libreria; il WorkoutEngine propone comunque i target se c'è storico.
- **PS-PG-07** [MVP] Editor programma: riordinare/sostituire esercizi, cambiare set e rep range, rinominare sessioni. Modifiche fuori range consigliato mostrano un avviso non bloccante.
- **PS-PG-08** [MVP] Adattamento giornaliero da readiness: se JEV READINESS < 40 *(proposta)*, la card Workout Today propone "Versione ridotta" (−1 set per esercizio, carichi invariati) — mai applicata automaticamente.
  - AC: la versione ridotta è un'opzione esplicita; scegliendola, il summary marca la sessione come "ridotta".
- **PS-PG-09** [MVP] Libreria esercizi: nome IT/EN, muscoli primari/secondari, pattern, attrezzatura, cue testuali (max 3), storico personale, e1RM. Esercizi custom creabili.
- **PS-PG-10** [V2] Illustrazioni/video esercizi; superset/circuiti strutturati; plate calculator.

### 6.4 Workout live (`PS-WK`) — `UF-04`, `SCR-WK-04..07`

- **PS-WK-01** [MVP] Live mode presentato a schermo intero. Per l'esercizio corrente mostra: nome, set corrente/totale, target reps, target weight, previous performance (stesso esercizio, ultima sessione), timer di recupero, input RIR (RPE opzionale da impostazioni).
  - AC: tutti questi elementi sono visibili senza scroll sull'esercizio corrente su iPhone 15 con Dynamic Type default.
- **PS-WK-02** [MVP] Completare un set con i valori target precompilati richiede **1 tap** ("Completa set"); con modifica di peso o reps ≤ 3 tap (BigStepper ±incremento).
  - AC: test UI: set con valori target → 1 tap; modifica +2,5 kg → 2 tap + completa.
- **PS-WK-03** [MVP] Tipi di set: Warm-up, Working, Top set, Back-off, Drop, Failure, AMRAP. Warm-up esclusi da volume e overload.
  - AC: il volume nel summary esclude i warm-up.
- **PS-WK-04** [MVP] RIR picker 0, 1, 2, 3, 4, 5+ (chip grandi). RPE opzionale (6–10, step 0,5) attivabile in impostazioni; internamente convertito.
- **PS-WK-05** [MVP] Timer di recupero parte automaticamente al completamento del set (durata da esercizio/programma, modificabile ±15 s). Notifica locale a fine timer se l'app è in background.
  - AC: con app in background, notifica entro ±2 s dalla scadenza; nessuna notifica se l'app è in foreground (feedback aptico + visivo).
- **PS-WK-06** [MVP] Swap esercizio: lista alternative ordinate per ExerciseScore con tag motivo ("Stesso pattern", "Attrezzatura disponibile", "Spalla: carico ridotto"). Il target dell'alternativa è calcolato dal suo storico o stimato.
  - AC: lo swap conserva i set già completati sull'esercizio originale; quelli rimanenti passano al nuovo.
- **PS-WK-07** [MVP] Aggiungi set, salta set, salta esercizio, aggiungi esercizio, riordina esercizi.
- **PS-WK-08** [MVP] Note dolore per set/esercizio: area, intensità (lieve/moderato/forte), testo. Intensità "forte" → suggerimento immediato di interrompere l'esercizio e opzione swap (vedi PS-SAF-03).
- **PS-WK-09** [MVP] Persistenza: ogni azione (set completato, modifica, swap) è salvata immediatamente su storage locale. Dopo kill/crash, all'apertura l'app riprende il workout (ResumeWorkoutBanner + riapertura live mode).
  - AC: test: completa 5 set, kill del processo, riapri → 5 set presenti, timer ricalcolato da timestamp.
- **PS-WK-10** [MVP] Workout abbandonato: se un workout in corso non riceve input per 4 ore *(proposta)*, all'apertura si chiede "Concludi e salva" / "Riprendi" / "Scarta". Mai scartato in automatico.
- **PS-WK-11** [MVP] Modifica set dopo il completamento (durante e dopo il workout, anche dallo storico): ricalcolo di volume, PR e recovery; i suggerimenti futuri usano il dato aggiornato.
  - AC: modificare un set dallo storico aggiorna PR ed e1RM entro la stessa sessione d'uso.
- **PS-WK-12** [MVP] Pulsanti grandi: target minimo 56×56 pt per azioni primarie in live mode; usabile con una mano (azioni primarie nella metà inferiore).
- **PS-WK-13** [MVP] Durante il workout, il pulsante JEV apre lo sheet con contesto "esercizio corrente" (es. "Perché 85 kg?").
- **PS-WK-14** [V2] Live Activity / Dynamic Island con timer e set corrente.

### 6.5 Summary post workout (`PS-WK`, cont.) — `SCR-WK-07`

- **PS-WK-20** [MVP] Summary: durata, Total Volume (kg o lb, warm-up esclusi), hard sets per gruppo, PR (peso, reps, e1RM, volume), Muscles Trained (mini MuscleMap), Performance vs Previous (per esercizio, delta %), Estimated Recovery (ore stimate per gruppo principale), commento JEV.
  - AC: ogni valore è calcolato da WorkoutEngine/RecoveryEngine; il commento JEV cita solo questi valori.
- **PS-WK-21** [MVP] Rating sessione opzionale (fatica percepita 1–5) e nota libera.
- **PS-WK-22** [MVP] Salvataggio: write su HealthKit come workout "Traditional Strength Training" se il toggle è attivo (PS-HK-05).
- **PS-WK-23** [V2] Condivisione immagine del summary.

### 6.6 Progressive overload (`PS-PO`)

- **PS-PO-01** [MVP] Double progression di default: quando tutti i working set raggiungono il top del rep range con RIR ≥ target, la sessione successiva aumenta il carico del minimo incremento disponibile; altrimenti progressione sulle reps.
  - AC: test di accettazione con fixture: 3×8 @ 80 kg RIR 2 su range 6–8 → proposta 82,5 kg × 6–8.
- **PS-PO-02** [MVP] Esiti possibili per esercizio: Aumenta carico, Aumenta reps, Mantieni, Regressione, Deload. Ogni esito ha un reason code visualizzabile.
- **PS-PO-03** [MVP] Incrementi rispettano l'attrezzatura: bilanciere 2,5 kg (5 lb), manubri secondo range dichiarato, macchine step configurabile per esercizio.
- **PS-PO-04** [MVP] Plateau detection: ≥ 6 esposizioni in ≥ 21 giorni (deload esclusi) con pendenza dell'e1RM stabile non significativamente sopra +0,25%/settimana (IC 80%) e nessun PR di reps — vedi ARCHITECTURE_PLAN §5.7 → raccomandazione JEV (cambio rep range, variante, deload locale).
- **PS-PO-05** [MVP] e1RM: Epley/Brzycki su set con reps ≤ 12 e RIR noto; la UI mostra la "stima stabile" (da storico, smoothed) e non il singolo set. Valori singoli disponibili nel dettaglio.
  - AC: un singolo set anomalo non sposta la stima stabile più del limite definito dall'engine.
- **PS-PO-06** [MVP] Regola "primo set": il target live può essere ricalcolato dopo il primo working set se RIR reale si discosta di ≥ 2 dal target (es. "Primo set RIR 0: secondo set 80 kg"). Proposta mostrata, non imposta.
- **PS-PO-07** [MVP] Deload: pianificato (al massimo ogni N settimane, default 6) o reattivo (fatica/performance in calo). Deload = −40–50% set, carichi −10% *(proposta)*. Sempre proposto via check-in o JEV, mai attivato in silenzio.

### 6.7 Recovery & Body (`PS-RC`) — `SCR-BODY-01..02`

- **PS-RC-01** [MVP] RecoveryEngine calcola recovery 0–100 per 17 gruppi: petto, dorsali, trapezi/alta schiena, deltoidi anteriori, deltoidi laterali, deltoidi posteriori, bicipiti, tricipiti, avambracci, addominali, obliqui, lombari, glutei, quadricipiti, femorali, adduttori, polpacci.
- **PS-RC-02** [MVP] Body screen: mappa grafica originale fronte/retro, colore semantico per fascia di recovery (sezione 8.3), percentuale accessibile via tap e VoiceOver.
  - AC: ogni gruppo ha un'area tappabile ≥ 44 pt (o è selezionabile dalla lista sotto la mappa).
- **PS-RC-03** [MVP] Tap su gruppo → sheet con: last trained (data + sessione), sets (ultimi 7 giorni, hard sets), volume (7 giorni vs media 4 settimane), recovery estimate (% + ore a ≥ 90%), next recommended training (sessione del programma che lo allena + data stimata).
- **PS-RC-04** [MVP] Workout HealthKit non di forza (corsa, bici, ecc.) contribuiscono al carico dei gruppi pertinenti con peso ridotto, marcati "da Salute".
- **PS-RC-05** [MVP] Aree con limitazione dichiarata mostrano un badge; il tap mostra la nota dell'utente.
- **PS-RC-06** [V2] Misure corporee (circonferenze) e foto progressi nella tab Corpo.

### 6.8 JEV READINESS (`PS-RD`) — `SCR-BODY-03`

- **PS-RD-01** [MVP] ReadinessEngine produce 0–100 con fascia testuale: 0–39 "Basso", 40–64 "Moderato", 65–84 "Buono", 85–100 "Alto" *(soglie proposta)*, e confidence.
- **PS-RD-02** [MVP] Input disponibili, pesati dall'engine: recovery dei gruppi della prossima sessione, carico acuto/cronico, sonno (HK o manuale), HRV e resting HR vs baseline personale (se disponibili da HK), check soggettivo opzionale (energia, dolori, sonno 1–5).
- **PS-RD-03** [MVP] Senza HealthKit: readiness da carico + recovery + check soggettivo; confidence ridotta e label "Stima parziale".
  - AC: con HK negato la readiness è comunque visibile entro il primo giorno successivo a un workout loggato.
- **PS-RD-04** [MVP] Dettaglio readiness: contributo di ogni fattore (barre +/−), dati usati con fonte (HK/Manuale/Calcolato), confidence.
- **PS-RD-05** [MVP] La readiness non cambia mai automaticamente il workout (vedi PS-PG-08).

### 6.9 Nutrizione: target, macro, expenditure (`PS-NU`) — `SCR-NU-01, 10, 11`

- **PS-NU-01** [MVP] Stima iniziale BMR/TDEE dall'onboarding (formula scelta dal NutritionEngine; Katch-McArdle se body fat noto). La stima iniziale perde peso man mano che arrivano calorie loggate e trend peso.
- **PS-NU-02** [MVP] Expenditure mostrata come "TDEE 2.740 kcal · Confidence 91%" con trend 7 e 21 giorni.
  - AC: confidence < 50% → label "Stima iniziale"; 50–79% "In calibrazione"; ≥ 80% "Affidabile" *(soglie proposta)*.
- **PS-NU-03** [MVP] Giorni con logging incompleto: l'utente può marcare un giorno "Incompleto"; i giorni incompleti sono esclusi dal calcolo dell'expenditure. Default: giorno con < 50% del target loggato a fine giornata viene proposto come incompleto.
- **PS-NU-04** [MVP] Macro: protein, carbs, fat, fiber. Modalità:
  - **AUTO**: l'engine imposta e aggiorna tutto al check-in.
  - **ASSISTED**: l'utente fissa proteine (g/kg) e preferenza carbs/fat (bilanciato, low fat, low carb); l'engine calcola il resto.
  - **MANUAL**: l'utente inserisce calorie e grammi; l'engine non modifica, ma il check-in può suggerire.
  - AC: in MANUAL nessun valore cambia senza azione dell'utente.
- **PS-NU-05** [MVP] Limiti di sicurezza *(proposta)*: target automatico mai < max(BMR stimato, 1.200 kcal); proteine AUTO 1,6–2,2 g/kg (fino a 2,4 g/kg in dimagrimento); fibra ≥ 14 g/1.000 kcal come target.
  - AC: in MANUAL un target < 1.200 kcal è consentito solo dopo conferma con SafetyNotice.
- **PS-NU-06** [MVP] Calorie differenziate allenamento/riposo (toggle, default ON per Forza/Ipertrofia/Ricomposizione): delta max ±15% *(proposta)*, media settimanale preservata.
  - AC: somma dei target dei 7 giorni = 7 × target medio (±1 kcal per arrotondamento).
- **PS-NU-07** [MVP] Se l'utente si allena in un giorno pianificato di riposo, il giorno diventa "allenamento" e i giorni rimanenti della settimana si ribilanciano entro i limiti; se salta un allenamento, il giorno resta com'era (nessuna penalità retroattiva).
- **PS-NU-08** [MVP] Aggiustamento settimanale solo al check-in: variazione automatica proposta |Δ| ≤ 150 kcal/die per check-in *(proposta)*.
- **PS-NU-09** [MVP] Unità energia kcal/kJ; i target sono memorizzati in kcal e visualizzati convertiti.
- **PS-NU-10** [V2] Micronutrienti, acqua, target per singolo pasto.

### 6.10 Food logger (`PS-FL`) — `UF-06`, `SCR-NU-02..09`

- **PS-FL-01** [MVP] Punto d'ingresso unico: "+" globale in Nutrizione e "+" per pasto (Colazione, Pranzo, Cena, Snack). Il pasto è preselezionato in base all'ora (modificabile).
- **PS-FL-02** [MVP] Logger con segmenti: Cerca, Recenti, Preferiti, Ricette, Miei (custom). Pulsanti sempre visibili: Barcode, Quick add.
  - AC: aprendo il logger, la lista Recenti è visibile in < 300 ms anche offline.
- **PS-FL-03** [MVP] Search: prima DB locale + cache, poi provider online (Open Food Facts) se disponibile. Risultati locali mostrati subito; quelli online si aggiungono senza far "saltare" la lista (sezione separata).
  - AC: offline, la ricerca restituisce risultati locali/recenti/custom e mostra "Risultati online non disponibili".
- **PS-FL-04** [MVP] FoodProvider intercambiabili: interfaccia unica, provenienza visibile (SourceTag: "Database", "Open Food Facts", "Personale").
- **PS-FL-05** [MVP] Barcode con fotocamera: trovato localmente → dettaglio porzione; non trovato localmente e online → lookup OFF; non trovato ovunque → "Crea alimento" precompilato con il codice. Offline e non in cache → stessa opzione + Quick add.
  - AC: un alimento custom creato da barcode viene trovato alla scansione successiva dello stesso codice, offline.
- **PS-FL-06** [MVP] Porzioni: grammi/ml, porzione dichiarata dal prodotto, unità naturali ("1 uovo"), multipli (0,5×, 1×, 2×). Ultima porzione usata ricordata per alimento.
- **PS-FL-07** [MVP] Alimento custom: nome, marca (opz.), kcal, P/C/F, fibra (opz.), base 100 g o per porzione, barcode (opz.).
- **PS-FL-08** [MVP] Quick add: calorie e/o macro senza alimento; se mancano le kcal sono calcolate da P/C/F (4/4/9); se mancano i macro, la voce conta solo per le calorie.
- **PS-FL-09** [MVP] Ricette base: ingredienti con grammi, numero porzioni o peso finale cotto; log per porzioni o grammi. Modificare una ricetta non altera i log passati (snapshot).
- **PS-FL-10** [MVP] Copia: "Copia ieri" (giorno intero), "Copia pasto" da qualsiasi data in qualsiasi pasto; anteprima con totale kcal prima di confermare.
- **PS-FL-11** [MVP] Preferiti (stella) e storico per giorno con navigazione date.
- **PS-FL-12** [MVP] Giorno nutrizionale = giorno locale dell'utente al momento del log. Tra 00:00 e 04:00 il logger mostra il toggle "Aggiungi a ieri".
- **PS-FL-13** [MVP] Dati da Open Food Facts marcati "Dati community — verifica l'etichetta"; l'utente può "Salva come personale" per correggerli.
- **PS-FL-14** [V2] Food logging da foto con AI; ricerca vocale.

### 6.11 Peso (`PS-WT`) — `UF-07`, `SCR-WT-01`, `SCR-PR-02`

- **PS-WT-01** [MVP] Pesata manuale da Home (card pesata), Corpo e Progressi; precompilata con l'ultimo valore, BigStepper 0,1 kg / 0,2 lb.
- **PS-WT-02** [MVP] Import da HealthKit (body mass, body fat %). Le pesate scritte dalla nostra app non vengono re-importate.
- **PS-WT-03** [MVP] Deduplica: stesso valore (±0,05 kg) entro 10 minuti da fonti diverse = una sola pesata (prevale la manuale).
- **PS-WT-04** [MVP] Più pesate nello stesso giorno sono tutte conservate; valore giornaliero = prima pesata del giorno (default) o media (impostazione).
- **PS-WT-05** [MVP] Trend peso con filtro robusto (NutritionEngine/WeightTrend): una singola pesata anomala non sposta il trend oltre il limite definito dall'engine.
  - AC: fixture con pesata +2,5 kg isolata → trend varia < 0,2 kg *(soglia da allineare con engine)*.
- **PS-WT-06** [MVP] Conferma soft per possibili errori di battitura: scostamento > 3% dal trend → "Confermi 84,1 kg? È 2,6 kg sopra il trend." Mai bloccante.
- **PS-WT-07** [MVP] Visualizzazione: peso del giorno secondario, trend primario ("Trend 78,6 kg · −0,4 kg/sett.").

### 6.12 Weekly check-in (`PS-CI`) — `UF-08`, `SCR-CI-01..04`

- **PS-CI-01** [MVP] Frequenza: ogni 7 giorni nel giorno scelto (default lunedì, disponibile dalle 05:00). Rinviabile di 24/48 h. Non completato entro 3 giorni → archiviato come "Saltato", piano invariato.
- **PS-CI-02** [MVP] CheckInEngine calcola: Weight Trend, Expenditure, Average Calories, Protein adherence, Workout adherence, Strength trend, Training volume, Recovery, Readiness, Goal progress.
- **PS-CI-03** [MVP] Decisioni possibili (una o più): KEEP, INCREASE CALORIES, DECREASE CALORIES, CHANGE MACROS, REDUCE TRAINING LOAD, INCREASE TRAINING LOAD, DELOAD, CHANGE EXERCISE, NO ACTION.
- **PS-CI-04** [MVP] Ogni decisione mostra: numeri deterministici (prima → dopo), WHY/DATA USED/CONFIDENCE, testo JEV. Azioni: Accetta / Modifica / Rifiuta. Pulsante "Accetta tutto".
  - AC: nessuna modifica al piano finché l'utente non conferma; rifiutare lascia il valore precedente.
- **PS-CI-05** [MVP] Modifica entro limiti *(proposta)*: calorie ±250 kcal/die dal valore attuale e mai sotto il floor PS-NU-05; volume ±20% per gruppo; cambio esercizio solo con alternative da ExerciseScore.
  - AC: lo stepper di modifica si ferma ai limiti e mostra il motivo.
- **PS-CI-06** [MVP] Dati insufficienti (< 4 pesate o < 4 giorni loggati completi *(proposta)*): check-in parziale; le decisioni nutrizionali diventano NO ACTION con motivo "Dati insufficienti", quelle di allenamento restano.
- **PS-CI-07** [MVP] Storico check-in consultabile dallo sheet JEV, con decisione proposta vs decisione finale.
- **PS-CI-08** [MVP] Il check-in funziona offline (numeri + testo template); il testo AI viene aggiunto quando torna la rete, senza cambiare i numeri.

### 6.13 JEV (`PS-JEV`) — `UF-09`, `SCR-JEV-*`

- **PS-JEV-01** [MVP] JEV non è un tab. Punti d'accesso: (a) card JEV TODAY in Oggi; (b) pulsante JEV nella navigation bar di ogni tab → JEV sheet; (c) commenti nel summary workout e nel check-in.
- **PS-JEV-02** [MVP] JEV sheet: Consiglio di oggi, Raccomandazioni attive (con WDC), Chiedi a JEV (chat contestuale), Storico check-in. Il contesto della tab di origine ordina raccomandazioni e domande suggerite.
- **PS-JEV-03** [MVP] Ogni raccomandazione ha un pannello WHY / DATA USED / CONFIDENCE quando disponibile. DATA USED elenca metriche, periodo e fonte.
- **PS-JEV-04** [MVP] Regola dei numeri: JevCoach riceve un payload strutturato (valori + reason code). Ogni numero nel testo generato deve corrispondere a un valore del payload (con arrotondamenti di formato); altrimenti il testo è scartato e si usa il template.
  - AC: test automatico su set di prompt: 100% dei numeri nel testo mostrato è presente nel payload.
- **PS-JEV-05** [MVP] Offline o senza account: testo deterministico da template per reason code (stessa struttura, tono asciutto). Label discreta "Spiegazione offline".
  - AC: con rete disattivata, card JEV TODAY e raccomandazioni sono sempre popolate se esistono reason code.
- **PS-JEV-06** [MVP] Chat: richiede account + rete. Senza: campo disabilitato con motivazione e CTA ("Accedi per parlare con JEV" / "Torna online per la chat"). Le domande suggerite con risposta template restano disponibili offline.
- **PS-JEV-07** [MVP] Tono: diretto, sintetico, data-driven, motivante senza frasi vuote. Max 3 frasi nella card, max 120 parole in chat salvo richiesta. Niente emoji, niente esclamazioni multiple, niente "Ottimo lavoro!" senza dato.
  - Esempio: "Performance ottima. Panca +4,8% nelle ultime tre settimane e recupero petto al 94%. Domani aumenterei da 82,5 kg a 85 kg mantenendo target 8 reps. Se il primo set scende sotto RIR 1, resta a 82,5."
- **PS-JEV-08** [MVP] Raccomandazioni azionabili ("Applica al prossimo workout", "Applica target") passano sempre per validazione engine prima di modificare il piano.
- **PS-JEV-09** [MVP] Le risposte chat che toccano salute rispettano PS-SAF.
- **PS-JEV-10** [V2] Provider AI on-device; App Intents/Siri ("Chiedi a JEV quanto caricare").

### 6.14 Progressi (`PS-PR`) — `SCR-PR-01..03`

- **PS-PR-01** [MVP] Grafici: Weight, Weight Trend, Calories, TDEE, Energy Balance, Protein, Carbs, Fat, Strength (indice aggregato), Estimated 1RM (per esercizio), Training Volume, Workout Frequency, Recovery (media), Readiness.
- **PS-PR-02** [MVP] Filtri: 7g, 30g, 3m, 6m, 1a, Tutto. Il filtro scelto è ricordato per sessione.
- **PS-PR-03** [MVP] Ogni grafico: valore corrente, delta sul periodo, media; tap-and-hold per valore puntuale; Audio Graph / descrizione VoiceOver.
- **PS-PR-04** [MVP] Weight e Weight Trend nello stesso grafico (punti = pesate, linea = trend).
- **PS-PR-05** [MVP] Strength: lista esercizi principali con e1RM stabile e trend; dettaglio esercizio con storico set e PR.
- **PS-PR-06** [MVP] Stati vuoti per ogni grafico con quanti dati mancano ("Ancora 3 pesate per mostrare il trend").

### 6.15 HealthKit (`PS-HK`) — `UF-02`, `SCR-SET-03`

- **PS-HK-01** [MVP] Letture: body mass, body fat %, step count, active energy, workouts, sleep, resting HR, HRV, heart rate.
- **PS-HK-02** [MVP] Pre-permesso: per ogni tipo, una riga "cosa leggiamo → a cosa serve" (es. "Sonno → JEV READINESS"). Mai richiesta di permessi senza spiegazione.
- **PS-HK-03** [MVP] Permessi parziali: ogni feature degrada al proprio fallback manuale (sezione 7) e lo dichiara nella UI con PermissionCallout.
- **PS-HK-04** [MVP] Revoca successiva: all'avvio/foreground l'app rileva l'assenza di nuovi dati e mostra in Impostazioni → Salute lo stato "Nessun dato recente"; nessun popup ripetuto.
- **PS-HK-05** [MVP] Scritture opzionali con toggle separati (default OFF, proposti in onboarding): workout completati, peso inserito, nutrizione (dietary energy, protein, carbs, fat, fiber).
  - AC: disattivando un toggle, nessuna nuova scrittura di quel tipo; i dati già scritti restano in Salute.
- **PS-HK-06** [MVP] Dati HK marcati con SourceTag "Salute" ovunque compaiano.

### 6.16 Notifiche (`PS-NT`) — `UF-14`, `SCR-SET-04`

| ID | Notifica | Default | Note |
|---|---|---|---|
| PS-NT-01 [MVP] | Promemoria pesata mattutina | ON se l'utente ha scelto "pesata quotidiana", 07:30 | Non inviata se la pesata esiste già |
| PS-NT-02 [MVP] | Promemoria log pasti | OFF | Orari per pasto; non inviata se il pasto è già loggato |
| PS-NT-03 [MVP] | Fine timer recupero | ON | Solo con app in background |
| PS-NT-04 [MVP] | Promemoria workout | ON nei giorni preferiti, orario scelto | Non inviata se workout già fatto |
| PS-NT-05 [MVP] | Weekly check-in pronto | ON | Una sola volta + 1 promemoria a 24 h |

- **PS-NT-06** [MVP] Limite: max 2 notifiche non-timer al giorno; quiet hours 22:00–07:00 configurabili.
- **PS-NT-07** [MVP] Se una categoria viene ignorata 14 volte consecutive, JEV propone (in-app, una volta) di disattivarla.
- **PS-NT-08** [MVP] Ogni notifica apre il deep link pertinente (vedi SCREEN_MAP).

### 6.17 Account, sync, dati (`PS-AC`) — `UF-12`, `UF-13`, `SCR-SET-05`

- **PS-AC-01** [MVP] Nessun account richiesto. Sign in with Apple opzionale per sync e JEV AI online.
- **PS-AC-02** [MVP] Prima attivazione sync con dati locali: upload completo dei dati locali; nessuna perdita.
- **PS-AC-03** [MVP] Login su dispositivo con dati locali e dati cloud: merge per ID univoco; nessun duplicato; conflitti sullo stesso record → vince la modifica più recente; i set di un workout non vengono mai eliminati da un merge.
  - AC: test: stesso workout presente su due dispositivi → 1 workout dopo il merge.
- **PS-AC-04** [MVP] Stato sync visibile in Impostazioni (ultima sync, errori). In Home solo se l'errore persiste > 24 h.
- **PS-AC-05** [MVP] Export dati (JSON + CSV per workout, nutrizione, peso), eliminazione dati locali, eliminazione account (dati cloud inclusi).
- **PS-AC-06** [MVP] Senza account, Impostazioni avvisa: "I tuoi dati sono solo su questo iPhone (inclusi nei backup del dispositivo)."
- **PS-AC-07** [V2] Abbonamenti StoreKit.

### 6.18 Impostazioni, unità, lingua (`PS-ST`) — `UF-11`, `SCR-SET-*`

- **PS-ST-01** [MVP] Unità peso kg/lb, energia kcal/kJ, altezza cm/ft-in, indipendenti. Storage interno metrico.
- **PS-ST-02** [MVP] Cambio unità: tutta la UI si aggiorna; target di carico convertiti e arrotondati all'incremento valido nella nuova unità; storico mostrato convertito (valore originale conservato).
  - AC: 100 kg → 220,5 lb mostrati nello storico; target prossimo arrotondato a 220 lb (incremento 5 lb).
- **PS-ST-03** [MVP] Lingua: segue il sistema (IT/EN), override in app.
- **PS-ST-04** [MVP] Aspetto: Sistema/Chiaro/Scuro.
- **PS-ST-05** [MVP] Profilo modificabile: obiettivo (UF-10), dati corpo, attrezzatura, esclusioni, limitazioni, giorni, split, macro mode, giorno check-in, RPE on/off, formato pesata giornaliera.

### 6.19 Accessibilità (`PS-A11Y`)

- **PS-A11Y-01** [MVP] Dynamic Type fino a AX3 su tutte le schermate; layout che passa da orizzontale a verticale ai size accessibili.
- **PS-A11Y-02** [MVP] VoiceOver: ogni metrica legge valore + unità + fascia ("Readiness 72, buono"); MuscleMap navigabile come lista.
- **PS-A11Y-03** [MVP] Contrasto ≥ 4.5:1 per testo, ≥ 3:1 per elementi grafici; colore mai unico portatore di significato (sempre label o simbolo).
- **PS-A11Y-04** [MVP] Reduce Motion: niente animazioni di anelli/numeri, solo crossfade.
- **PS-A11Y-05** [MVP] Haptics disattivabili.

---

## 7. Comportamento con dati mancanti

| Area | Dato mancante | Comportamento |
|---|---|---|
| Readiness | Nessun HK (sonno/HRV/RHR) | Calcolo da carico + recovery + check soggettivo; label "Stima parziale"; confidence ridotta |
| Readiness | Nessun workout ancora | Readiness mostrata come "—" con "Completa il primo workout per calibrare"; JEV usa solo sonno/soggettivo se presenti |
| Recovery | Gruppo mai allenato | 100% con label "Nessun dato"; colore neutro (non Mint) |
| Recovery | Storico < 2 settimane | Stima con curva di default per esperienza; confidence bassa |
| Overload | Esercizio nuovo senza storico | Target da e1RM di esercizi correlati se disponibili, altrimenti "Primo set esplorativo: scegli un carico da RIR 3" |
| Expenditure | < 7 giorni di log + pesate | Mostra stima formula, "Stima iniziale", confidence bassa |
| Expenditure | Giorni incompleti | Esclusi; se > 50% della finestra è escluso, confidence ridotta e nota |
| Peso | Nessuna pesata in 7 giorni | Trend congelato all'ultimo valore con "Ultima pesata 9 gg fa"; check-in nutrizionale = NO ACTION |
| Peso | Una sola pesata | Mostra valore, trend "In calcolo" |
| Nutrizione | Giorno senza log | Home: Remaining = target; nessun messaggio colpevolizzante; nel check-in conta come non loggato |
| Macro | Alimento senza fibra/macro | Conteggiato per i valori disponibili; badge "Dati parziali" nel dettaglio |
| Check-in | Dati insufficienti | Check-in parziale (PS-CI-06) |
| Goal progress | Target weight non impostato | Goal progress basato sull'obiettivo qualitativo (es. forza: indice Strength vs inizio fase) |
| JEV | Offline / no account | Template deterministici (PS-JEV-05) |
| HK | Permessi revocati | Fallback manuali, stato in Impostazioni, nessun popup |
| Sonno | Nessuna fonte | Check soggettivo opzionale in readiness (1 tap: Male/Ok/Bene) |

---

## 8. Design & identità visiva

### 8.1 Concept: "Instrument"
JEV FIT è uno **strumento di misura**, non un poster da palestra. Riferimenti concettuali: cronografo, strumentazione di bordo, tipografia tecnica. Superfici scure profonde, numeri come protagonisti, colore usato solo per significato. Nessuna foto stock, nessun gradiente decorativo, nessuna illustrazione di atleti.

Elementi firma (originali):
1. **Ion Rail** — una barra verticale di 3 pt colore Ion a sinistra di ogni contenuto scritto da JEV. L'utente distingue sempre "dato" da "interpretazione".
2. **Data ticks** — sottili tacche (hairline) sotto i numeri eroe e nei grafici, come scale di uno strumento.
3. **Unit-light** — unità e suffissi al 55–60% della dimensione del numero, peso Regular, colore secondario: "82,5 kg" dove "kg" è sottovoce.
4. **Source tag** — micro-etichette maiuscole (SALUTE · MANUALE · STIMA · OFF) accanto ai dati, in SF Mono 10–11 pt.
5. **Mappa muscolare sfaccettata** — silhouette geometrica a pannelli (stile low-poly pulito), non anatomia realistica.

### 8.2 Palette (token semantici, varianti light/dark)

| Token | Ruolo | Dark | Light |
|---|---|---|---|
| `bg.base` | Sfondo app | Graphite #0B0C0E | Bone #F4F3EF |
| `bg.card` | Card | #15171A | #FFFFFF |
| `bg.elevated` | Sheet, card annidate | #1D2024 | #FAFAF8 |
| `line.hairline` | Separatori, data ticks | #2A2E33 | #E3E1DC |
| `text.primary` / `text.secondary` | Testo | #F2F2F0 / #8E949B | #111214 / #6B7077 |
| `accent.ion` | JEV, CTA primarie | Ion #7C8BFF | Ion #3F4FF0 |
| `scale.1` Ember | 0–39 | #FF5A36 | #E0401E |
| `scale.2` Amber | 40–64 | #FFAA2C | #C77A00 |
| `scale.3` Citrine | 65–84 | #CFE34A | #7E8F00 |
| `scale.4` Mint | 85–100 | #2ED3A0 | #0E9A70 |
| `macro.protein` | Proteine | Orchid #B66DFF | #8A3FE0 |
| `macro.carbs` | Carboidrati | Sky #33B5FF | #0A84C8 |
| `macro.fat` | Grassi | Rose #FF6FA3 | #D23F77 |
| `macro.fiber` | Fibra | Sage #8FB996 | #4F8A5A |
| `state.pr` | Personal record | Gold #F5C451 | #A57A00 |

Regole: la scala Ember→Mint è usata **solo** per recovery e readiness; Ion **solo** per JEV e CTA primarie; i colori macro solo per macro. Tutti i valori sono proposte da validare per contrasto (PS-A11Y-03). Il colore è sempre accompagnato da label di fascia.

### 8.3 Scala semantica recovery/readiness
| Fascia | Range | Colore | Label recovery | Label readiness | Glifo |
|---|---|---|---|---|---|
| 1 | 0–39 | Ember | Affaticato | Basso | 1 tacca su 4 |
| 2 | 40–64 | Amber | In recupero | Moderato | 2 tacche |
| 3 | 65–84 | Citrine | Quasi pronto | Buono | 3 tacche |
| 4 | 85–100 | Mint | Pronto | Alto | 4 tacche |

### 8.4 Tipografia
| Livello | Uso | Font | Esempio |
|---|---|---|---|
| H0 Hero number | Readiness, calorie rimaste, peso trend | SF Pro Rounded Bold, 56–64 pt (scala con Dynamic Type), cifre monospaziate | 72 |
| H1 Key metric | Valori nelle card | SF Pro Rounded Semibold 28–34 pt | 2.740 kcal |
| Data | Tabelle set, valori nutrizionali, grafici | SF Mono Medium 15–17 pt | 82,5 × 8 @ RIR 2 |
| Title | Titoli schermate/card | SF Pro Display Semibold | Workout di oggi |
| Body | Testo, JEV | SF Pro Text Regular 17 pt | — |
| Meta | Source tag, timestamp | SF Mono 11 pt, maiuscolo, tracking +4% | SALUTE · 07:12 |

Gerarchia dei numeri: un solo H0 per schermata; H1 al massimo 4 per card; i delta (DeltaBadge) usano segno esplicito e freccia SF Symbol, colore neutro salvo PR (Gold). Separatore decimale e migliaia secondo locale (IT: "82,5", "2.740").

### 8.5 Forma, layout, motion
- Card: raggio 22 pt continuo, padding 16 pt, nessuna ombra in dark, ombra 1% in light; griglia 8 pt.
- Margini laterali 16 pt; spaziatura tra card 12 pt.
- Icone: solo SF Symbols, rendering hierarchical.
- Motion: `numericText` per numeri che cambiano; anelli che si riempiono in 400 ms ease-out; nessun bounce eccessivo. Reduce Motion rispettato.
- Haptics: `.success` set completato, `.impact(light)` stepper, `.notification(.success)` + Gold flash su PR.

### 8.6 Differenziazione da benchmark
Fitbod e MacroFactor sono benchmark **solo funzionali** (es. esistenza di una mappa recovery, di un'expenditure adattiva). JEV FIT non riprende: nomi di feature, testi, palette, stile grafico della mappa muscolare, layout di schermate o sequenze di flusso identiche. Differenze intenzionali: JEV con Ion Rail e WDC, check-in unico allenamento+nutrizione, scala recovery warm→cool a 4 fasce con glifi, mappa sfaccettata, numeri in SF Rounded/SF Mono.

---

## 9. AI safety (`PS-SAF`)

- **PS-SAF-01** [MVP] JEV non diagnostica, non nomina patologie come ipotesi, non suggerisce farmaci o integratori a dosaggio.
- **PS-SAF-02** [MVP] Trigger con SafetyNotice (card non rimovibile per 24 h, testo chiaro, link "Perché lo vedo"):
  - dolore segnalato sullo stesso gruppo/area in ≥ 2 sessioni entro 14 giorni, o un dolore "forte";
  - perdita di peso trend > 1,5% del peso/settimana per 2 settimane consecutive *(proposta)*;
  - intake medio < 1.000 kcal/die su 7 giorni con ≥ 5 giorni loggati completi *(proposta)*;
  - sintomi riportati in chat (vertigini, dolore al petto, svenimento, ecc.): JEV interrompe il coaching e indica di rivolgersi a un medico; per sintomi acuti, "contatta subito i servizi di emergenza (112)".
  - Testo tipo: "Hai segnalato dolore alla spalla in 3 sessioni su 2 settimane. Non posso valutarne la causa: parlane con un medico o un fisioterapista. Nel frattempo ho tolto le spinte sopra la testa dalle proposte."
- **PS-SAF-03** [MVP] Dopo un trigger: nessun aumento automatico di carico sul gruppo interessato e nessuna riduzione calorica proposta finché l'utente non conferma di aver letto.
- **PS-SAF-04** [MVP] Nessuna modifica estrema automatica: limiti PS-NU-05, PS-NU-08, PS-CI-05, PS-PO-07 sono hard constraint degli engine, non della UI.
- **PS-SAF-05** [MVP] Disclaimer in onboarding (1 schermata, leggibile, non legalese) e in Impostazioni → Info.
- **PS-SAF-06** [MVP] Rate of change fuori range non selezionabile; target weight che porterebbe a BMI < 18,5 mostra avviso e non è selezionabile come obiettivo automatico *(proposta)*.
- **PS-SAF-07** [MVP] JEV evita linguaggio colpevolizzante su cibo e peso ("sgarro", "hai sbagliato").

---

## 10. Privacy (punto di vista utente)

Cosa l'utente deve poter capire in 30 secondi (schermata Impostazioni → Privacy):
1. **Senza account, tutto resta sul tuo iPhone.** Nessun dato lascia il dispositivo, salvo ricerche alimenti e barcode verso Open Food Facts (solo il testo cercato o il codice, nessun dato personale).
2. **Con account:** i dati vengono sincronizzati sul nostro cloud, cifrati in transito e a riposo, per averli su più dispositivi.
3. **JEV AI online:** riceve un riepilogo strutturato (metriche calcolate, non lo storico grezzo di Salute) solo quando chiedi o quando genera un consiglio. Toggle "JEV AI online" disattivabile: JEV torna ai template.
4. **Dati Salute:** mai usati per pubblicità, mai venduti, mai condivisi con terzi diversi dal provider AI indicato.
5. **Controllo:** export completo, eliminazione dati, eliminazione account in app.
6. **Permessi granulari:** ogni tipo HealthKit e ogni scrittura è indipendente.

---

## 11. Metriche di successo

### 11.1 Uso personale (MVP, primi 60 giorni)
| Metrica | Target |
|---|---|
| Onboarding completato, tempo mediano | < 4 min |
| Tempo per loggare un set con valori target | ≤ 1 s, 1 tap |
| Tempo per loggare un alimento dai recenti | ≤ 5 s |
| Giorni nutrizione loggati completi / settimana | ≥ 5 |
| Pesate / settimana | ≥ 4 |
| Workout completati / pianificati | ≥ 85% |
| Check-in completati | ≥ 80% delle settimane |
| Decisioni check-in accettate (senza modifica) | ≥ 60% (indicatore di fiducia) |
| Confidence expenditure ≥ 80% | entro 28 giorni |

### 11.2 Qualità
| Metrica | Target |
|---|---|
| Crash-free sessions | ≥ 99,8% |
| Workout in corso persi | 0 |
| Duplicati dopo sync/merge | 0 |
| Numeri nei testi JEV non presenti nel payload | 0 (test automatici) |
| Flussi core funzionanti in modalità aereo | 100% |

### 11.3 Commerciali future (V2+)
Retention D30, % utenti con check-in 4 settimane consecutive, conversione abbonamento, NPS.

---

## 12. Glossario

| Termine | Definizione |
|---|---|
| **RIR** | Reps In Reserve: ripetizioni che avresti potuto ancora fare. RIR 0 = cedimento. |
| **RPE** | Rating of Perceived Exertion (6–10). Con i pesi, RPE ≈ 10 − RIR. |
| **e1RM** | Estimated One-Rep Max: massimale stimato da un set sub-massimale (Epley, Brzycki). |
| **e1RM stabile** | Stima smussata su più sessioni, resistente a singoli set anomali. |
| **Epley / Brzycki** | Formule e1RM: Epley = w·(1 + r/30); Brzycki = w·36/(37 − r). |
| **Double progression** | Prima aumenti le reps fino al top del range, poi il carico. |
| **Deload** | Settimana/sessioni a volume e intensità ridotti per smaltire fatica. |
| **Plateau** | Nessun progresso misurabile per più esposizioni consecutive. |
| **Hard set** | Working set con RIR ≤ 4; unità base del volume per muscolo. |
| **Volume / Tonnage** | Volume: hard set per gruppo. Tonnage: Σ carico × reps (warm-up esclusi). |
| **Top set / Back-off** | Set più pesante della sessione / set successivi a carico ridotto. |
| **Drop set / AMRAP** | Set con riduzione del carico senza pausa / "as many reps as possible". |
| **Split** | Divisione dei gruppi muscolari tra le sessioni (es. Upper/Lower). |
| **Mesociclo** | Blocco di più settimane con progressione e deload. |
| **BMR** | Basal Metabolic Rate: consumo a riposo. |
| **TDEE / Expenditure** | Total Daily Energy Expenditure: consumo totale giornaliero; in JEV FIT stimato in modo adattivo da calorie loggate e trend peso. |
| **Energy balance** | Calorie assunte − expenditure. |
| **Weight trend** | Peso filtrato che rappresenta la tendenza reale, robusto alle oscillazioni giornaliere. |
| **Rate of change** | Variazione di peso desiderata per settimana (% del peso). |
| **Recomposition** | Ricomposizione: perdere grasso e aumentare massa a peso circa stabile. |
| **Recovery** | Stima 0–100 di quanto un gruppo muscolare è pronto a essere riallenato. |
| **JEV READINESS** | Stima 0–100 di prontezza complessiva per allenarsi oggi. |
| **Adherence** | Aderenza: % di target rispettati (proteine, workout). |
| **Confidence** | Affidabilità 0–100% di una stima, calcolata dall'engine. |
| **Reason code** | Codice stabile prodotto da un engine che motiva un output (es. `PO_LOAD_INCREASE_TOP_RANGE`). |
| **WDC** | Pannello WHY / DATA USED / CONFIDENCE. |
| **ExerciseScore** | Punteggio dell'engine per scegliere o sostituire esercizi. |
| **HRV / RHR** | Heart Rate Variability / Resting Heart Rate, da Salute. |
| **Quick add** | Inserimento rapido di calorie/macro senza alimento. |
| **Check-in** | Revisione settimanale con decisioni sul piano. |

---

## 13. Domande aperte (sintesi; dettaglio nel report al CTO)
1. Superset/circuiti nell'MVP o V2?
2. Soglie *(proposta)* di sicurezza e confidence: confermare con le spec di NutritionEngine/ReadinessEngine.
3. Provider JEV AI online e quota messaggi chat.
4. Valore giornaliero del peso: prima pesata (default proposto) vs media.
5. Backend sync (CloudKit vs backend proprietario) — impatta copy privacy.
