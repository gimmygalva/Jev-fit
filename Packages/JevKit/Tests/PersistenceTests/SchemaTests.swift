import Foundation
import GRDB
import Testing
@testable import Persistence

/// I record generati devono coincidere con lo schema SQL: stessi nomi di colonna, nessuna
/// colonna in più o in meno, e ogni tabella sincronizzata accoda nell'outbox.
@Suite("Schema — record generati e tabelle sincronizzate")
struct SchemaTests {
    @Test("Ogni record sincronizzato ha esattamente le colonne della sua tabella")
    func recordColumnsMatchSchema() throws {
        let store = try DataStore.inMemory()
        try store.writer.read { db in
            for type in SyncedTables.all {
                let table = type.databaseTableName
                let columns = try db.columns(in: table).map(\.name)
                #expect(Set(columns) == Set(type.databaseColumnNames), "Colonne diverse per \(table)")
                #expect(columns.count == type.databaseColumnNames.count, "Colonne duplicate per \(table)")
            }
        }
    }

    @Test("Le tabelle sincronizzate sono tutte e sole quelle con sync_state")
    func syncedTablesAreComplete() throws {
        let store = try DataStore.inMemory()
        let tablesWithSyncState = try store.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT m.name FROM sqlite_master m
                WHERE m.type = 'table'
                  AND EXISTS (SELECT 1 FROM pragma_table_info(m.name) p WHERE p.name = 'sync_state')
                """)
        }
        #expect(Set(tablesWithSyncState) == Set(SyncedTables.all.map { $0.databaseTableName }))
        #expect(SyncedTables.all.count == 31)
    }

    @Test("Ogni tabella sincronizzata ha i trigger di accodamento nell'outbox")
    func outboxTriggers() throws {
        let store = try DataStore.inMemory()
        let triggers = try store.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger'")
        }
        for type in SyncedTables.all {
            let table = type.databaseTableName
            #expect(triggers.contains("\(table)_outbox_insert"), "Manca il trigger insert per \(table)")
            #expect(triggers.contains("\(table)_outbox_update"), "Manca il trigger update per \(table)")
        }
    }

    @Test("Le tabelle locali, derivate e di sistema esistono")
    func localTables() throws {
        let store = try DataStore.inMemory()
        let expected = [
            "food_cache", "ai_conversation", "ai_message",
            "weight_trend_daily", "performance_record", "exercise_trend", "personal_record",
            "muscle_recovery", "readiness_entry", "daily_nutrition", "energy_expenditure",
            "outbox", "sync_cursor", "schema_meta",
        ]
        let existing = try store.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        for table in expected {
            #expect(existing.contains(table), "Manca \(table)")
        }
        // I dati fisiologici di HealthKit non stanno nel DB principale (SEC-LS-04).
        #expect(!existing.contains("health_metric_daily"))
    }
}
