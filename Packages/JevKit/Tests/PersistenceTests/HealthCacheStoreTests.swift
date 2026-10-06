import Foundation
import GRDB
import JevCore
import Testing
@testable import Persistence

@Suite("HealthCacheStore — dati HealthKit solo sul dispositivo (SEC-LS-04)")
struct HealthCacheStoreTests {
    @Test("Upsert per giorno e lettura per intervallo")
    func upsertAndRange() throws {
        let cache = try HealthCacheStore.inMemory()
        #expect(HealthCacheStore.registeredMigrations == ["h001_initial"])
        let d1 = DayKey("2026-10-05")!
        let d2 = DayKey("2026-10-06")!
        try cache.upsert(HealthMetricDaily(dayKey: d1, steps: 8000, updatedAt: Fixtures.start))
        try cache.upsert(HealthMetricDaily(dayKey: d2, steps: 3000, restingHr: 52, updatedAt: Fixtures.start))
        try cache.upsert(HealthMetricDaily(dayKey: d2, steps: 9500, restingHr: 51, updatedAt: Fixtures.start))
        let rows = try cache.metrics(from: d1, through: d2)
        #expect(rows.map(\.steps) == [8000, 9500])
        #expect(try cache.metrics(from: d2, through: d2).first?.restingHr == 51)
        try cache.removeAll()
        #expect(try cache.metrics(from: d1, through: d2).isEmpty)
    }

    @Test("Il file della cache sta in una cartella esclusa dal backup")
    func excludedFromBackup() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("HealthCache", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let cache = try HealthCacheStore.onDisk(directory: dir)
        try cache.upsert(HealthMetricDaily(dayKey: Fixtures.day, steps: 1, updatedAt: Fixtures.start))
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("health-cache.sqlite").path))
    }
}
