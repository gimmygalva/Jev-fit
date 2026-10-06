import Foundation
import GRDB
import Testing
@testable import Persistence

@Suite("DataStore — bootstrap e migrazioni")
struct DataStoreTests {
    @Test("Il database in memoria applica tutte le migrazioni")
    func bootstrap() throws {
        let store = try DataStore.inMemory()
        let exists = try store.writer.read { db in try db.tableExists("schema_meta") }
        #expect(exists)
        #expect(DataStore.registeredMigrations == ["v000_bootstrap", "v001_initial"])
        let applied = try store.writer.read { db in try DataStore.migrator.appliedMigrations(db) }
        #expect(applied == DataStore.registeredMigrations)
    }

    @Test("Riaprire lo stesso database non riapplica le migrazioni e conserva il device id")
    func idempotentMigration() throws {
        let queue = try DatabaseQueue()
        let first = try DataStore(writer: queue)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO schema_meta (key, value) VALUES ('engine_version', '1')")
        }
        let second = try DataStore(writer: queue)
        let value = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM schema_meta WHERE key = 'engine_version'")
        }
        #expect(value == "1")
        #expect(first.deviceID == second.deviceID)
    }

    @Test("Un database della versione precedente (solo v000) migra senza perdere dati")
    func upgradeFromPreviousVersion() throws {
        let queue = try DatabaseQueue()
        try DataStore.migrator.migrate(queue, upTo: "v000_bootstrap")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO schema_meta (key, value) VALUES ('engine_version', '1')")
        }
        _ = try DataStore(writer: queue)
        let (value, hasSets, hasOutbox) = try queue.read { db in
            (
                try String.fetchOne(db, sql: "SELECT value FROM schema_meta WHERE key = 'engine_version'"),
                try db.tableExists("workout_set"),
                try db.tableExists("outbox")
            )
        }
        #expect(value == "1")
        #expect(hasSets)
        #expect(hasOutbox)
    }

    @Test("Lo schema rispetta le chiavi esterne")
    func foreignKeysAreConsistent() throws {
        let store = try DataStore.inMemory()
        let violations = try store.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
        }
        #expect(violations.isEmpty)
        let enabled = try store.writer.read { db in try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") }
        #expect(enabled == true)
    }

    @Test("Il database su file funziona e la cartella è protetta (SEC-LS-01)")
    func onDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("JevFit", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let store = try DataStore.onDisk(at: dir.appendingPathComponent("jev.sqlite"))
        #expect(try store.writer.read { db in try db.tableExists("workout_set") })

        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == false, "Il DB principale è incluso nel backup (SEC-LS-03)")
        #if os(iOS) && !targetEnvironment(simulator)
        // Sul simulatore la Data Protection non esiste: l'attributo si verifica su dispositivo.
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.path)
        #expect(attributes[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication)
        #endif
    }

    @Test("La migrazione v001 è inclusa nel bundle del modulo")
    func migrationResource() throws {
        let sql = try MigrationSQL.load("v001_initial")
        #expect(sql.contains("CREATE TABLE workout_set"))
        #expect(throws: MigrationSQL.LoadError.missing("v999_missing")) {
            try MigrationSQL.load("v999_missing")
        }
    }
}
