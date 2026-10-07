import Foundation
import GRDB
import JevCore
import Persistence

/// Lato server della sync (PostgREST o un server finto nei test). Le righe sono JSON con i nomi
/// di colonna del database; la sicurezza (RLS, consenso, merge) resta tutta sul server.
public protocol SyncRemote: Sendable {
    /// `upsert on conflict (id)`; restituisce `server_updated_at` deciso dal server.
    func upsert(table: String, row: [String: Any]) async throws -> Date?
    /// Righe con `server_updated_at > since` (tutte se nil), in ordine di `server_updated_at`.
    func changes(table: String, since: Date?, limit: Int) async throws -> [[String: Any]]
    /// Riga viva dell'utente in una tabella "una riga per utente".
    func singleton(table: String) async throws -> [String: Any]?
}

public enum SyncRemoteError: Error, Equatable, Sendable {
    /// Rete, 5xx, 429: si ritenta con backoff.
    case transient(String)
    /// RLS (42501), check (23514), dati non validi: il record diventa `conflict`.
    case permanent(String)
    /// Violazione di unicità (23505).
    case uniqueViolation
}

/// Motore di sync (DATA_MODEL §5). Idempotente: ripetere push o pull non duplica nulla.
public struct SyncEngine: Sendable {
    public let facts: FactRepository
    public let outbox: OutboxRepository
    public let remote: any SyncRemote
    public let pageSize: Int

    /// Tabelle "una riga per utente" (§5.4): un 23505 qui si risolve adottando la riga del server.
    public static let singletonTables: Set<String> = ["user_profile", "app_settings", "training_preferences"]
    /// Colonne JSON (testo in locale, jsonb sul server).
    static let jsonColumns: [String: Set<String>] = [
        "app_settings": ["notifications", "display"],
        "workout_template": ["scheme"],
        "weekly_check_in": ["metrics", "decisions", "responses"],
        "ai_recommendation": ["payload"],
    ]
    /// Colonne solo locali: non si inviano.
    static let localOnlyColumns: Set<String> = ["sync_state", "server_updated_at"]
    /// Finestra di sovrapposizione del pull (§5.5).
    static let pullOverlap: TimeInterval = 120

    public init(store: DataStore, remote: any SyncRemote, time: any TimeSource = SystemTimeSource(), pageSize: Int = 200) {
        self.facts = FactRepository(store: store, time: time)
        self.outbox = OutboxRepository(store: store)
        self.remote = remote
        self.pageSize = pageSize
    }

    public struct Report: Sendable, Equatable {
        public var pushed = 0
        public var failed = 0
        public var conflicts = 0
        public var adopted = 0
        public var pulled = 0

        public init() {}
    }

    /// Push e poi pull.
    public func sync() async throws -> Report {
        var report = try await push()
        report.pulled = try await pull()
        return report
    }

    // MARK: Push

    public func push() async throws -> Report {
        var report = Report()
        let now = facts.time.now()
        for entry in try outbox.ready(at: now, limit: 500) {
            guard let type = Self.type(named: entry.tableName) else {
                try outbox.markConflict(entry)
                report.conflicts += 1
                continue
            }
            switch try await push(entry, type: type, now: now) {
            case .pushed: report.pushed += 1
            case .failed: report.failed += 1
            case .conflict: report.conflicts += 1
            case .adopted: report.adopted += 1
            }
        }
        return report
    }

    enum PushOutcome { case pushed, failed, conflict, adopted }

    func push<R: SyncedRecord>(_ entry: OutboxEntry, type: R.Type, now: Date) async throws -> PushOutcome {
        guard let record = try facts.writer.read({ db in try R.fetchOne(db, key: entry.recordId) }) else {
            try outbox.markConflict(entry)
            return .conflict
        }
        let row = try Self.remoteRow(record, table: R.databaseTableName)
        do {
            let serverUpdatedAt = try await remote.upsert(table: R.databaseTableName, row: row)
            try outbox.markPushed(entry, serverUpdatedAt: serverUpdatedAt)
            return .pushed
        } catch SyncRemoteError.uniqueViolation where Self.singletonTables.contains(R.databaseTableName) {
            return try await adopt(entry, local: record)
        } catch SyncRemoteError.transient(let code) {
            let delay = min(pow(2, Double(entry.attempts)) * 30, 3600)
            try outbox.markFailed(entry, code: code, retryAt: now.addingTimeInterval(delay))
            return .failed
        } catch SyncRemoteError.permanent(_), SyncRemoteError.uniqueViolation {
            try outbox.markConflict(entry)
            return .conflict
        } catch {
            try outbox.markFailed(entry, code: "unknown", retryAt: now.addingTimeInterval(60))
            return .failed
        }
    }

    /// §5.4: adotta la riga del server (stesso id), con last-writer-wins sui campi; la riga locale
    /// diventa un tombstone solo locale, mai inviato.
    func adopt<R: SyncedRecord>(_ entry: OutboxEntry, local: R) async throws -> PushOutcome {
        guard let serverRow = try await remote.singleton(table: R.databaseTableName) else {
            let now = facts.time.now()
            try outbox.markFailed(entry, code: "23505", retryAt: now.addingTimeInterval(60))
            return .failed
        }
        let server: R = try Self.decode(serverRow, table: R.databaseTableName)
        let table = try Self.quoted(R.databaseTableName)
        try facts.writer.write { db in
            if local.updatedAt > server.updatedAt {
                // I campi locali sono più recenti: vanno sulla riga del server (stesso id) e si inviano.
                var merged = try Self.jsonObject(local)
                merged["id"] = server.id.uuidString
                merged["created_at"] = try Self.jsonObject(server)["created_at"]
                let adopted: R = try Self.decode(merged, table: R.databaseTableName, fromRemote: false)
                try server.save(db)
                try facts.save(adopted, in: db)
            } else {
                try server.save(db)
            }
            let now = facts.time.now()
            try db.execute(sql: "UPDATE \(table) SET deleted_at = ?, sync_state = 'synced' WHERE id = ?",
                           arguments: [now, local.id])
            try db.execute(sql: "DELETE FROM outbox WHERE seq = ?", arguments: [entry.seq])
        }
        return .adopted
    }

