import SwiftUI

/// Radice dell'interfaccia: `TabView` con le 5 tab di SCREEN_MAP §2.
///
/// M1: ogni tab mostra un segnaposto. Le schermate reali arrivano nelle milestone successive.
///
/// Stringhe (ADR-015): le chiavi sono il testo italiano. Finché il modulo `Features` non ha
/// risorse proprie, `LocalizedStringKey` viene risolta nel bundle principale, cioè nello
/// String Catalog dell'app (`App/Resources/Localizable.xcstrings`), dove queste chiavi sono
/// registrate. Quando `Features` avrà un suo catalogo, passare `bundle: .module`.
///
/// I test UI si appoggiano agli identificatori di accessibilità, mai ai testi.
public struct RootView: View {
    @State private var selection: RootTab = .today

    public init() {}

    public var body: some View {
        // API `Tab` di iOS 18 (sostituisce `.tabItem`), disponibile dal nostro deployment target.
        TabView(selection: $selection) {
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
        .accessibilityIdentifier("root.tabview")
    }
}

/// Le 5 tab principali. Interno al modulo: il deep link `jevfit://` (AppRouter) lo userà più avanti.
enum RootTab: Hashable {
    case today
    case training
    case nutrition
    case body
    case progress
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
