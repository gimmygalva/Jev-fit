import Foundation
import JevCore
import Testing
@testable import Health

@Suite("Aggregazione dei dati di Salute (M7)")
struct HealthAggregatorTests {
    let rome = TimeZone(identifier: "Europe/Rome")!
    /// 2026-10-06 00:00 a Roma (UTC+2).
    let midnight = Date(timeIntervalSince1970: 1_791_237_600)
    var day: DayKey { DayKey(date: midnight, timeZone: rome) }

    private func at(_ hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }

    @Test("Sonno: unione delle fasi di più sorgenti, attribuito al giorno del risveglio")
    func sleepUnion() {
        let intervals = [
            SleepInterval(start: at(-1), end: at(3), stage: .asleep, sourceID: "watch"),
            SleepInterval(start: at(2), end: at(7), stage: .asleep, sourceID: "phone"),
            SleepInterval(start: at(-1.5), end: at(7.5), stage: .inBed, sourceID: "phone"),
            SleepInterval(start: at(3), end: at(3.5), stage: .awake, sourceID: "watch"),
            SleepInterval(start: at(4), end: at(4), stage: .asleep, sourceID: "watch"),
        ]
        let minutes = HealthAggregator.sleepMinutesByNight(intervals, timeZone: rome)
        #expect(minutes[day] == 480)
        #expect(minutes.count == 1)
    }

    @Test("Sonno: solo 'a letto' quando mancano le fasi; massimo 24 ore")
    func sleepFallback() {
        let inBed = [SleepInterval(start: at(-2), end: at(6), stage: .inBed, sourceID: "old")]
        #expect(HealthAggregator.sleepMinutesByNight(inBed, timeZone: rome)[day] == 480)
        let huge = [SleepInterval(start: at(-30), end: at(6), stage: .asleep, sourceID: "bad")]
        #expect(HealthAggregator.sleepMinutesByNight(huge, timeZone: rome)[day] == 1440)
    }

    @Test("HRV: solo campioni notturni di una sola sorgente, media per giorno")
    func hrv() {
        let samples = [
            HealthQuantitySample(date: at(2), value: 50, sourceID: "watch"),
            HealthQuantitySample(date: at(4), value: 60, sourceID: "watch"),
            HealthQuantitySample(date: at(26), value: 70, sourceID: "watch"),
            HealthQuantitySample(date: at(3), value: 200, sourceID: "ring"),
            HealthQuantitySample(date: at(14), value: 30, sourceID: "watch"),
            HealthQuantitySample(date: at(5), value: 900, sourceID: "watch"),
        ]
        let nightly = HealthAggregator.nightlyHRV(samples, timeZone: rome)
        #expect(nightly[day] == 55)
        #expect(nightly[day.adding(days: 1)] == 70)
        #expect(HealthAggregator.nightlyHRV([], timeZone: rome).isEmpty)
    }

    @Test("FC a riposo: media giornaliera, valori impossibili scartati")
    func restingHR() {
        let samples = [
            HealthQuantitySample(date: at(8), value: 56, sourceID: "watch"),
            HealthQuantitySample(date: at(9), value: 58, sourceID: "watch"),
            HealthQuantitySample(date: at(10), value: 400, sourceID: "watch"),
        ]
        #expect(HealthAggregator.dailyRestingHeartRate(samples, timeZone: rome)[day] == 57)
    }

    @Test("Riepiloghi: una riga per giorno ordinata, valori fuori range scartati, giorni vuoti omessi")
    func summaries() {
        let next = day.adding(days: 1)
        let empty = day.adding(days: 2)
        let result = HealthAggregator.summaries(
            activity: [day: DailyActivity(steps: 8000, activeKcal: 450), next: DailyActivity(steps: 900_000, activeKcal: .nan),
                       empty: DailyActivity()],
            sleepMinutes: [next: 420], restingHeartRate: [day: 55], hrv: [day: 60]
        )
        #expect(result.map(\.dayKey) == [day, next])
        #expect(result[0] == HealthAggregator.DailySummary(dayKey: day, steps: 8000, activeKcal: 450,
                                                           restingHeartRate: 55, hrvSDNNMilliseconds: 60))
        #expect(result[1].steps == nil && result[1].activeKcal == nil && result[1].sleepMinutes == 420)
    }
}

