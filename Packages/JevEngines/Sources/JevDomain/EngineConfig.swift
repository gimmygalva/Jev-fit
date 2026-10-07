import Foundation

/// Fonte unica di tutte le soglie numeriche degli engine (ADR-013).
///
/// Regole:
/// - nessun numero magico negli engine o nella UI: si legge da qui;
/// - ogni modifica di un valore incrementa `version`, che invalida le cache derivate (ADR-005);
/// - i valori v1 sono quelli del piano (ARCHITECTURE_PLAN §5) allineati a PRODUCT_SPEC dopo la
///   review QA-10. Sono default iniziali da tarare sui dati reali, non verità scientifiche.
public struct EngineConfig: Sendable, Hashable {
    public var version: Int
    public var scoreBands: ScoreBands
    public var confidence: ConfidenceLabels
    public var readiness: Readiness
    public var recovery: Recovery
    public var nutrition: Nutrition
    public var progression: Progression
    public var checkIn: CheckIn
    public var safety: Safety
    public var trend: Trend
    public var workout: Workout

    public static let v1 = EngineConfig(
        version: 1,
        scoreBands: ScoreBands(moderateFrom: 40, goodFrom: 65, highFrom: 85),
        confidence: ConfidenceLabels(calibratingFrom: 0.50, reliableFrom: 0.80),
        readiness: Readiness(
            weights: [
                .muscleRecovery: 0.22,
                .sleep: 0.18,
                .subjective: 0.12,
                .heartRateVariability: 0.12,
                .restingHeartRate: 0.08,
                .trainingLoad: 0.08,
                .energyBalance: 0.08,
                .performance: 0.08,
                .consecutiveDays: 0.04,
            ],
            baselineDays: 28,
            minimumTrainingLoadHistoryDays: 21,
            minimumHRVSamples: 5,
            consecutiveTrainingDaysPenaltyFrom: 4,
            minimumBaselineSamples: 14,
            sleepRatioFloor: 0.6,
            partialSleepQuality: 0.6,
            zScoreSlope: 25,
            minimumLogSDNNSD: 0.05,
            minimumRestingHRSD: 1.5,
            acuteLoadDays: 7,
            chronicLoadDays: 28,
            loadRatioSafeMax: 1.3,
            loadRatioZeroAt: 2.0,
            energyBalanceTolerancePoints: 10,
            energyBalancePenaltyPerPoint: 5,
            performanceNeutralScore: 70,
            performanceScorePerUnitResidual: 600,
            consecutiveDayPenalty: 25
        ),
        recovery: Recovery(
            readyThresholdPercent: 90,
            referenceFatigue: 5.4 / log(1 / 0.35),
            baseTauHours: [.small: 24, .medium: 30, .large: 38],
            ageTauSlopePerYear: 0.005,
            ageTauFromYears: 30,
            userTauMultiplierRange: 0.7...1.5,
            adaptationStep: 0.05,
            adaptationMinimumExposures: 6,
            intensityByRIR: [1.0, 0.9, 0.8, 0.65],
            intensityRIR4Plus: 0.5,
            intensityMissingRIR: 0.8,
            intensityWarmup: 0.1,
            toleranceReferenceWeeklySets: 10,
            toleranceMinimumWeeklySets: 5,
            toleranceExponent: 0.3,
            toleranceRange: 0.7...1.25,
            toleranceWindowDays: 28,
            adaptationResidualThreshold: 0.02,
            adaptationHighRecoveryPercent: 90,
            adaptationLowRecoveryPercent: 75
        ),
        nutrition: Nutrition(
            energyDensityKcalPerKg: 7700,
            expenditureConfidenceReferenceKcal: 400,
            priorRelativeSD: 0.15,
            priorRelativeSDWithoutSex: 0.18,
            sexNeutralMifflinConstant: -78,
            maxLossPercentPerWeek: 1.0,
            minLossPercentPerWeek: 0.25,
            maxGainPercentPerWeek: 0.5,
            minGainPercentPerWeek: 0.1,
            absoluteFloorKcal: 1200,
            automaticAdjustmentLimitKcal: 150,
            manualAdjustmentLimitKcal: 250,
            adjustmentDeadBandKcal: 50,
            calorieCyclingMaxDeviation: 0.15,
            implausibleDailyIntakeKcal: 6000,
            implausibleIntakeToExpenditureRatio: 2.5,
            proteinGramsPerKg: [
                .strength: 1.8, .hypertrophy: 1.8, .maintenance: 1.8,
                .recomposition: 2.0, .fatLoss: 2.2, .generalFitness: 1.6,
            ],
            proteinFloorGramsPerKg: 1.6,
            fatEnergyShare: 0.30,
            fatFloorGramsPerKg: 0.6,
            fiberGramsPer1000Kcal: 14,
            referenceWeightBMICap: 30,
            referenceWeightBMITarget: 27,
            activityFactors: [.sedentary: 1.2, .light: 1.375, .moderate: 1.55, .high: 1.725],
            // Filtro dell'expenditure (§5.2), tarato con Monte Carlo su 500 seed (tools/proto):
            // logging completo → errore mediano 84 kcal e 90° percentile 194 kcal a 28 giorni,
            // 90° percentile 74 kcal a 56; con 20% di giorni mancanti 99 / 246 e 144 kcal.
            expenditureDriftKcalPerDay: 10,
            scaleNoiseKg: 0.7,
            tissueProcessNoiseKg: 0.05,
            unknownIntakeSDKcal: 600,
            intakeChangeThresholdKcal: 300,
            intakeChangeScaleNoiseKg: 1.0,
            completenessWindowDays: 21
        ),
        progression: Progression(
            plateauMinimumExposures: 6,
            plateauMinimumDays: 21,
            plateauMaxSlopePercentPerWeek: 0.25,
            plateauConfidenceLevel: 0.80,
            e1rmMaxRepsToFailure: 12,
            strengthIndexMaxRepsToFailure: 20,
            e1rmMaxRIR: 3,
            regressionFraction: 0.05,
            deloadSetReduction: 0.45,
            deloadLoadReduction: 0.10,
            painLookbackDays: 14
        ),
        checkIn: CheckIn(
            minimumCompleteLoggedDays: 4,
            minimumWeighIns: 4,
            safetyMaxLossPercentPerWeek: 1.5,
            safetyMinAverageIntakeKcal: 1000,
            underweightBMI: 18.5,
            goalReachedToleranceKg: 0.5,
            proteinTargetChangeThresholdGrams: 10,
            reduceLoadReadinessBelow: 50,
            reduceLoadRecoveryBelow: 60,
            increaseLoadReadinessFrom: 65,
            increaseLoadAdherenceFrom: 0.80,
            increaseLoadRecoveryFrom: 75,
            deloadReadinessBelow: 40,
            deloadPlateauShare: 0.50,
            trainingLoadSetChangeFraction: 0.20
        ),
        safety: Safety(
            minimumAppAgeYears: 16,
            minimumDeficitAgeYears: 18,
            maximumAgeYears: 100,
            aggressiveLossPercentPerWeek: 0.75,
            defaultLossPercentPerWeek: 0.5,
            defaultGainPercentPerWeek: 0.25,
            plausibleWeightKg: 20...400,
            plausibleHeightCm: 100...250
        ),
        trend: Trend(
            // Tarati con simulazione (tools/proto, §5.1): una pesata anomala di +1,8 kg sposta il
            // trend di < 0,2 kg; errore mediano della pendenza ~0,03 kg/settimana su 6 settimane.
            weightProcessNoise: 1e-5,
            weightMeasurementSDKg: 0.6,
            huberThreshold: 2.0,
            weightInitialSlopeSDPerDay: 0.03,
            // e1RM in scala logaritmica: rumore relativo ~4% tra sessioni.
            strengthProcessNoise: 2e-7,
            strengthMeasurementSDLog: 0.04,
            strengthInitialSlopeSDPerDay: 0.003
        ),
        workout: Workout(
            weeklyHardSets: [.beginner: 8...10, .intermediate: 10...16, .advanced: 14...20],
            goalVolumeMultiplier: [
                .strength: 0.7, .hypertrophy: 1.0, .maintenance: 0.45,
                .recomposition: 1.0, .fatLoss: 0.85, .generalFitness: 0.6,
            ],
            priorityVolumeBoost: 0.30,
            maxHardSetsPerMuscleSession: 10,
            setDurationSeconds: 45,
            warmupSeconds: 360,
            restSecondsStrengthCompound: 180,
            restSecondsCompound: 120,
            restSecondsIsolation: 75,
            rirByProgramWeek: [3, 2, 2, 1],
            deloadSetReduction: 0.45,
            scoreWeights: ScoreWeights(
                recovery: 0.25, goal: 0.20, preference: 0.15, priority: 0.10,
                variety: 0.05, performance: 0.10, fatigue: 0.10, pain: 0.05
            ),
            scoreFloor: 0.05,
            fatigueUtilityPenalty: 0.05,
            recoverySigmoidCenter: 55,
            recoverySigmoidWidth: 10,
            painDecayDays: 14,
            weeklyReusePenalty: 0.85,
            maxSetsPerExercise: 4,
            minSetsPerExercise: 2,
            // Muscoli che ricevono molto lavoro indiretto dai multiarticolari: serie dirette ridotte.
            muscleVolumeFactor: [
                .frontDelts: 0.5, .forearms: 0.4, .lowerBack: 0.5, .adductors: 0.6,
                .obliques: 0.6, .abs: 0.7, .calves: 0.8,
            ]
        )
    )

