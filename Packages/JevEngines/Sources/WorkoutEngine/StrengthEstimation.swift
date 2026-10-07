import Foundation
import JevCore
import JevDomain

/// Una serie eseguita, come la vede l'engine (i valori canonici sono in kg e secondi).
public struct PerformedSet: Sendable, Hashable, Codable {
    public var type: SetType
    /// Carico usato per la progressione: peso esterno (external), zavorra (bodyweight),
    /// assistenza (assisted, valore positivo = aiuto). `nil` se non registrato.
    public var loadKg: Double?
    public var reps: Int?
    public var rir: Double?
    public var durationSeconds: Int?
    public var pain: PainLevel

    public init(type: SetType = .working, loadKg: Double? = nil, reps: Int? = nil, rir: Double? = nil,
                durationSeconds: Int? = nil, pain: PainLevel = .none) {
        self.type = type
        self.loadKg = loadKg
        self.reps = reps
        self.rir = rir
        self.durationSeconds = durationSeconds
        self.pain = pain
    }

    /// Serie che contano per progressione, e1RM e volume (tutto tranne il riscaldamento).
    public var isWorking: Bool { type.countsAsWorkingSet }
}

/// Stima del massimale (e1RM) e indice di forza (§5.7).
public enum StrengthEstimation {
    /// Carico effettivo sollevato per tipo di esercizio: external → carico; bodyweight →
    /// peso corporeo × frazione + zavorra; assisted → peso corporeo × frazione − assistenza;
    /// timed → nessun carico. `nil` se mancano i dati.
    public static func effectiveLoadKg(
        loadType: LoadType, loadKg: Double?, bodyweightKg: Double?, bodyweightFraction: Double?
    ) -> Double? {
        switch loadType {
        case .external:
            return loadKg
        case .bodyweight:
            guard let bw = bodyweightKg, let f = bodyweightFraction else { return nil }
            return bw * f + (loadKg ?? 0)
        case .assisted:
            guard let bw = bodyweightKg, let f = bodyweightFraction else { return nil }
            return max(bw * f - (loadKg ?? 0), 0)
        case .timed:
            return nil
        }
    }

    /// e1RM di una serie. Regole: reps ≥ 1, RIR noto e ≤ `e1rmMaxRIR` (3); ripetizioni a
    /// cedimento r' = reps + RIR; r' = 1 → carico; 2…10 → media di Epley e Brzycki;
    /// 11…12 → solo Epley; oltre → nessuna stima.
    public static func e1RM(loadKg: Double, reps: Int, rir: Double?, config: EngineConfig = .current) -> Double? {
        guard loadKg > 0, loadKg.isFinite, reps >= 1, let rir, rir >= 0,
              rir <= Double(config.progression.e1rmMaxRIR) else { return nil }
        let r = Double(reps) + rir
        guard r <= Double(config.progression.e1rmMaxRepsToFailure) else { return nil }
        if r <= 1 { return loadKg }
        let epley = loadKg * (1 + r / 30)
        if r <= 10 {
            let brzycki = loadKg * 36 / (37 - r)
            return (epley + brzycki) / 2
        }
        return epley
    }

    /// Migliore e1RM tra le serie working di un'esposizione.
    public static func bestE1RM(
        _ sets: [PerformedSet], loadType: LoadType, bodyweightKg: Double?, bodyweightFraction: Double?,
        config: EngineConfig = .current
    ) -> Double? {
        sets.filter(\.isWorking).compactMap { set -> Double? in
            guard let reps = set.reps,
                  let load = effectiveLoadKg(loadType: loadType, loadKg: set.loadKg, bodyweightKg: bodyweightKg,
                                             bodyweightFraction: bodyweightFraction)
            else { return nil }
            return e1RM(loadKg: load, reps: reps, rir: set.rir, config: config)
        }.max()
    }

    /// Indice di forza relativo (Epley con ripetizioni a cedimento fino a 20): per il trend e il
    /// plateau anche sugli esercizi ad alte ripetizioni. RIR mancante → 2 (valore tipico).
    public static func strengthIndex(loadKg: Double, reps: Int, rir: Double?, config: EngineConfig = .current) -> Double? {
        guard loadKg > 0, loadKg.isFinite, reps >= 1 else { return nil }
        let r = Double(reps) + min(rir ?? 2, 4)
        guard r <= Double(config.progression.strengthIndexMaxRepsToFailure) else { return nil }
        return loadKg * (1 + r / 30)
    }

    /// Volume di un'esposizione: Σ carico × reps sulle serie working (kg).
    public static func volumeKg(_ sets: [PerformedSet]) -> Double {
        sets.filter(\.isWorking).reduce(0) { sum, set in
            sum + (set.loadKg ?? 0) * Double(set.reps ?? 0)
        }
    }
}
