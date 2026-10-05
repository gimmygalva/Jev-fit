import Foundation
import GRDB

/// Punto d'accesso al database locale SQLite (ADR-004, ADR-005).
///
/// M1: solo il bootstrap con la tabella `schema_meta` (versione degli engine, usata per
/// invalidare le cache derivate). Lo schema completo e i repository arrivano in M2
/// (Agent 03, docs/DATA_MODEL.md). Le migrazioni sono nominate e IMMUTABILI dopo il rilascio.
public final class DataStore: Sendable {
    public let writer: any DatabaseWriter

    /// Apre il database e applica tutte le migrazioni mancanti.
    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try DataStore.migrator.migrate(writer)
    }

    /// Database in memoria per test e anteprime SwiftUI.
    public static func inMemory() throws -> DataStore {
        try DataStore(writer: DatabaseQueue())
    }

    /// Database su file. La classe di Data Protection è decisa in SECURITY.md
    /// (`completeUntilFirstUserAuthentication`) e viene applicata in M2 insieme al percorso definitivo.
    public static func onDisk(at url: URL) throws -> DataStore {
        try DataStore(writer: DatabasePool(path: url.path))
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
        return migrator
    }

    /// Nomi delle migrazioni registrate, in ordine (verificati dai test).
    public static var registeredMigrations: [String] {
        migrator.migrations
    }
}