    // MARK: Pull

    /// Scarica le modifiche di tutte le tabelle (genitori prima dei figli) e le applica.
    public func pull() async throws -> Int {
        var applied = 0
        for type in SyncedTables.all {
            applied += try await pull(type)
        }
        return applied
    }

    func pull<R: SyncedRecord>(_ type: R.Type) async throws -> Int {
        let table = R.databaseTableName
        let cursorKey = "sync.cursor.\(table)"
        var cursor = try readCursor(cursorKey)
        var applied = 0
        var since = cursor.map { $0.addingTimeInterval(-Self.pullOverlap) }
        while true {
            let rows = try await remote.changes(table: table, since: since, limit: pageSize)
            if rows.isEmpty { break }
            let records: [R] = try rows.map { try Self.decode($0, table: table) }
            let pageMax = records.compactMap(\.serverUpdatedAt).max()
            let previous = cursor
            applied += try facts.writer.write { db -> Int in
                var count = 0
                for remoteRecord in records {
                    if try Self.apply(remoteRecord, db: db) { count += 1 }
                }
                if let pageMax, pageMax > (previous ?? .distantPast) {
                    try Self.writeCursor(cursorKey, pageMax, db: db)
                }
                return count
            }
            if let pageMax, pageMax > (cursor ?? .distantPast) { cursor = pageMax }
            guard rows.count == pageSize, let next = pageMax, next != since else { break }
            since = next
        }
        return applied
    }

    /// Regole di merge del client (§5.3): il tombstone vince, poi last-writer-wins; una modifica
    /// locale più recente ancora da inviare non viene sovrascritta.
    static func apply<R: SyncedRecord>(_ remote: R, db: Database) throws -> Bool {
        var incoming = remote
        incoming.syncState = .synced
        if let local = try R.fetchOne(db, key: remote.id) {
            if local.deletedAt != nil && remote.deletedAt == nil { return false }
            if remote.deletedAt == nil, local.syncState == .pending, local.updatedAt > remote.updatedAt { return false }
            if local.syncState != .pending, local.updatedAt == remote.updatedAt, local.deletedAt == remote.deletedAt,
               local.serverUpdatedAt == remote.serverUpdatedAt {
                return false
            }
        }
        try incoming.save(db)
        return true
    }

    func readCursor(_ key: String) throws -> Date? {
        try facts.writer.read { db in
            guard let text = try String.fetchOne(db, sql: "SELECT value FROM schema_meta WHERE key = ?", arguments: [key]),
                  let seconds = Double(text) else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
    }

    static func writeCursor(_ key: String, _ date: Date, db: Database) throws {
        try db.execute(sql: "INSERT INTO schema_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       arguments: [key, String(date.timeIntervalSince1970)])
    }

    // MARK: Conversione

    static func type(named table: String) -> (any SyncedRecord.Type)? {
        SyncedTables.all.first { $0.databaseTableName == table }
    }

    static func quoted(_ table: String) throws -> String {
        guard type(named: table) != nil else { throw OutboxError.unknownTable(table) }
        return "\"\(table)\""
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SyncDate.format(date))
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = SyncDate.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "data non valida: \(text)")
            }
            return date
        }
        return decoder
    }

    static func jsonObject<R: SyncedRecord>(_ record: R) throws -> [String: Any] {
        let data = try encoder.encode(record)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Riga da inviare: niente colonne locali, colonne JSON come oggetti.
    static func remoteRow<R: SyncedRecord>(_ record: R, table: String) throws -> [String: Any] {
        var row = try jsonObject(record)
        for column in localOnlyColumns { row.removeValue(forKey: column) }
        for column in jsonColumns[table] ?? [] {
            if let text = row[column] as? String, let data = text.data(using: .utf8),
               let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                row[column] = value
            }
        }
        return row.filter { !($0.value is NSNull) }
    }

    /// Riga ricevuta → record locale `synced`; le colonne JSON tornano testo.
    static func decode<R: SyncedRecord>(_ row: [String: Any], table: String, fromRemote: Bool = true) throws -> R {
        var row = row
        if fromRemote {
            for column in jsonColumns[table] ?? [] {
                if let value = row[column], !(value is String), !(value is NSNull) {
                    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
                    row[column] = String(decoding: data, as: UTF8.self)
                }
            }
            row["sync_state"] = RecordSyncState.synced.rawValue
        }
        let data = try JSONSerialization.data(withJSONObject: row, options: [])
        return try decoder.decode(R.self, from: data)
    }
}

/// Date nel formato di PostgREST: ISO 8601 con frazioni (fino ai microsecondi) e fuso.
public enum SyncDate {
    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func parse(_ text: String) -> Date? {
        var value = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        // Microsecondi → millisecondi: ISO8601DateFormatter accetta al massimo tre decimali.
        if let dot = value.firstIndex(of: ".") {
            let fraction = value[value.index(after: dot)...].prefix { $0.isNumber }
            if fraction.count > 3 {
                let start = value.index(after: dot)
                let end = value.index(start, offsetBy: fraction.count)
                value.replaceSubrange(start..<end, with: fraction.prefix(3))
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
