import Foundation
import Health
import JevCore
import Persistence

/// Importa i dati di Salute (M7): aggregati giornalieri nella cache locale esclusa dal backup
/// (mai sincronizzati, ADR-012) e pesate come fatti `weight_entry` con `source = healthkit`.
///
/// Idempotente: una pesata già importata (anche se poi cancellata dall'utente) non torna, una
/// pesata scritta da JEV FIT in Salute non viene reimportata, i valori fuori scala sono scartati.
public struct HealthImporter: Sendable {
    public struct Report: Sendable, Equatable {
        public var importedWeighIns: Int
        public var skippedWeighIns: Int
        public var daysUpdated: Int
    }

    let source: any HealthDataSource
    let cache: HealthCacheStore
    let facts: FactRepository

    public init(source: any HealthDataSource, cache: HealthCacheStore, facts: FactRepository) {
        self.source = source
        self.cache = cache
        self.facts = facts
    }

    /// Chiede i permessi (lettura di tutti i tipi, scrittura di pesate e allenamenti).
    public func requestAuthorization() async throws {
        try await source.requestAuthorization(read: HealthDataType.readTypes, write: HealthDataType.writeTypes)
    }

    /// Chiede i permessi (HealthKit mostra il foglio solo per i tipi mai chiesti) e importa.
    /// Gli errori non bloccano l'app: senza Salute si continua con l'inserimento manuale.
    @discardableResult
    public func refresh(days: Int = 30, timeZone: TimeZone = .current) async -> Report? {
        try? await requestAuthorization()
        return try? await importRecent(days: days, timeZone: timeZone)
    }

    public func importRecent(days: Int = 30, timeZone: TimeZone = .current) async throws -> Report {
        guard source.isAvailable else { return Report(importedWeighIns: 0, skippedWeighIns: 0, daysUpdated: 0) }
        let now = facts.time.now()
        let start = now.addingTimeInterval(-Double(max(days, 1)) * 86_400)

        let activity = try await source.dailyActivity(from: start, to: now, timeZone: timeZone)
        let sleepSamples = try await source.sleepIntervals(from: start, to: now)
        let restingSamples = try await source.restingHeartRateSamples(from: start, to: now)
        let hrvSamples = try await source.heartRateVariabilitySamples(from: start, to: now)
        let sleep = HealthAggregator.sleepMinutesByNight(sleepSamples, timeZone: timeZone)
        let restingHR = HealthAggregator.dailyRestingHeartRate(restingSamples, timeZone: timeZone)
        let hrv = HealthAggregator.nightlyHRV(hrvSamples, timeZone: timeZone)
        let summaries = HealthAggregator.summaries(activity: activity, sleepMinutes: sleep, restingHeartRate: restingHR, hrv: hrv)
        for summary in summaries {
            try cache.upsert(HealthMetricDaily(
                dayKey: summary.dayKey, steps: summary.steps, activeKcal: summary.activeKcal,
                sleepMinutes: summary.sleepMinutes, restingHr: summary.restingHeartRate,
                hrvSdnnMs: summary.hrvSDNNMilliseconds, updatedAt: now
            ))
        }

        let samples = try await source.bodyMassSamples(from: start, to: now)
        let weighIns = samples.map {
            HealthKitWeighIn(healthKitUUID: $0.healthKitUUID, date: $0.date, kilograms: $0.mass.kilograms,
                             writtenByThisApp: $0.writtenByThisApp)
        }
        let (imported, skipped) = try facts.importHealthKitWeighIns(weighIns, timeZone: timeZone)
        return Report(importedWeighIns: imported, skippedWeighIns: skipped, daysUpdated: summaries.count)
    }
}
