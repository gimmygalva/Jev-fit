import Foundation
import GRDB
import JevCore
import JevDomain

/// Diario alimentare (M9): voci con snapshot dei nutrienti, stato del giorno, copia di un giorno,
/// ricette e pesate. Funziona interamente offline (fatti locali + outbox).
public struct NutritionLogRepository: Sendable {
    public let facts: FactRepository

    public init(facts: FactRepository) {
        self.facts = facts
    }

    public enum NutritionError: Error, Equatable {
        case invalidQuantity
        case invalidNutrients
        case notFound
    }

    /// Totali di un insieme di voci.
    public struct Totals: Sendable, Equatable {
        public var energyKcal: Double = 0
        public var proteinG: Double = 0
        public var carbsG: Double = 0
        public var fatG: Double = 0
        public var fiberG: Double = 0

        public init() {}

        mutating func add(_ entry: FoodLogEntryRecord) {
            energyKcal += entry.energyKcal
            proteinG += entry.proteinG
            carbsG += entry.carbsG
            fatG += entry.fatG
            fiberG += entry.fiberG ?? 0
        }
    }

    // MARK: Voci

    /// Registra `grams` grammi di un alimento: i nutrienti sono copiati (snapshot), quindi lo
    /// storico non cambia se il provider modifica il prodotto.
    @discardableResult
    public func log(
        source: FoodSource, sourceID: String, name: String, per100g: NutrientProfile, grams: Double,
        slot: MealSlot, day: DayKey, timeZone: TimeZone = .current, servings: Double? = nil, servingLabel: String? = nil
    ) throws -> FoodLogEntryRecord {
        guard grams.isFinite, grams > 0, grams <= 10_000 else { throw NutritionError.invalidQuantity }
        guard Self.isValid(per100g) else { throw NutritionError.invalidNutrients }
        let n = per100g.scaled(toGrams: grams)
        let now = facts.time.now()
        return try facts.save(FoodLogEntryRecord(
            id: UUIDv7.make(at: now), dayKey: day, tz: timeZone.identifier, mealSlot: slot, loggedAt: now,
            foodSource: source, foodSourceId: String(sourceID.prefix(64)), foodName: String(name.prefix(160)),
            grams: grams, servings: servings, servingLabel: servingLabel,
            energyKcal: Self.round(n.energyKcal), proteinG: Self.round(n.proteinGrams),
            carbsG: Self.round(n.carbohydrateGrams), fatG: Self.round(n.fatGrams),
            fiberG: n.fiberGrams.map(Self.round), createdAt: now, updatedAt: now
        ))
    }

