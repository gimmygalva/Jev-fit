import Foundation
import JevDomain
import Testing
@testable import RecoveryEngine

@Suite("JEV READINESS (§5.9)")
struct ReadinessTests {
    /// Solo dati disponibili con l'iPhone: niente sonno, HRV né FC a riposo.
    private var iPhoneOnly: Readiness.Input {
        Readiness.Input(
            sessionRecoveryPercent: 80,
            subjective: Readiness.Subjective(sleepQuality: 4, energy: 4, soreness: 2),
            dailyTrainingLoad: Array(repeating: 10, count: 28),
            energyBalance: Readiness.EnergyBalance(averageIntakeKcal: 2000, expenditureKcal: 2500, plannedTargetKcal: 2000),
            performanceResidual: 0,
            consecutiveTrainingDays: 2
        )
    }

    @Test("Nessun componente: nessun punteggio")
    func empty() {
        #expect(Readiness.compute(Readiness.Input()) == nil)
    }

    @Test("Con soli dati iPhone il punteggio è valido, pesi rinormalizzati, confidence più bassa")
    func iPhone() throws {
        let result = try #require(Readiness.compute(iPhoneOnly))
        #expect(result.score == 84)
        #expect(result.band == .good)
        #expect(abs(result.confidence - 0.62) < 1e-9)
        #expect(result.confidenceLabel == .calibrating)
        #expect(Set(result.missing) == [.sleep, .heartRateVariability, .restingHeartRate])
        #expect(result.components.count == 6)
    }

    @Test("Con tutti i componenti la confidence è piena")
    func full() throws {
        var input = iPhoneOnly
        input.sleep = Readiness.Sleep(lastNightHours: 8, threeNightAverageHours: 8, needHours: 8)
        let baseline: [Double] = Array(repeating: [4.0, 4.2], count: 7).flatMap { $0 }
        input.hrv = Readiness.Baseline(recent: Array(repeating: 4.1, count: 7), baseline: baseline)
        let heart: [Double] = Array(repeating: [58.0, 62.0], count: 7).flatMap { $0 }
        input.restingHeartRate = Readiness.Baseline(recent: [60], baseline: heart)
        let result = try #require(Readiness.compute(input))
        #expect(abs(result.confidence - 1) < 1e-9)
        #expect(result.confidenceLabel == .reliable)
        #expect(result.missing.isEmpty)
        let hrv = try #require(result.components.first { $0.component == .heartRateVariability })
        #expect(abs(hrv.score - 50) < 1e-9)
    }

