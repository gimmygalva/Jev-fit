import Foundation
import ExerciseCatalog
import JevCore
import JevDomain

/// Recupero muscolare (§5.8): fatica a decadimento esponenziale per muscolo, con tolleranza
/// cronica, costante di tempo per taglia/età e moltiplicatore personale appreso.
public enum MuscleRecovery {
    /// Una serie eseguita, già tradotta nei contributi per muscolo (1 primario, 0,5 secondario).
    public struct SetDose: Sendable, Hashable {
        public var date: Date
        public var contributions: [MuscleGroup: Double]
        /// Fatigue score dell'esercizio (F_e, 0,3–1,3 nel catalogo).
        public var exerciseFatigue: Double
        public var rir: Double?
        public var isWarmup: Bool

        public init(date: Date, contributions: [MuscleGroup: Double], exerciseFatigue: Double = 1,
                    rir: Double? = nil, isWarmup: Bool = false) {
            self.date = date
            self.contributions = contributions
            self.exerciseFatigue = exerciseFatigue
            self.rir = rir
            self.isWarmup = isWarmup
        }

        /// Dose di una serie dell'esercizio del catalogo.
        public init(date: Date, exercise: CatalogExercise, rir: Double?, isWarmup: Bool = false) {
            var contributions: [MuscleGroup: Double] = [:]
            for item in exercise.muscleContributions {
                contributions[item.muscle, default: 0] += item.contribution
            }
            self.init(date: date, contributions: contributions, exerciseFatigue: exercise.fatigueScore,
                      rir: rir, isWarmup: isWarmup)
        }
    }

    public struct MuscleState: Sendable, Hashable {
        public var muscle: MuscleGroup
        public var fatigue: Double
        /// 0…100.
        public var recoveryPercent: Double
        public var hoursToReady: Double
        public var tauHours: Double
        public var isReady: Bool
    }

    /// Prossimità al cedimento I(RIR): 0 → 1,0 · 1 → 0,9 · 2 → 0,8 · 3 → 0,65 · ≥ 4 → 0,5;
    /// RIR mancante 0,8; riscaldamento 0,1.
    public static func intensity(rir: Double?, isWarmup: Bool, config: EngineConfig = .current) -> Double {
        let r = config.recovery
        if isWarmup { return r.intensityWarmup }
        guard let rir, rir.isFinite else { return r.intensityMissingRIR }
        let index = Int(max(rir, 0).rounded())
        return index < r.intensityByRIR.count ? r.intensityByRIR[index] : r.intensityRIR4Plus
    }

    /// Tolleranza cronica k (repeated bout): chi fa molto volume accumula meno fatica per serie.
    public static func tolerance(weeklyHardSets: Double, config: EngineConfig = .current) -> Double {
        let r = config.recovery
        let volume = max(weeklyHardSets.isFinite ? weeklyHardSets : 0, r.toleranceMinimumWeeklySets)
        let raw = pow(r.toleranceReferenceWeeklySets / volume, r.toleranceExponent)
        return RobustStatistics.clamp(raw, r.toleranceRange)
    }

    /// τ_m = τ_base(taglia) · (1 + 0,005 · max(0, età − 30)) · u_m, u_m nel range consentito.
    public static func tauHours(
        for muscle: MuscleGroup, ageYears: Int?, userMultiplier: Double = 1, config: EngineConfig = .current
    ) -> Double {
        let r = config.recovery
        let base = r.baseTauHours[muscle.sizeClass] ?? 30
        let age = Double(ageYears ?? Int(r.ageTauFromYears))
        let ageFactor = 1 + r.ageTauSlopePerYear * max(0, age - r.ageTauFromYears)
        let multiplier = RobustStatistics.clamp(userMultiplier.isFinite ? userMultiplier : 1, r.userTauMultiplierRange)
        return base * ageFactor * multiplier
    }

    /// R = 100 · exp(−F / F_ref).
    public static func recoveryPercent(fatigue: Double, config: EngineConfig = .current) -> Double {
        guard fatigue.isFinite, fatigue > 0 else { return 100 }
        return 100 * exp(-fatigue / config.recovery.referenceFatigue)
    }

    /// Ore fino al 90%: 0 se già pronto; `τ · ln(F / (F_ref · ln(100/90)))`. Guard: F nulla o
    /// non finita → 0 (mai `ln(0)`).
    public static func hoursToReady(fatigue: Double, tauHours: Double, config: EngineConfig = .current) -> Double {
        let r = config.recovery
        guard fatigue.isFinite, fatigue > 0, tauHours.isFinite, tauHours > 0 else { return 0 }
        guard recoveryPercent(fatigue: fatigue, config: config) < r.readyThresholdPercent else { return 0 }
        let threshold = r.referenceFatigue * log(100 / r.readyThresholdPercent)
        return max(tauHours * log(fatigue / threshold), 0)
    }

    /// Volume settimanale "hard" per muscolo nelle 4 settimane prima di `now` (riscaldamenti esclusi).
    public static func weeklyHardSets(_ sets: [SetDose], at now: Date, config: EngineConfig = .current) -> [MuscleGroup: Double] {
        let days = Double(config.recovery.toleranceWindowDays)
        let start = now.addingTimeInterval(-days * 86_400)
        var totals: [MuscleGroup: Double] = [:]
        for set in sets where !set.isWarmup && set.date >= start && set.date <= now {
            for (muscle, contribution) in set.contributions {
                totals[muscle, default: 0] += contribution
            }
        }
        return totals.mapValues { $0 / (days / 7) }
    }

