import Testing
@testable import JevFit

/// Smoke test del target app: il composition root deve potersi creare senza dipendenze
/// esterne (niente rete, niente HealthKit, niente database). Se un giorno `init()` iniziasse
/// a richiedere servizi reali, questo test lo segnalerebbe subito.
@MainActor
struct AppContainerTests {
    @Test("AppContainer si istanzia e ogni chiamata crea un'istanza distinta")
    func instantiates() {
        let first = AppContainer()
        let second = AppContainer()
        #expect(first !== second)
    }
}
