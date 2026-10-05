import SwiftUI
import Testing
@testable import Features

@Suite("Features — radice")
@MainActor
struct RootViewTests {
    @Test("La radice si costruisce senza dipendenze esterne")
    func builds() {
        let view = RootView()
        _ = view.body
    }
}
