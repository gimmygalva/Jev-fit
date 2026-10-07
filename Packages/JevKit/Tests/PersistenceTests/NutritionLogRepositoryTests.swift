import Foundation
import JevCore
import JevDomain
import Testing
@testable import Persistence

@Suite("Diario alimentare, giorni, ricette e pesate (M9)")
struct NutritionLogRepositoryTests {
    let store: DataStore
    let repo: NutritionLogRepository
    let utc = TimeZone(identifier: "UTC")!
    let day = DayKey("2026-10-06")!
    let chicken = NutrientProfile(energyKcal: 110, proteinGrams: 23, carbohydrateGrams: 0, fatGrams: 1.5, fiberGrams: 0)
    let rice = NutrientProfile(energyKcal: 358, proteinGrams: 6.7, carbohydrateGrams: 79, fatGrams: 0.6, fiberGrams: 1)

    init() throws {
        store = try DataStore.inMemory()
        repo = NutritionLogRepository(facts: FactRepository(store: store, time: FixedTimeSource(Fixtures.start)))
    }

    @Test("Voce con snapshot scalato ai grammi e totali del giorno")
    func logAndTotals() throws {
        let entry = try repo.log(source: .catalog, sourceID: "chicken_breast_raw", name: "Petto di pollo", per100g: chicken,
                                 grams: 150, slot: .lunch, day: day, timeZone: utc)
        #expect(entry.energyKcal == 165 && entry.proteinG == 34.5 && entry.fatG == 2.3)
        try repo.quickAdd(energyKcal: 200, proteinG: 10, slot: .snack, day: day, timeZone: utc)
        let totals = try repo.totals(day: day)
        #expect(totals.energyKcal == 365 && totals.proteinG == 44.5)
        #expect(try repo.entries(day: day).count == 2)
        try repo.delete(entryID: entry.id)
        #expect(try repo.totals(day: day).energyKcal == 200)
    }

    @Test("Quantità e nutrienti non validi rifiutati")
    func invalid() throws {
        #expect(throws: NutritionLogRepository.NutritionError.invalidQuantity) {
            try repo.log(source: .catalog, sourceID: "x", name: "x", per100g: chicken, grams: 0, slot: .lunch, day: day)
        }
        let impossible = NutrientProfile(energyKcal: 1200, proteinGrams: 1, carbohydrateGrams: 1, fatGrams: 1)
        #expect(throws: NutritionLogRepository.NutritionError.invalidNutrients) {
            try repo.log(source: .catalog, sourceID: "x", name: "x", per100g: impossible, grams: 10, slot: .lunch, day: day)
        }
        #expect(throws: NutritionLogRepository.NutritionError.invalidNutrients) {
            try repo.quickAdd(energyKcal: -5, slot: .lunch, day: day)
        }
    }

    @Test("Copia del giorno precedente con nuovi id; il giorno sorgente non cambia")
    func copy() throws {
        let yesterday = day.adding(days: -1)
        try repo.log(source: .catalog, sourceID: "rice", name: "Riso", per100g: rice, grams: 80, slot: .lunch,
                     day: yesterday, timeZone: utc)
        try repo.quickAdd(energyKcal: 100, slot: .snack, day: yesterday, timeZone: utc)
        #expect(try repo.copyDay(from: yesterday, to: day, timeZone: utc) == 2)
        let copied = try repo.entries(day: day)
        let originals = try repo.entries(day: yesterday)
        #expect(copied.count == 2 && originals.count == 2)
        #expect(Set(copied.map(\.id)).isDisjoint(with: originals.map(\.id)))
        #expect(try repo.totals(day: day) == repo.totals(day: yesterday))
    }

    @Test("Stato del giorno: un solo record per giorno, aggiornato; intake per l'expenditure")
    func dayStatusAndIntake() throws {
        #expect(try repo.dayStatus(day) == nil)
        let first = try repo.setDay(day, status: .complete)
        let second = try repo.setDay(day, status: .incomplete, type: .training)
        #expect(first.id == second.id && second.status == .incomplete && second.dayType == .training)
        try repo.setDay(day, status: .complete)
        try repo.quickAdd(energyKcal: 2000, slot: .lunch, day: day)
        try repo.quickAdd(energyKcal: 500, slot: .dinner, day: day)
        try repo.quickAdd(energyKcal: 1800, slot: .lunch, day: day.adding(days: 1))
        let intake = try repo.intake(from: day.adding(days: -3), through: day.adding(days: 1))
        #expect(intake.count == 2)
        #expect(intake[0].day == day && intake[0].energyKcal == 2500 && intake[0].isComplete)
        #expect(intake[1].energyKcal == 1800 && !intake[1].isComplete)
    }

    @Test("Ricette: nutrienti come somma degli ingredienti, porzione registrata")
    func recipes() throws {
        let recipe = try repo.createRecipe(name: "  Riso e pollo ", servings: 2, ingredients: [
            .init(source: .catalog, sourceID: "rice", name: "Riso", grams: 200, per100g: rice),
            .init(source: .catalog, sourceID: "chicken", name: "Pollo", grams: 300, per100g: chicken),
        ])
        #expect(recipe.name == "Riso e pollo" && recipe.yieldGrams == 500)
        let total = try repo.recipeNutrients(recipe.id)
        #expect(abs(total.energyKcal - (716 + 330)) < 1e-9)
        let entry = try repo.logRecipe(recipe.id, servings: 1, slot: .dinner, day: day, timeZone: utc)
        #expect(entry.foodSource == .recipe && entry.grams == 250)
        #expect(abs(entry.energyKcal - 523) < 0.1)
        #expect(try repo.recipes().map(\.name) == ["Riso e pollo"])
        #expect(throws: NutritionLogRepository.NutritionError.invalidQuantity) {
            try repo.createRecipe(name: " ", ingredients: [])
        }
        #expect(throws: NutritionLogRepository.NutritionError.invalidNutrients) {
            try repo.createRecipe(name: "X", ingredients: [.init(source: .recipe, sourceID: "r", name: "r", grams: 10, per100g: rice)])
        }
        #expect(throws: NutritionLogRepository.NutritionError.notFound) {
            try repo.logRecipe(UUID(), servings: 1, slot: .dinner, day: day)
        }
    }

    @Test("Pesate manuali: limiti e lettura in ordine")
    func weights() throws {
        try repo.addWeight(kilograms: 80.4, at: Fixtures.start, timeZone: utc)
        try repo.addWeight(kilograms: 80.1, at: Fixtures.start.addingTimeInterval(86_400), timeZone: utc)
        #expect(throws: NutritionLogRepository.NutritionError.invalidQuantity) {
            try repo.addWeight(kilograms: 10, at: Fixtures.start)
        }
        let weights = try repo.weights(from: DayKey(date: Fixtures.start, timeZone: utc))
        #expect(weights.map(\.weightKg) == [80.4, 80.1])
        #expect(weights.allSatisfy { $0.source == .manual })
    }
}
