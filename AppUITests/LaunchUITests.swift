import XCTest

/// Test UI dei flussi principali. Usano solo identificatori di accessibilità, mai testi (ADR-015).
/// L'argomento `-jev-in-memory-store` fa partire l'app da un'installazione pulita.
final class LaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchClean() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-jev-in-memory-store"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(app, identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Elemento '\(identifier)' non trovato", file: file, line: line)
        target.tap()
    }

    @MainActor
    private func type(_ app: XCUIApplication, _ identifier: String, _ text: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Campo '\(identifier)' non trovato")
        field.tap()
        field.typeText(text)
    }

    @MainActor
    func testFirstLaunchShowsOnboarding() throws {
        let app = launchClean()
        // Timeout ampio: al primo avvio il simulatore in CI può essere lento.
        XCTAssertTrue(
            element(app, "onboarding.step.welcome").waitForExistence(timeout: 30),
            "L'onboarding non compare al primo avvio"
        )
    }

    /// UF-01 con le sole risposte obbligatorie: dati salvati e arrivo sulle tab (PS-ON-02, PS-ON-11).
    @MainActor
    func testOnboardingHappyPathReachesTabs() throws {
        let app = launchClean()
        XCTAssertTrue(element(app, "onboarding.step.welcome").waitForExistence(timeout: 30))
        tap(app, "onboarding.continue")

        tap(app, "onboarding.goal.maintenance")
        tap(app, "onboarding.continue")

        tap(app, "onboarding.experience.intermediate")
        tap(app, "onboarding.continue")

        type(app, "onboarding.body.weight", "80")
        type(app, "onboarding.body.height", "180")
        type(app, "onboarding.body.age", "30")
        tap(app, "onboarding.continue")

        XCTAssertTrue(element(app, "onboarding.step.activity").waitForExistence(timeout: 10))
        tap(app, "onboarding.continue")

        tap(app, "onboarding.availability.days.3")
        tap(app, "onboarding.continue")

        tap(app, "onboarding.equipment.preset.full_gym")
        tap(app, "onboarding.continue")

        // Split, limitazioni, priorità, macro, unità: valori predefiniti.
        for _ in 0..<5 { tap(app, "onboarding.skip") }

        XCTAssertTrue(element(app, "onboarding.step.summary").waitForExistence(timeout: 10))
        tap(app, "onboarding.continue")

        XCTAssertTrue(
            element(app, "root.tabview").waitForExistence(timeout: 15),
            "Dopo l'onboarding non compaiono le tab"
        )
        XCTAssertFalse(element(app, "onboarding.step.summary").exists)
    }
}
