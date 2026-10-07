import DesignSystem
import SwiftUI

/// Radice dell'interfaccia: `TabView` con le 5 tab di SCREEN_MAP §1.
///
/// Le schermate reali delle tab arrivano nelle milestone successive; per ora ogni tab mostra
/// un segnaposto dentro il suo `NavigationStack`.
///
/// Stringhe (ADR-015): le chiavi sono il testo italiano e stanno nello String Catalog dell'app
/// (`App/Resources/Localizable.xcstrings`), dove `LocalizedStringKey` le cerca per default.
/// I test UI usano gli identificatori di accessibilità, mai i testi.
public struct RootView: View {
    @Bindable private var router: AppRouter

    public init(router: AppRouter = AppRouter()) {
        self.router = router
    }

    public var body: some View {
        // API `Tab` di iOS 18 (sostituisce `.tabItem`), disponibile dal nostro deployment target.
        TabView(selection: $router.selectedTab) {
            Tab("Oggi", systemImage: "sun.max", value: RootTab.today) {
                PlaceholderTabView(title: "Oggi", systemImage: "sun.max", identifier: "tab.today")
            }
            Tab("Allenamento", systemImage: "dumbbell", value: RootTab.training) {
                PlaceholderTabView(title: "Allenamento", systemImage: "dumbbell", identifier: "tab.training")
            }
            Tab("Nutrizione", systemImage: "fork.knife", value: RootTab.nutrition) {
                PlaceholderTabView(title: "Nutrizione", systemImage: "fork.knife", identifier: "tab.nutrition")
            }
            Tab("Corpo", systemImage: "figure.arms.open", value: RootTab.body) {
                PlaceholderTabView(title: "Corpo", systemImage: "figure.arms.open", identifier: "tab.body")
            }
            Tab("Progressi", systemImage: "chart.line.uptrend.xyaxis", value: RootTab.progress) {
                PlaceholderTabView(
                    title: "Progressi",
                    systemImage: "chart.line.uptrend.xyaxis",
                    identifier: "tab.progress"
                )
            }
        }
        .tint(JevColor.ion)
        .accessibilityIdentifier("root.tabview")
    }
}

/// Contenuto provvisorio di una tab, sostituito dalle feature reali nelle prossime milestone.
private struct PlaceholderTabView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let identifier: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text("Questa sezione è in costruzione.")
            }
            .symbolRenderingMode(.hierarchical)
            .navigationTitle(title)
            .accessibilityIdentifier(identifier)
        }
    }
}