@Suite("Sorgente Salute simulata: permessi concessi, negati, parziali (M7)")
struct MockHealthDataSourceTests {
    let now = Date(timeIntervalSince1970: 1_791_300_000)
    let utc = TimeZone(identifier: "UTC")!

    private var demo: MockHealthDataSource.Fixture {
        MockHealthDataSource.demoData(now: now, days: 14, timeZone: utc)
    }

    @Test("Prima della richiesta nulla è leggibile; dopo, i tipi concessi")
    func granted() async throws {
        let source = MockHealthDataSource(data: demo)
        let start = now.addingTimeInterval(-20 * 86_400)
        #expect(try await source.bodyMassSamples(from: start, to: now).isEmpty)
        #expect(source.writeAuthorization(for: .bodyMass) == .notDetermined)
        try await source.requestAuthorization(read: HealthDataType.readTypes, write: HealthDataType.writeTypes)
        #expect(source.authorizationRequested)
        #expect(try await source.bodyMassSamples(from: start, to: now).count == 14)
        #expect(try await source.dailyActivity(from: start, to: now, timeZone: utc).count == 14)
        #expect(try await source.sleepIntervals(from: start, to: now).count == 14)
        #expect(try await source.restingHeartRateSamples(from: start, to: now).count == 14)
        #expect(try await source.heartRateVariabilitySamples(from: start, to: now).count == 14)
        #expect(source.writeAuthorization(for: .bodyMass) == .authorized)
        let id = try await source.saveBodyMass(.kilograms(80), at: now)
        #expect(source.savedBodyMass.map(\.healthKitUUID) == [id])
        #expect(try await source.bodyMassSamples(from: start, to: now).last?.writtenByThisApp == true)
    }

    @Test("Permessi negati: letture vuote, scrittura rifiutata")
    func denied() async throws {
        let source = MockHealthDataSource(data: demo, grantOnRequest: [])
        try await source.requestAuthorization(read: HealthDataType.readTypes, write: HealthDataType.writeTypes)
        let start = now.addingTimeInterval(-20 * 86_400)
        #expect(try await source.bodyMassSamples(from: start, to: now).isEmpty)
        #expect(try await source.dailyActivity(from: start, to: now, timeZone: utc).isEmpty)
        #expect(source.writeAuthorization(for: .bodyMass) == .denied)
        await #expect(throws: HealthDataError.writeNotAuthorized) {
            _ = try await source.saveBodyMass(.kilograms(80), at: now)
        }
    }

    @Test("Permessi parziali: solo i tipi concessi")
    func partial() async throws {
        let source = MockHealthDataSource(data: demo, grantOnRequest: [.bodyMass, .steps])
        try await source.requestAuthorization(read: HealthDataType.readTypes, write: [])
        let start = now.addingTimeInterval(-20 * 86_400)
        #expect(try await source.bodyMassSamples(from: start, to: now).count == 14)
        let activity = try await source.dailyActivity(from: start, to: now, timeZone: utc)
        #expect(activity.values.allSatisfy { $0.steps != nil && $0.activeKcal == nil })
        #expect(try await source.sleepIntervals(from: start, to: now).isEmpty)
        #expect(try await source.heartRateVariabilitySamples(from: start, to: now).isEmpty)
    }

    @Test("Salute non disponibile: nessun dato, permessi e scrittura falliscono")
    func unavailable() async throws {
        let source = UnavailableHealthDataSource()
        #expect(!source.isAvailable)
        #expect(source.writeAuthorization(for: .bodyMass) == .denied)
        await #expect(throws: HealthDataError.unavailable) {
            try await source.requestAuthorization(read: [.bodyMass], write: [])
        }
        let start = now.addingTimeInterval(-86_400)
        #expect(try await source.bodyMassSamples(from: start, to: now).isEmpty)
        #expect(try await source.dailyActivity(from: start, to: now, timeZone: utc).isEmpty)
        #expect(try await source.sleepIntervals(from: start, to: now).isEmpty)
        #expect(try await source.restingHeartRateSamples(from: start, to: now).isEmpty)
        #expect(try await source.heartRateVariabilitySamples(from: start, to: now).isEmpty)
        await #expect(throws: HealthDataError.unavailable) {
            _ = try await source.saveBodyMass(.kilograms(80), at: now)
        }
    }
}
