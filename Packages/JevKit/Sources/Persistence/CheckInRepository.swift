import Foundation
import GRDB
import JevCore
import JevDomain

/// Check-in settimanali e target nutrizionali accettati (M11). Metriche, decisioni e risposte
/// sono JSON prodotti dagli engine: lo snapshot rende ogni decisione riproducibile.
public struct CheckInRepository: Sendable {
    public let facts: FactRepository

    public init(facts: FactRepository) {
        self.facts = facts
    }

    /// Salva (o aggiorna) il check-in della settimana; uno solo per settimana.
    @discardableResult
    public func save(weekStart: DayKey, metricsJSON: String, decisionsJSON: String, engineVersion: Int) throws -> WeeklyCheckInRecord {
        let now = facts.time.now()
        return try facts.writer.write { db in
            if var existing = try WeeklyCheckInRecord
                .filter(Column("week_start") == weekStart && Column("deleted_at") == nil).fetchOne(db) {
                existing.metrics = metricsJSON
                existing.decisions = decisionsJSON
                existing.engineVersion = max(engineVersion, 1)
                return try facts.save(existing, in: db)
            }
            return try facts.save(WeeklyCheckInRecord(
                id: UUIDv7.make(at: now), weekStart: weekStart, metrics: metricsJSON, decisions: decisionsJSON,
                responses: "{}", engineVersion: max(engineVersion, 1), createdAt: now, updatedAt: now
            ), in: db)
        }
    }

    public func checkIns(limit: Int = 12) throws -> [WeeklyCheckInRecord] {
        try facts.writer.read { db in
            try WeeklyCheckInRecord.filter(Column("deleted_at") == nil)
                .order(Column("week_start").desc).limit(limit).fetchAll(db)
        }
    }

    /// Registra la risposta dell'utente a una decisione (`true` = accettata).
    @discardableResult
    public func respond(checkInID: UUID, decisionKey: String, accepted: Bool) throws -> WeeklyCheckInRecord {
        let now = facts.time.now()
        return try facts.writer.write { db in
            guard var record = try WeeklyCheckInRecord.fetchOne(db, key: checkInID), record.deletedAt == nil else {
                throw FactRepositoryError.notFound
            }
            var responses = (try? JSONDecoder().decode([String: Bool].self, from: Data(record.responses.utf8))) ?? [:]
            responses[String(decisionKey.prefix(80))] = accepted
            record.responses = String(decoding: try JSONEncoder().encode(responses), as: UTF8.self)
            record.completedAt = now
            return try facts.save(record, in: db)
        }
    }

    /// Ultimo target calorico accettato in vigore a `day` (onboarding, check-in o modifica manuale).
    public func activeTarget(on day: DayKey) throws -> NutritionTargetRecord? {
        try facts.writer.read { db in
            try NutritionTargetRecord
                .filter(Column("effective_from") <= day && Column("deleted_at") == nil)
                .order(Column("effective_from").desc, Column("created_at").desc)
                .fetchOne(db)
        }
    }

    @discardableResult
    public func saveTarget(
        kcal: Double, effectiveFrom: DayKey, origin: NutritionTargetOrigin, mode: MacroMode = .auto,
        checkInID: UUID? = nil, engineVersion: Int
    ) throws -> NutritionTargetRecord {
        let clamped = min(max(kcal.rounded(), 800), 10_000)
        let now = facts.time.now()
        return try facts.save(NutritionTargetRecord(
            id: UUIDv7.make(at: now), effectiveFrom: effectiveFrom, mode: mode, kcalTraining: clamped, kcalRest: clamped,
            weeklyAvgKcal: clamped, origin: origin, checkInId: checkInID, engineVersion: max(engineVersion, 1),
            createdAt: now, updatedAt: now
        ))
    }
}
