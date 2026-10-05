import Foundation
import GRDB
import Testing
@testable import Persistence

@Suite("DataStore — bootstrap e migrazioni")
struct DataStoreTests {
    @Test("Il database in memoria applica le migrazioni e crea schema_meta")
    func bootstrap() throws {
        let store = try DataStore.inMemory()
        let exists = try store.writer.read { db in try db.tableExists("schema_meta") }
        #expect(exists)
        #expect(DataStore.registeredMigrations == ["v000_bootstrap"])
    }

    @Test("Riaprire lo stesso database non riapplica le migrazioni")
    func idempotentMigration() throws {
        let queue = try DatabaseQueue()
        _ = try DataStore(writer: queue)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO schema_meta (key, value) VALUES ('engine_version', '1')")
        }
        _ = try DataStore(writer: queue)
        let value = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM schema_meta WHERE key = 'engine_version'")
        }
        #expect(value == "1")
    }

    @Test("Il database su file funziona in una cartella temporanea")
    func onDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try DataStore.onDisk(at: dir.appendingPathComponent("jev.sqlite"))
        #expect(try store.writer.read { db in try db.tableExists("schema_meta") })
    }
}
