import Foundation
import GRDB

/// Punto d'accesso al database locale SQLite (ADR-004, ADR-005, docs/DATA_MODEL.md).
///
/// Migrazioni nominate e IMMUTABILI dopo il rilascio:
/// - `v000_bootstrap`: tabella `schema_meta` (M1);
/// - `v001_initial`: schema completo di M2, in `Migrations/v001_initial.sql` (lo stesso file è
///   confrontato in CI con lo schema Supabase da `scripts/ci/schema-parity.py`).
///
/// I dati fisiologici di HealthKit NON stanno qui ma in `HealthCacheStore` (file separato,
/// escluso dal backup, SEC-LS-04).
public final class DataStore: Sendable {
    public let writer: any DatabaseWriter

    /// Identificativo di questa installazione, scritto in `origin_device_id` di ogni modifica.
    /// Generato alla prima apertura e conservato in `schema_meta` (sopravvive al backup).
    public let deviceID: UUID

    /// Apre il database e applica tutte le migrazioni mancanti.
    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try DataStore.migrator.migrate(writer)
        self.deviceID = try writer.write { db in try DataStore.loadOrCreateDeviceID(db) }
    }

    /// Database in memoria per test e anteprime SwiftUI.
    public static func inMemory() throws -> DataStore {
        try DataStore(writer: DatabaseQueue(configuration: DataStore.configuration))
    }

    /// Database su file. La cartella che lo contiene riceve la Data Protection
    /// `completeUntilFirstUserAuthentication` PRIMA di creare il file, così anche `-wal` e `-shm`
    /// la ereditano (SEC-LS-01). Il file è incluso nel backup del dispositivo (SEC-LS-03).
    public static func onDisk(at url: URL) throws -> DataStore {
        try FileProtection.prepareDirectory(url.deletingLastPathComponent(), excludedFromBackup: false)
        return try DataStore(writer: DatabasePool(path: url.path, configuration: DataStore.configuration))
    }

    /// Percorso definitivo: `Application Support/JevFit/jev.sqlite` (mai in `Documents`, SEC-LS-01).
    public static func defaultURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("JevFit", isDirectory: true)
            .appendingPathComponent("jev.sqlite", isDirectory: false)
    }

    static var configuration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "JevFit.DataStore"
        return configuration
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // In debug uno schema cambiato rispetto alle migrazioni registrate ricrea il DB invece di
        // lasciare uno stato incoerente. Mai in release.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("v000_bootstrap") { db in
            try db.create(table: "schema_meta") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }
        migrator.registerMigration("v001_initial") { db in
            try db.execute(sql: try MigrationSQL.load("v001_initial"))
        }
        return migrator
    }

    /// Nomi delle migrazioni registrate, in ordine (verificati dai test).
    public static var registeredMigrations: [String] {
        migrator.migrations
    }

    private static func loadOrCreateDeviceID(_ db: Database) throws -> UUID {
        if let text = try String.fetchOne(db, sql: "SELECT value FROM schema_meta WHERE key = 'device_id'"),
           let id = UUID(uuidString: text) {
            return id
        }
        let id = UUID()
        try db.execute(
            sql: "INSERT INTO schema_meta (key, value) VALUES ('device_id', ?)",
            arguments: [id.uuidString.lowercased()]
        )
        return id
    }
}

/// Legge le migrazioni SQL incluse nel bundle del modulo (`Migrations/*.sql`).
enum MigrationSQL {
    enum LoadError: Error, Equatable {
        case missing(String)
    }

    static func load(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "sql", subdirectory: "Migrations")
            ?? Bundle.module.url(forResource: name, withExtension: "sql")
        else {
            throw LoadError.missing(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// Protezione dei file su disco (SECURITY §8).
enum FileProtection {
    /// Crea la cartella se manca, applica `completeUntilFirstUserAuthentication` e, se richiesto,
    /// la esclude dal backup (vale per tutto il contenuto, compresi `-wal` e `-shm`).
    static func prepareDirectory(_ directory: URL, excludedFromBackup: Bool) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = excludedFromBackup
        var mutableURL = directory
        try mutableURL.setResourceValues(values)
    }
}
