import Foundation
import JevCore
import JevDomain

/// JEV READINESS 0–100 (§5.9): media pesata dei soli componenti disponibili, con confidence
/// = somma dei pesi disponibili × qualità. Un componente mancante non viene mai inventato.
public enum Readiness {
    /// Dati del giorno. Ogni campo è opzionale: senza Watch restano recupero, check soggettivo,
    /// carico, bilancio energetico, performance e giorni consecutivi.
    public struct Input: Sendable, Hashable {
        /// Recupero medio (0–100) dei muscoli della sessione di oggi.
        public var sessionRecoveryPercent: Double?
        public var sleep: Sleep?
        public var subjective: Subjective?
        /// ln(SDNN) dei campioni notturni: ultimi 7 giorni e baseline di 28 giorni (una sola fonte).
        public var hrv: Baseline?
        /// FC a riposo: ultimi valori (media 3 giorni) e baseline di 28 giorni.
        public var restingHeartRate: Baseline?
        /// Carico giornaliero (Σ serie hard × I(RIR)), dal più vecchio a oggi, un valore per giorno.
        public var dailyTrainingLoad: [Double]?
        public var energyBalance: EnergyBalance?
        /// Residuo relativo medio della performance recente rispetto all'attesa (0 = come previsto).
        public var performanceResidual: Double?
        /// Giorni di allenamento consecutivi fino a oggi compreso.
        public var consecutiveTrainingDays: Int?

        public init(
            sessionRecoveryPercent: Double? = nil, sleep: Sleep? = nil, subjective: Subjective? = nil,
            hrv: Baseline? = nil, restingHeartRate: Baseline? = nil, dailyTrainingLoad: [Double]? = nil,
            energyBalance: EnergyBalance? = nil, performanceResidual: Double? = nil, consecutiveTrainingDays: Int? = nil
        ) {
            self.sessionRecoveryPercent = sessionRecoveryPercent
            self.sleep = sleep
            self.subjective = subjective
            self.hrv = hrv
            self.restingHeartRate = restingHeartRate
            self.dailyTrainingLoad = dailyTrainingLoad
            self.energyBalance = energyBalance
            self.performanceResidual = performanceResidual
            self.consecutiveTrainingDays = consecutiveTrainingDays
        }
    }

    public struct Sleep: Sendable, Hashable {
        public var lastNightHours: Double
        /// Media delle ultime 3 notti; `nil` se c'è una sola notte (qualità ridotta).
        public var threeNightAverageHours: Double?
        public var needHours: Double

        public init(lastNightHours: Double, threeNightAverageHours: Double? = nil, needHours: Double = 8) {
            self.lastNightHours = lastNightHours
            self.threeNightAverageHours = threeNightAverageHours
            self.needHours = needHours
        }
    }

    /// Check soggettivo 1–5 (indolenzimento: 5 = molto indolenzito).
    public struct Subjective: Sendable, Hashable {
        public var sleepQuality: Int
        public var energy: Int
        public var soreness: Int

        public init(sleepQuality: Int, energy: Int, soreness: Int) {
            self.sleepQuality = sleepQuality
            self.energy = energy
            self.soreness = soreness
        }
    }

    public struct Baseline: Sendable, Hashable {
        public var recent: [Double]
        public var baseline: [Double]

        public init(recent: [Double], baseline: [Double]) {
            self.recent = recent
            self.baseline = baseline
        }
    }

    public struct EnergyBalance: Sendable, Hashable {
        /// Intake medio dei giorni completi recenti.
        public var averageIntakeKcal: Double
        public var expenditureKcal: Double
        public var plannedTargetKcal: Double

        public init(averageIntakeKcal: Double, expenditureKcal: Double, plannedTargetKcal: Double) {
            self.averageIntakeKcal = averageIntakeKcal
            self.expenditureKcal = expenditureKcal
            self.plannedTargetKcal = plannedTargetKcal
        }
    }

    public struct Component: Sendable, Hashable {
        public var component: ReadinessComponent
        /// 0–100.
        public var score: Double
        /// 0–1.
        public var quality: Double
        public var weight: Double
    }

    public struct Result: Sendable, Hashable {
        /// 0–100, arrotondato all'intero.
        public var score: Int
        public var band: ScoreBand
        /// Σ pesi disponibili × qualità, 0–1.
        public var confidence: Double
        public var confidenceLabel: ConfidenceLabel
        public var components: [Component]
        public var missing: [ReadinessComponent]
    }

