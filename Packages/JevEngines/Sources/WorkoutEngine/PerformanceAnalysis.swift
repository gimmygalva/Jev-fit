import Foundation
import ExerciseCatalog
import JevCore
import JevDomain

/// Un'esposizione a un esercizio (le serie di una sessione) con la data.
public struct ExerciseExposure: Sendable, Hashable {
    public var date: Date
    public var sets: [PerformedSet]
    /// Sessione di deload o ridotta: esclusa da trend e plateau.
    public var isDeload: Bool

    public init(date: Date, sets: [PerformedSet], isDeload: Bool = false) {
        self.date = date
        self.sets = sets
        self.isDeload = isDeload
    }
}

/// Trend di forza, plateau e record personali (§5.7).
public enum PerformanceAnalysis {
    // MARK: Plateau

    public struct PlateauResult: Sendable, Hashable {
        public var isPlateau: Bool
        /// Esposizioni valide usate (deload esclusi).
        public var exposures: Int
        /// Pendenza stimata dell'indice di forza, % a settimana.
        public var slopePercentPerWeek: Double?
        /// Limite superiore dell'intervallo di confidenza (livello da EngineConfig, 80%).
        public var slopeUpperBoundPercentPerWeek: Double?
        public var reasonCode: String
    }

    /// Plateau: ≥ 6 esposizioni in ≥ 21 giorni (deload esclusi), limite superiore dell'IC della
    /// pendenza in scala logaritmica ≤ +0,25%/settimana, nessun record di ripetizioni.
    public static func plateau(
        _ history: [ExerciseExposure], loadType: LoadType, bodyweightKg: Double? = nil, bodyweightFraction: Double? = nil,
        config: EngineConfig = .current
    ) -> PlateauResult {
        let p = config.progression
        let valid = history.filter { !$0.isDeload }.sorted { $0.date < $1.date }
        let points: [(day: Double, value: Double)] = valid.compactMap { exposure in
            let indices = exposure.sets.filter(\.isWorking).compactMap { set -> Double? in
                guard let reps = set.reps,
                      let load = StrengthEstimation.effectiveLoadKg(loadType: loadType, loadKg: set.loadKg,
                                                                     bodyweightKg: bodyweightKg, bodyweightFraction: bodyweightFraction)
                else { return nil }
                return StrengthEstimation.strengthIndex(loadKg: load, reps: reps, rir: set.rir, config: config)
            }
            guard let best = indices.max(), best > 0 else { return nil }
            return (exposure.date.timeIntervalSince1970 / 86_400, log(best))
        }
        func result(_ plateau: Bool, _ slope: Double?, _ upper: Double?, _ code: String) -> PlateauResult {
            PlateauResult(isPlateau: plateau, exposures: points.count, slopePercentPerWeek: slope,
                          slopeUpperBoundPercentPerWeek: upper, reasonCode: "plateau.\(code)")
        }
        guard points.count >= p.plateauMinimumExposures,
              let first = points.first, let last = points.last,
              last.day - first.day >= Double(p.plateauMinimumDays)
        else { return result(false, nil, nil, "insufficient_data") }
        guard let fit = linearFit(points.map { $0.day }, points.map { $0.value }) else {
            return result(false, nil, nil, "insufficient_data")
        }
        let t = tQuantile(oneSided: (1 + p.plateauConfidenceLevel) / 2, degreesOfFreedom: points.count - 2)
        let toPercentPerWeek = { (slopePerDay: Double) in (exp(slopePerDay * 7) - 1) * 100 }
        let slope = toPercentPerWeek(fit.slope)
        let upper = toPercentPerWeek(fit.slope + t * fit.slopeSE)
        if repPersonalRecordInLastExposure(valid) {
            return result(false, slope, upper, "rep_record")
        }
        return upper <= p.plateauMaxSlopePercentPerWeek
            ? result(true, slope, upper, "detected")
            : result(false, slope, upper, "progressing")
    }

    /// L'ultima esposizione batte le ripetizioni fatte prima con un carico uguale o maggiore.
    static func repPersonalRecordInLastExposure(_ history: [ExerciseExposure]) -> Bool {
        guard let last = history.last else { return false }
        let previous = history.dropLast().flatMap { $0.sets.filter(\.isWorking) }
        for set in last.sets.filter(\.isWorking) {
            guard let reps = set.reps, let load = set.loadKg else { continue }
            let best = previous.filter { ($0.loadKg ?? -1) >= load }.compactMap(\.reps).max() ?? 0
            if !previous.isEmpty && reps > best { return true }
        }
        return false
    }

    struct LinearFit {
        var slope: Double
        var intercept: Double
        var slopeSE: Double
    }

    /// Regressione lineare ai minimi quadrati con errore standard della pendenza.
    static func linearFit(_ x: [Double], _ y: [Double]) -> LinearFit? {
        let n = Double(x.count)
        guard x.count == y.count, x.count >= 3 else { return nil }
        let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
        let sxx = x.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let slope = sxy / sxx
        let intercept = my - slope * mx
        let sse = zip(x, y).reduce(0) { sum, point in
            let residual = point.1 - (intercept + slope * point.0)
            return sum + residual * residual
        }
        let se = (sse / (n - 2) / sxx).squareRoot()
        return LinearFit(slope: slope, intercept: intercept, slopeSE: se)
    }

