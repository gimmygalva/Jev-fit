#if canImport(HealthKit)
import Foundation
import HealthKit
import JevCore

/// Implementazione reale su HealthKit (M7). Le query usano le API async di iOS 15.4+.
///
/// `@unchecked Sendable`: l'unico stato è `HKHealthStore`, documentato come thread-safe.
public final class HealthKitDataSource: HealthDataSource, @unchecked Sendable {
    private let store: HKHealthStore
    private let bundleIdentifier: String?

    public init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.store = HKHealthStore()
        self.bundleIdentifier = bundleIdentifier
    }

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func objectType(_ type: HealthDataType) -> HKObjectType {
        switch type {
        case .bodyMass: return HKQuantityType(.bodyMass)
        case .bodyFatPercentage: return HKQuantityType(.bodyFatPercentage)
        case .steps: return HKQuantityType(.stepCount)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .sleep: return HKCategoryType(.sleepAnalysis)
        case .heartRate: return HKQuantityType(.heartRate)
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .heartRateVariability: return HKQuantityType(.heartRateVariabilitySDNN)
        case .workouts: return HKObjectType.workoutType()
        }
    }

    public func requestAuthorization(read: Set<HealthDataType>, write: Set<HealthDataType>) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        let readTypes = Set(read.map { Self.objectType($0) })
        let shareTypes = Set(write.compactMap { Self.objectType($0) as? HKSampleType })
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    public func writeAuthorization(for type: HealthDataType) -> HealthWriteAuthorization {
        guard isAvailable else { return .denied }
        switch store.authorizationStatus(for: Self.objectType(type)) {
        case .sharingAuthorized: return .authorized
        case .notDetermined: return .notDetermined
        case .sharingDenied: return .denied
        @unknown default: return .denied
        }
    }

    // MARK: Letture

    private func quantitySamples(_ identifier: HKQuantityTypeIdentifier, from start: Date, to end: Date) async throws -> [HKQuantitySample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    private func sourceID(_ sample: HKSample) -> String {
        sample.sourceRevision.source.bundleIdentifier
    }

    public func bodyMassSamples(from start: Date, to end: Date) async throws -> [BodyMassSample] {
        let kilograms = HKUnit.gramUnit(with: .kilo)
        return try await quantitySamples(.bodyMass, from: start, to: end).map { sample in
            BodyMassSample(
                healthKitUUID: sample.uuid, date: sample.startDate,
                mass: .kilograms(sample.quantity.doubleValue(for: kilograms)),
                writtenByThisApp: bundleIdentifier != nil && sourceID(sample) == bundleIdentifier
            )
        }
    }

    public func dailyActivity(from start: Date, to end: Date, timeZone: TimeZone) async throws -> [DayKey: DailyActivity] {
        guard isAvailable else { return [:] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let anchor = calendar.startOfDay(for: start)
        var result: [DayKey: DailyActivity] = [:]
        let steps = try await dailySums(.stepCount, unit: .count(), from: anchor, to: end)
        for (date, value) in steps {
            result[DayKey(date: date, timeZone: timeZone), default: DailyActivity()].steps = Int(value.rounded())
        }
        let energy = try await dailySums(.activeEnergyBurned, unit: .kilocalorie(), from: anchor, to: end)
        for (date, value) in energy {
            result[DayKey(date: date, timeZone: timeZone), default: DailyActivity()].activeKcal = value
        }
        return result
    }

    /// Somme giornaliere (deduplicate da HealthKit tra iPhone e Watch).
    private func dailySums(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from anchor: Date, to end: Date) async throws -> [(Date, Double)] {
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        return collection.statistics().compactMap { statistics in
            statistics.sumQuantity().map { (statistics.startDate, $0.doubleValue(for: unit)) }
        }
    }

    public func sleepIntervals(from start: Date, to end: Date) async throws -> [SleepInterval] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.compactMap { sample in
            guard let stage = Self.stage(sample.value) else { return nil }
            return SleepInterval(start: sample.startDate, end: sample.endDate, stage: stage, sourceID: sourceID(sample))
        }
    }

    static func stage(_ raw: Int) -> SleepInterval.Stage? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: raw) else { return nil }
        switch value {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return .asleep
        @unknown default: return nil
        }
    }

    public func restingHeartRateSamples(from start: Date, to end: Date) async throws -> [HealthQuantitySample] {
        let unit = HKUnit.count().unitDivided(by: .minute())
        return try await quantitySamples(.restingHeartRate, from: start, to: end).map {
            HealthQuantitySample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit), sourceID: sourceID($0))
        }
    }

    public func heartRateVariabilitySamples(from start: Date, to end: Date) async throws -> [HealthQuantitySample] {
        let unit = HKUnit.secondUnit(with: .milli)
        return try await quantitySamples(.heartRateVariabilitySDNN, from: start, to: end).map {
            HealthQuantitySample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit), sourceID: sourceID($0))
        }
    }

    // MARK: Scritture

    public func saveBodyMass(_ mass: Mass, at date: Date) async throws -> UUID {
        guard isAvailable else { throw HealthDataError.unavailable }
        guard writeAuthorization(for: .bodyMass) == .authorized else { throw HealthDataError.writeNotAuthorized }
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: mass.kilograms)
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: quantity, start: date, end: date)
        try await store.save(sample)
        return sample.uuid
    }
}
#endif
