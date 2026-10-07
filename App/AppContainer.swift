import Features
import Foundation
import Health
import Persistence

/// Composition root di JEV FIT (ARCHITECTURE_PLAN §1.3, "DI").
///
/// È l'unico punto dell'app in cui si creano e si collegano le implementazioni concrete:
/// - M3: `DataStore` GRDB e repository dell'onboarding;
/// - M7: sorgente Salute (HealthKit reale, simulata nei test) e cache locale degli aggregati;
/// - prossime milestone: `SyncService`, `FoodProvider`, `InsightsPipeline`, provider AI.
///
/// Regole:
/// - le feature ricevono servizi e repository, mai il container;
/// - gli engine (JevEngines) sono funzioni pure e non passano da qui;
/// - è `@MainActor` perché nasce e vive con la UI (ARCHITECTURE_PLAN §1.4).
@MainActor
final class AppContainer {
    enum Storage {
        /// `Application Support/JevFit/jev.sqlite`, con Data Protection (SEC-LS-01).
        case onDisk
        /// Database in memoria: test e UI test (`-jev-in-memory-store`), nessun dato persistente.
        case inMemory
    }

    /// Argomento di avvio usato dai test UI per partire sempre da un'installazione pulita.
    static let inMemoryLaunchArgument = "-jev-in-memory-store"
    /// Dati di Salute simulati (simulatore, demo). Implicito con il database in memoria:
    /// i test UI non devono mai vedere il foglio dei permessi di sistema.
    static let mockHealthLaunchArgument = "-jev-mock-health"

    let store: DataStore?
    let healthCache: HealthCacheStore?
    let healthSource: any HealthDataSource

    init(storage: Storage, mockHealth: Bool = false) {
        // Se il database non si apre l'app mostra una schermata d'errore invece di andare in crash.
        switch storage {
        case .onDisk:
            store = try? DataStore.onDisk(at: DataStore.defaultURL())
            healthCache = try? HealthCacheStore.onDisk(directory: HealthCacheStore.defaultDirectory())
        case .inMemory:
            store = try? DataStore.inMemory()
            healthCache = try? HealthCacheStore.inMemory()
        }
        healthSource = Self.makeHealthSource(mock: mockHealth || storage == .inMemory)
    }

    /// Sceglie storage e sorgente Salute dagli argomenti di avvio.
    convenience init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.init(
            storage: arguments.contains(Self.inMemoryLaunchArgument) ? .inMemory : .onDisk,
            mockHealth: arguments.contains(Self.mockHealthLaunchArgument)
        )
    }

    static func makeHealthSource(mock: Bool) -> any HealthDataSource {
        if mock {
            let data = MockHealthDataSource.demoData(now: Date(), days: 42, timeZone: .current)
            return MockHealthDataSource(data: data)
        }
        let healthKit = HealthKitDataSource()
        return healthKit.isAvailable ? healthKit : UnavailableHealthDataSource()
    }

    var services: AppServices {
        guard let store else { return AppServices(onboarding: nil) }
        let facts = FactRepository(store: store)
        let health = healthCache.map { HealthImporter(source: healthSource, cache: $0, facts: facts) }
        let training = TrainingPlanService.bundled(facts: facts)
        return AppServices(onboarding: OnboardingRepository(store: store), health: health, training: training)
    }
}
