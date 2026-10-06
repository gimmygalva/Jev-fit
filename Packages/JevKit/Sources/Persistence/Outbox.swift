import Foundation
import GRDB

/// Riga dell'outbox: un record locale da inviare al server (DATA_MODEL §5.2).
///
/// Le righe sono create e aggiornate dai trigger SQL delle tabelle sincronizzate; il codice Swift
/// le legge e le chiude soltanto. `lastError` contiene un codice, mai payload o messaggi del
/// server (SECURITY §3).
public struct OutboxEntry: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "outbox"

    public var seq: Int64
    public var tableName: String
    public var recordId: UUID
    public var enqueuedAt: Date
    public var revision: Int
    public var attempts: Int
    public var nextAttemptAt: Date?
    public var lastError: String?

    public enum CodingKeys: String, CodingKey {
        case seq
        case tableName = "table_name"
        case recordId = "record_id"
        case enqueuedAt = "enqueued_at"
        case revision
        case attempts
        case nextAttemptAt = "next_attempt_at"
        case lastError = "last_error"
    }
}

/// Lettura e chiusura dell'outbox da parte della sync (M12).
///
/// Protocollo di push, per ogni riga: leggere il record ATTUALE → upsert sul server →
/// `markPushed(entry, ...)` con la riga letta. Se nel frattempo il record è stato modificato,
/// la revisione dell'outbox è cambiata: la riga resta in coda e il record resta `pending`.
public struct OutboxRepository: Sendable {
    public let writer: any DatabaseWriter

    public init(store: DataStore) {
        self.writer = store.writer
    }

    /// Righe pronte per l'invio, in ordine di accodamento.
    public func ready(at now: Date, limit: Int = 100) throws -> [OutboxEntry] {
        try writer.read { db in
            try OutboxEntry
                .filter(Column("next_attempt_at") == nil || Column("next_attempt_at") <= now)
                .order(Column("seq"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func count() throws -> Int {
        try writer.read { db in try OutboxEntry.fetchCount(db) }
    }

    /// Il server ha accettato la revisione `entry.revision` del record.
    /// - Returns: `true` se il record è ora `synced`; `false` se è stato modificato dopo la lettura
    ///   (resta in coda per il prossimo push).
    @discardableResult
    public func markPushed(_ entry: OutboxEntry, serverUpdatedAt: Date?) throws -> Bool {
        let table = try SyncedTableName(entry.tableName)
        return try writer.write { db in
            try db.execute(
                sql: "DELETE FROM outbox WHERE seq = ? AND revision = ?",
                arguments: [entry.seq, entry.revision]
            )
            guard db.changesCount == 1 else { return false }
            try db.execute(
                sql: "UPDATE \(table.quoted) SET sync_state = 'synced', server_updated_at = ? WHERE id = ? AND sync_state = 'pending'",
                arguments: [serverUpdatedAt, entry.recordId]
            )
            return true
        }
    }

    /// Errore temporaneo (rete, 5xx, rate limit): nuovo tentativo dopo `retryAt`.
    public func markFailed(_ entry: OutboxEntry, code: String, retryAt: Date) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE outbox SET attempts = attempts + 1, last_error = ?, next_attempt_at = ? WHERE seq = ?",
                arguments: [String(code.prefix(64)), retryAt, entry.seq]
            )
        }
    }

    /// Errore permanente (es. 42501, 23514): il record diventa `conflict` ed esce dalla coda.
    /// Non viene mai ritentato in automatico (SECURITY §6.5). Il codice d'errore lo registra
    /// la sync nel log tecnico.
    public func markConflict(_ entry: OutboxEntry) throws {
        let table = try SyncedTableName(entry.tableName)
        try writer.write { db in
            try db.execute(sql: "DELETE FROM outbox WHERE seq = ?", arguments: [entry.seq])
            try db.execute(
                sql: "UPDATE \(table.quoted) SET sync_state = 'conflict' WHERE id = ?",
                arguments: [entry.recordId]
            )
        }
    }
}

/// Nome di una tabella sincronizzata, validato contro l'elenco generato: è l'unico modo di
/// interpolarlo in SQL (i nomi di tabella non si possono passare come argomenti).
struct SyncedTableName: Sendable {
    let name: String

    init(_ name: String) throws {
        guard SyncedTables.all.contains(where: { $0.databaseTableName == name }) else {
            throw OutboxError.unknownTable(name)
        }
        self.name = name
    }

    var quoted: String { "\"\(name)\"" }
}

public enum OutboxError: Error, Equatable {
    case unknownTable(String)
}