    @Test("Sonno: rapporto sul fabbisogno, qualità ridotta con una sola notte")
    func sleep() throws {
        let config = EngineConfig.current
        let partial = try #require(Readiness.sleepScore(Readiness.Sleep(lastNightHours: 6.4, needHours: 8), config: config))
        #expect(abs(partial.score - 50) < 1e-9)
        #expect(partial.quality == 0.6)
        let averaged = try #require(Readiness.sleepScore(
            Readiness.Sleep(lastNightHours: 8, threeNightAverageHours: 4.8, needHours: 8), config: config))
        #expect(abs(averaged.score - 50) < 1e-9 && averaged.quality == 1)
        #expect(Readiness.sleepScore(Readiness.Sleep(lastNightHours: 3, needHours: 8), config: config)?.score == 0)
        #expect(Readiness.sleepScore(Readiness.Sleep(lastNightHours: 10, needHours: 8), config: config)?.score == 100)
        #expect(Readiness.sleepScore(Readiness.Sleep(lastNightHours: 8, needHours: 0), config: config) == nil)
    }

    @Test("Check soggettivo 1–5 con indolenzimento invertito")
    func subjective() {
        #expect(Readiness.subjectiveScore(Readiness.Subjective(sleepQuality: 5, energy: 5, soreness: 1))?.score == 100)
        #expect(Readiness.subjectiveScore(Readiness.Subjective(sleepQuality: 1, energy: 1, soreness: 5))?.score == 0)
        #expect(Readiness.subjectiveScore(Readiness.Subjective(sleepQuality: 0, energy: 3, soreness: 3)) == nil)
    }

    @Test("HRV e FC a riposo rispetto alla baseline personale, con minimi di campioni")
    func baselines() throws {
        let config = EngineConfig.current
        let baseline: [Double] = Array(repeating: [4.0, 4.2], count: 7).flatMap { $0 }
        let high = try #require(Readiness.zScoreComponent(
            Readiness.Baseline(recent: Array(repeating: 4.2, count: 7), baseline: baseline),
            minimumRecent: 5, minimumSD: 0.05, higherIsBetter: true, config: config))
        let sd: Double = 0.1 * (14.0 / 13.0).squareRoot()
        let expected: Double = 50 + 25 * (0.1 / sd)
        #expect(abs(high.score - expected) < 1e-9)
        #expect(Readiness.zScoreComponent(Readiness.Baseline(recent: [4.2, 4.2, 4.2, 4.2], baseline: baseline),
                                          minimumRecent: 5, minimumSD: 0.05, higherIsBetter: true, config: config) == nil)
        #expect(Readiness.zScoreComponent(Readiness.Baseline(recent: [4.2, 4.2, 4.2, 4.2, 4.2], baseline: [4.1]),
                                          minimumRecent: 5, minimumSD: 0.05, higherIsBetter: true, config: config) == nil)
        let heart: [Double] = Array(repeating: [58.0, 62.0], count: 7).flatMap { $0 }
        var input = Readiness.Input(restingHeartRate: Readiness.Baseline(recent: [64], baseline: heart))
        let elevated = try #require(Readiness.compute(input))
        #expect(elevated.score < 10)
        input.restingHeartRate = Readiness.Baseline(recent: [56], baseline: heart)
        #expect((Readiness.compute(input)?.score ?? 0) > 90)
    }

    @Test("Carico: attivo con ≥ 21 giorni, penalizza solo un rapporto acuto/cronico oltre 1,3")
    func trainingLoad() throws {
        let config = EngineConfig.current
        #expect(Readiness.trainingLoadScore(Array(repeating: 10, count: 20), config: config) == nil)
        #expect(Readiness.trainingLoadScore(Array(repeating: 10, count: 28), config: config)?.score == 100)
        #expect(Readiness.trainingLoadScore(Array(repeating: 0, count: 28), config: config)?.score == 100)
        let spike: [Double] = Array(repeating: 10, count: 21) + Array(repeating: 40, count: 7)
        let ratio = try #require(Readiness.acuteChronicRatio(spike))
        #expect(abs(ratio - 1.6506) < 0.001)
        let score = try #require(Readiness.trainingLoadScore(spike, config: config)?.score)
        #expect(abs(score - 49.92) < 0.1)
        let constant = try #require(Readiness.acuteChronicRatio(Array(repeating: 12, count: 30)))
        #expect(abs(constant - 1) < 1e-12)
        #expect(Readiness.acuteChronicRatio([]) == nil)
    }

    @Test("Bilancio energetico: penalità solo oltre 10 punti di deficit in più del piano")
    func energy() {
        let config = EngineConfig.current
        let planned = Readiness.EnergyBalance(averageIntakeKcal: 2000, expenditureKcal: 2500, plannedTargetKcal: 2000)
        #expect(Readiness.energyBalanceScore(planned, config: config)?.score == 100)
        let deeper = Readiness.EnergyBalance(averageIntakeKcal: 1500, expenditureKcal: 2500, plannedTargetKcal: 2000)
        let deeperScore = Readiness.energyBalanceScore(deeper, config: config)?.score ?? 0
        #expect(abs(deeperScore - 50) < 1e-9)
        let invalid = Readiness.EnergyBalance(averageIntakeKcal: 1500, expenditureKcal: 0, plannedTargetKcal: 2000)
        #expect(Readiness.energyBalanceScore(invalid, config: config) == nil)
        let starving = Readiness.Input(energyBalance: Readiness.EnergyBalance(averageIntakeKcal: 0, expenditureKcal: 2500, plannedTargetKcal: 2000))
        #expect(Readiness.compute(starving)?.score == 0)
    }

    @Test("Performance e giorni consecutivi")
    func performanceAndStreak() {
        let config = EngineConfig.current
        #expect(Readiness.performanceScore(0, config: config)?.score == 70)
        let below = Readiness.performanceScore(-0.05, config: config)?.score ?? 0
        #expect(abs(below - 40) < 1e-9)
        #expect(Readiness.performanceScore(.nan, config: config) == nil)
        #expect(Readiness.compute(Readiness.Input(performanceResidual: 0.2))?.score == 100)
        #expect(Readiness.consecutiveDaysScore(3, config: config).score == 100)
        #expect(Readiness.consecutiveDaysScore(4, config: config).score == 75)
        #expect(Readiness.consecutiveDaysScore(7, config: config).score == 0)
    }

    @Test("Un componente con peso nullo non entra né tra i mancanti")
    func zeroWeight() throws {
        var config = EngineConfig.current
        config.readiness.weights[.performance] = 0
        let result = try #require(Readiness.compute(iPhoneOnly, config: config))
        #expect(!result.components.contains { $0.component == .performance })
        #expect(!result.missing.contains(.performance))
    }

    @Test("Carico giornaliero: serie hard × I(RIR), riscaldamenti esclusi")
    func dailyLoad() {
        let load = Readiness.dailyLoad([(rir: 1, isWarmup: false), (rir: nil, isWarmup: false), (rir: 0, isWarmup: true)])
        #expect(abs(load - 1.7) < 1e-12)
    }
}
