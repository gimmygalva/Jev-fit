import Foundation
import Testing
@testable import JevDomain

/// Invarianti della configurazione: se uno di questi test fallisce, una soglia è stata
/// modificata in modo incoerente (QA-10, ADR-013).
@Suite("EngineConfig v1 — invarianti")
struct EngineConfigTests {
    let config = EngineConfig.v1

    @Test("I pesi della readiness coprono tutti i componenti e sommano a 1")
    func readinessWeights() {
        let weights = config.readiness.weights
        #expect(Set(weights.keys) == Set(ReadinessComponent.allCases))
        #expect(abs(weights.values.reduce(0, +) - 1) < 1e-9)
        #expect(weights.values.allSatisfy { $0 > 0 })
    }

    @Test("Fasce 0–100 allineate a PRODUCT_SPEC (40 / 65 / 85)", arguments: [
        (0.0, ScoreBand.low), (39.9, ScoreBand.low), (40.0, ScoreBand.moderate), (64.9, ScoreBand.moderate),
        (65.0, ScoreBand.good), (84.9, ScoreBand.good), (85.0, ScoreBand.high), (100.0, ScoreBand.high),
        (-Double.infinity, ScoreBand.low),
    ] as [(Double, ScoreBand)])
    func scoreBands(score: Double, expected: ScoreBand) {
        #expect(config.scoreBands.band(for: score) == expected)
    }

    @Test("NaN non causa crash e cade nella fascia bassa")
    func nanBand() {
        #expect(config.scoreBands.band(for: .nan) == .low)
        #expect(config.confidence.label(for: .nan) == .initialEstimate)
    }

    @Test("Etichette confidence (50% / 80%)", arguments: [
        (0.0, ConfidenceLabel.initialEstimate), (0.49, ConfidenceLabel.initialEstimate),
        (0.5, ConfidenceLabel.calibrating), (0.79, ConfidenceLabel.calibrating),
        (0.8, ConfidenceLabel.reliable), (0.99, ConfidenceLabel.reliable),
    ] as [(Double, ConfidenceLabel)])
    func confidenceLabels(value: Double, expected: ConfidenceLabel) {
        #expect(config.confidence.label(for: value) == expected)
    }

    @Test("Un config incoerente non causa trap")
    func incoherentConfigDoesNotTrap() {
        var broken = config
        broken.scoreBands = .init(moderateFrom: 90, goodFrom: 50, highFrom: 10)
        _ = broken.scoreBands.band(for: 30)
        broken.confidence = .init(calibratingFrom: 0.9, reliableFrom: 0.1)
        _ = broken.confidence.label(for: 0.5)
    }

    @Test("Calibrazione del recupero: 6 serie a RIR 1 → 35%, ritorno al 90% in ~69 h con τ = 30 h")
    func recoveryCalibration() {
        let fRef = config.recovery.referenceFatigue
        #expect(abs(fRef - 5.143) < 0.01)
        let dose = 6 * 0.9
        let recoveryAfter = 100 * exp(-dose / fRef)
        #expect(abs(recoveryAfter - 35) < 1e-9)
        // Tempo perché la fatica scenda al livello del 90%: t = τ·ln(F / (F_ref·ln(100/90)))
        let hours = 30 * log(dose / (fRef * log(100.0 / 90.0)))
        #expect(abs(hours - 69.0) < 0.2)
        #expect(config.recovery.readyThresholdPercent == 90)
    }

    @Test("Costanti di recupero coprono tutte le classi e crescono con la dimensione")
    func recoveryTau() {
        let tau = config.recovery.baseTauHours
        #expect(Set(tau.keys) == Set(MuscleSizeClass.allCases))
        #expect(tau[.small]! < tau[.medium]!)
        #expect(tau[.medium]! < tau[.large]!)
        #expect(config.recovery.userTauMultiplierRange.contains(1))
    }

    @Test("Nutrizione: limiti coerenti e proteine per ogni obiettivo sopra il minimo")
    func nutrition() {
        let n = config.nutrition
        #expect(Set(n.proteinGramsPerKg.keys) == Set(GoalType.allCases))
        #expect(n.proteinGramsPerKg.values.allSatisfy { $0 >= n.proteinFloorGramsPerKg })
        #expect(n.minLossPercentPerWeek < n.maxLossPercentPerWeek)
        #expect(n.minGainPercentPerWeek < n.maxGainPercentPerWeek)
        #expect(n.adjustmentDeadBandKcal < n.automaticAdjustmentLimitKcal)
        #expect(n.automaticAdjustmentLimitKcal <= n.manualAdjustmentLimitKcal)
        #expect(n.priorRelativeSD < n.priorRelativeSDWithoutSex)
        #expect(n.fatEnergyShare > 0 && n.fatEnergyShare < 1)
        #expect(n.referenceWeightBMITarget < n.referenceWeightBMICap)
    }

    @Test("Check-in e progressione: soglie ordinate in modo sensato")
    func checkInAndProgression() {
        let c = config.checkIn
        #expect(c.reduceLoadReadinessBelow < c.increaseLoadReadinessFrom)
        #expect(c.deloadReadinessBelow <= c.reduceLoadReadinessBelow)
        #expect(c.safetyMaxLossPercentPerWeek > config.nutrition.maxLossPercentPerWeek)
        #expect(c.minimumCompleteLoggedDays <= 7 && c.minimumWeighIns <= 7)
        let p = config.progression
        #expect(p.e1rmMaxRepsToFailure < p.strengthIndexMaxRepsToFailure)
        #expect(p.plateauConfidenceLevel > 0.5 && p.plateauConfidenceLevel < 1)
        #expect(p.deloadSetReduction > 0 && p.deloadSetReduction < 1)
        #expect(EngineConfig.current == EngineConfig.v1)
        #expect(EngineConfig.current.version >= 1)
    }
}
