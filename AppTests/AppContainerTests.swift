import Testing
@testable import JevFit

/// Smoke test del composition root: si crea senza rete né HealthKit e apre il database.
@MainActor
struct AppContainerTests {
    @Test("AppContainer in memoria apre il database e fornisce il repository dell'onboarding")
    func inMemory() throws {
        let container = AppContainer(storage: .inMemory)
        #expect(container.store != nil)
        let onboarding = try #require(container.services.onboarding)
        #expect(try onboarding.isCompleted() == false)
    }

    @Test("L'argomento di avvio dei test UI sceglie il database in memoria")
    func launchArgument() {
        let first = AppContainer(arguments: [AppContainer.inMemoryLaunchArgument])
        let second = AppContainer(arguments: [AppContainer.inMemoryLaunchArgument])
        #expect(first !== second)
        #expect(first.store != nil)
        #expect(first.store?.deviceID != second.store?.deviceID, "Ogni database in memoria è indipendente")
    }
}