    /// Quantile della t di Student per probabilità 0,90 (IC bilaterale 80%) con interpolazione
    /// verso la normale; per altre probabilità usa l'approssimazione normale.
    static func tQuantile(oneSided probability: Double, degreesOfFreedom df: Int) -> Double {
        let table90: [Double] = [3.078, 1.886, 1.638, 1.533, 1.476, 1.440, 1.415, 1.397, 1.383, 1.372,
                                 1.363, 1.356, 1.350, 1.345, 1.341, 1.337, 1.333, 1.330, 1.328, 1.325]
        if abs(probability - 0.90) < 1e-9 {
            guard df >= 1 else { return table90[0] }
            return df <= table90.count ? table90[df - 1] : 1.2816 + (table90[table90.count - 1] - 1.2816) * 20 / Double(df)
        }
        // Approssimazione di Abramowitz–Stegun per la normale (sufficiente fuori dalla tabella).
        let p = min(max(probability, 0.5), 0.999_999)
        let t = (-2 * log(1 - p)).squareRoot()
        return t - (2.515517 + 0.802853 * t + 0.010328 * t * t) / (1 + 1.432788 * t + 0.189269 * t * t + 0.001308 * t * t * t)
    }

    // MARK: e1RM stabile

    /// e1RM stabile: filtro livello + pendenza in scala logaritmica sulle esposizioni non di
    /// deload (§5.7). Restituisce valore e deviazione standard in kg (approssimata).
    public static func stableE1RM(
        _ history: [ExerciseExposure], loadType: LoadType, bodyweightKg: Double? = nil, bodyweightFraction: Double? = nil,
        config: EngineConfig = .current
    ) -> (valueKg: Double, sdKg: Double)? {
        let observations = history.filter { !$0.isDeload }.compactMap { exposure -> LevelSlopeFilter.Observation? in
            guard let best = StrengthEstimation.bestE1RM(exposure.sets, loadType: loadType, bodyweightKg: bodyweightKg,
                                                         bodyweightFraction: bodyweightFraction, config: config),
                  best > 0 else { return nil }
            return .init(day: (exposure.date.timeIntervalSince1970 / 86_400).rounded(.down), value: log(best))
        }
        let t = config.trend
        let parameters = LevelSlopeFilter.Parameters(
            processNoise: t.strengthProcessNoise, measurementSD: t.strengthMeasurementSDLog,
            huberThreshold: t.huberThreshold, initialSlopeSD: t.strengthInitialSlopeSDPerDay
        )
        guard let last = LevelSlopeFilter.filter(observations, parameters: parameters).last else { return nil }
        let value = exp(last.level)
        return (value, value * last.levelSD)
    }

    // MARK: Sessione

    public enum RecordKind: String, Sendable, Hashable, Codable, CaseIterable {
        case e1rm
        case repsAtWeight = "reps_at_weight"
        case volume
    }

    public struct PersonalRecord: Sendable, Hashable {
        public var exerciseID: String
        public var kind: RecordKind
        public var value: Double
        public var previous: Double?
    }

    public struct SessionSummary: Sendable, Hashable {
        public var volumeKg: Double
        public var workingSets: Int
        /// Serie hard per muscolo (primario 1, secondario 0,5).
        public var hardSetsByMuscle: [MuscleGroup: Double]
        public var records: [PersonalRecord]
    }

    /// Riepilogo di una sessione con i record rispetto allo storico (SCR-WK-07).
    /// - Parameter history: esposizioni precedenti per esercizio.
    public static func summarize(
        session: [String: [PerformedSet]], catalog: ExerciseCatalog, history: [String: [ExerciseExposure]],
        bodyweightKg: Double?, config: EngineConfig = .current
    ) -> SessionSummary {
        var volume = 0.0
        var workingSets = 0
        var hard: [MuscleGroup: Double] = [:]
        var records: [PersonalRecord] = []
        for exerciseID in session.keys.sorted() {
            let sets = session[exerciseID] ?? []
            let working = sets.filter(\.isWorking)
            workingSets += working.count
            let exerciseVolume = StrengthEstimation.volumeKg(sets)
            volume += exerciseVolume
            guard let exercise = catalog[exerciseID] else { continue }
            for item in exercise.muscleContributions {
                hard[item.muscle, default: 0] += item.contribution * Double(working.count)
            }
            let past = history[exerciseID] ?? []
            guard !past.isEmpty else { continue }
            // e1RM
            let current = StrengthEstimation.bestE1RM(sets, loadType: exercise.loadType, bodyweightKg: bodyweightKg,
                                                      bodyweightFraction: exercise.bodyweightFraction, config: config)
            let best = past.compactMap {
                StrengthEstimation.bestE1RM($0.sets, loadType: exercise.loadType, bodyweightKg: bodyweightKg,
                                            bodyweightFraction: exercise.bodyweightFraction, config: config)
            }.max()
            if let current, current > (best ?? 0) + 1e-9, best != nil {
                records.append(PersonalRecord(exerciseID: exerciseID, kind: .e1rm, value: current, previous: best))
            }
            // Ripetizioni a parità di carico (o più)
            let pastSets = past.flatMap { $0.sets.filter(\.isWorking) }
            for set in working {
                guard let reps = set.reps, let load = set.loadKg else { continue }
                let previousBest = pastSets.filter { ($0.loadKg ?? -1) >= load }.compactMap(\.reps).max()
                if let previousBest, reps > previousBest {
                    records.append(PersonalRecord(exerciseID: exerciseID, kind: .repsAtWeight, value: Double(reps),
                                                  previous: Double(previousBest)))
                    break
                }
            }
            // Volume dell'esercizio
            let bestVolume = past.map { StrengthEstimation.volumeKg($0.sets) }.max() ?? 0
            if exerciseVolume > bestVolume, bestVolume > 0 {
                records.append(PersonalRecord(exerciseID: exerciseID, kind: .volume, value: exerciseVolume, previous: bestVolume))
            }
        }
        return SessionSummary(volumeKg: volume, workingSets: workingSets, hardSetsByMuscle: hard, records: records)
    }
}
