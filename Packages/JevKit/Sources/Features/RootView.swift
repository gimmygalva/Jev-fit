import DesignSystem
import Food
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
    private let training: TrainingPlanService?
    private let nutrition: NutritionPlanService?
    private let foodSearch: FoodSearch?
    private let dashboard: DashboardService?

    public init(router: AppRouter = AppRouter(), training: TrainingPlanService? = nil,
                nutrition: NutritionPlanService? = nil, foodSearch: FoodSearch? = nil,
                dashboard: DashboardService? = nil) {
        self.router = router
        self.training = training
        self.nutrition = nutrition
        self.foodSearch = foodSearch
        self.dashboard = dashboard
    }

    public var body: some View {
        // API `Tab` di iOS 18 (sostituisce `.tabItem`), disponibile dal nostro deployment target.
        TabView(selection: $router.selectedTab) {
            Tab("Oggi", systemImage: "sun.max", value: RootTab.today) {
                if let dashboard {
                    TodayTabView(service: dashboard)
                } else {
                    PlaceholderTabView(title: "Oggi", systemImage: "sun.max", identifier: "tab.today")
                }
            }
            Tab("Allenamento", systemImage: "dumbbell", value: RootTab.training) {
                if let training {
                    TrainingTabView(service: training)
                } else {
                    PlaceholderTabView(title: "Allenamento", systemImage: "dumbbell", identifier: "tab.training")
                }
            }
            Tab("Nutrizione", systemImage: "fork.knife", value: RootTab.nutrition) {
                if let nutrition, let foodSearch {
                    NutritionTabView(service: nutrition, search: foodSearch)
                } else {
                    PlaceholderTabView(title: "Nutrizione", systemImage: "fork.knife", identifier: "tab.nutrition")
                }
            }
            Tab("Corpo", systemImage: "figure.arms.open", value: RootTab.body) {
                if let dashboard {
                    BodyTabView(service: dashboard)
                } else {
                    PlaceholderTabView(title: "Corpo", systemImage: "figure.arms.open", identifier: "tab.body")
                }
            }
            Tab("Progressi", systemImage: "chart.line.uptrend.xyaxis", value: RootTab.progress) {
                if let dashboard {
                    ProgressTabView(service: dashboard)
                } else {
                    PlaceholderTabView(
                        title: "Progressi",
                        systemImage: "chart.line.uptrend.xyaxis",
                        identifier: "tab.progress"
                    )
                }
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