    /// Stato di tutti i muscoli a `now`. Le serie future rispetto a `now` sono ignorate.
    public static func state(
        sets: [SetDose], at now: Date, ageYears: Int?, userMultipliers: [MuscleGroup: Double] = [:],
        config: EngineConfig = .current
    ) -> [MuscleGroup: MuscleState] {
        let volume = weeklyHardSets(sets, at: now, config: config)
        var fatigue: [MuscleGroup: Double] = [:]
        var taus: [MuscleGroup: Double] = [:]
        for muscle in MuscleGroup.allCases {
            taus[muscle] = tauHours(for: muscle, ageYears: ageYears, userMultiplier: userMultipliers[muscle] ?? 1, config: config)
        }
        for set in sets where set.date <= now {
            let hours = now.timeIntervalSince(set.date) / 3600
            let dose = intensity(rir: set.rir, isWarmup: set.isWarmup, config: config) * set.exerciseFatigue
            for (muscle, contribution) in set.contributions {
                let k = tolerance(weeklyHardSets: volume[muscle] ?? 0, config: config)
                let tau = taus[muscle] ?? 30
                fatigue[muscle, default: 0] += contribution * dose * k * exp(-hours / tau)
            }
        }
        var result: [MuscleGroup: MuscleState] = [:]
        for muscle in MuscleGroup.allCases {
            let f = fatigue[muscle] ?? 0
            let tau = taus[muscle] ?? 30
            let recovery = recoveryPercent(fatigue: f, config: config)
            result[muscle] = MuscleState(
                muscle: muscle, fatigue: f, recoveryPercent: recovery,
                hoursToReady: hoursToReady(fatigue: f, tauHours: tau, config: config), tauHours: tau,
                isReady: recovery >= config.recovery.readyThresholdPercent
            )
        }
        return result
    }

    /// Recupero medio dei muscoli coinvolti in una sessione (pesato sul contributo).
    public static func sessionRecovery(
        _ states: [MuscleGroup: MuscleState], muscles: [MuscleGroup: Double]
    ) -> Double? {
        var weighted = 0.0
        var total = 0.0
        for (muscle, weight) in muscles where weight > 0 {
            guard let state = states[muscle] else { continue }
            weighted += state.recoveryPercent * weight
            total += weight
        }
        return total > 0 ? weighted / total : nil
    }

    // MARK: Adattamento di u_m

    /// Un'esposizione del muscolo: recupero stimato all'inizio e residuo relativo della performance
    /// rispetto all'attesa al netto del trend e1RM (`osservato / atteso − 1`).
    public struct Exposure: Sendable, Hashable {
        public var estimatedRecoveryPercent: Double
        public var performanceResidual: Double

        public init(estimatedRecoveryPercent: Double, performanceResidual: Double) {
            self.estimatedRecoveryPercent = estimatedRecoveryPercent
            self.performanceResidual = performanceResidual
        }
    }

    public struct Adaptation: Sendable, Hashable {
        public var multiplier: Double
        public var reasonCode: String
    }

    /// Un passo (η = 0,05) di adattamento del moltiplicatore personale, solo con ≥ 6 esposizioni:
    /// residui negativi a recupero "alto" → recupero più lento (u ↑); positivi a recupero "basso"
    /// → più rapido (u ↓). Sempre nel range consentito.
    public static func adapt(
        multiplier current: Double, exposures: [Exposure], config: EngineConfig = .current
    ) -> Adaptation {
        let r = config.recovery
        let base = RobustStatistics.clamp(current.isFinite ? current : 1, r.userTauMultiplierRange)
        let valid = exposures.filter { $0.estimatedRecoveryPercent.isFinite && $0.performanceResidual.isFinite }
        guard valid.count >= r.adaptationMinimumExposures else {
            return Adaptation(multiplier: base, reasonCode: "recovery.adapt_insufficient_data")
        }
        let high = valid.filter { $0.estimatedRecoveryPercent >= r.adaptationHighRecoveryPercent }.map(\.performanceResidual)
        let low = valid.filter { $0.estimatedRecoveryPercent < r.adaptationLowRecoveryPercent }.map(\.performanceResidual)
        let highMean = high.isEmpty ? 0 : high.reduce(0, +) / Double(high.count)
        let lowMean = low.isEmpty ? 0 : low.reduce(0, +) / Double(low.count)
        var next = base
        var code = "recovery.adapt_keep"
        if highMean < -r.adaptationResidualThreshold && lowMean <= r.adaptationResidualThreshold {
            next = base + r.adaptationStep
            code = "recovery.adapt_slower"
        } else if lowMean > r.adaptationResidualThreshold && highMean >= -r.adaptationResidualThreshold {
            next = base - r.adaptationStep
            code = "recovery.adapt_faster"
        }
        return Adaptation(multiplier: RobustStatistics.clamp(next, r.userTauMultiplierRange), reasonCode: code)
    }
}