    /// Configurazione corrente usata dall'app.
    public static let current = v1
}

// MARK: - Sezioni

extension EngineConfig {
    /// Fasce 0–100 condivise da recovery e readiness (PS-RD-01, PRODUCT_SPEC §8).
    public struct ScoreBands: Sendable, Hashable {
        public var moderateFrom: Double
        public var goodFrom: Double
        public var highFrom: Double

        public func band(for score: Double) -> ScoreBand {
            // Catena di if (non range): un config incoerente non deve mai causare un trap a runtime.
            if score >= highFrom { return .high }
            if score >= goodFrom { return .good }
            if score >= moderateFrom { return .moderate }
            return .low
        }
    }

    /// Etichette della confidence (ConfidenceBadge): valori in [0, 1].
    public struct ConfidenceLabels: Sendable, Hashable {
        public var calibratingFrom: Double
        public var reliableFrom: Double

        public func label(for confidence: Double) -> ConfidenceLabel {
            if confidence >= reliableFrom { return .reliable }
            if confidence >= calibratingFrom { return .calibrating }
            return .initialEstimate
        }
    }

    public struct Readiness: Sendable, Hashable {
        public var weights: [ReadinessComponent: Double]
        public var baselineDays: Int
        public var minimumTrainingLoadHistoryDays: Int
        public var minimumHRVSamples: Int
        public var consecutiveTrainingDaysPenaltyFrom: Int
        /// Campioni minimi della baseline (28 giorni) per usare HRV e FC a riposo.
        public var minimumBaselineSamples: Int
        /// Sonno: rapporto dormito/fabbisogno sotto cui il punteggio è 0 (1 → 100).
        public var sleepRatioFloor: Double
        /// Qualità del componente sonno con una sola notte disponibile.
        public var partialSleepQuality: Double
        /// Punti per deviazione standard nei componenti a z-score (50 = baseline).
        public var zScoreSlope: Double
        public var minimumLogSDNNSD: Double
        public var minimumRestingHRSD: Double
        public var acuteLoadDays: Int
        public var chronicLoadDays: Int
        /// Rapporto acuto/cronico fino a cui il carico non penalizza; a `loadRatioZeroAt` vale 0.
        public var loadRatioSafeMax: Double
        public var loadRatioZeroAt: Double
        /// Deficit reale oltre il pianificato tollerato (punti %), poi penalità per punto.
        public var energyBalanceTolerancePoints: Double
        public var energyBalancePenaltyPerPoint: Double
        /// Performance: punteggio a residuo nullo e pendenza per unità di residuo relativo.
        public var performanceNeutralScore: Double
        public var performanceScorePerUnitResidual: Double
        /// Punti persi per ogni giorno consecutivo dal quarto in poi.
        public var consecutiveDayPenalty: Double
    }

