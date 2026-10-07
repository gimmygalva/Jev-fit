import Foundation
import Observation

/// Stato di navigazione globale (ARCHITECTURE_PLAN §1.3): tab selezionata, onboarding attivo,
/// deep link in attesa. Le feature lo leggono dall'ambiente SwiftUI.
@MainActor
@Observable
public final class AppRouter {
    public var selectedTab: RootTab = .today
    /// `true` finché l'onboarding è a schermo: i deep link vengono messi in attesa.
    public private(set) var isOnboardingActive: Bool
    /// Ultimo deep link ricevuto durante l'onboarding, applicato quando finisce.
    public private(set) var pendingLink: DeepLink?

    public init(isOnboardingActive: Bool = false) {
        self.isOnboardingActive = isOnboardingActive
    }

    /// Gestisce un URL aperto dal sistema. Restituisce `false` se non è un deep link valido.
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        if isOnboardingActive {
            pendingLink = link
        } else {
            apply(link)
        }
        return true
    }

    /// Chiamato alla fine dell'onboarding: si va su Oggi (PS-ON-11) oppure sul link in attesa.
    public func onboardingFinished() {
        isOnboardingActive = false
        if let link = pendingLink {
            pendingLink = nil
            apply(link)
        } else {
            selectedTab = .today
        }
    }

    private func apply(_ link: DeepLink) {
        selectedTab = link.targetTab
    }
}
