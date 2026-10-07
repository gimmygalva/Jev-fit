import Foundation
import GRDB
import JevCore
import JevDomain
import Testing
@testable import Persistence
@testable import Sync

/// Orologio condiviso dai test: avanza a comando (i retry con backoff diventano pronti).
final class MutableClock: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
}

/// Server finto con le regole del trigger `private.tg_fact_sync_columns` (DATA_MODEL §5.3),
/// unicità delle tabelle "una riga per utente" e iniezione di guasti: errori temporanei prima
/// di scrivere e risposte perse dopo aver scritto.
final class FakeServer: SyncRemote, @unchecked Sendable {
    private let lock = NSLock()
    private var tables: [String: [String: [String: Any]]] = [:]
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var generator: SeededGenerator
    var failureRate: Double
    var lostResponseRate: Double
    private(set) var upserts = 0

    init(seed: UInt64 = 1, failureRate: Double = 0, lostResponseRate: Double = 0) {
        generator = SeededGenerator(seed: seed)
        self.failureRate = failureRate
        self.lostResponseRate = lostResponseRate
    }

    private func date(_ value: Any?) -> Date? { (value as? String).flatMap(SyncDate.parse) }

    func upsert(table: String, row: [String: Any]) async throws -> Date? {
        try lock.withLock {
            if Double.random(in: 0..<1, using: &generator) < failureRate { throw SyncRemoteError.transient("503") }
            guard let id = row["id"] as? String else { throw SyncRemoteError.permanent("23502") }
            var rows = tables[table] ?? [:]
            if SyncEngine.singletonTables.contains(table),
               rows.contains(where: { $0.key != id && $0.value["deleted_at"] == nil }) {
                throw SyncRemoteError.uniqueViolation
            }
            clock += 0.001
            let stamp = SyncDate.format(clock)
            var incoming = row
            incoming["server_updated_at"] = stamp
            incoming["user_id"] = "user-a"
            if var existing = rows[id] {
                let existingUpdated = date(existing["updated_at"]) ?? .distantPast
                let incomingUpdated = date(incoming["updated_at"]) ?? .distantPast
                if existing["deleted_at"] != nil || incomingUpdated < existingUpdated {
                    existing["server_updated_at"] = stamp       // tombstone vince / LWW: valori del server
                } else {
                    incoming["created_at"] = existing["created_at"]
                    existing = incoming
                }
                rows[id] = existing
            } else {
                rows[id] = incoming
            }
            tables[table] = rows
            upserts += 1
            if Double.random(in: 0..<1, using: &generator) < lostResponseRate { throw SyncRemoteError.transient("timeout") }
            return clock
        }
    }

    func changes(table: String, since: Date?, limit: Int) async throws -> [[String: Any]] {
        lock.withLock {
            let rows = (tables[table] ?? [:]).values.filter { row in
                guard let since else { return true }
                return (date(row["server_updated_at"]) ?? .distantPast) > since
            }
            let sorted = rows.sorted { (date($0["server_updated_at"]) ?? .distantPast) < (date($1["server_updated_at"]) ?? .distantPast) }
            return Array(sorted.prefix(limit))
        }
    }

    func singleton(table: String) async throws -> [String: Any]? {
        lock.withLock { tables[table]?.values.first { $0["deleted_at"] == nil } }
    }

    func liveIDs(_ table: String) -> Set<String> {
        lock.withLock { Set((tables[table] ?? [:]).filter { $0.value["deleted_at"] == nil }.keys) }
    }

    func count(_ table: String) -> Int { lock.withLock { tables[table]?.count ?? 0 } }
}

