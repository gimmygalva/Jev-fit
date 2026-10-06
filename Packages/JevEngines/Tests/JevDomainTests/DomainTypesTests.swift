import Foundation
import Testing
@testable import JevDomain

@Suite("Tipi di dominio")
struct DomainTypesTests {
    @Test("17 gruppi muscolari, ognuno con una classe dimensionale")
    func muscles() {
        #expect(MuscleGroup.allCases.count == 17)
        #expect(MuscleGroup.quads.sizeClass == .large)
        #expect(MuscleGroup.calves.sizeClass == .small)
        #expect(MuscleGroup.chest.sizeClass == .medium)
        for size in MuscleSizeClass.allCases {
            #expect(MuscleGroup.allCases.contains { $0.sizeClass == size })
        }
    }

    @Test("Raw value stabili (finiscono nel database)")
    func stableRawValues() {
        #expect(GoalType.fatLoss.rawValue == "fat_loss")
        #expect(GoalType.generalFitness.rawValue == "general_fitness")
        #expect(SplitType.pushPullLegs.rawValue == "push_pull_legs")
        #expect(MuscleGroup.upperBack.rawValue == "upper_back")
        #expect(Equipment.smithMachine.rawValue == "smith_machine")
        #expect(GoalType.allCases.count == 6)
        #expect(SplitType.allCases.count == 6)
        #expect(SetType.allCases.count == 7)
        #expect(LoadType.allCases.count == 4)
    }

    @Test("Esperienza ordinata")
    func experience() {
        #expect(ExperienceLevel.beginner < .intermediate)
        #expect(ExperienceLevel.intermediate < .advanced)
        #expect(!(ExperienceLevel.advanced < .beginner))
    }

    @Test("Le serie di riscaldamento non contano come working")
    func warmups() {
        #expect(!SetType.warmup.countsAsWorkingSet)
        #expect(SetType.allCases.filter(\.countsAsWorkingSet).count == 6)
    }

    @Test("Profilo nutrizionale: scala per grammi e plausibilità")
    func nutrients() {
        let rice = NutrientProfile(energyKcal: 356, proteinGrams: 7, carbohydrateGrams: 79, fatGrams: 0.6, fiberGrams: 1.3)
        let portion = rice.scaled(toGrams: 80)
        #expect(abs(portion.energyKcal - 284.8) < 1e-9)
        #expect(abs(portion.fiberGrams! - 1.04) < 1e-9)
        #expect(rice.isPhysicallyPlausiblePer100g)
        // Atwater: 4 kcal/g proteine e carboidrati, 9 kcal/g grassi. Tipo esplicito per il type-checker.
        let expectedAtwater: Double = 7.0 * 4.0 + 79.0 * 4.0 + 0.6 * 9.0
        #expect(abs(rice.atwaterEnergyKcal - expectedAtwater) < 1e-9)
        let noFiber = NutrientProfile(energyKcal: 100, proteinGrams: 1, carbohydrateGrams: 1, fatGrams: 1)
        #expect(noFiber.scaled(toGrams: 50).fiberGrams == nil)
        #expect(!NutrientProfile(energyKcal: -1, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0).isPhysicallyPlausiblePer100g)
        #expect(!NutrientProfile(energyKcal: 950, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 100).isPhysicallyPlausiblePer100g)
        #expect(!NutrientProfile(energyKcal: 400, proteinGrams: 60, carbohydrateGrams: 60, fatGrams: 0).isPhysicallyPlausiblePer100g)
        #expect(!NutrientProfile(energyKcal: .nan, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0).isPhysicallyPlausiblePer100g)
    }
}
