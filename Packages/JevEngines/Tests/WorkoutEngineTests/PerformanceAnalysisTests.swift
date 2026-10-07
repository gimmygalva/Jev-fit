import Foundation
import ExerciseCatalog
import JevCore
import JevDomain
import Testing
@testable import WorkoutEngine

@Suite("Trend di forza, plateau e record (§5.7)")
struct PerformanceAnalysisTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// Esposizioni ogni `everyDays` giorni con carico che cresce di `weeklyPercent` a settimana.
    private func history(count: Int, everyDays: Double = 4, weeklyPercent: Double, reps: Int = 8,
                         noise: Double = 0, seed: UInt64 = 1) -> [ExerciseExposure] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { i in
            let day = Double(i) * everyDays
            let jitter = noise == 0 ? 0 : (Double.random(in: -1...1, using: &generator) * noise)
            let load = 100 * pow(1 + weeklyPercent / 100, day / 7) * (1 + jitter)
            return ExerciseExposure(date: start.addingTimeInterval(day * 86_400),
                                    sets: [PerformedSet(loadKg: load, reps: reps, rir: 2)])
        }
    }

    @Test("Progressi dell'1% a settimana: nessun plateau")
    func progressing() {
        let result = PerformanceAnalysis.plateau(history(count: 8, weeklyPercent: 1), loadType: .external)
        #expect(!result.isPlateau)
        #expect(result.reasonCode == "plateau.progressing")
        #expect(abs((result.slopePercentPerWeek ?? 0) - 1) < 0.05)
    }

    @Test("Forza ferma per 6 esposizioni in 4 settimane: plateau")
    func flat() {
        let result = PerformanceAnalysis.plateau(history(count: 7, weeklyPercent: 0), loadType: .external)
        #expect(result.isPlateau)
        #expect(result.reasonCode == "plateau.detected")
        #expect(result.exposures == 7)
    }

    @Test("Dati insufficienti: meno di 6 esposizioni o meno di 21 giorni; i deload non contano")
    func insufficient() {
        #expect(PerformanceAnalysis.plateau(history(count: 5, weeklyPercent: 0), loadType: .external).reasonCode == "plateau.insufficient_data")
        #expect(!PerformanceAnalysis.plateau(history(count: 8, everyDays: 1, weeklyPercent: 0), loadType: .external).isPlateau)
        var withDeload = history(count: 6, weeklyPercent: 0)
        withDeload[2].isDeload = true
        #expect(PerformanceAnalysis.plateau(withDeload, loadType: .external).exposures == 5)
    }

    @Test("Un record di ripetizioni nell'ultima esposizione esclude il plateau")
    func repRecord() {
        var flat = history(count: 7, weeklyPercent: 0)
        flat[6].sets = [PerformedSet(loadKg: 100, reps: 10, rir: 1)]
        #expect(PerformanceAnalysis.plateau(flat, loadType: .external).reasonCode == "plateau.rep_record")
    }

    @Test("Regressione lineare e quantili t")
    func statistics() throws {
        let fit = try #require(PerformanceAnalysis.linearFit([0, 1, 2, 3], [1, 3, 5, 7]))
        #expect(abs(fit.slope - 2) < 1e-12 && abs(fit.intercept - 1) < 1e-12 && fit.slopeSE < 1e-9)
        #expect(PerformanceAnalysis.linearFit([1, 1, 1], [1, 2, 3]) == nil)
        #expect(PerformanceAnalysis.linearFit([1, 2], [1, 2]) == nil)
        #expect(PerformanceAnalysis.tQuantile(oneSided: 0.9, degreesOfFreedom: 1) == 3.078)
        #expect(PerformanceAnalysis.tQuantile(oneSided: 0.9, degreesOfFreedom: 0) == 3.078)
        #expect(abs(PerformanceAnalysis.tQuantile(oneSided: 0.9, degreesOfFreedom: 1_000) - 1.2816) < 0.01)
        #expect(abs(PerformanceAnalysis.tQuantile(oneSided: 0.975, degreesOfFreedom: 100) - 1.96) < 0.01)
    }

    @Test("e1RM stabile: filtrato in scala logaritmica, deload esclusi")
    func stable() throws {
        #expect(PerformanceAnalysis.stableE1RM([], loadType: .external) == nil)
        let steady = history(count: 10, weeklyPercent: 0)
        let estimate = try #require(PerformanceAnalysis.stableE1RM(steady, loadType: .external))
        let expected = try #require(StrengthEstimation.e1RM(loadKg: 100, reps: 8, rir: 2))
        #expect(abs(estimate.valueKg - expected) < 0.5)
        #expect(estimate.sdKg > 0)
    }

    @Test("Riepilogo di sessione: volume, serie per muscolo, record")
    func summary() throws {
        let catalog = try ExerciseCatalog.bundled()
        let past = [ExerciseExposure(date: start, sets: [PerformedSet(loadKg: 100, reps: 6, rir: 2)])]
        let session: [String: [PerformedSet]] = [
            "barbell_bench_press": [
                PerformedSet(type: .warmup, loadKg: 60, reps: 10),
                PerformedSet(loadKg: 100, reps: 8, rir: 2),
                PerformedSet(loadKg: 100, reps: 7, rir: 1),
            ],
            "lateral_raise": [PerformedSet(loadKg: 10, reps: 15, rir: 1)],
            "unknown_exercise": [PerformedSet(loadKg: 10, reps: 10, rir: 1)],
        ]
        let summary = PerformanceAnalysis.summarize(session: session, catalog: catalog,
                                                    history: ["barbell_bench_press": past], bodyweightKg: 80)
        let expectedVolume: Double = 800 + 700 + 150 + 100
        #expect(summary.volumeKg == expectedVolume)
        #expect(summary.workingSets == 4)
        #expect(summary.hardSetsByMuscle[.chest] == 2)
        #expect(summary.hardSetsByMuscle[.triceps] == 1)
        #expect(summary.hardSetsByMuscle[.sideDelts] == 1)
        let kinds = Set(summary.records.map(\.kind))
        #expect(kinds == [.e1rm, .repsAtWeight, .volume])
        #expect(summary.records.allSatisfy { $0.exerciseID == "barbell_bench_press" })
    }
}
