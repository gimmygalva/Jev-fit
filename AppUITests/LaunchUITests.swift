import XCTest

/// Smoke test UI: l'app si avvia e mostra la radice a tab.
/// I test UI usano solo identificatori di accessibilità, mai testi (ADR-015).
final class LaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsRootTabView() throws {
        let app = XCUIApplication()
        app.launch()

        // `firstMatch` + qualsiasi tipo di elemento: SwiftUI può esporre l'identificatore
        // sul contenitore della TabView o propagarlo ai figli; a noi basta che esista.
        let root = app.descendants(matching: .any)
            .matching(identifier: "root.tabview")
            .firstMatch
        // Timeout ampio: al primo avvio il simulatore in CI può essere lento.
        XCTAssertTrue(root.waitForExistence(timeout: 30), "Elemento 'root.tabview' non trovato dopo l'avvio")
    }
}
