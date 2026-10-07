import Foundation
import Testing
@testable import JevCore

@Suite("LevelSlopeFilter — Kalman robusto livello + pendenza (§5.1)")
struct LevelSlopeFilterTests {
    /// Parametri del trend del peso (EngineConfig.trend): tarati perché una pesata anomala di
    /// +1,8 kg sposti il trend di meno di 0,2 kg.
    let weight = LevelSlopeFilter.Parameters(processNoise: 1e-5, measurementSD: 0.6, huberThreshold: 2.0, initialSlopeSD: 0.03)

    private func series(_ days: Range<Int>, _ value: (Int) -> Double) -> [LevelSlopeFilter.Observation] {
        days.map { .init(day: Double($0), value: value($0)) }
    }

    @Test("Serie vuota o con una sola osservazione")
    func degenerate() throws {
        #expect(LevelSlopeFilter.filter([], parameters: weight).isEmpty)
        #expect(LevelSlopeFilter.smooth([], parameters: weight).isEmpty)
        let one = LevelSlopeFilter.filter([.init(day: 0, value: 80)], parameters: weight)
        #expect(one.count == 1)
        #expect(one[0].level == 80)
        #expect(one[0].slope == 0)
        #expect(LevelSlopeFilter.smooth([.init(day: 0, value: 80)], parameters: weight).first?.level == 80)
    }

    @Test("Serie costante: il livello resta sul valore e la pendenza a zero")
    func constant() throws {
        let estimates = LevelSlopeFilter.filter(series(0..<30) { _ in 80 }, parameters: weight)
        let last = try #require(estimates.last)
        #expect(abs(last.level - 80) < 1e-9)
        #expect(abs(last.slope) < 1e-9)
        #expect(last.levelSD < 0.6, "L'incertezza si riduce con i dati")
    }

    @Test("Pesata anomala di +1,8 kg: il trend si sposta di meno di 0,2 kg e l'osservazione è de-pesata")
    func outlier() throws {
        let estimates = LevelSlopeFilter.filter(series(0..<30) { $0 == 20 ? 81.8 : 80 }, parameters: weight)
        let atOutlier = estimates[20]
        #expect(atOutlier.level - 80 < 0.2)
        #expect(atOutlier.observationWeight < 1)
        #expect(estimates[19].observationWeight == 1)
    }

    @Test("Rampa di −0,5 kg/settimana: la pendenza viene stimata")
    func ramp() throws {
        var generator = SeededGenerator(seed: 7)
        var errors: [Double] = []
        for _ in 0..<50 {
            let obs = series(0..<42) { day in 85 - 0.5 / 7 * Double(day) + gaussian(&generator) * 0.5 }
            let last = try #require(LevelSlopeFilter.filter(obs, parameters: weight).last)
            errors.append(abs(last.slope * 7 + 0.5))
        }
        let median = try #require(RobustStatistics.median(errors))
        #expect(median < 0.08, "Errore mediano della pendenza \(median) kg/settimana")
    }

    @Test("Buchi di 10 giorni: il filtro resta finito e segue il nuovo livello")
    func gaps() throws {
        let obs = series(0..<10) { _ in 80 } + series(20..<25) { _ in 79 }
        let estimates = LevelSlopeFilter.filter(obs, parameters: weight)
        #expect(estimates.count == 15)
        #expect(estimates.allSatisfy { $0.level.isFinite && $0.slope.isFinite && $0.levelSD.isFinite })
        #expect(estimates.last!.level < 80)
    }

    @Test("Una sola osservazione per giorno, valori non finiti scartati, ordine ricostruito")
    func prepare() {
        let prepared = LevelSlopeFilter.prepare([
            .init(day: 2, value: 79), .init(day: 1, value: 80), .init(day: 1, value: 99),
            .init(day: 3, value: .nan), .init(day: .infinity, value: 70),
        ])
        #expect(prepared == [.init(day: 1, value: 80), .init(day: 2, value: 79)])
    }

    @Test("Lo smoother usa anche i dati successivi: un gradino viene anticipato")
    func smoother() throws {
        let obs = series(0..<40) { $0 < 20 ? 80 : 78 }
        let filtered = LevelSlopeFilter.filter(obs, parameters: weight)
        let smoothed = LevelSlopeFilter.smooth(obs, parameters: weight)
        #expect(smoothed.count == filtered.count)
        #expect(smoothed[18].level < filtered[18].level, "Il livello lisciato prima del gradino scende già")
        #expect(abs(smoothed.last!.level - filtered.last!.level) < 1e-9, "All'ultimo punto coincidono")
        #expect(smoothed.allSatisfy { $0.levelSD.isFinite && $0.levelSD >= 0 })
    }

    @Test("Matrice 2×2: prodotto, inversa, simmetria")
    func matrix() throws {
        let m = Matrix2(a: 2, b: 1, c: 1, d: 3)
        let inverse = try #require(m.inverse)
        let identity = m * inverse
        #expect(abs(identity.a - 1) < 1e-12 && abs(identity.d - 1) < 1e-12)
        #expect(abs(identity.b) < 1e-12 && abs(identity.c) < 1e-12)
        #expect(Matrix2(a: 1, b: 2, c: 2, d: 4).inverse == nil)
        #expect(Matrix2(a: 1, b: 2, c: 4, d: 1).symmetrized == Matrix2(a: 1, b: 3, c: 3, d: 1))
        #expect((m - m) == Matrix2(a: 0, b: 0, c: 0, d: 0))
    }
}

/// Normale standard con Box–Muller, deterministica dato il generatore.
func gaussian(_ generator: inout SeededGenerator) -> Double {
    let u1 = max(Double.random(in: 0..<1, using: &generator), 1e-12)
    let u2 = Double.random(in: 0..<1, using: &generator)
    return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
}
