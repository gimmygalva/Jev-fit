import Foundation
import JevCore
import JevDomain
import Testing
@testable import NutritionEngine

/// Normale standard (Box–Muller) con il generatore deterministico.
private func gaussian(_ generator: inout SeededGenerator) -> Double {
    let u1 = max(Double.random(in: 0..<1, using: &generator), 1e-12)
    let u2 = Double.random(in: 0..<1, using: &generator)
    return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
}

/// Utente sintetico (§5.2): TDEE vero 2.600 kcal, intake medio 2.300 ± 250, errore di logging
/// 5%, bilancia ± 0,7 kg, prior sbagliato fino a ± 500 kcal.
private struct SyntheticUser {
    static let trueExpenditure = 2600.0
    let days: [ExpenditureEstimator.Day]
    let prior: (kcal: Double, sd: Double)

    init(seed: UInt64, days count: Int, missing: Double) {
        var generator = SeededGenerator(seed: seed &* 7919 &+ 17)
        var mass = 80.0
        let start = DayKey(year: 2026, month: 3, day: 1)!
        var days: [ExpenditureEstimator.Day] = []
        let priorError = Double.random(in: -500...500, using: &generator)
        for i in 0..<count {
            let eaten = 2300 + 250 * gaussian(&generator)
            let logged = eaten * (1 + 0.05 * gaussian(&generator))
            let isMissing = Double.random(in: 0..<1, using: &generator) < missing
            let weight = mass + 0.7 * gaussian(&generator)
            days.append(ExpenditureEstimator.Day(
                dayKey: start.adding(days: i), intakeKcal: isMissing ? nil : logged,
                isComplete: !isMissing, weightKg: weight
            ))
            mass += (eaten - Self.trueExpenditure) / 7700
        }
        self.days = days
        self.prior = (Self.trueExpenditure + priorError, 0.15 * Self.trueExpenditure)
    }
}

@Suite("Expenditure adattiva (§5.2)")
struct ExpenditureEstimatorTests {
    let day0 = DayKey(year: 2026, month: 2, day: 1)!

    private struct Summary {
        var median: Double
        var p90: Double
        var meanConfidence: Double
    }

    private func monteCarlo(days: Int, missing: Double, seeds: Int = 500) -> Summary {
        var errors: [Double] = []
        var confidence = 0.0
        for seed in 0..<seeds {
            let user = SyntheticUser(seed: UInt64(seed), days: days, missing: missing)
            guard let result = ExpenditureEstimator.estimate(days: user.days, prior: user.prior) else { continue }
            errors.append(abs(result.expenditureKcal - SyntheticUser.trueExpenditure))
            confidence += result.confidence
        }
        errors.sort()
        let n = errors.count
        return Summary(median: errors[n / 2], p90: errors[n * 9 / 10], meanConfidence: confidence / Double(n))
    }

    @Test("Monte Carlo su 500 seed, logging completo: 28 giorni mediana ≤ 120 e p90 ≤ 250; 56 giorni p90 ≤ 150")
    func monteCarloComplete() {
        let early = monteCarlo(days: 14, missing: 0)
        let d28 = monteCarlo(days: 28, missing: 0)
        let d56 = monteCarlo(days: 56, missing: 0)
        #expect(d28.median <= 120)
        #expect(d28.p90 <= 250)
        #expect(d56.p90 <= 150)
        #expect(early.meanConfidence < d28.meanConfidence)
        #expect(d28.meanConfidence < d56.meanConfidence)
    }

    @Test("Monte Carlo con 20% di giorni non registrati: soglie +25%")
    func monteCarloMissing() {
        let d28 = monteCarlo(days: 28, missing: 0.2)
        let d56 = monteCarlo(days: 56, missing: 0.2)
        #expect(d28.median <= 150)
        #expect(d28.p90 <= 312.5)
        #expect(d56.p90 <= 187.5)
        #expect(d28.meanConfidence < d56.meanConfidence)
    }

    @Test("Un intake da 40.000 kcal non confermato non corrompe la stima")
    func typo() throws {
        let user = SyntheticUser(seed: 42, days: 42, missing: 0)
        var corrupted = user.days
        corrupted[20].intakeKcal = 40_000
        let clean = try #require(ExpenditureEstimator.estimate(days: user.days, prior: user.prior))
        let dirty = try #require(ExpenditureEstimator.estimate(days: corrupted, prior: user.prior))
        #expect(abs(clean.expenditureKcal - dirty.expenditureKcal) < 150)
        // Confermato dall'utente, invece, conta.
        corrupted[20].intakeConfirmed = true
        let confirmed = try #require(ExpenditureEstimator.estimate(days: corrupted, prior: user.prior))
        #expect(abs(confirmed.expenditureKcal - clean.expenditureKcal) > 500)
    }

