import Foundation
import JevCore
import JevDomain

/// Progressive overload (§5.7): dalla serie di lavoro dell'ultima esposizione al target della
/// prossima. La tabella delle regole è completa e mutuamente esclusiva, valutata in ordine; il
/// default è "mantieni". Ogni decisione porta il numero della regola e un reason code.
public enum Progression {
    public enum Action: String, Sendable, Hashable, Codable, CaseIterable {
        case keep
        case increaseLoad = "increase_load"
        case increaseReps = "increase_reps"
        case regress
        case increaseDuration = "increase_duration"
        case decreaseDuration = "decrease_duration"
    }

    public struct Prescription: Sendable, Hashable {
        public var loadType: LoadType
        /// Passo di carico Δ in kg (> 0 salvo esercizi a tempo).
        public var incrementKg: Double
        public var repRange: ClosedRange<Int>
        public var targetRIR: Int
        /// Durata target per gli esercizi a tempo.
        public var targetDurationSeconds: Int?

        public init(loadType: LoadType, incrementKg: Double, repRange: ClosedRange<Int>, targetRIR: Int,
                    targetDurationSeconds: Int? = nil) {
            self.loadType = loadType
            self.incrementKg = incrementKg
            self.repRange = repRange
            self.targetRIR = targetRIR
            self.targetDurationSeconds = targetDurationSeconds
        }
    }

    public struct Context: Sendable, Hashable {
        /// Dolore segnalato sull'area negli ultimi 14 giorni e non ancora letto (QA-02).
        public var painBlocksIncrease: Bool
        /// Sessione di deload o ridotta.
        public var isDeload: Bool
        /// L'esposizione precedente era già sotto il target (per la regressione, regola 3).
        public var previousExposureUnderperformed: Bool

        public init(painBlocksIncrease: Bool = false, isDeload: Bool = false, previousExposureUnderperformed: Bool = false) {
            self.painBlocksIncrease = painBlocksIncrease
            self.isDeload = isDeload
            self.previousExposureUnderperformed = previousExposureUnderperformed
        }
    }

    public struct Decision: Sendable, Hashable {
        public var action: Action
        /// Regola della tabella §5.7 che ha deciso (0…6; 7–9 per gli esercizi a tempo).
        public var rule: Int
        /// Carico della prossima esposizione: esterno, zavorra o assistenza secondo il tipo.
        public var nextLoadKg: Double?
        public var nextReps: Int
        public var nextDurationSeconds: Int?
        /// `true` se l'esposizione è sotto il target: serve alla regola 3 la volta successiva.
        public var underperformed: Bool
        public var reasonCode: String
    }

    public static func decide(
        lastExposure: [PerformedSet], prescription p: Prescription, context: Context = .init()
    ) -> Decision {
        let sets = lastExposure.filter(\.isWorking)
        if p.loadType == .timed {
            return decideTimed(sets, prescription: p, context: context)
        }
        let lo = p.repRange.lowerBound, hi = p.repRange.upperBound
        let load = referenceLoad(sets)
        let reps = sets.map { $0.reps ?? 0 }
        let knownRIR = sets.compactMap(\.rir)
        let underperformingSets = sets.filter { set in
            (set.reps ?? 0) < lo || (set.rir.map { $0 < Double(p.targetRIR - 1) } ?? false)
        }.count
        let underperformed = underperformingSets >= 2

        func decision(_ action: Action, _ rule: Int, load nextLoad: Double?, reps nextReps: Int, _ code: String) -> Decision {
            // Il target di ripetizioni resta sempre dentro il range prescritto.
            let reps = min(max(nextReps, lo), hi)
            return Decision(action: action, rule: rule, nextLoadKg: nextLoad, nextReps: reps, nextDurationSeconds: nil,
                            underperformed: underperformed, reasonCode: "overload.\(code)")
        }

        // 0 — dolore non letto o deload: niente aumenti.
        if context.painBlocksIncrease || context.isDeload {
            return decision(.keep, 0, load: load, reps: min(max(reps.min() ?? lo, lo), hi), context.isDeload ? "keep_deload" : "keep_pain")
        }
        guard !sets.isEmpty else { return decision(.keep, 6, load: load, reps: lo, "keep_no_data") }
        // 1 — RIR mancante su tutte le serie: solo progressione per ripetizioni.
        if knownRIR.isEmpty {
            if reps.allSatisfy({ $0 >= hi }) {
                return decision(.increaseLoad, 1, load: increased(load, steps: 1, p), reps: lo, "load_increase_reps_only")
            }
            return decision(.increaseReps, 1, load: load, reps: min((reps.max() ?? lo) + 1, hi), "reps_increase_no_rir")
        }
        // 2 — tutte le serie al massimo del range con RIR ≥ target: aumento di carico.
        if reps.allSatisfy({ $0 >= hi }) && knownRIR.allSatisfy({ $0 >= Double(p.targetRIR) }) {
            let firstRIR = sets.first?.rir ?? 0
            let steps = firstRIR >= Double(p.targetRIR + 2) ? 2 : 1
            return decision(.increaseLoad, 2, load: increased(load, steps: steps, p), reps: lo,
                            steps == 2 ? "load_increase_double" : "load_increase")
        }
        // 3 — sotto il target per la seconda esposizione consecutiva: regressione.
        if underperformed && context.previousExposureUnderperformed {
            return decision(.regress, 3, load: regressed(load, p), reps: lo, "regress")
        }
        // 4 — sotto il target la prima volta: mantieni.
        if underperformed {
            return decision(.keep, 4, load: load, reps: min(max(reps.min() ?? lo, lo), hi), "keep_underperformed")
        }
        // 5 — double progression: ripetizioni nel range e sforzo coerente.
        let meanReps = Double(reps.reduce(0, +)) / Double(reps.count)
        let meanRIR = knownRIR.reduce(0, +) / Double(knownRIR.count)
        if meanReps >= Double(lo) && meanReps < Double(hi) && meanRIR >= Double(p.targetRIR - 1) {
            return decision(.increaseReps, 5, load: load, reps: min((reps.min() ?? lo) + 1, hi), "reps_increase")
        }
        // 6 — altrimenti: mantieni.
        return decision(.keep, 6, load: load, reps: min(max(reps.min() ?? lo, lo), hi), "keep")
    }

