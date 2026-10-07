import Foundation
import Health
import JevCore
import Persistence
import Testing
@testable import Features

@Suite("Import da Salute: cache locale e pesate (M7)")
struct HealthImporterTests {
    let now = Date(timeIntervalSince1970: 1_791_300_000)
    let utc = TimeZone(identifier: "UTC")!
    let store: DataStore
    let cache: HealthCacheStore
    let facts: FactRepository

    init() throws {
        store = try DataStore.inMemory()
        cache = try HealthCacheStore.inMemory()
        facts = FactRepository(store: store, time: FixedTimeSource(now))
    }

    private func importer(_ source: any HealthDataSource) -> HealthImporter {
        HealthImporter(source: source, cache: cache, facts: facts)
    }

    @Test("Permessi concessi: aggregati nella cache e pesate come fatti healthkit, senza duplicati")
    func grantedImport() async throws {
        let source = MockHealthDataSource(data: MockHealthDataSource.demoData(now: now, days: 14, timeZone: utc))
        let health = importer(source)
        let report = try #require(await health.refresh(days: 30, timeZone: utc))
        #expect(report.importedWeighIns == 14)
        #expect(report.daysUpdated >= 14)
        let first = DayKey(date: now.addingTimeInterval(-13 * 86_400), timeZone: utc)
        let rows = try cache.metrics(from: first, through: DayKey(date: now, timeZone: utc))
        #expect(rows.count == 14)
        #expect(rows.allSatisfy { $0.steps != nil && $0.sleepMinutes == 450 && $0.restingHr != nil && $0.hrvSdnnMs != nil })
        let weights = try facts.fetchAll(WeightEntryRecord.self)
        #expect(weights.count == 14)
        #expect(weights.allSatisfy { $0.source == .healthkit && $0.hkUuid != nil })
        // Secondo import: niente di nuovo.
        let again = try await health.importRecent(days: 30, timeZone: utc)
        #expect(again.importedWeighIns == 0 && again.skippedWeighIns == 14)
        #expect(try facts.fetchAll(WeightEntryRecord.self).count == 14)
    }

    @Test("Una pesata cancellata dall'utente non viene reimportata; quelle scritte da JEV FIT sono ignorate")
    func tombstonesAndOwnSamples() throws {
        let id = UUID()
        let sample = HealthKitWeighIn(healthKitUUID: id, date: now, kilograms: 80, writtenByThisApp: false)
        #expect(try facts.importHealthKitWeighIns([sample], timeZone: utc).imported == 1)
        let record = try #require(try facts.fetchAll(WeightEntryRecord.self).first)
        try facts.delete(WeightEntryRecord.self, id: record.id)
        #expect(try facts.importHealthKitWeighIns([sample], timeZone: utc).imported == 0)
        let own = HealthKitWeighIn(healthKitUUID: UUID(), date: now, kilograms: 80, writtenByThisApp: true)
        let absurd = HealthKitWeighIn(healthKitUUID: UUID(), date: now, kilograms: 900, writtenByThisApp: false)
        let result = try facts.importHealthKitWeighIns([own, absurd], timeZone: utc)
        #expect(result.imported == 0 && result.skipped == 2)
        #expect(try facts.fetchAll(WeightEntryRecord.self).isEmpty)
    }

    @Test("Permessi negati o Salute assente: nessun dato, nessun errore")
    func deniedOrUnavailable() async throws {
        let denied = MockHealthDataSource(data: MockHealthDataSource.demoData(now: now, days: 14, timeZone: utc),
                                          grantOnRequest: [])
        let report = try #require(await importer(denied).refresh(timeZone: utc))
        #expect(report.importedWeighIns == 0 && report.daysUpdated == 0)
        let unavailable = try #require(await importer(UnavailableHealthDataSource()).refresh(timeZone: utc))
        #expect(unavailable.importedWeighIns == 0)
        #expect(try facts.fetchAll(WeightEntryRecord.self).isEmpty)
    }

    @Test("Permessi parziali: solo i dati concessi")
    func partial() async throws {
        let source = MockHealthDataSource(data: MockHealthDataSource.demoData(now: now, days: 7, timeZone: utc),
                                          grantOnRequest: [.steps])
        let report = try #require(await importer(source).refresh(timeZone: utc))
        #expect(report.importedWeighIns == 0)
        let rows = try cache.metrics(from: DayKey(date: now.addingTimeInterval(-6 * 86_400), timeZone: utc),
                                     through: DayKey(date: now, timeZone: utc))
        #expect(rows.count == 7)
        #expect(rows.allSatisfy { $0.steps != nil && $0.sleepMinutes == nil && $0.hrvSdnnMs == nil })
    }
}