    @Test("Senza intake registrati l'expenditure resta al prior e la confidence è zero")
    func noLogging() throws {
        let days = (0..<30).map { ExpenditureEstimator.Day(dayKey: day0.adding(days: $0), weightKg: 80) }
        let result = try #require(ExpenditureEstimator.estimate(days: days, prior: (2500, 375)))
        #expect(abs(result.expenditureKcal - 2500) < 1e-9)
        #expect(result.sdKcal > 375)
        #expect(result.completeness == 0)
        #expect(result.confidence == 0)
        #expect(result.label == .initialEstimate)
        #expect(result.weighIns == 30)
        #expect(result.lastDay == day0.adding(days: 29))
    }

    @Test("Meno di due pesate: confidence zero; nessun giorno: nessuna stima")
    func sparse() throws {
        #expect(ExpenditureEstimator.estimate(days: [], prior: (2500, 375)) == nil)
        let days = (0..<10).map { i in
            ExpenditureEstimator.Day(dayKey: day0.adding(days: i), intakeKcal: 2500, isComplete: true,
                                     weightKg: i == 0 ? 80 : nil)
        }
        let result = try #require(ExpenditureEstimator.estimate(days: days, prior: (2500, 375)))
        #expect(result.weighIns == 1)
        #expect(result.confidence == 0)
        #expect(result.completeness == 1)
        // Pesata fuori scala ignorata.
        var outlier = days
        outlier[5].weightKg = 900
        #expect(ExpenditureEstimator.estimate(days: outlier, prior: (2500, 375))?.weighIns == 1)
    }

    @Test("Plausibilità dell'intake e intake utilizzabile")
    func plausibility() {
        #expect(ExpenditureEstimator.isPlausible(intakeKcal: 3000, expenditureKcal: 2500))
        #expect(!ExpenditureEstimator.isPlausible(intakeKcal: 7000, expenditureKcal: 3000))
        #expect(!ExpenditureEstimator.isPlausible(intakeKcal: 5500, expenditureKcal: 2000))
        #expect(!ExpenditureEstimator.isPlausible(intakeKcal: -1, expenditureKcal: 2000))
        let config = EngineConfig.current
        let incomplete = ExpenditureEstimator.Day(dayKey: day0, intakeKcal: 2000, isComplete: false)
        #expect(ExpenditureEstimator.usableIntake(incomplete, expenditure: 2500, config: config) == nil)
        let huge = ExpenditureEstimator.Day(dayKey: day0, intakeKcal: 9000, isComplete: true)
        #expect(ExpenditureEstimator.usableIntake(huge, expenditure: 2500, config: config) == nil)
        let confirmed = ExpenditureEstimator.Day(dayKey: day0, intakeKcal: 9000, isComplete: true, intakeConfirmed: true)
        #expect(ExpenditureEstimator.usableIntake(confirmed, expenditure: 2500, config: config) == 9000)
    }

    @Test("Cambio di intake oltre 300 kcal tra due settimane")
    func shift() {
        let base: [Double?] = Array(repeating: 2000, count: 7)
        #expect(!ExpenditureEstimator.intakeShift(base, threshold: 300))
        let up: [Double?] = base + Array(repeating: 2500, count: 7)
        #expect(ExpenditureEstimator.intakeShift(up, threshold: 300))
        let small: [Double?] = base + Array(repeating: 2100, count: 7)
        #expect(!ExpenditureEstimator.intakeShift(small, threshold: 300))
        let sparse: [Double?] = base + [2500, nil, nil, nil, nil, 2500, 2500]
        #expect(!ExpenditureEstimator.intakeShift(sparse, threshold: 300))
    }

    @Test("Dopo un cambio di intake la stima resta stabile")
    func afterShift() throws {
        // Intake 2.600 per 3 settimane poi 2.100, expenditure vera 2.600, pesate esatte.
        var mass = 80.0
        var days: [ExpenditureEstimator.Day] = []
        for i in 0..<56 {
            let intake: Double = i < 21 ? 2600 : 2100
            days.append(ExpenditureEstimator.Day(dayKey: day0.adding(days: i), intakeKcal: intake, isComplete: true, weightKg: mass))
            mass += (intake - 2600) / 7700
        }
        let result = try #require(ExpenditureEstimator.estimate(days: days, prior: (2400, 390)))
        #expect(abs(result.expenditureKcal - 2600) < 60)
        #expect(result.label == .reliable || result.label == .calibrating)
    }
}
