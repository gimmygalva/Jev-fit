# BRIEF ORIGINALE — JEV FIT

Testo fornito dall'utente (Gianmarco) il 2026-10-05, riportato integralmente. È la fonte dei requisiti: in caso di dubbio vale questo documento, interpretato secondo `docs/REQUIREMENTS_AUDIT.md` e `DECISIONS.md`.

---

SEI IL CTO E LEAD ARCHITECT DI UN TEAM MULTI-AGENT.

Devi progettare e sviluppare fino a una versione realmente funzionante un'app iPhone nativa denominata provvisoriamente:

JEV FIT

TARGET
- iOS 18+
- Swift 6
- SwiftUI
- architettura moderna, modulare e production-ready
- utilizzo iniziale personale, ma struttura predisposta per diventare un prodotto commerciale

OBIETTIVO

Creare un'unica applicazione fitness e nutrizione intelligente che combini:

1. generazione e adattamento degli allenamenti;
2. progressive overload;
3. monitoraggio recupero muscolare;
4. diario alimentare;
5. stima dinamica del dispendio energetico;
6. gestione calorie e macronutrienti;
7. andamento del peso;
8. HealthKit;
9. analisi con intelligenza artificiale;
10. un coach AI denominato JEV.

Fitbod e MacroFactor possono essere studiati esclusivamente come benchmark funzionali.

NON copiare:
- codice sorgente proprietario;
- loghi;
- nomi registrati;
- grafica;
- fotografie;
- database proprietari;
- testi protetti;
- formule non pubbliche dichiarate proprietarie.

Implementare algoritmi originali basati su principi pubblicamente documentati della fisiologia dell'esercizio, nutrizione e statistica.

==================================================
PRINCIPIO FONDAMENTALE
==================================================

NON costruire un semplice chatbot che dà consigli.

Il sistema deve avere TRE LIVELLI:

LIVELLO 1 — DATA ENGINE
Dati reali, cronologia, HealthKit, workout, nutrizione, peso.

LIVELLO 2 — DETERMINISTIC ENGINE
Algoritmi nostri e testabili per:
- calorie
- TDEE
- trend peso
- recupero
- volume
- progressive overload
- readiness
- scelta esercizi
- programmazione allenamento
- macro
- verifica obiettivi

LIVELLO 3 — JEV AI
L'AI interpreta i dati prodotti dai primi due livelli.

L'AI NON deve inventare numeri che dovrebbero provenire dagli algoritmi deterministici.

==================================================
TEAM MULTI-AGENT
==================================================

Crea e coordina i seguenti agenti.

AGENT 00 — LEAD ARCHITECT / CTO
Responsabilità:
- guida dell'intero progetto;
- architettura;
- dipendenze;
- integrazione;
- decisioni tecniche;
- code review finale;
- merge delle modifiche;
- gestione roadmap.

Questo agente NON deve implementare indiscriminatamente tutto.
Deve delegare ai team specialistici.

--------------------------------------------------

AGENT 01 — PRODUCT & UX

Studia tutti i flussi necessari.

Definisce:
- onboarding;
- home;
- workout;
- nutrition;
- progress;
- body/recovery;
- JEV;
- impostazioni;
- HealthKit;
- notifiche;
- check-in.

Deve creare:

docs/PRODUCT_SPEC.md
docs/USER_FLOWS.md
docs/SCREEN_MAP.md

UX moderna iOS.

Non clonare graficamente altre applicazioni.

--------------------------------------------------

AGENT 02 — IOS CORE

Responsabile di:

- Swift 6;
- SwiftUI;
- navigation;
- dependency injection;
- app lifecycle;
- design system;
- components;
- accessibility;
- dark/light mode;
- haptics;
- widgets se utili;
- local notifications;
- error handling.

Architettura consigliata:

Feature-based + MVVM dove appropriato.

Evitare overengineering.

--------------------------------------------------

AGENT 03 — DATA ARCHITECT

Progetta database locale e cloud.

Entità minime:

UserProfile
Goal
BodyMeasurement
WeightEntry
WeightTrend
Exercise
MuscleGroup
ExerciseMuscle
WorkoutTemplate
WorkoutSession
WorkoutExercise
WorkoutSet
PerformanceRecord
PersonalRecord
MuscleRecovery
ReadinessEntry
Food
FoodServing
Recipe
RecipeIngredient
Meal
FoodLogEntry
NutritionTarget
MacroTarget
DailyNutrition
EnergyExpenditure
WeeklyCheckIn
HealthMetric
AIRecommendation
AIConversation
AppSettings

Creare migration strategy.

Scrivere:

docs/DATA_MODEL.md

