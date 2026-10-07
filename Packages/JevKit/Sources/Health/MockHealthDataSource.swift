import Foundation
import JevCore

/// Sorgente simulata per test, simulatore e UI test (M7). Riproduce i tre casi della checklist:
/// permessi concessi, negati, parziali. Con i permessi negati ogni lettura è vuota, come in
/// HealthKit (che non rivela il rifiuto della lettura).
public final class MockHealthDataSource: HealthDataSource, @unchecked Sendable {
    public struct Fixture: Sendable, Hashable {
        public var bodyMass: [BodyMassSample] = []
        public var activity: [DayKey: DailyActivity] = [:]
        public var sleep: [SleepInterval] = []
        public var restingHeartRate: [HealthQuantitySample] = []
        public var heartRateVariability: [HealthQuantitySample] = []

        public init() {}
    }

    private let lock = NSLock()
    private let data: Fixture
    private var granted: Set<HealthDataType>
    private let grantOnRequest: Set<HealthDataType>
    private var requested = false
    private var saved: [BodyMassSample] = []

    /// `grantOnRequest`: tipi che l'utente "concede" quando l'app chiede i permessi.
    public init(data: Fixture, grantOnRequest: Set<HealthDataType> = Set(HealthDataType.allCases),
                alreadyGranted: Set<HealthDataType> = []) {
        self.data = data
        self.grantOnRequest = grantOnRequest
        self.granted = alreadyGranted
    }

    public var isAvailable: Bool { true }

    public var authorizationRequested: Bool {
        lock.withLock { requested }
    }

    public var savedBodyMass: [BodyMassSample] {
        lock.withLock { saved }
    }

    private func isGranted(_ type: HealthDataType) -> Bool {
        lock.withLock { granted.contains(type) }
    }

    public func requestAuthorization(read: Set<HealthDataType>, write: Set<HealthDataType>) async throws {
        lock.withLock {
            requested = true
            granted.formUnion(read.union(write).intersection(grantOnRequest))
        }
    }

    public func writeAuthorization(for type: HealthDataType) -> HealthWriteAuthorization {
        lock.withLock {
            if granted.contains(type) { return .authorized }
            return requested ? .denied : .notDetermined
        }
    }

    private func inRange(_ date: Date, _ start: Date, _ end: Date) -> Bool {
        date >= start && date <= end
    }

    public func bodyMassSamples(from start: Date, to end: Date) async throws -> [BodyMassSample] {
        guard isGranted(.bodyMass) else { return [] }
        let all = data.bodyMass + savedBodyMass
        return all.filter { inRange($0.date, start, end) }.sorted { $0.date < $1.date }
    }

    public func dailyActivity(from start: Date, to end: Date, timeZone: TimeZone) async throws -> [DayKey: DailyActivity] {
        let first = DayKey(date: start, timeZone: timeZone)
        let last = DayKey(date: end, timeZone: timeZone)
        let steps = isGranted(.steps)
        let energy = isGranted(.activeEnergy)
        var result: [DayKey: DailyActivity] = [:]
        for (day, value) in data.activity where day >= first && day <= last {
            let filtered = DailyActivity(steps: steps ? value.steps : nil, activeKcal: energy ? value.activeKcal : nil)
            if filtered.steps != nil || filtered.activeKcal != nil { result[day] = filtered }
        }
        return result
    }

    public func sleepIntervals(from start: Date, to end: Date) async throws -> [SleepInterval] {
        guard isGranted(.sleep) else { return [] }
        return data.sleep.filter { inRange($0.end, start, end) }
    }

    public func restingHeartRateSamples(from start: Date, to end: Date) async throws -> [HealthQuantitySample] {
        guard isGranted(.restingHeartRate) else { return [] }
        return data.restingHeartRate.filter { inRange($0.date, start, end) }
    }

    public func heartRateVariabilitySamples(from start: Date, to end: Date) async throws -> [HealthQuantitySample] {
        guard isGranted(.heartRateVariability) else { return [] }
        return data.heartRateVariability.filter { inRange($0.date, start, end) }
    }

    public func saveBodyMass(_ mass: Mass, at date: Date) async throws -> UUID {
        guard writeAuthorization(for: .bodyMass) == .authorized else { throw HealthDataError.writeNotAuthorized }
        let id = UUIDv7.make(at: date)
        lock.withLock {
            saved.append(BodyMassSample(healthKitUUID: id, date: date, mass: mass, writtenByThisApp: true))
        }
        return id
    }

    // MARK: Dati dimostrativi

    /// `days` giorni di dati plausibili e deterministici fino a `now`: pesata ogni mattina,
    /// passi, energia attiva, sonno 23:30–7:00, FC a riposo e HRV notturna (sorgente "watch").
    public static func demoData(now: Date, days: Int, timeZone: TimeZone, seed: UInt64 = 7) -> Fixture {
        var generator = SeededGenerator(seed: seed)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        var data = Fixture()
        for offset in (0..<days).reversed() {
            guard let midnight = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayKey = DayKey(date: midnight, timeZone: timeZone)
            let index = Double(days - offset)
            let noise = Double.random(in: -0.4...0.4, using: &generator)
            let weight = 82 - 0.05 * index + noise
            data.bodyMass.append(BodyMassSample(
                healthKitUUID: UUIDv7.make(at: midnight.addingTimeInterval(7 * 3600)),
                date: midnight.addingTimeInterval(7 * 3600), mass: .kilograms(weight), writtenByThisApp: false
            ))
            data.activity[dayKey] = DailyActivity(
                steps: Int.random(in: 5_000...12_000, using: &generator),
                activeKcal: Double(Int.random(in: 300...700, using: &generator))
            )
            data.sleep.append(SleepInterval(
                start: midnight.addingTimeInterval(-1_800), end: midnight.addingTimeInterval(7 * 3600),
                stage: .asleep, sourceID: "watch"
            ))
            data.restingHeartRate.append(HealthQuantitySample(
                date: midnight.addingTimeInterval(8 * 3600), value: Double(Int.random(in: 55...62, using: &generator)),
                sourceID: "watch"
            ))
            data.heartRateVariability.append(HealthQuantitySample(
                date: midnight.addingTimeInterval(3 * 3600), value: Double(Int.random(in: 45...70, using: &generator)),
                sourceID: "watch"
            ))
        }
        return data
    }
}
