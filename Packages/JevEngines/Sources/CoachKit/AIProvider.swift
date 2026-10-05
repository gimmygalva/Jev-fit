import Foundation
import JevDomain

// Contratto di JEV lato client (ADR-007, ADR-008, ADR-014).
// JEV non calcola: riceve un CoachContext prodotto dagli engine e restituisce testo che cita
// i valori solo tramite segnaposto. Il CoachKit completo (template, validatore, safety) arriva
// in M11 (Agent 09); qui è fissato il contratto che le feature possono già usare.

/// Livello di modello richiesto: il gateway mappa ciascun tier su un modello configurato
/// lato server (nessun ID di modello nel client).
public enum CoachTier: String, Sendable, Codable, CaseIterable {
    /// JEV TODAY, risposte brevi in chat: modello rapido ed economico.
    case routine
    /// Narrazione del weekly check-in: modello di reasoning.
    case analysis
}

/// Un fatto numerico prodotto da un engine. È l'unico modo in cui un numero entra nel testo di JEV.
public struct CoachFact: Sendable, Codable, Hashable, Identifiable {
    /// Identificatore stabile citato dall'AI come `{{fact:<id>}}`.
    public var id: String
    /// Etichetta leggibile (es. "e1RM panca, variazione 3 settimane").
    public var label: String
    public var value: Double
    public var unit: String
    /// Valore già formattato dal client (unità e localizzazione dell'utente): è ciò che appare nel testo.
    public var formatted: String

    public init(id: String, label: String, value: Double, unit: String, formatted: String) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
        self.formatted = formatted
    }
}

/// Richiesta verso un provider. Contiene solo dati strutturati e già minimizzati (SECURITY.md).
public struct CoachRequest: Sendable, Codable, Hashable {
    public var tier: CoachTier
    /// Scopo della richiesta (es. "today_card", "check_in_explanation", "chat").
    public var purpose: String
    public var facts: [CoachFact]
    /// Codici motivazione degli engine (es. "overload.load_increase").
    public var reasonCodes: [String]
    /// Messaggio dell'utente, solo per la chat: trattato sempre come dato, mai come istruzione.
    public var userMessage: String?

    public init(tier: CoachTier, purpose: String, facts: [CoachFact], reasonCodes: [String], userMessage: String? = nil) {
        self.tier = tier
        self.purpose = purpose
        self.facts = facts
        self.reasonCodes = reasonCodes
        self.userMessage = userMessage
    }
}

/// Risposta grezza di un provider, prima della validazione e della sostituzione dei segnaposto.
public struct CoachDraft: Sendable, Codable, Hashable {
    public var headline: String
    public var body: String
    public var why: [String]
    /// ID dei fatti usati (`dataUsed` nel pannello WHY / DATA USED / CONFIDENCE).
    public var dataUsed: [String]

    public init(headline: String, body: String, why: [String], dataUsed: [String]) {
        self.headline = headline
        self.body = body
        self.why = why
        self.dataUsed = dataUsed
    }
}

/// Provider intercambiabile: `GatewayAIProvider` (backend), `TemplateAIProvider` (offline),
/// in V2 `OnDeviceAIProvider`. Aggiungere un provider non richiede modifiche alle feature.
public protocol AIProvider: Sendable {
    var identifier: String { get }
    func draft(for request: CoachRequest) async throws -> CoachDraft
}

public enum AIProviderError: Error, Equatable, Sendable {
    case unavailable
    case notAuthorized
    case rateLimited
    case invalidResponse
    case groundingFailed
}