==================================================
AGENT 04 — WORKOUT SCIENCE ENGINE
==================================================

È uno dei componenti più importanti.

Creare un Workout Engine completamente indipendente dall'LLM.

INPUT:

- obiettivo;
- esperienza;
- sesso se fornito;
- età;
- altezza;
- peso;
- attrezzatura disponibile;
- giorni disponibili;
- tempo disponibile;
- esercizi preferiti;
- esercizi esclusi;
- split preferito;
- workout recenti;
- recovery;
- volume settimanale;
- performance;
- RIR/RPE;
- eventuale dolore/limitazioni dichiarate;
- muscle priority.

OBIETTIVI SUPPORTATI:

- forza;
- ipertrofia;
- mantenimento;
- ricomposizione;
- dimagrimento preservando massa;
- fitness generale.

SUPPORTARE:

Full Body
Upper/Lower
Push Pull Legs
Torso/Limbs
Hybrid
Custom

OGNI ESERCIZIO deve avere:

- id;
- nome;
- categoria;
- movimento;
- equipment;
- musclePrimary;
- muscleSecondary;
- difficulty;
- unilateral/bilateral;
- compound/isolation;
- fatigueScore;
- stimulusScore;
- stabilityRequirement;
- ROM characteristics;
- alternatives.

Implementare ExerciseScore.

Esempio concettuale:

ExerciseScore =
RecoveryCompatibility
× GoalCompatibility
× EquipmentCompatibility
× UserPreference
× ExercisePriority
× VarietyFactor
× PerformanceFactor
× FatiguePenalty

Non usare questa formula alla cieca:
progettare una versione matematicamente sensata e testabile.

==================================================
PROGRESSIVE OVERLOAD
==================================================

Registrare per ogni set:

weight
reps
RIR
RPE opzionale
tempo
setType

Creare algoritmi per:

- double progression;
- aumento carico;
- aumento reps;
- mantenimento;
- regressione;
- deload;
- plateau detection.

Stimare 1RM con almeno:

Epley
Brzycki

e creare una stima stabile derivata dallo storico.

==================================================
AGENT 05 — RECOVERY & READINESS ENGINE
==================================================

Creare un recovery score 0-100 per ciascun gruppo muscolare.

Considerare:

- tempo dall'ultimo allenamento;
- numero serie;
- volume;
- intensità;
- RIR;
- exercise fatigue;
- frequenza;
- workload recente;
- storico individuale.

NON usare soltanto un timer lineare.

Il recupero deve adattarsi all'utente nel tempo.

Creare inoltre:

JEV READINESS SCORE

0-100

Input potenziali:

- muscle recovery;
- sleep;
- resting heart rate;
- HRV se disponibile;
- attività recente;
- training load;
- performance trend;
- calorie availability;
- deficit calorico;
- giorni consecutivi di training;
- dati HealthKit disponibili.

Se alcuni dati non esistono, il sistema deve funzionare comunque.

==================================================
AGENT 06 — NUTRITION ENGINE
==================================================

Creare un motore nutrizionale deterministico.

ONBOARDING:

peso
altezza
età
sesso biologico se l'utente decide di fornirlo
attività
goal
target weight
desired rate of change

Calcolare una stima iniziale di BMR/TDEE.

Successivamente la stima iniziale DEVE perdere progressivamente importanza.

Il sistema deve imparare il vero expenditure tramite:

- calorie introdotte;
- weight trend;
- variazione peso nel tempo.

Implementare:

Weight Trend
Energy Expenditure Estimate
Energy Balance
Calorie Target
Macro Targets
Weekly Adjustment

Il peso quotidiano NON deve provocare grandi variazioni immediate.

Utilizzare smoothing robusto.

Creare confidence score dell'Expenditure.

Esempio:

TDEE estimate: 2740 kcal
Confidence: 91%
7-day trend: ...
21-day trend: ...

==================================================
MACRONUTRIENTI
==================================================

Supportare:

protein
carbohydrates
fat
fiber

L'utente può scegliere:

AUTO
ASSISTED
MANUAL

AUTO:
JEV Nutrition Engine decide.

ASSISTED:
utente modifica distribuzione mantenendo vincoli energetici.

MANUAL:
target completamente manuali.

Permettere calorie differenti nei diversi giorni.

Esempio:

training day:
2450 kcal

rest day:
2200 kcal

mantenendo il target medio settimanale.

==================================================
AGENT 07 — FOOD LOGGER
==================================================

Implementare:

- search;
- recent foods;
- favorites;
- custom food;
- barcode;
- meals;
- recipes;
- copy yesterday;
- quick calories/macros;
- serving sizes;
- grams;
- history.

