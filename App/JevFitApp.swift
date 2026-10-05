import SwiftUI
import Features

/// Punto d'ingresso dell'app. Resta volutamente sottile: crea il composition root
/// (`AppContainer`) e mostra la radice dell'interfaccia, che vive nel modulo `Features`.
@main
struct JevFitApp: App {
    /// `@State` garantisce un'unica istanza per tutta la vita del processo.
    /// In M1 il container è vuoto; da M2/M3 verrà passato alle feature via `EnvironmentValues`.
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