    public struct Recovery: Sendable, Hashable {
        public var readyThresholdPercent: Double
        /// F_ref: calibrato perché 6 serie a RIR 1 (dose 5,4) portino il recupero al 35% (piano §5.8).
        public var referenceFatigue: Double
        public var baseTauHours: [MuscleSizeClass: Double]
        public var ageTauSlopePerYear: Double
        public var ageTauFromYears: Double
        public var userTauMultiplierRange: ClosedRange<Double>
        public var adaptationStep: Double
        public var adaptationMinimumExposures: Int
        /// I(RIR) per RIR 0…3; da 4 in su `intensityRIR4Plus`.
        public var intensityByRIR: [Double]
        public var intensityRIR4Plus: Double
        public var intensityMissingRIR: Double
        public var intensityWarmup: Double
        /// Tolleranza cronica `k = clamp((ref / max(volume, min))^esponente)` (repeated bout).
        public var toleranceReferenceWeeklySets: Double
        public var toleranceMinimumWeeklySets: Double
        public var toleranceExponent: Double
        public var toleranceRange: ClosedRange<Double>
        public var toleranceWindowDays: Int
        /// Adattamento di u_m: residuo medio minimo e soglie di recupero "alto" / "basso".
        public var adaptationResidualThreshold: Double
        public var adaptationHighRecoveryPercent: Double
        public var adaptationLowRecoveryPercent: Double
    }