Predisporre un FoodProvider protocol.

Non vincolare l'app a un unico database alimentare.

Prevedere providers intercambiabili.

==================================================
AGENT 08 — HEALTHKIT SPECIALIST
==================================================

Implementare integrazione HealthKit iOS 18.

Richiedere solamente permessi necessari.

Possibili letture:

- body mass;
- body fat percentage;
- step count;
- active energy;
- workouts;
- sleep;
- resting heart rate;
- HRV;
- heart rate.

Mai assumere che Apple Watch sia presente.

L'app deve funzionare perfettamente anche solo con iPhone.

Implementare:
HealthKitService

con dependency injection e mock per testing.

==================================================
AGENT 09 — JEV AI
==================================================

JEV è il coach AI dell'app.

NON è il workout engine.
NON è il nutrition engine.

JEV riceve dati strutturati da questi engine.

Usare un'interfaccia:

AIProvider

con provider intercambiabili.

Implementare inizialmente:

OpenAIProvider

ma rendere possibile aggiungere:

AnthropicProvider
LocalProvider
FutureProvider

senza modificare l'app.

MODEL ROUTING:

ROUTINE:
modello economico/rapido.

ANALYSIS:
modello reasoning più potente.

Esempio iniziale:

routine -> GPT-5.6 Terra
deep weekly analysis -> GPT-5.6 Sol

Le chiavi API NON devono essere incluse nell'app.

Le chiamate devono attraversare backend sicuro.

==================================================
PERSONALITÀ JEV
==================================================

JEV deve essere:

- diretto;
- sintetico;
- basato sui dati;
- motivante senza frasi vuote;
- capace di spiegare perché propone una modifica.

Esempio:

"Performance ottima.
Panca +4,8% nelle ultime tre settimane e recupero petto al 94%.

Domani aumenterei da 82,5 kg a 85 kg mantenendo target 8 reps.

Se il primo set scende sotto RIR 1, resta a 82,5."

Ogni consiglio deve, quando possibile, mostrare:

WHY
DATA USED
CONFIDENCE

==================================================
JEV WEEKLY CHECK-IN
==================================================

Una volta a settimana calcolare:

Weight Trend
Energy Expenditure
Average Calories
Protein adherence
Workout adherence
Strength Trend
Training Volume
Recovery
Readiness
Goal Progress

Poi JEV deve decidere tra:

KEEP
INCREASE CALORIES
DECREASE CALORIES
CHANGE MACROS
REDUCE TRAINING LOAD
INCREASE TRAINING LOAD
DELOAD
CHANGE EXERCISE
NO ACTION

La decisione numerica deve provenire dai deterministic engines.

L'AI genera spiegazione e contestualizzazione.

==================================================
AGENT 10 — ANALYTICS
==================================================

Creare schermata Progress completa.

Grafici:

Weight
Weight Trend
Calories
TDEE
Energy Balance
Protein
Carbs
Fat
Strength
Estimated 1RM
Training Volume
Workout Frequency
Recovery
Readiness

Filtri:

7 days
30 days
3 months
6 months
1 year
all time

==================================================
AGENT 11 — QA / SCIENTIFIC VALIDATION
==================================================

Questo agente NON implementa nuove feature.

Deve tentare di distruggere il sistema.

Testare:

- formule;
- edge cases;
- dati mancanti;
- calorie impossibili;
- peso mancante;
- valori negativi;
- workout incompleti;
- HealthKit denied;
- offline mode;
- sync conflict;
- timezone;
- daylight saving;
- kg/lb;
- kcal/kJ;
- crash;
- corrupted state.

Creare unit test per ogni algoritmo.

Target:
>90% coverage per gli engine matematici.

==================================================
AGENT 12 — SECURITY & PRIVACY
==================================================

Analizzare:

- HealthKit privacy;
- secrets;
- Supabase RLS;
- authentication;
- encryption;
- API access;
- logs;
- personal health data.

Mai loggare dati sanitari sensibili inutilmente.

==================================================
AGENT 13 — RELEASE ENGINEER
==================================================

Responsabile di:

- Xcode project;
- schemes;
- build;
- tests;
- warnings;
- signing documentation;
- TestFlight readiness.

Il progetto deve compilare realmente.

Non dichiarare "finito" se non compila.

==================================================
HOME SCREEN
==================================================

La Home deve mostrare immediatamente:

JEV READINESS
Workout Today
Calories Remaining
Protein
Carbs
Fat
Weight Trend
Muscle Recovery
Goal Progress

JEV deve avere una piccola card:

"JEV TODAY"

con il consiglio più importante della giornata.

