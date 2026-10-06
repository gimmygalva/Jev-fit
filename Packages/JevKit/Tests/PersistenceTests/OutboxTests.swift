import Foundation
import GRDB
import JevCore
import Testing
@testable import Persistence

@Suite("Outbox — accodamento automatico e chiusura del push")
struct OutboxTests {
    let store: DataStore
    let clock: TestClock
    let repo: FactRepository
    let outbox: OutboxRepository

    init() throws {
        store = try DataStore.inMemory()
        clock = TestClock(Fixtures.start)
        repo = FactRepository(store: store, time: clock)
        outbox = OutboxRepository(store: store)
    }

    @Test("Ogni scrittura locale accoda il record una sola volta (coalescing)")
    func enqueueAndCoalesce() throws {
        var profile = try repo.save(Fixtures.profile())
        #expect(try outbox.count() == 1)
        let first = try #require(try outbox.ready(at: Fixtures.start).first)
        #expect(first.tableName == "user_profile")
        #expect(first.recordId == profile.id)
        #expect(first.revision == 0)

        profile.heightCm = 182
        clock.advance(1)
        try repo.save(profile)
        try repo.delete(UserProfileRecord.self, id: profile.id)
        let entries = try outbox.ready(at: Fixtures.start)
        #expect(entries.count == 1)
        #expect(entries.first?.revision == 2)
    }

    @Test("Push confermato: il record diventa synced ed esce dalla coda")
    func markPushed() throws {
        let weight = try repo.save(Fixtures.weight(80))
        let entry = try #require(try outbox.ready(at: Fixtures.start).first)
        let serverTime = Fixtures.start.addingTimeInterval(5)
        #expect(try outbox.markPushed(entry, serverUpdatedAt: serverTime))
        #expect(try outbox.count() == 0)
        let stored = try #require(try repo.fetch(WeightEntryRecord.self, id: weight.id))
        #expect(stored.syncState == .synced)
        #expect(stored.serverUpdatedAt == serverTime)
    }

    @Test("Una modifica arrivata durante il push non viene persa")
    func modificationDuringPush() throws {
        var weight = try repo.save(Fixtures.weight(80))
        let snapshot = try #require(try outbox.ready(at: Fixtures.start).first)
        // Mentre il push è in volo l'utente corregge la pesata.
        weight.weightKg = 79.6
        clock.advance(1)
        try repo.save(weight)
        #expect(try outbox.markPushed(snapshot, serverUpdatedAt: Fixtures.start) == false)
        #expect(try outbox.count() == 1)
        #expect(try repo.fetch(WeightEntryRecord.self, id: weight.id)?.syncState == .pending)
    }

    @Test("Errore temporaneo: nuovo tentativo dopo l'attesa; errore permanente: conflict")
    func failures() throws {
        let weight = try repo.save(Fixtures.weight(80))
        let entry = try #require(try outbox.ready(at: Fixtures.start).first)
        let retryAt = Fixtures.start.addingTimeInterval(60)
        try outbox.markFailed(entry, code: "network_offline", retryAt: retryAt)
        #expect(try outbox.ready(at: Fixtures.start).isEmpty)
        let retried = try #require(try outbox.ready(at: retryAt).first)
        #expect(retried.attempts == 1)
        #expect(retried.lastError == "network_offline")

        try outbox.markConflict(retried)
        #expect(try outbox.count() == 0)
        let stored = try store.writer.read { db in try WeightEntryRecord.fetchOne(db, key: weight.id) }
        #expect(stored?.syncState == .conflict)
    }

    @Test("I record applicati dal server (synced) non vengono riaccodati")
    func pulledRecordsAreNotEnqueued() throws {
        var pulled = Fixtures.weight(77)
        pulled.syncState = .synced
        pulled.serverUpdatedAt = Fixtures.start
        try store.writer.write { db in try pulled.insert(db) }
        #expect(try outbox.count() == 0)
    }

    @Test("Una riga d'outbox con una tabella sconosciuta è rifiutata prima di toccare l'SQL")
    func unknownTable() throws {
        let fake = OutboxEntry(
            seq: 1, tableName: "sqlite_master", recordId: UUID(), enqueuedAt: Fixtures.start,
            revision: 0, attempts: 0, nextAttemptAt: nil, lastError: nil
        )
        #expect(throws: OutboxError.unknownTable("sqlite_master")) {
            try outbox.markPushed(fake, serverUpdatedAt: nil)
        }
    }
}
