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
            consecutiveTrainingDaysPenaltyFrom: 4
        ),
        recovery: Recovery(
            readyThresholdPercent: 90,
            referenceFatigue: 5.4 / log(1 / 0.35),
            baseTauHours: [.small: 24, .medium: 30, .large: 38],
            ageTauSlopePerYear: 0.005,
            ageTauFromYears: 30,
            userTauMultiplierRange: 0.7...1.5,
            adaptationStep: 0.05,
            adaptationMinimumExposures: 6
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
            referenceWeightBMITarget: 27
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