    public static func compute(_ input: Input, config: EngineConfig = .current) -> Result? {
        let weights = config.readiness.weights
        var components: [Component] = []
        func add(_ component: ReadinessComponent, _ value: (score: Double, quality: Double)?) {
            guard let value, value.score.isFinite, let weight = weights[component], weight > 0 else { return }
            components.append(Component(component: component, score: RobustStatistics.clamp(value.score, 0...100),
                                        quality: RobustStatistics.clamp(value.quality, 0...1), weight: weight))
        }
        let r = config.readiness
        var recovery: (score: Double, quality: Double)?
        if let value = input.sessionRecoveryPercent { recovery = (score: value, quality: 1) }
        add(.muscleRecovery, recovery)
        if let sleep = input.sleep { add(.sleep, sleepScore(sleep, config: config)) }
        if let subjective = input.subjective { add(.subjective, subjectiveScore(subjective)) }
        if let hrv = input.hrv {
            add(.heartRateVariability, zScoreComponent(hrv, minimumRecent: r.minimumHRVSamples, minimumSD: r.minimumLogSDNNSD,
                                                       higherIsBetter: true, config: config))
        }
        if let restingHR = input.restingHeartRate {
            add(.restingHeartRate, zScoreComponent(restingHR, minimumRecent: 1, minimumSD: r.minimumRestingHRSD,
                                                   higherIsBetter: false, config: config))
        }
        if let loads = input.dailyTrainingLoad { add(.trainingLoad, trainingLoadScore(loads, config: config)) }
        if let balance = input.energyBalance { add(.energyBalance, energyBalanceScore(balance, config: config)) }
        if let residual = input.performanceResidual { add(.performance, performanceScore(residual, config: config)) }
        if let days = input.consecutiveTrainingDays { add(.consecutiveDays, consecutiveDaysScore(days, config: config)) }

        let totalWeight: Double = components.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let weightedSum: Double = components.reduce(0) { $0 + $1.weight * $1.score }
        let weighted = weightedSum / totalWeight
        let qualitySum: Double = components.reduce(0) { $0 + $1.weight * $1.quality }
        let confidence = min(qualitySum, 1)
        let score = Int(weighted.rounded())
        let present = Set(components.map(\.component))
        return Result(
            score: score, band: config.scoreBands.band(for: Double(score)), confidence: confidence,
            confidenceLabel: config.confidence.label(for: confidence), components: components,
            missing: ReadinessComponent.allCases.filter { !present.contains($0) && (weights[$0] ?? 0) > 0 }
        )
    }

    // MARK: Componenti

    /// Sonno: metà ultima notte e metà media di 3 notti rispetto al fabbisogno; lineare tra
    /// il 60% (0) e il 100% (100) del fabbisogno.
    static func sleepScore(_ s: Sleep, config: EngineConfig) -> (score: Double, quality: Double)? {
        guard s.needHours > 0, s.lastNightHours.isFinite, s.lastNightHours >= 0 else { return nil }
        let average = s.threeNightAverageHours.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let hours = average.map { 0.5 * s.lastNightHours + 0.5 * $0 } ?? s.lastNightHours
        let floor = config.readiness.sleepRatioFloor
        let ratio = hours / s.needHours
        let score = 100 * RobustStatistics.clamp((ratio - floor) / (1 - floor), 0...1)
        return (score, average == nil ? config.readiness.partialSleepQuality : 1)
    }

    static func subjectiveScore(_ s: Subjective) -> (score: Double, quality: Double)? {
        let values: [Int] = [s.sleepQuality, s.energy, 6 - s.soreness]
        guard [s.sleepQuality, s.energy, s.soreness].allSatisfy({ (1...5).contains($0) }) else { return nil }
        let mean = Double(values.reduce(0, +)) / 3
        return (100 * (mean - 1) / 4, 1)
    }

