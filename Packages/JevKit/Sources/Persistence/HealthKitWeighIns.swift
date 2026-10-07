import Foundation
import GRDB
import JevCore

/// Una pesata letta da Salute, già convertita in kg (il modulo Health non dipende da qui).
public struct HealthKitWeighIn: Sendable, Hashable {
    public var healthKitUUID: UUID
    public var date: Date
    public var kilograms: Double
    public var writtenByThisApp: Bool

    public init(healthKitUUID: UUID, date: Date, kilograms: Double, writtenByThisApp: Bool) {
        self.healthKitUUID = healthKitUUID
        self.date = date
        self.kilograms = kilograms
        self.writtenByThisApp = writtenByThisApp
    }
}

extension FactRepository {
    /// Importa le pesate di Salute come `weight_entry` con `source = healthkit`, in un'unica
    /// transazione. Scarta le pesate scritte da JEV FIT, quelle già importate (anche se poi
    /// cancellate: `hk_uuid` è UNIQUE e una pesata cancellata non deve tornare) e i valori
    /// fuori dal range del database (20–400 kg).
    public func importHealthKitWeighIns(
        _ samples: [HealthKitWeighIn], timeZone: TimeZone
    ) throws -> (imported: Int, skipped: Int) {
        try writer.write { db in
            var known = try UUID.fetchSet(db, sql: "SELECT hk_uuid FROM weight_entry WHERE hk_uuid IS NOT NULL")
            var imported = 0
            var skipped = 0
            for sample in samples.sorted(by: { $0.date < $1.date }) {
                let kilograms = sample.kilograms
                guard !sample.writtenByThisApp, !known.contains(sample.healthKitUUID),
                      kilograms.isFinite, (20...400).contains(kilograms) else {
                    skipped += 1
                    continue
                }
                try save(WeightEntryRecord(
                    id: UUIDv7.make(at: sample.date), measuredAt: sample.date,
                    dayKey: DayKey(date: sample.date, timeZone: timeZone), tz: timeZone.identifier,
                    weightKg: kilograms, source: .healthkit, hkUuid: sample.healthKitUUID,
                    createdAt: sample.date, updatedAt: sample.date
                ), in: db)
                known.insert(sample.healthKitUUID)
                imported += 1
            }
            return (imported, skipped)
        }
    }
}
