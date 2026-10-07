import Features
import SwiftUI

/// Punto d'ingresso dell'app. Resta volutamente sottile: crea il composition root
/// (`AppContainer`) e mostra la radice dell'interfaccia, che vive nel modulo `Features`.
@main
struct JevFitApp: App {
    /// `@State` garantisce un'unica istanza per tutta la vita del processo.
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            AppRootView(services: container.services)
        }
    }
}
