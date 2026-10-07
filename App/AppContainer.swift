import Features
import Foundation
import Persistence

/// Composition root di JEV FIT (ARCHITECTURE_PLAN §1.3, "DI").
///
/// È l'unico punto dell'app in cui si creano e si collegano le implementazioni concrete:
/// - M3: `DataStore` GRDB e repository dell'onboarding;
/// - prossime milestone: `HealthKitService`, `SyncService`, `FoodProvider`, `InsightsPipeline`,
///   provider AI.
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

    let store: DataStore?

    init(storage: Storage) {
        // Se il database non si apre l'app mostra una schermata d'errore invece di andare in crash.
        switch storage {
        case .onDisk:
            store = try? DataStore.onDisk(at: DataStore.defaultURL())
        case .inMemory:
            store = try? DataStore.inMemory()
        }
    }

    /// Sceglie lo storage dagli argomenti di avvio.
    convenience init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.init(storage: arguments.contains(Self.inMemoryLaunchArgument) ? .inMemory : .onDisk)
    }

    var services: AppServices {
        AppServices(onboarding: store.map { OnboardingRepository(store: $0) })
    }
}