    /// Aggiustamento durante la sessione (§5.7): se la prima serie working devia dal RIR target
    /// di almeno 2, le serie successive cambiano del 2,5% (deviazione 2) o del 5% (≥ 3),
    /// arrotondato al passo e di almeno un passo. Restituisce il carico per le serie successive.
    public static func liveAdjustedLoad(firstSetLoadKg load: Double, firstSetRIR rir: Double, prescription p: Prescription) -> Double {
        let deviation = rir - Double(p.targetRIR)
        guard abs(deviation) >= 2, p.incrementKg > 0, load > 0 else { return load }
        let fraction = abs(deviation) >= 3 ? 0.05 : 0.025
        let direction: Double = deviation > 0 ? 1 : -1
        var change = roundToStep(load * fraction, p.incrementKg)
        if change < p.incrementKg { change = p.incrementKg }
        return max(load + direction * change, 0)
    }

    // MARK: Esercizi a tempo (regole 7–9)

    private static func decideTimed(_ sets: [PerformedSet], prescription p: Prescription, context: Context) -> Decision {
        let target = p.targetDurationSeconds ?? 30
        let durations = sets.map { $0.durationSeconds ?? 0 }
        let short = durations.filter { Double($0) < Double(target) * 0.8 }.count >= 2
        func decision(_ action: Action, _ rule: Int, _ next: Int, _ code: String) -> Decision {
            Decision(action: action, rule: rule, nextLoadKg: nil, nextReps: 1, nextDurationSeconds: next,
                     underperformed: short, reasonCode: "overload.\(code)")
        }
        if context.painBlocksIncrease || context.isDeload || sets.isEmpty {
            return decision(.keep, 0, target, "keep_timed")
        }
        if durations.allSatisfy({ $0 >= target }) {
            return decision(.increaseDuration, 7, target + max(5, target / 10), "duration_increase")
        }
        if short && context.previousExposureUnderperformed {
            return decision(.decreaseDuration, 8, max(target - 5, 5), "duration_decrease")
        }
        return decision(.keep, 9, target, "keep_timed")
    }

    // MARK: Carichi

    /// Carico di riferimento: il più alto tra le serie working (zavorra/assistenza per i corpo libero).
    static func referenceLoad(_ sets: [PerformedSet]) -> Double? {
        sets.compactMap(\.loadKg).max()
    }

    static func roundToStep(_ value: Double, _ step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// Aumento: Δ (o +2,5% arrotondato a Δ se maggiore) per ogni passo. Per gli esercizi
    /// assistiti "aumentare" significa ridurre l'assistenza; senza carico registrato a corpo
    /// libero la prima zavorra è Δ.
    static func increased(_ load: Double?, steps: Int, _ p: Prescription) -> Double? {
        let base = load ?? 0
        let step = max(p.incrementKg, roundToStep(base * 0.025, p.incrementKg))
        switch p.loadType {
        case .assisted:
            return max(base - step * Double(steps), 0)
        case .external, .bodyweight:
            return base + step * Double(steps)
        case .timed:
            return nil
        }
    }

    /// Regressione −5% arrotondata al passo, di almeno un passo (QA-16: −5% di 10 kg con Δ = 2
    /// non deve arrotondare a 0). Per gli assistiti aumenta l'assistenza.
    static func regressed(_ load: Double?, _ p: Prescription) -> Double? {
        guard let base = load else { return nil }
        let step = max(roundToStep(base * 0.05, p.incrementKg), p.incrementKg)
        switch p.loadType {
        case .assisted:
            return base + step
        case .external, .bodyweight:
            return max(base - step, 0)
        case .timed:
            return nil
        }
    }
}