    public struct Nutrition: Sendable, Hashable {
        public var energyDensityKcalPerKg: Double
        public var expenditureConfidenceReferenceKcal: Double
        public var priorRelativeSD: Double
        public var priorRelativeSDWithoutSex: Double
        public var sexNeutralMifflinConstant: Double
        public var maxLossPercentPerWeek: Double
        public var minLossPercentPerWeek: Double
        public var maxGainPercentPerWeek: Double
        public var minGainPercentPerWeek: Double
        public var absoluteFloorKcal: Double
        public var automaticAdjustmentLimitKcal: Double
        public var manualAdjustmentLimitKcal: Double
        public var adjustmentDeadBandKcal: Double
        public var calorieCyclingMaxDeviation: Double
        public var implausibleDailyIntakeKcal: Double
        public var implausibleIntakeToExpenditureRatio: Double
        public var proteinGramsPerKg: [GoalType: Double]
        public var proteinFloorGramsPerKg: Double
        public var fatEnergyShare: Double
        public var fatFloorGramsPerKg: Double
        public var fiberGramsPer1000Kcal: Double
        public var referenceWeightBMICap: Double
        public var referenceWeightBMITarget: Double
        /// Fattori di attività per il prior dell'expenditure (BMR × fattore).
        public var activityFactors: [ActivityLevel: Double]
        /// Deviazione standard della deriva giornaliera dell'expenditure (kcal).
        public var expenditureDriftKcalPerDay: Double
        /// Rumore della bilancia (acqua, glicogeno, contenuto intestinale), kg.
        public var scaleNoiseKg: Double
        /// Rumore di processo della massa di tessuto, kg al giorno.
        public var tissueProcessNoiseKg: Double
        /// Incertezza dell'intake in un giorno non registrato o incompleto (kcal).
        public var unknownIntakeSDKcal: Double
        /// Variazione dell'intake medio settimanale che aumenta il rumore della bilancia per 14 giorni.
        public var intakeChangeThresholdKcal: Double
        public var intakeChangeScaleNoiseKg: Double
        /// Finestra per la completezza del logging nella confidence.
        public var completenessWindowDays: Int
    }

    public struct Progression: Sendable, Hashable {
        public var plateauMinimumExposures: Int
        public var plateauMinimumDays: Int
        public var plateauMaxSlopePercentPerWeek: Double
        public var plateauConfidenceLevel: Double
        public var e1rmMaxRepsToFailure: Int
        public var strengthIndexMaxRepsToFailure: Int
        public var e1rmMaxRIR: Int
        public var regressionFraction: Double
        public var deloadSetReduction: Double
        public var deloadLoadReduction: Double
        public var painLookbackDays: Int
    }

    /// Gate di sicurezza sull'obiettivo e limiti dei dati di onboarding (ARCHITECTURE_PLAN §5.3,
    /// PS-ON-03, PS-ON-05, QA-14). I range dei dati coincidono con i CHECK del database.
    public struct Safety: Sendable, Hashable {
        /// Sotto questa età l'onboarding non procede (UF-01).
        public var minimumAppAgeYears: Int
        /// Sotto questa età nessun obiettivo in deficit.
        public var minimumDeficitAgeYears: Int
        public var maximumAgeYears: Int
        /// Oltre questo ritmo di perdita compare la nota "Ritmo aggressivo" (PS-ON-05).
        public var aggressiveLossPercentPerWeek: Double
        public var defaultLossPercentPerWeek: Double
        public var defaultGainPercentPerWeek: Double
        public var plausibleWeightKg: ClosedRange<Double>
        public var plausibleHeightCm: ClosedRange<Double>
    }

