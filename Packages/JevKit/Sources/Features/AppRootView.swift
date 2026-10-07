import DesignSystem
import Persistence
import SwiftUI

/// Servizi che le feature ricevono dal composition root (`AppContainer`, ADR-002).
/// `nil` per lo store significa che il database non si è aperto: si mostra l'errore.
public struct AppServices {
    public let onboarding: OnboardingRepository?
    /// Import da Salute; `nil` se il database non è disponibile.
    public let health: HealthImporter?

    public init(onboarding: OnboardingRepository?, health: HealthImporter? = nil) {
        self.onboarding = onboarding
        self.health = health
    }
}

/// Vista di primo livello: tab, onboarding a schermo intero al primo avvio (SCREEN_MAP §1),
/// deep link `jevfit://`.
public struct AppRootView: View {
    @State private var router: AppRouter
    @State private var onboarding: OnboardingModel?
    private let services: AppServices

    public init(services: AppServices) {
        self.services = services
        let completed = (try? services.onboarding?.isCompleted()) ?? false
        let router = AppRouter(isOnboardingActive: services.onboarding != nil && !completed)
        _router = State(initialValue: router)
        // Il modello carica la bozza salvata: si riparte dallo step in cui l'utente era rimasto.
        _onboarding = State(initialValue: router.isOnboardingActive
            ? OnboardingModel(repository: services.onboarding) { router.onboardingFinished() }
            : nil)
    }

    public var body: some View {
        Group {
            if services.onboarding == nil {
                StartupErrorView()
            } else {
                RootView(router: router)
                    .fullScreenCover(isPresented: $router.isOnboardingPresented) {
                        if let onboarding {
                            OnboardingView(model: onboarding)
                                .interactiveDismissDisabled()
                        }
                    }
            }
        }
        .onOpenURL { url in
            router.handle(url)
        }
        // Dopo l'onboarding (SCR-ONB-15): permessi Salute e primo import; poi a ogni avvio.
        .task(id: router.isOnboardingActive) {
            guard !router.isOnboardingActive, let health = services.health else { return }
            await health.refresh()
        }
    }
}

extension AppRouter {
    /// Binding per `fullScreenCover`: l'onboarding si chiude solo completandolo.
    var isOnboardingPresented: Bool {
        get { isOnboardingActive }
        // La chiusura avviene solo da `onboardingFinished()`: un dismiss di sistema non ha effetto.
        set { _ = newValue }
    }
}

/// Mostrata se il database locale non si apre (disco pieno, file danneggiato).
/// Nessun dettaglio tecnico a schermo (SECURITY §10).
struct StartupErrorView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Impossibile aprire i dati", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Chiudi e riapri JEV FIT. Se il problema continua, controlla lo spazio libero sull'iPhone.")
        }
        .accessibilityIdentifier("startup.error")
    }
}
