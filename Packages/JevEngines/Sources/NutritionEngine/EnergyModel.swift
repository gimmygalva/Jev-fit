import Foundation
import JevCore
import JevDomain

/// Metabolismo basale e prior dell'expenditure (§5.2).
public enum EnergyModel {
    /// BMR in kcal/giorno. Katch–McArdle se la massa grassa è nota e plausibile (2–70%),
    /// altrimenti Mifflin–St Jeor; senza sesso indicato costante neutra −78 kcal (PS-ON-04).
    public static func bmr(
        weightKg: Double, heightCm: Double, ageYears: Int, sex: BiologicalSex?, bodyFatPercent: Double? = nil,
        config: EngineConfig = .current
    ) -> Double {
        if let bodyFat = bodyFatPercent, (2...70).contains(bodyFat) {
            let leanMass = weightKg * (1 - bodyFat / 100)
            return 370 + 21.6 * leanMass
        }
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case nil: return base + config.nutrition.sexNeutralMifflinConstant
        }
    }

    public static func activityFactor(_ level: ActivityLevel, config: EngineConfig = .current) -> Double {
        config.nutrition.activityFactors[level] ?? 1.4
    }

    /// Prior dell'expenditure: BMR × fattore di attività, deviazione standard 15% (18% senza
    /// sesso indicato: la stima iniziale è meno precisa e la confidence lo mostra).
    public static func priorExpenditure(
        weightKg: Double, heightCm: Double, ageYears: Int, sex: BiologicalSex?, bodyFatPercent: Double? = nil,
        activity: ActivityLevel, config: EngineConfig = .current
    ) -> (kcal: Double, sd: Double) {
        let kcal = bmr(weightKg: weightKg, heightCm: heightCm, ageYears: ageYears, sex: sex,
                       bodyFatPercent: bodyFatPercent, config: config) * activityFactor(activity, config: config)
        let relative = sex == nil ? config.nutrition.priorRelativeSDWithoutSex : config.nutrition.priorRelativeSD
        return (kcal, kcal * relative)
    }
}

/// Trend del peso (§5.1): filtro robusto livello + pendenza su una pesata per giorno.
public enum WeightTrend {
    public struct Entry: Sendable, Hashable {
        public var dayKey: DayKey
        public var weightKg: Double

        public init(dayKey: DayKey, weightKg: Double) {
            self.dayKey = dayKey
            self.weightKg = weightKg
        }
    }

    public struct Result: Sendable, Hashable {
        public var lastDay: DayKey
        public var trendKg: Double
        public var trendSDKg: Double
        public var slopeKgPerWeek: Double
        public var slopeSDKgPerWeek: Double
        /// Variazione del livello lisciato negli ultimi 7 e 21 giorni (nil se lo storico è più corto).
        public var change7DaysKg: Double?
        public var change21DaysKg: Double?
        /// Livello lisciato per i grafici.
        public var smoothed: [Point]
        public var entriesUsed: Int
    }

    public struct Point: Sendable, Hashable {
        public var dayKey: DayKey
        public var trendKg: Double
    }

    public static func parameters(config: EngineConfig = .current) -> LevelSlopeFilter.Parameters {
        let t = config.trend
        return LevelSlopeFilter.Parameters(
            processNoise: t.weightProcessNoise, measurementSD: t.weightMeasurementSDKg,
            huberThreshold: t.huberThreshold, initialSlopeSD: t.weightInitialSlopeSDPerDay
        )
    }

    /// Pesate fuori dal range plausibile vengono rifiutate; con più pesate nello stesso giorno
    /// conta la prima (ordine d'ingresso).
    public static func compute(_ entries: [Entry], config: EngineConfig = .current) -> Result? {
        var seen = Set<DayKey>()
        let plausible = entries
            .filter { config.safety.plausibleWeightKg.contains($0.weightKg) && seen.insert($0.dayKey).inserted }
            .sorted { $0.dayKey < $1.dayKey }
        guard let origin = plausible.first?.dayKey else { return nil }
        let observations = plausible.map {
            LevelSlopeFilter.Observation(day: Double(origin.days(to: $0.dayKey)), value: $0.weightKg)
        }
        let p = parameters(config: config)
        let filtered = LevelSlopeFilter.filter(observations, parameters: p)
        let smoothed = LevelSlopeFilter.smooth(observations, parameters: p)
        guard let last = filtered.last, let lastSmoothed = smoothed.last else { return nil }
        let points = smoothed.map { Point(dayKey: origin.adding(days: Int($0.day)), trendKg: $0.level) }
        func change(_ days: Double) -> Double? {
            let target = lastSmoothed.day - days
            guard let base = smoothed.last(where: { $0.day <= target }) else { return nil }
            return lastSmoothed.level - base.level
        }
        return Result(
            lastDay: origin.adding(days: Int(last.day)), trendKg: last.level, trendSDKg: last.levelSD,
            slopeKgPerWeek: last.slope * 7, slopeSDKgPerWeek: last.slopeSD * 7,
            change7DaysKg: change(7), change21DaysKg: change(21), smoothed: points, entriesUsed: filtered.count
        )
    }
}
