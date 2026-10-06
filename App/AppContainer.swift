import Foundation

/// Composition root di JEV FIT (ARCHITECTURE_PLAN §1.3, "DI").
///
/// È l'unico punto dell'app in cui si creano e si collegano le implementazioni concrete:
/// - M2: `DataStore` GRDB e repository (`Persistence`);
/// - M3 e seguenti: `HealthKitService` (`Health`), `SyncService` (`Sync`),
///   `FoodProvider` (`Food`), `InsightsPipeline`, provider AI.
///
/// Regole:
/// - le feature ricevono i servizi come protocolli tramite `EnvironmentValues`, mai il container;
/// - gli engine (JevEngines) sono funzioni pure e non passano da qui;
/// - è `@MainActor` perché nasce e vive con la UI; i servizi con stato proprio sono `actor`
///   (ARCHITECTURE_PLAN §1.4).
///
/// In M1 è volutamente vuoto.
@MainActor
final class AppContainer {
    init() {}
}