    /// Filtri livello + pendenza (§5.1 peso, §5.7 e1RM stabile).
    public struct Trend: Sendable, Hashable {
        public var weightProcessNoise: Double
        public var weightMeasurementSDKg: Double
        public var huberThreshold: Double
        public var weightInitialSlopeSDPerDay: Double
        public var strengthProcessNoise: Double
        public var strengthMeasurementSDLog: Double
        public var strengthInitialSlopeSDPerDay: Double
    }

    /// Generazione del programma e punteggio degli esercizi (§5.5, §5.6).
    public struct Workout: Sendable, Hashable {
        /// Serie "hard" settimanali per muscolo in ipertrofia, per esperienza.
        public var weeklyHardSets: [ExperienceLevel: ClosedRange<Double>]
        /// Volume relativo all'ipertrofia per obiettivo.
        public var goalVolumeMultiplier: [GoalType: Double]
        /// Aumento del volume per i muscoli prioritari, entro il massimo dell'esperienza.
        public var priorityVolumeBoost: Double
        public var maxHardSetsPerMuscleSession: Double
        public var setDurationSeconds: Double
        public var warmupSeconds: Double
        public var restSecondsStrengthCompound: Double
        public var restSecondsCompound: Double
        public var restSecondsIsolation: Double
        /// RIR target per settimana di programma del mesociclo; dopo l'ultima: deload.
        public var rirByProgramWeek: [Int]
        public var deloadSetReduction: Double
        public var scoreWeights: ScoreWeights
        /// Limite inferiore di ogni fattore dell'ExerciseScore (ε, nessun annullamento).
        public var scoreFloor: Double
        /// κ: peso della fatica nell'utilità marginale della selezione.
        public var fatigueUtilityPenalty: Double
        public var recoverySigmoidCenter: Double
        public var recoverySigmoidWidth: Double
        public var painDecayDays: Double
        /// Utilità di un esercizio già scelto in un'altra sessione della settimana (varietà A/B).
        public var weeklyReusePenalty: Double
        public var maxSetsPerExercise: Int
        public var minSetsPerExercise: Int
        /// Fattore sul volume settimanale per muscolo (assente = 1).
        public var muscleVolumeFactor: [MuscleGroup: Double]

        public var mesocycleWeeks: Int { rirByProgramWeek.count }
    }

    /// Pesi della media geometrica dell'ExerciseScore (§5.6): sommano a 1.
    public struct ScoreWeights: Sendable, Hashable {
        public var recovery: Double
        public var goal: Double
        public var preference: Double
        public var priority: Double
        public var variety: Double
        public var performance: Double
        public var fatigue: Double
        public var pain: Double

        public init(recovery: Double, goal: Double, preference: Double, priority: Double, variety: Double,
                    performance: Double, fatigue: Double, pain: Double) {
            self.recovery = recovery
            self.goal = goal
            self.preference = preference
            self.priority = priority
            self.variety = variety
            self.performance = performance
            self.fatigue = fatigue
            self.pain = pain
        }

        public var sum: Double { recovery + goal + preference + priority + variety + performance + fatigue + pain }
    }

    public struct CheckIn: Sendable, Hashable {
        public var minimumCompleteLoggedDays: Int
        public var minimumWeighIns: Int
        public var safetyMaxLossPercentPerWeek: Double
        public var safetyMinAverageIntakeKcal: Double
        public var underweightBMI: Double
        public var goalReachedToleranceKg: Double
        public var proteinTargetChangeThresholdGrams: Double
        public var reduceLoadReadinessBelow: Double
        public var reduceLoadRecoveryBelow: Double
        public var increaseLoadReadinessFrom: Double
        public var increaseLoadAdherenceFrom: Double
        public var increaseLoadRecoveryFrom: Double
        public var deloadReadinessBelow: Double
        public var deloadPlateauShare: Double
        public var trainingLoadSetChangeFraction: Double
    }
}

public enum ScoreBand: String, Sendable, Codable, CaseIterable {
    case low
    case moderate
    case good
    case high
}

public enum ConfidenceLabel: String, Sendable, Codable, CaseIterable {
    case initialEstimate = "initial_estimate"
    case calibrating
    case reliable
}

public enum ReadinessComponent: String, Sendable, Codable, CaseIterable {
    case muscleRecovery = "muscle_recovery"
    case sleep
    case subjective
    case heartRateVariability = "hrv"
    case restingHeartRate = "resting_hr"
    case trainingLoad = "training_load"
    case energyBalance = "energy_balance"
    case performance
    case consecutiveDays = "consecutive_days"
}