    /// Aggiunta rapida di sole calorie e macro (senza alimento).
    @discardableResult
    public func quickAdd(
        energyKcal: Double, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0,
        slot: MealSlot, day: DayKey, timeZone: TimeZone = .current
    ) throws -> FoodLogEntryRecord {
        let values = [energyKcal, proteinG, carbsG, fatG]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }), energyKcal <= 20_000,
              proteinG <= 2_000, carbsG <= 2_000, fatG <= 2_000 else { throw NutritionError.invalidNutrients }
        let now = facts.time.now()
        return try facts.save(FoodLogEntryRecord(
            id: UUIDv7.make(at: now), dayKey: day, tz: timeZone.identifier, mealSlot: slot, loggedAt: now,
            foodSource: .quickAdd, energyKcal: energyKcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG,
            createdAt: now, updatedAt: now
        ))
    }

    public func entries(day: DayKey) throws -> [FoodLogEntryRecord] {
        try facts.writer.read { db in
            try FoodLogEntryRecord
                .filter(Column("day_key") == day && Column("deleted_at") == nil)
                .order(Column("logged_at"))
                .fetchAll(db)
        }
    }

    public func delete(entryID: UUID) throws {
        try facts.delete(FoodLogEntryRecord.self, id: entryID)
    }

    public func totals(day: DayKey) throws -> Totals {
        var totals = Totals()
        for entry in try entries(day: day) { totals.add(entry) }
        return totals
    }

    /// Copia le voci di un giorno (es. "copia ieri") in un altro, con nuovi id.
    @discardableResult
    public func copyDay(from source: DayKey, to target: DayKey, timeZone: TimeZone = .current) throws -> Int {
        let now = facts.time.now()
        return try facts.writer.write { db in
            let originals = try FoodLogEntryRecord
                .filter(Column("day_key") == source && Column("deleted_at") == nil)
                .order(Column("logged_at"))
                .fetchAll(db)
            for original in originals {
                var copy = original
                copy.id = UUIDv7.make(at: now)
                copy.dayKey = target
                copy.tz = timeZone.identifier
                copy.loggedAt = now
                copy.createdAt = now
                copy.updatedAt = now
                copy.serverUpdatedAt = nil
                try facts.save(copy, in: db)
            }
            return originals.count
        }
    }

    // MARK: Stato del giorno

    public func dayStatus(_ day: DayKey) throws -> NutritionDayRecord? {
        try facts.writer.read { db in
            try NutritionDayRecord.filter(Column("day_key") == day && Column("deleted_at") == nil).fetchOne(db)
        }
    }

    /// Marca il giorno completo/incompleto (solo i giorni completi informano l'expenditure).
    @discardableResult
    public func setDay(_ day: DayKey, status: NutritionDayStatus, type: DayType? = nil) throws -> NutritionDayRecord {
        let now = facts.time.now()
        return try facts.writer.write { db in
            if var existing = try NutritionDayRecord
                .filter(Column("day_key") == day && Column("deleted_at") == nil).fetchOne(db) {
                existing.status = status
                if let type { existing.dayType = type }
                return try facts.save(existing, in: db)
            }
            return try facts.save(NutritionDayRecord(
                id: UUIDv7.make(at: now), dayKey: day, status: status, dayType: type ?? .rest,
                createdAt: now, updatedAt: now
            ), in: db)
        }
    }

    /// Intake e completezza per giorno in un intervallo (per l'ExpenditureEstimator).
    public struct DayIntake: Sendable, Equatable {
        public var day: DayKey
        public var energyKcal: Double?
        public var isComplete: Bool
    }

    public func intake(from start: DayKey, through end: DayKey) throws -> [DayIntake] {
        try facts.writer.read { db in
            let sums = try Row.fetchAll(db, sql: """
                SELECT day_key, SUM(energy_kcal) AS kcal FROM food_log_entry
                WHERE deleted_at IS NULL AND day_key >= ? AND day_key <= ? GROUP BY day_key
                """, arguments: [start, end])
            var kcal: [DayKey: Double] = [:]
            for row in sums {
                let day: DayKey = row["day_key"]
                kcal[day] = row["kcal"]
            }
            let statuses = try NutritionDayRecord
                .filter(Column("day_key") >= start && Column("day_key") <= end && Column("deleted_at") == nil)
                .fetchAll(db)
            var complete: [DayKey: Bool] = [:]
            for status in statuses { complete[status.dayKey] = status.status == .complete }
            let days = Set(kcal.keys).union(complete.keys).sorted()
            return days.map { DayIntake(day: $0, energyKcal: kcal[$0], isComplete: complete[$0] ?? false) }
        }
    }

    // MARK: Ricette

    public struct Ingredient: Sendable, Hashable {
        public var source: FoodSource
        public var sourceID: String
        public var name: String
        public var grams: Double
        public var per100g: NutrientProfile

        public init(source: FoodSource, sourceID: String, name: String, grams: Double, per100g: NutrientProfile) {
            self.source = source
            self.sourceID = sourceID
            self.name = name
            self.grams = grams
            self.per100g = per100g
        }
    }

    /// Crea una ricetta; `servings` porzioni uguali (default 1).
    @discardableResult
    public func createRecipe(name: String, servings: Double = 1, ingredients: [Ingredient]) throws -> RecipeRecord {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !ingredients.isEmpty, servings > 0, servings <= 100 else { throw NutritionError.invalidQuantity }
        // Gli ingredienti sono alimenti veri: niente ricette annidate né aggiunte rapide (CHECK del DB).
        let allowed: Set<FoodSource> = [.catalog, .custom, .openFoodFacts, .usda]
        guard ingredients.allSatisfy({ $0.grams > 0 && $0.grams <= 10_000 && Self.isValid($0.per100g)
                                       && allowed.contains($0.source) }) else {
            throw NutritionError.invalidNutrients
        }
        let now = facts.time.now()
        let yield = ingredients.reduce(0) { $0 + $1.grams }
        return try facts.writer.write { db in
            let recipe = try facts.save(RecipeRecord(
                id: UUIDv7.make(at: now), name: String(trimmed.prefix(120)), yieldGrams: min(yield, 50_000),
                servings: servings, createdAt: now, updatedAt: now
            ), in: db)
            for (position, item) in ingredients.enumerated() {
                try facts.save(RecipeIngredientRecord(
                    id: UUIDv7.make(at: now), recipeId: recipe.id, position: position, foodSource: item.source,
                    foodSourceId: String(item.sourceID.prefix(64)), foodName: String(item.name.prefix(160)),
                    grams: item.grams, energyKcal100g: item.per100g.energyKcal, proteinG100g: item.per100g.proteinGrams,
                    carbsG100g: item.per100g.carbohydrateGrams, fatG100g: item.per100g.fatGrams,
                    fiberG100g: item.per100g.fiberGrams, createdAt: now, updatedAt: now
                ), in: db)
            }
            return recipe
        }
    }

    public func recipes() throws -> [RecipeRecord] {
        try facts.fetchAll(RecipeRecord.self).sorted { $0.name < $1.name }
    }

    /// Nutrienti dell'intera ricetta (somma degli ingredienti).
    public func recipeNutrients(_ recipeID: UUID) throws -> NutrientProfile {
        let ingredients = try facts.writer.read { db in
            try RecipeIngredientRecord
                .filter(Column("recipe_id") == recipeID && Column("deleted_at") == nil)
                .fetchAll(db)
        }
        guard !ingredients.isEmpty else { throw NutritionError.notFound }
        var total = NutrientProfile(energyKcal: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0, fiberGrams: 0)
        for item in ingredients {
            let profile = NutrientProfile(energyKcal: item.energyKcal100g, proteinGrams: item.proteinG100g,
                                          carbohydrateGrams: item.carbsG100g, fatGrams: item.fatG100g,
                                          fiberGrams: item.fiberG100g).scaled(toGrams: item.grams)
            total.energyKcal += profile.energyKcal
            total.proteinGrams += profile.proteinGrams
            total.carbohydrateGrams += profile.carbohydrateGrams
            total.fatGrams += profile.fatGrams
            total.fiberGrams = (total.fiberGrams ?? 0) + (profile.fiberGrams ?? 0)
        }
        return total
    }

    /// Registra `servings` porzioni di una ricetta.
    @discardableResult
    public func logRecipe(_ recipeID: UUID, servings: Double, slot: MealSlot, day: DayKey,
                          timeZone: TimeZone = .current) throws -> FoodLogEntryRecord {
        guard let recipe = try facts.fetch(RecipeRecord.self, id: recipeID) else { throw NutritionError.notFound }
        guard servings.isFinite, servings > 0, servings <= 100 else { throw NutritionError.invalidQuantity }
        let total = try recipeNutrients(recipeID)
        let yield = recipe.yieldGrams ?? 100
        let portions = recipe.servings ?? 1
        let grams = yield / portions * servings
        let per100g = NutrientProfile(
            energyKcal: total.energyKcal / yield * 100, proteinGrams: total.proteinGrams / yield * 100,
            carbohydrateGrams: total.carbohydrateGrams / yield * 100, fatGrams: total.fatGrams / yield * 100,
            fiberGrams: total.fiberGrams.map { $0 / yield * 100 }
        )
        return try log(source: .recipe, sourceID: recipe.id.uuidString, name: recipe.name, per100g: per100g,
                       grams: min(grams, 10_000), slot: slot, day: day, timeZone: timeZone, servings: servings)
    }

    // MARK: Peso

    @discardableResult
    public func addWeight(kilograms: Double, at date: Date, timeZone: TimeZone = .current) throws -> WeightEntryRecord {
        guard kilograms.isFinite, (20...400).contains(kilograms) else { throw NutritionError.invalidQuantity }
        let now = facts.time.now()
        return try facts.save(WeightEntryRecord(
            id: UUIDv7.make(at: date), measuredAt: date, dayKey: DayKey(date: date, timeZone: timeZone),
            tz: timeZone.identifier, weightKg: kilograms, source: .manual, createdAt: now, updatedAt: now
        ))
    }

    public func weights(from start: DayKey) throws -> [WeightEntryRecord] {
        try facts.writer.read { db in
            try WeightEntryRecord
                .filter(Column("day_key") >= start && Column("deleted_at") == nil)
                .order(Column("measured_at"))
                .fetchAll(db)
        }
    }

    // MARK: Validazione

    static func isValid(_ p: NutrientProfile) -> Bool {
        let values = [p.energyKcal, p.proteinGrams, p.carbohydrateGrams, p.fatGrams, p.fiberGrams ?? 0]
        return values.allSatisfy { $0.isFinite && $0 >= 0 } && p.energyKcal <= 900
            && p.proteinGrams + p.carbohydrateGrams + p.fatGrams <= 100.5
    }

    static func round(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
