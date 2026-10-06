import Foundation
import GRDB
import JevCore

/// Cache locale degli aggregati giornalieri di HealthKit (ADR-012, SEC-LS-04).
///
/// File SQLite SEPARATO (`HealthCache/health-cache.sqlite`) in una cartella esclusa dal backup:
/// nessun dato fisiologico di HealthKit finisce nel backup iCloud. È ricostruibile da Salute
/// in qualsiasi momento (UF-13), quindi non ha colonne di sync e non entra nell'outbox.
public final class HealthCacheStore: Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try HealthCacheStore.migrator.migrate(writer)
    }

    public static func inMemory() throws -> HealthCacheStore {
        try HealthCacheStore(writer: DatabaseQueue())
    }

    /// `directory` riceve la stessa protezione del DB principale ed è esclusa dal backup.
    public static func onDisk(directory: URL) throws -> HealthCacheStore {
        try FileProtection.prepareDirectory(directory, excludedFromBackup: true)
        let url = directory.appendingPathComponent("health-cache.sqlite", isDirectory: false)
        return try HealthCacheStore(writer: DatabasePool(path: url.path))
    }

    /// `Application Support/JevFit/HealthCache/`.
    public static func defaultDirectory() throws -> URL {
        try DataStore.defaultURL()
            .deletingLastPathComponent()
            .appendingPathComponent("HealthCache", isDirectory: true)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("h001_initial") { db in
            try db.execute(sql: try MigrationSQL.load("h001_health_cache"))
        }
        return migrator
    }

    public static var registeredMigrations: [String] {
        migrator.migrations
    }

    public func upsert(_ metric: HealthMetricDaily) throws {
        try writer.write { db in try metric.upsert(db) }
    }

    public func metrics(from start: DayKey, through end: DayKey) throws -> [HealthMetricDaily] {
        try writer.read { db in
            try HealthMetricDaily
                .filter(Column("day_key") >= start && Column("day_key") <= end)
                .order(Column("day_key"))
                .fetchAll(db)
        }
    }

    /// Svuota la cache (revoca dei permessi Salute, eliminazione dei dati).
    public func removeAll() throws {
        try writer.write { db in _ = try HealthMetricDaily.deleteAll(db) }
    }
}

/// Aggregati giornalieri letti da HealthKit. Mai sincronizzati, mai inviati all'AI (ADR-012).
public struct HealthMetricDaily: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "health_metric_daily"

    public var dayKey: DayKey
    public var steps: Int?
    public var activeKcal: Double?
    public var sleepMinutes: Double?
    public var restingHr: Double?
    public var hrvSdnnMs: Double?
    public var updatedAt: Date

    public init(
        dayKey: DayKey,
        steps: Int? = nil,
        activeKcal: Double? = nil,
        sleepMinutes: Double? = nil,
        restingHr: Double? = nil,
        hrvSdnnMs: Double? = nil,
        updatedAt: Date
    ) {
        self.dayKey = dayKey
        self.steps = steps
        self.activeKcal = activeKcal
        self.sleepMinutes = sleepMinutes
        self.restingHr = restingHr
        self.hrvSdnnMs = hrvSdnnMs
        self.updatedAt = updatedAt
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case dayKey = "day_key"
        case steps
        case activeKcal = "active_kcal"
        case sleepMinutes = "sleep_minutes"
        case restingHr = "resting_hr"
        case hrvSdnnMs = "hrv_sdnn_ms"
        case updatedAt = "updated_at"
    }
}