    /// z-score della media recente rispetto alla baseline: 50 + 25·z (invertito per la FC).
    static func zScoreComponent(
        _ b: Baseline, minimumRecent: Int, minimumSD: Double, higherIsBetter: Bool, config: EngineConfig
    ) -> (score: Double, quality: Double)? {
        let recent = b.recent.filter(\.isFinite)
        let baseline = b.baseline.filter(\.isFinite)
        guard recent.count >= max(minimumRecent, 1), baseline.count >= config.readiness.minimumBaselineSamples else {
            return nil
        }
        let mean = baseline.reduce(0, +) / Double(baseline.count)
        let squares: Double = baseline.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        let variance = squares / Double(baseline.count - 1)
        let sd = max(variance.squareRoot(), minimumSD)
        let recentMean = recent.reduce(0, +) / Double(recent.count)
        let z = (recentMean - mean) / sd
        let signed = higherIsBetter ? z : -z
        return (50 + config.readiness.zScoreSlope * signed, 1)
    }

    /// Rapporto EWMA acuto/cronico del carico; attivo solo con ≥ 21 giorni di storico.
    static func trainingLoadScore(_ loads: [Double], config: EngineConfig) -> (score: Double, quality: Double)? {
        let r = config.readiness
        guard loads.count >= r.minimumTrainingLoadHistoryDays else { return nil }
        guard let ratio = acuteChronicRatio(loads, config: config) else { return (100, 1) }
        if ratio <= r.loadRatioSafeMax { return (100, 1) }
        let span = r.loadRatioZeroAt - r.loadRatioSafeMax
        return (100 * RobustStatistics.clamp((r.loadRatioZeroAt - ratio) / span, 0...1), 1)
    }

    /// EWMA con λ = 2 / (N + 1); `nil` se il carico cronico è nullo.
    public static func acuteChronicRatio(_ loads: [Double], config: EngineConfig = .current) -> Double? {
        let r = config.readiness
        let acuteLambda = 2 / (Double(r.acuteLoadDays) + 1)
        let chronicLambda = 2 / (Double(r.chronicLoadDays) + 1)
        // Entrambe le medie partono dal primo valore: un carico costante dà rapporto 1.
        let first = loads.first.map { $0.isFinite ? max($0, 0) : 0 } ?? 0
        var acute = first
        var chronic = first
        for load in loads.dropFirst() {
            let value = load.isFinite ? max(load, 0) : 0
            acute += acuteLambda * (value - acute)
            chronic += chronicLambda * (value - chronic)
        }
        guard chronic > 1e-9 else { return nil }
        return acute / chronic
    }

    /// Penalizza solo il deficit reale oltre quello pianificato di più di 10 punti percentuali.
    static func energyBalanceScore(_ e: EnergyBalance, config: EngineConfig) -> (score: Double, quality: Double)? {
        guard e.expenditureKcal > 0, e.averageIntakeKcal.isFinite, e.plannedTargetKcal.isFinite else { return nil }
        let actualDeficit = 100 * (e.expenditureKcal - e.averageIntakeKcal) / e.expenditureKcal
        let plannedDeficit = 100 * (e.expenditureKcal - e.plannedTargetKcal) / e.expenditureKcal
        let excess = actualDeficit - plannedDeficit - config.readiness.energyBalanceTolerancePoints
        guard excess > 0 else { return (100, 1) }
        return (100 - config.readiness.energyBalancePenaltyPerPoint * excess, 1)
    }

    static func performanceScore(_ residual: Double, config: EngineConfig) -> (score: Double, quality: Double)? {
        guard residual.isFinite else { return nil }
        let r = config.readiness
        return (r.performanceNeutralScore + r.performanceScorePerUnitResidual * residual, 1)
    }

    /// Dal quarto giorno consecutivo in poi: −25 punti per giorno.
    static func consecutiveDaysScore(_ days: Int, config: EngineConfig) -> (score: Double, quality: Double) {
        let r = config.readiness
        let over = days - r.consecutiveTrainingDaysPenaltyFrom + 1
        guard over > 0 else { return (100, 1) }
        return (max(100 - r.consecutiveDayPenalty * Double(over), 0), 1)
    }

    /// Carico di una giornata: Σ serie hard × I(RIR) (riscaldamenti esclusi).
    public static func dailyLoad(_ sets: [(rir: Double?, isWarmup: Bool)], config: EngineConfig = .current) -> Double {
        sets.filter { !$0.isWarmup }.reduce(0) { total, set in
            total + MuscleRecovery.intensity(rir: set.rir, isWarmup: false, config: config)
        }
    }
}
