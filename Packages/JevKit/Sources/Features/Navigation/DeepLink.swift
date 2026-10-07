import Foundation

/// Le 5 tab principali (SCREEN_MAP §1).
public enum RootTab: String, Hashable, Sendable, CaseIterable {
    case today
    case training
    case nutrition
    case body
    case progress
}

/// Deep link `jevfit://…` (SCREEN_MAP §0: funzionano tutti offline).
///
/// M3 porta ogni link documentato nella tab che lo contiene; le schermate di dettaglio
/// (sessione, alimento, muscolo…) si aggiungono qui quando esistono, senza cambiare chi chiama.
public enum DeepLink: Equatable, Sendable {
    case tab(RootTab)

    public static let scheme = "jevfit"

    /// `nil` per schema diverso o percorso sconosciuto: il link viene ignorato senza errori.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == DeepLink.scheme else { return nil }
        // In `jevfit://workout/today` "workout" è l'host; accettiamo anche `jevfit:///workout`.
        let host = url.host(percentEncoded: false).flatMap { $0.isEmpty ? nil : $0 }
        let first = (host ?? url.pathComponents.dropFirst().first ?? "").lowercased()
        switch first {
        case "today", "profile", "weight", "settings", "check-in", "checkin":
            self = .tab(.today)
        case "workout", "exercises":
            self = .tab(.training)
        case "nutrition":
            self = .tab(.nutrition)
        case "body":
            self = .tab(.body)
        case "progress":
            self = .tab(.progress)
        default:
            return nil
        }
    }

    public var targetTab: RootTab {
        switch self {
        case .tab(let tab): tab
        }
    }
}
