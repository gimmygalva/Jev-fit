import Foundation
import JevCore

/// Accesso ai dati di Salute (Agent 08, M7). L'app non assume mai la presenza di Apple Watch
/// né l'autorizzazione: ogni metodo deve gestire "nessun dato" senza errori.
///
/// HealthKit non rivela se la lettura di un tipo è stata negata (privacy): un tipo negato
/// appare semplicemente vuoto. Per questo ogni componente a valle tratta "nessun campione"
/// come "dato mancante" e non come zero.
///
/// I dati fisiologici restano sul dispositivo (ADR-012).
public protocol HealthDataSource: Sendable {
    var isAvailable: Bool { get }
    /// Chiede i permessi. Non fallisce se l'utente nega: fallisce solo se Salute non è disponibile
    /// o la richiesta non è valida.
    func requestAuthorization(read: Set<HealthDataType>, write: Set<HealthDataType>) async throws
    /// Stato della richiesta per la scrittura (l'unico che HealthKit espone).
    func writeAuthorization(for type: HealthDataType) -> HealthWriteAuthorization
    func bodyMassSamples(from start: Date, to end: Date) async throws -> [BodyMassSample]
    /// Passi ed energia attiva sommati per giorno locale.
    func dailyActivity(from start: Date, to end: Date, timeZone: TimeZone) async throws -> [DayKey: DailyActivity]
    func sleepIntervals(from start: Date, to end: Date) async throws -> [SleepInterval]
    func restingHeartRateSamples(from start: Date, to end: Date) async throws -> [HealthQuantitySample]
    /// SDNN in millisecondi (Salute fornisce SDNN, non rMSSD).
    func heartRateVariabilitySamples(from start: Date, to end: Date) async throws -> [HealthQuantitySample]
    /// Salva una pesata e restituisce l'UUID del campione (per non reimportarla).
    func saveBodyMass(_ mass: Mass, at date: Date) async throws -> UUID
}

public enum HealthDataType: String, Sendable, Hashable, CaseIterable {
    case bodyMass = "body_mass"
    case bodyFatPercentage = "body_fat"
    case steps
    case activeEnergy = "active_energy"
    case sleep
    case heartRate = "heart_rate"
    case restingHeartRate = "resting_hr"
    case heartRateVariability = "hrv"
    case workouts

    /// Tipi letti dall'app (NSHealthShareUsageDescription).
    public static let readTypes: Set<HealthDataType> = Set(allCases)
    /// Tipi che l'app può scrivere, ognuno attivabile separatamente.
    public static let writeTypes: Set<HealthDataType> = [.bodyMass, .workouts]
}

public enum HealthWriteAuthorization: String, Sendable, Hashable {
    case notDetermined = "not_determined"
    case denied
    case authorized
}

public enum HealthDataError: Error, Equatable {
    case unavailable
    case writeNotAuthorized
}

/// Una pesata letta da Salute. `healthKitUUID` serve alla deduplica (vincolo unique `hk_uuid`).
public struct BodyMassSample: Sendable, Hashable {
    public var healthKitUUID: UUID
    public var date: Date
    public var mass: Mass
    /// Vero se la pesata è stata scritta da JEV FIT (per non reimportarla come nuova).
    public var writtenByThisApp: Bool

    public init(healthKitUUID: UUID, date: Date, mass: Mass, writtenByThisApp: Bool) {
        self.healthKitUUID = healthKitUUID
        self.date = date
        self.mass = mass
        self.writtenByThisApp = writtenByThisApp
    }
}

public struct DailyActivity: Sendable, Hashable {
    public var steps: Int?
    public var activeKcal: Double?

    public init(steps: Int? = nil, activeKcal: Double? = nil) {
        self.steps = steps
        self.activeKcal = activeKcal
    }
}

public struct SleepInterval: Sendable, Hashable {
    public enum Stage: String, Sendable, Hashable {
        /// Sonno effettivo (core, profondo, REM o "asleep" non specificato).
        case asleep
        case inBed = "in_bed"
        case awake
    }

    public var start: Date
    public var end: Date
    public var stage: Stage
    public var sourceID: String

    public init(start: Date, end: Date, stage: Stage, sourceID: String) {
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceID = sourceID
    }
}

public struct HealthQuantitySample: Sendable, Hashable {
    public var date: Date
    public var value: Double
    public var sourceID: String

    public init(date: Date, value: Double, sourceID: String) {
        self.date = date
        self.value = value
        self.sourceID = sourceID
    }
}

/// Sorgente usata quando Salute non è disponibile (es. iPad, simulatore senza dati) o
/// l'utente non ha concesso i permessi: l'app continua a funzionare con input manuale.
public struct UnavailableHealthDataSource: HealthDataSource {
    public init() {}
    public var isAvailable: Bool { false }
    public func requestAuthorization(read: Set<HealthDataType>, write: Set<HealthDataType>) async throws {
        throw HealthDataError.unavailable
    }
    public func writeAuthorization(for type: HealthDataType) -> HealthWriteAuthorization { .denied }
    public func bodyMassSamples(from start: Date, to end: Date) async throws -> [BodyMassSample] { [] }
    public func dailyActivity(from start: Date, to end: Date, timeZone: TimeZone) async throws -> [DayKey: DailyActivity] { [:] }
    public func sleepIntervals(from start: Date, to end: Date) async throws -> [SleepInterval] { [] }
    public func restingHeartRateSamples(from start: Date, to end: Date) async throws -> [HealthQuantitySample] { [] }
    public func heartRateVariabilitySamples(from start: Date, to end: Date) async throws -> [HealthQuantitySample] { [] }
    public func saveBodyMass(_ mass: Mass, at date: Date) async throws -> UUID { throw HealthDataError.unavailable }
}
