import Foundation
import JevCore

/// Accesso ai dati di Salute (Agent 08, M7). L'app non assume mai la presenza di Apple Watch
/// né l'autorizzazione: ogni metodo deve gestire "nessun dato" senza errori.
///
/// I dati fisiologici restano sul dispositivo (ADR-012).
public protocol HealthDataSource: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func bodyMassSamples(from start: Date, to end: Date) async throws -> [BodyMassSample]
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

/// Sorgente usata quando Salute non è disponibile (es. iPad, simulatore senza dati) o
/// l'utente non ha concesso i permessi: l'app continua a funzionare con input manuale.
public struct UnavailableHealthDataSource: HealthDataSource {
    public init() {}
    public var isAvailable: Bool { false }
    public func requestAuthorization() async throws {}
    public func bodyMassSamples(from start: Date, to end: Date) async throws -> [BodyMassSample] { [] }
}
