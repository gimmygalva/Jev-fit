import Foundation
import JevDomain
import Testing
@testable import NutritionEngine

@Suite("Macro AUTO / ASSISTED / MANUAL (§5.4)")
struct MacroPlannerTests {
    @Test("Peso di riferimento: trend, o peso a BMI 27 se BMI > 30 e % grasso ignota")
    func referenceWeight() {
        let capped = MacroPlanner.referenceWeightKg(trendWeightKg: 120, heightCm: 175, bodyFatKnown: false)
        let expected: Double = 27.0 * 1.75 * 1.75
        #expect(abs(capped - expected) < 1e-9)
        #expect(MacroPlanner.referenceWeightKg(trendWeightKg: 120, heightCm: 175, bodyFatKnown: true) == 120)
        #expect(MacroPlanner.referenceWeightKg(trendWeightKg: 80, heightCm: 180, bodyFatKnown: false) == 80)
    }

    @Test("AUTO: proteine per obiettivo, grassi 30%, carboidrati residuo, somma entro ±1%")
    func auto() {
        let macros = MacroPlanner.auto(kcal: 2500, goal: .hypertrophy, referenceWeightKg: 80)
        #expect(macros.proteinG == 144)
        #expect(macros.fatG == 83)
        #expect(macros.carbsG == 294)
        #expect(abs(macros.kcal - 2500) <= 25)
        #expect(macros.fiberG == 35)
        #expect(!macros.infeasible)
        #expect(macros.warnings.isEmpty)
    }

    @Test("AUTO con target basso: grassi al minimo, poi proteine verso 1,6 g/kg, poi infeasible")
    func autoLow() {
        let tight = MacroPlanner.auto(kcal: 1000, goal: .fatLoss, referenceWeightKg: 80)
        #expect(tight.fatG == 48)
        #expect(tight.proteinG == 142)
        #expect(tight.carbsG == 0)
        #expect(!tight.infeasible)
        let impossible = MacroPlanner.auto(kcal: 800, goal: .fatLoss, referenceWeightKg: 80)
        #expect(impossible.infeasible)
        #expect(impossible.proteinG == 128 && impossible.fatG == 48 && impossible.carbsG == 0)
    }

    @Test("ASSISTED: proteine bloccate sopra il minimo, ripartizione carboidrati/grassi, kcal ±1%")
    func assisted() {
        let half = MacroPlanner.assisted(kcal: 2500, goal: .hypertrophy, referenceWeightKg: 80, carbShare: 0.5)
        #expect(half.proteinG == 144)
        #expect(half.fatG == 107)
        #expect(abs(half.kcal - 2500) <= 25)
        let lowProtein = MacroPlanner.assisted(kcal: 2500, goal: .hypertrophy, referenceWeightKg: 80, carbShare: 0.5, proteinG: 100)
        #expect(lowProtein.proteinG == 128)
        let allCarbs = MacroPlanner.assisted(kcal: 2500, goal: .hypertrophy, referenceWeightKg: 80, carbShare: 1)
        #expect(allCarbs.fatG == 48)
        #expect(allCarbs.carbsG > half.carbsG)
        let invalid = MacroPlanner.assisted(kcal: 2500, goal: .hypertrophy, referenceWeightKg: 80, carbShare: .nan)
        #expect(invalid == half)
        let starving = MacroPlanner.assisted(kcal: 400, goal: .hypertrophy, referenceWeightKg: 80, carbShare: 0.5)
        #expect(starving.infeasible)
        #expect(starving.carbsG == 0 && starving.fatG == 0)
        #expect(starving.warnings == ["macro.fat_below_minimum"])
    }

    @Test("MANUAL: kcal derivate, avvisi non bloccanti sotto i minimi")
    func manual() {
        let macros = MacroPlanner.manual(proteinG: 100, carbsG: 200, fatG: 50, referenceWeightKg: 80)
        #expect(macros.kcal == 1650)
        #expect(macros.warnings == ["macro.protein_below_minimum"])
        #expect(macros.fiberG == 23)
        #expect(!macros.infeasible)
        let lowFat = MacroPlanner.manual(proteinG: 150, carbsG: 200, fatG: 30, referenceWeightKg: 80)
        #expect(lowFat.warnings == ["macro.fat_below_minimum"])
    }
}
