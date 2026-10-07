# Release candidate (M13) — verifica della Definition of Done

Ogni punto della Definition of Done del brief con la prova che lo dimostra. "CI" significa che c'è un test automatico che gira a ogni push (`.github/workflows/ci.yml`, 5 job); "device" significa che serve una verifica sull'iPhone, a cura dell'utente.

| # | Punto | Prova | Stato |
|---|---|---|---|
| 1 | Compila con Xcode | Job "iOS · build e test su simulatore" (Xcode 26.3, `xcodebuild` dell'app e di JevKit) | ✔ CI |
| 2 | Gira su iOS 18 | Deployment target iOS 18; simulatore iOS nel job iOS; test UI dell'onboarding (`AppUITests/LaunchUITests`) | ✔ CI · device consigliato |
| 3 | Onboarding funziona | `OnboardingModelTests`, `OnboardingRepositoryTests`, test UI del percorso completo | ✔ CI |
| 4 | Si può creare un workout | `TrainingPlanServiceTests` (programma dal profilo, sessione della rotazione), `WorkoutRepositoryTests.start` | ✔ CI |
| 5 | Si può completare e salvare un workout | `WorkoutRepositoryTests` (serie salvate subito, ripresa dopo il riavvio, chiusura), `TrainingPlanServiceTests.liveModel` (riepilogo) | ✔ CI |
| 6 | Progressive overload funziona | `StrengthAndProgressionTests` (regole 0–9 e proprietà su 2.000 input), `TrainingPlanServiceTests.overloadAcrossSessions` (carico che sale tra due sessioni) | ✔ CI |
| 7 | Recovery viene aggiornato | `MuscleRecoveryTests` (calibrazione 35% → 90% in ~69 h), `DashboardServiceTests.afterWorkout` (muscoli allenati affaticati) | ✔ CI |
| 8 | Food logging funziona | `NutritionLogRepositoryTests` (snapshot, aggiunta rapida, copia ieri, ricette), `FoodProvidersTests` (database locale, Open Food Facts) | ✔ CI · barcode con fotocamera: device |
| 9 | Calorie e macro funzionano | `CalorieTargetsTests`, `MacroPlannerTests`, `NutritionPlanServiceTests` | ✔ CI |
| 10 | Trend peso funziona | `EnergyModelTests` (trend costante, perdita di 0,5 kg/sett., pesate scartate), serie del grafico in `DashboardServiceTests.series` | ✔ CI |
| 11 | Expenditure estimate funziona | `ExpenditureEstimatorTests` (Monte Carlo su 500 seed entro le soglie del §5.2, errore di battitura, cambio di intake) | ✔ CI |
| 12 | Weekly check-in funziona | `CheckInEvaluatorTests` (priorità, safety, isteresi), `CheckInServiceTests` (metriche dai dati, snapshot, target accettato in vigore, rifiuto con isteresi) | ✔ CI |
| 13 | HealthKit funziona con autorizzazioni reali | Logica: `HealthAggregatorTests`, `MockHealthDataSourceTests`, `HealthImporterTests` (concessi/negati/parziali). Autorizzazioni reali: `docs/HEALTHKIT_CHECKLIST.md` | ✔ CI · **device: da fare** |
| 14 | JEV riceve dati strutturati | `CoachRequest` con soli fatti e reason code; `CheckInCoach.facts`; il prompt del gateway non contiene i valori (`grounding_test.ts`) | ✔ CI |
| 15 | JEV può spiegare il piano | `CoachTests` (grounding, retry, fallback, safety), card di JEV su Oggi, schermata del check-in | ✔ CI · AI online: richiede i segreti della Edge Function (`docs/BACKEND.md`) |
| 16 | Offline logging funziona | Tutto il logging scrive su GRDB locale; la sync è facoltativa; database alimenti offline; template di JEV offline | ✔ CI |
| 17 | Sync non duplica record | `SyncEngineTests` (due dispositivi, adozione del profilo, fault injection su 5 seed: convergenza, nessun duplicato) | ✔ CI · sync reale: richiede il provider Apple attivo in Supabase |
| 18 | Test degli engine passano | Job Linux e macOS; coverage gate 90% su tutti gli 8 moduli degli engine | ✔ CI |
| 19 | Non ci sono API key nel client | `scripts/ci/check-secrets.sh` a ogni push; nel client solo la chiave `sb_publishable_` | ✔ CI |
| 20 | Nessun crash noto nei flussi principali | Nessun crash noto; test UI dell'onboarding; flussi principali coperti dai test di integrazione sopra | ✔ (nessun bug aperto) |

## Prima di TestFlight (a cura dell'utente)
1. Apple Developer Program: firma (`docs/SIGNING.md`), App ID con HealthKit e Sign in with Apple.
2. Supabase: provider Apple, 2FA sull'account (`docs/BACKEND.md`).
3. Edge Function `coach`: deploy e segreti dei modelli; Edge Function `account-delete`: deploy (`docs/BACKEND.md`).
4. Checklist HealthKit su iPhone (`docs/HEALTHKIT_CHECKLIST.md`).
5. AppIcon 1024×1024 originale.