==================================================
BODY SCREEN
==================================================

Visualizzazione grafica dei gruppi muscolari.

Ogni gruppo:
0-100% recovery.

Tap:
mostra

- last trained;
- sets;
- volume;
- recovery estimate;
- next recommended training.

==================================================
WORKOUT LIVE MODE
==================================================

Durante allenamento:

exercise
set
target reps
target weight
previous performance
timer
RIR input

Pulsanti grandi utilizzabili in palestra.

Al termine:

Workout Summary
Total Volume
PR
Muscles Trained
Performance vs Previous
Estimated Recovery

==================================================
NUTRITION HOME
==================================================

Mostrare:

CALORIES
consumed / target

PROTEIN
CARBS
FAT

Meals:

Breakfast
Lunch
Dinner
Snacks

e:

Expenditure Estimate
Weight Trend
Weekly Goal

==================================================
AI SAFETY
==================================================

JEV non deve diagnosticare patologie.

Segnalare chiaramente quando una situazione richiede un medico o un professionista qualificato.

Le decisioni di allenamento e alimentazione devono avere limiti ragionevoli.

Nessuna modifica calorica estrema automatica.

==================================================
OFFLINE FIRST
==================================================

Workout logging deve funzionare SENZA internet.

Nutrition logging deve funzionare offline per alimenti già presenti/locali.

La sincronizzazione cloud deve essere successiva e resiliente.

==================================================
PERFORMANCE
==================================================

Startup rapida.
Scrolling fluido.
Niente chiamate AI per operazioni che possono essere calcolate localmente.

==================================================
DESIGN
==================================================

Aspetto premium.

Non deve sembrare:
- un clone di Fitbod;
- un clone di MacroFactor;
- un template generico.

Design:
Apple-like
sportivo
molto pulito
data rich
minimal

Utilizzare SF Symbols quando appropriato.

==================================================
PROCESSO DI LAVORO OBBLIGATORIO
==================================================

FASE 0
Audit requisiti.

FASE 1
Product specification.

FASE 2
Architecture.

FASE 3
Database.

FASE 4
Design system e navigation.

FASE 5
Workout Engine.

FASE 6
Nutrition Engine.

FASE 7
Recovery/Readiness.

FASE 8
HealthKit.

FASE 9
UI features.

FASE 10
JEV AI.

FASE 11
Testing.

FASE 12
Integration audit.

FASE 13
Release Candidate.

Gli agenti possono lavorare in parallelo SOLO quando non esistono dipendenze dirette.

==================================================
REGOLE PER GLI AGENTI
==================================================

Ogni agente deve:

1. leggere documentazione già presente;
2. non rompere feature precedenti;
3. eseguire test;
4. documentare decisioni importanti;
5. non duplicare codice;
6. segnalare blocchi reali;
7. non inventare che un test sia passato;
8. non utilizzare mock come soluzione finale;
9. eliminare file temporanei inutili;
10. lasciare il repository in stato migliore di prima.

==================================================
SHARED PROJECT MEMORY
==================================================

Creare:

PROJECT_STATE.md

Contenente:

Current phase
Completed features
Known bugs
Architecture decisions
Open questions
Next tasks

Aggiornarlo ad ogni milestone.

Creare inoltre:

DECISIONS.md

per Architecture Decision Records semplificati.

==================================================
PRIMA DI SCRIVERE CODICE
==================================================

Il Lead Architect deve farmi vedere:

1. architettura proposta;
2. struttura cartelle;
3. schema database;
4. elenco schermate;
5. algoritmi principali;
6. divisione compiti agenti;
7. roadmap;
8. rischi tecnici;
9. cosa sarà MVP;
10. cosa sarà V2.

NON iniziare ancora a generare centinaia di file senza questa verifica iniziale.

Dopo aver presentato il piano, procedi con l'implementazione per milestone.

==================================================
DEFINITION OF DONE
==================================================

Il progetto è considerato terminato solamente quando:

- compila con Xcode;
- gira su iOS 18;
- onboarding funziona;
- si può creare un workout;
- si può completare e salvare un workout;
- progressive overload funziona;
- recovery viene aggiornato;
- food logging funziona;
- calorie e macro funzionano;
- trend peso funziona;
- expenditure estimate funziona;
- weekly check-in funziona;
- HealthKit funziona con autorizzazioni reali;
- JEV riceve dati strutturati;
- JEV può spiegare il piano;
- offline logging funziona;
- sync non duplica record;
- test degli engine passano;
- non ci sono API key nel client;
- non ci sono crash noti nei flussi principali.

NON limitarti a creare una demo grafica.
Voglio un'app realmente utilizzabile.
