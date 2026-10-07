import Foundation
import JevDomain
import Testing
@testable import NutritionEngine

@Suite("Target calorico, calorie cycling, aggiustamento (§5.3)")
struct CalorieTargetsTests {
    @Test("Media = E + ritmo × peso × ρ / 7, ritmo nei limiti, floor max(BMR, 1.200)")
    func dailyTarget() {
        let loss = CalorieTargets.dailyTarget(expenditureKcal: 2600, weightKg: 80, goal: .fatLoss,
                                              ratePercentPerWeek: -0.5, bmrKcal: 1780)
        #expect(loss.kcal == 2160)
        #expect(loss.ratePercentPerWeek == -0.5)
        #expect(!loss.floorApplied)
        let aggressive = CalorieTargets.dailyTarget(expenditureKcal: 2600, weightKg: 80, goal: .fatLoss,
                                                    ratePercentPerWeek: -3, bmrKcal: 1780)
        #expect(aggressive.ratePercentPerWeek == -1)
        #expect(aggressive.floorApplied)
        #expect(aggressive.kcal == 1780)
        let gain = CalorieTargets.dailyTarget(expenditureKcal: 2600, weightKg: 80, goal: .hypertrophy,
                                              ratePercentPerWeek: 0.25, bmrKcal: 1780)
        #expect(gain.kcal == 2820)
        let maintain = CalorieTargets.dailyTarget(expenditureKcal: 2604, weightKg: 80, goal: .maintenance,
                                                  ratePercentPerWeek: -0.5, bmrKcal: 1780)
        #expect(maintain.kcal == 2600)
        #expect(maintain.ratePercentPerWeek == 0)
        let gated = CalorieTargets.dailyTarget(expenditureKcal: 2600, weightKg: 80, goal: .fatLoss,
                                               ratePercentPerWeek: -0.5, bmrKcal: 1780, deficitAllowed: false)
        #expect(gated.kcal == 2600)
        #expect(CalorieTargets.floor(bmrKcal: 1000) == 1200)
        #expect(CalorieTargets.floor(bmrKcal: 1500) == 1500)
    }

    @Test("Cycling: somma settimanale esatta, rapporto rispettato quando sicuro")
    func cycling() {
        let schedule: [DayType] = [.training, .rest, .training, .rest, .training, .rest, .training]
        let cycle = CalorieTargets.cycle(averageKcal: 2000, schedule: schedule, ratio: 1.1, floorKcal: 1500)
        #expect(cycle.kcal.reduce(0, +) == 14_000)
        #expect(abs(cycle.effectiveRatio - 1.1) < 1e-12)
        #expect(cycle.kcal[0] > cycle.kcal[1])
        let allowed: ClosedRange<Double> = 1700...2300
        #expect(cycle.kcal.allSatisfy { allowed.contains($0) })
        #expect(!cycle.belowFloor)
    }

    @Test("Esempio del piano: A = 1.500, t = 6, r = 1,30 non scende sotto il floor né oltre il ±15%")
    func cyclingLimits() {
        let schedule: [DayType] = [.training, .training, .training, .rest, .training, .training, .training]
        let cycle = CalorieTargets.cycle(averageKcal: 1500, schedule: schedule, ratio: 1.3, floorKcal: 1200)
        #expect(cycle.effectiveRatio < 1.3)
        let restBound: Double = 7.0 / 0.85 - 1.0
        let expectedRatio: Double = restBound / 6.0
        #expect(abs(cycle.effectiveRatio - expectedRatio) < 1e-9)
        #expect(cycle.kcal.reduce(0, +) == 10_500)
        #expect(cycle.kcal.allSatisfy { $0 >= 1200 })
        #expect(cycle.kcal[3] >= 1270)
    }

    @Test("Cycling degenere: nessun allenamento, tutti allenamenti, rapporto < 1, schema vuoto")
    func cyclingDegenerate() {
        let rest = CalorieTargets.cycle(averageKcal: 2000, schedule: Array(repeating: .rest, count: 7), ratio: 1.2, floorKcal: 1500)
        #expect(rest.kcal == Array(repeating: 2000, count: 7))
        #expect(rest.effectiveRatio == 1)
        let training = CalorieTargets.cycle(averageKcal: 2003, schedule: Array(repeating: .training, count: 7), ratio: 1.2, floorKcal: 1500)
        #expect(training.kcal.reduce(0, +) == 14_020)
        let flat = CalorieTargets.cycle(averageKcal: 2000, schedule: [.training, .rest], ratio: 0.8, floorKcal: 1500)
        #expect(flat.kcal == [2000, 2000])
        #expect(CalorieTargets.cycle(averageKcal: 2000, schedule: [], ratio: 1.2, floorKcal: 1500).kcal.isEmpty)
        let low = CalorieTargets.cycle(averageKcal: 1100, schedule: [.training, .rest], ratio: 1.2, floorKcal: 1200)
        #expect(low.belowFloor)
    }

    @Test("Ribilanciamento a metà settimana senza scendere sotto il floor")
    func rebalance() {
        let remaining: [DayType] = [.training, .rest, .training, .rest]
        let result = CalorieTargets.rebalance(weeklyTotalKcal: 14_000, pastDaysKcal: [2080, 2080, 1890],
                                              remaining: remaining, ratio: 1.1, floorKcal: 1500)
        #expect(result.kcal.count == 4)
        #expect(result.kcal.reduce(0, +) == 7950)
        #expect(result.kcal[0] > result.kcal[1])
        let starved = CalorieTargets.rebalance(weeklyTotalKcal: 10_000, pastDaysKcal: [3000, 3000, 3000],
                                               remaining: remaining, ratio: 1.1, floorKcal: 1234)
        #expect(starved.belowFloor)
        #expect(starved.kcal == Array(repeating: 1240, count: 4))
        #expect(CalorieTargets.rebalance(weeklyTotalKcal: 14_000, pastDaysKcal: [], remaining: [], ratio: 1.1,
                                         floorKcal: 1500).kcal.isEmpty)
    }

    @Test("Aggiustamento: dead band ±50, passo ±150 automatico, ±250 manuale, mai sotto il floor")
    func adjustment() {
        let still = CalorieTargets.adjust(currentKcal: 2000, proposedKcal: 2030, floorKcal: 1500)
        #expect(still.kcal == 2000 && still.deltaKcal == 0 && still.reasonCode == "target.dead_band")
        let small = CalorieTargets.adjust(currentKcal: 2000, proposedKcal: 2100, floorKcal: 1500)
        #expect(small.kcal == 2100 && small.reasonCode == "target.adjusted")
        let limited = CalorieTargets.adjust(currentKcal: 2000, proposedKcal: 2400, floorKcal: 1500)
        #expect(limited.kcal == 2150 && limited.reasonCode == "target.limited")
        let manual = CalorieTargets.adjust(currentKcal: 2000, proposedKcal: 2400, floorKcal: 1500, manual: true)
        #expect(manual.kcal == 2250)
        let floored = CalorieTargets.adjust(currentKcal: 1600, proposedKcal: 1000, floorKcal: 1500)
        #expect(floored.kcal == 1500 && floored.deltaKcal == -100 && floored.reasonCode == "target.floor")
    }

    @Test("Arrotondamento a 10 kcal mai sotto il minimo")
    func rounding() {
        #expect(CalorieTargets.roundUp10(1234, minimum: 1234) == 1240)
        #expect(CalorieTargets.roundUp10(1236, minimum: 1200) == 1240)
        #expect(CalorieTargets.roundUp10(1234, minimum: 1200) == 1230)
    }
}