@Suite("Sync: push dall'outbox, pull con cursore, merge, singleton, guasti (M12)")
struct SyncEngineTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let utc = TimeZone(identifier: "UTC")!

    private func weight(_ kg: Double, at date: Date) -> WeightEntryRecord {
        WeightEntryRecord(id: UUIDv7.make(at: date), measuredAt: date, dayKey: DayKey(date: date, timeZone: utc), tz: "UTC",
                          weightKg: kg, source: .manual, createdAt: date, updatedAt: date)
    }

    private func profile(at date: Date, birthYear: Int) -> UserProfileRecord {
        UserProfileRecord(id: UUIDv7.make(at: date), birthYear: birthYear, heightCm: 180, experience: .intermediate,
                          activityLevel: .moderate, createdAt: date, updatedAt: date)
    }

    @Test("Date di PostgREST: microsecondi, fuso, spazio al posto di T")
    func dates() throws {
        let parsed = try #require(SyncDate.parse("2026-10-07T01:02:03.123456+00:00"))
        #expect(abs(parsed.timeIntervalSince1970 - 1_791_334_923.123) < 0.001)
        #expect(SyncDate.parse("2026-10-07 03:02:03+02:00") == Date(timeIntervalSince1970: 1_791_334_923))
        #expect(SyncDate.parse(SyncDate.format(parsed)) == parsed)
        #expect(SyncDate.parse("ieri") == nil)
    }

    @Test("Righe remote: niente colonne locali, JSON come oggetti, ritorno identico")
    func conversion() throws {
        let record = WeeklyCheckInRecord(id: UUID(), weekStart: DayKey("2026-09-28")!, metrics: #"{"a":1}"#,
                                         decisions: #"[{"type":"keep"}]"#, responses: "{}", engineVersion: 1,
                                         createdAt: start, updatedAt: start)
        let row = try SyncEngine.remoteRow(record, table: "weekly_check_in")
        #expect(row["sync_state"] == nil && row["server_updated_at"] == nil)
        #expect((row["metrics"] as? [String: Any])?["a"] as? Int == 1)
        #expect(row["decisions"] is [Any])
        var serverRow = row
        serverRow["server_updated_at"] = SyncDate.format(start)
        serverRow["user_id"] = UUID().uuidString
        let back: WeeklyCheckInRecord = try SyncEngine.decode(serverRow, table: "weekly_check_in")
        #expect(back.metrics == #"{"a":1}"# && back.syncState == .synced && back.serverUpdatedAt == start)
        #expect(back.weekStart == record.weekStart && back.id == record.id)
    }

    @Test("Push e pull tra due dispositivi: stesso stato, nessun duplicato, tombstone propagato")
    func twoDevices() async throws {
        let server = FakeServer()
        let clock = MutableClock(start)
        let a = try DataStore.inMemory()
        let b = try DataStore.inMemory()
        let factsA = FactRepository(store: a, time: clock)
        let factsB = FactRepository(store: b, time: clock)
        let first = try factsA.save(weight(80, at: start))
        try factsA.save(weight(79.8, at: start + 86_400))
        let engineA = SyncEngine(store: a, remote: server, time: clock)
        let engineB = SyncEngine(store: b, remote: server, time: clock)
        let reportA = try await engineA.sync()
        #expect(reportA.pushed == 2)
        let reportB = try await engineB.sync()
        #expect(reportB.pulled == 2)
        #expect(try factsB.fetchAll(WeightEntryRecord.self).count == 2)
        #expect(try OutboxRepository(store: b).count() == 0, "I record ricevuti non tornano nell'outbox")
        // B cancella, A riceve il tombstone.
        clock.advance(60)
        try factsB.delete(WeightEntryRecord.self, id: first.id)
        _ = try await engineB.sync()
        _ = try await engineA.sync()
        #expect(try factsA.fetchAll(WeightEntryRecord.self).map(\.weightKg) == [79.8])
        // Ripetere la sync non cambia nulla.
        let idle = try await engineA.sync()
        #expect(idle.pushed == 0)
        #expect(server.count("weight_entry") == 2)
    }

    @Test("Profilo creato offline su due dispositivi: il secondo adotta la riga del server")
    func singletonAdoption() async throws {
        let server = FakeServer()
        let clock = MutableClock(start)
        let a = try DataStore.inMemory()
        let b = try DataStore.inMemory()
        let factsA = FactRepository(store: a, time: clock)
        let factsB = FactRepository(store: b, time: clock)
        let profileA = try factsA.save(profile(at: start, birthYear: 1990))
        clock.advance(10)
        try factsB.save(profile(at: start + 10, birthYear: 1991))
        let engineA = SyncEngine(store: a, remote: server, time: clock)
        let engineB = SyncEngine(store: b, remote: server, time: clock)
        _ = try await engineA.sync()
        let reportB = try await engineB.sync()
        #expect(reportB.adopted == 1)
        _ = try await engineB.sync()
        _ = try await engineA.sync()
        let liveB = try factsB.fetchAll(UserProfileRecord.self)
        let liveA = try factsA.fetchAll(UserProfileRecord.self)
        #expect(liveB.map(\.id) == [profileA.id])
        #expect(liveA.map(\.id) == [profileA.id])
        // Last-writer-wins sui campi: il profilo di B era più recente.
        #expect(liveA.first?.birthYear == 1991 && liveB.first?.birthYear == 1991)
        #expect(server.liveIDs("user_profile") == [profileA.id.uuidString])
    }

    @Test("Errori permanenti: record in conflitto, fuori dalla coda, mai ritentato")
    func permanentError() async throws {
        final class Rejecting: SyncRemote, @unchecked Sendable {
            func upsert(table: String, row: [String: Any]) async throws -> Date? { throw SyncRemoteError.permanent("42501") }
            func changes(table: String, since: Date?, limit: Int) async throws -> [[String: Any]] { [] }
            func singleton(table: String) async throws -> [String: Any]? { nil }
        }
        let store = try DataStore.inMemory()
        let facts = FactRepository(store: store)
        let saved = try facts.save(weight(80, at: start))
        let report = try await SyncEngine(store: store, remote: Rejecting()).push()
        #expect(report.conflicts == 1)
        #expect(try OutboxRepository(store: store).count() == 0)
        #expect(try facts.fetch(WeightEntryRecord.self, id: saved.id)?.syncState == .conflict)
    }

    @Test("Fault injection: errori e risposte perse, modifiche concorrenti, convergenza senza duplicati",
          arguments: [UInt64(1), 2, 3, 4, 5])
    func faultInjection(seed: UInt64) async throws {
        let server = FakeServer(seed: seed, failureRate: 0.3, lostResponseRate: 0.2)
        let clock = MutableClock(start)
        let stores = [try DataStore.inMemory(), try DataStore.inMemory()]
        let facts = stores.map { FactRepository(store: $0, time: clock) }
        let engines = stores.map { SyncEngine(store: $0, remote: server, time: clock, pageSize: 7) }
        var generator = SeededGenerator(seed: seed &+ 100)
        var created: [UUID] = []
        for round in 0..<12 {
            for device in 0..<2 {
                clock.advance(1)
                let action = Int.random(in: 0..<4, using: &generator)
                let mine = try facts[device].fetchAll(WeightEntryRecord.self)
                if action == 0, let victim = mine.randomElement(using: &generator) {
                    try facts[device].delete(WeightEntryRecord.self, id: victim.id)
                } else if action == 1, var edited = mine.randomElement(using: &generator) {
                    edited.weightKg = Double(Int.random(in: 600...900, using: &generator)) / 10
                    try facts[device].save(edited)
                } else {
                    let record = try facts[device].save(weight(70 + Double(round), at: clock.now()))
                    created.append(record.id)
                }
                _ = try? await engines[device].sync()
            }
            clock.advance(3_600)
        }
        // Rete stabile: si sincronizza finché le code sono vuote.
        server.failureRate = 0
        server.lostResponseRate = 0
        for _ in 0..<4 {
            clock.advance(7_200)
            for engine in engines { _ = try await engine.sync() }
        }
        for store in stores { #expect(try OutboxRepository(store: store).count() == 0) }
        let states = try facts.map { repo in
            try repo.writer.read { db in
                try WeightEntryRecord.fetchAll(db).reduce(into: [UUID: String]()) { result, record in
                    result[record.id] = "\(record.weightKg)|\(record.deletedAt != nil)"
                }
            }
        }
        #expect(states[0] == states[1], "I due dispositivi convergono")
        #expect(Set(states[0].keys) == Set(created), "Nessun record perso o duplicato")
        #expect(server.count("weight_entry") == created.count)
        let live = Set(states[0].filter { !$0.value.hasSuffix("true") }.keys.map(\.uuidString))
        #expect(server.liveIDs("weight_entry") == live)
        for repo in facts {
            let conflicts = try repo.writer.read { db in
                try WeightEntryRecord.filter(Column("sync_state") == "conflict").fetchCount(db)
            }
            #expect(conflicts == 0)
        }
    }
}

@Suite("PostgREST: mappatura degli errori")
struct PostgRESTMappingTests {
    @Test("23505 unicità, 42501 permanente, 5xx e 429 temporanei")
    func mapping() {
        let unique = Data(#"{"code":"23505"}"#.utf8)
        #expect(PostgRESTSyncRemote.map(status: 409, body: unique) == .uniqueViolation)
        #expect(PostgRESTSyncRemote.map(status: 403, body: Data(#"{"code":"42501"}"#.utf8)) == .permanent("42501"))
        #expect(PostgRESTSyncRemote.map(status: 503, body: Data()) == .transient("http_503"))
        #expect(PostgRESTSyncRemote.map(status: 429, body: Data()) == .transient("http_429"))
        #expect(PostgRESTSyncRemote.map(status: 400, body: Data(#"{"code":"23514"}"#.utf8)) == .permanent("23514"))
    }
}
