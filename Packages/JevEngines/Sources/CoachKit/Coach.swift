import Foundation
import JevDomain

// JEV (M11, §5.11): number grounding, safety in ingresso e in uscita, provider template offline e
// orchestrazione con un retry e fallback. JEV non calcola: spiega fatti e decisioni degli engine.

/// Esito della validazione di una bozza.
public enum GroundingIssue: Sendable, Hashable, Codable {
    /// Una cifra letterale fuori dai segnaposto.
    case literalDigits(String)
    /// Un numero scritto in lettere.
    case numberWord(String)
    /// Un segnaposto che non corrisponde a nessun fatto.
    case unknownFact(String)
    /// `dataUsed` cita un fatto inesistente.
    case unknownDataUsed(String)
    /// Contenuto non ammesso (digiuni, farmaci, dosaggi, diagnosi).
    case disallowedContent(String)
    case empty
}

public enum GroundingValidator {
    nonisolated(unsafe) static let placeholder = try! NSRegularExpression(pattern: #"\{\{fact:([a-z0-9_]{1,64})\}\}"#)
    nonisolated(unsafe) static let digits = try! NSRegularExpression(pattern: #"[0-9]"#)

    /// Numeri in lettere che falserebbero il grounding ("novecento", "trenta", "duemila"...).
    /// Esclusi "uno/una" e "sei" (articolo e verbo nel testo normale).
    nonisolated(unsafe) static let numberWords = try! NSRegularExpression(
        pattern: #"\b(zero|due|tre|quattro|cinque|sette|otto|nove|dieci|undici|dodici|tredici|quattordici|quindici|sedici|diciassette|diciotto|diciannove|venti|ventuno|trenta|quaranta|cinquanta|sessanta|settanta|ottanta|novanta|cento|mille|mila|milione|milioni|[a-z]+cento|[a-z]+mila|mezzo chilo|dozzina)\b"#,
        options: [.caseInsensitive]
    )

    public static func validate(_ draft: CoachDraft, facts: [CoachFact]) -> [GroundingIssue] {
        let known = Set(facts.map(\.id))
        var issues: [GroundingIssue] = []
        let texts = [draft.headline, draft.body] + draft.why
        if draft.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.empty)
        }
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in placeholder.matches(in: text, range: range) {
                if let id = Range(match.range(at: 1), in: text).map({ String(text[$0]) }), !known.contains(id) {
                    issues.append(.unknownFact(id))
                }
            }
            let stripped = placeholder.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            let strippedRange = NSRange(stripped.startIndex..., in: stripped)
            if digits.firstMatch(in: stripped, range: strippedRange) != nil {
                issues.append(.literalDigits(text))
            }
            if let match = numberWords.firstMatch(in: stripped, range: strippedRange),
               let word = Range(match.range, in: stripped) {
                issues.append(.numberWord(String(stripped[word])))
            }
            if let banned = SafetyFilter.disallowedOutput(in: stripped) {
                issues.append(.disallowedContent(banned))
            }
        }
        for id in draft.dataUsed where !known.contains(id) {
            issues.append(.unknownDataUsed(id))
        }
        return issues
    }

    /// Sostituisce i segnaposto con i valori formattati dal client.
    public static func render(_ text: String, facts: [CoachFact]) -> String {
        var result = text
        for fact in facts {
            result = result.replacingOccurrences(of: "{{fact:\(fact.id)}}", with: fact.formatted)
        }
        return result
    }
}

/// Segnali di allarme nei messaggi dell'utente e contenuti non ammessi nelle risposte (§5.11).
public enum SafetyFilter {
    public enum Alert: String, Sendable, Hashable, Codable, CaseIterable {
        case chestPain = "chest_pain"
        case fainting
        case injury
        case eatingDisorder = "eating_disorder"
        case extremeIntake = "extreme_intake"
    }

    static let alertPatterns: [(Alert, [String])] = [
        (.chestPain, ["dolore al petto", "dolore toracico", "oppressione al petto", "fitta al petto", "palpitazioni"]),
        (.fainting, ["svenut", "svenimento", "perso i sensi", "mi gira la testa", "vertigini forti"]),
        (.injury, ["infortun", "strappo", "frattura", "lussazione", "mi sono fatto male", "mi sono fatta male", "rottura del"]),
        (.eatingDisorder, ["vomit", "abbuffat", "lassativ", "non mangio da", "digiuno da giorni", "odio il mio corpo",
                           "mi faccio vomitare", "anoress", "bulimi"]),
        (.extremeIntake, ["mangiare zero", "zero calorie", "solo acqua per", "smettere di mangiare"]),
    ]

    static let disallowed = ["digiun", "farmac", "medicin", "steroid", "anabolizzant", "diuretic", "lassativ",
                             "diagnosi", "ti diagnostico", "hai una malattia", "insulina", "clenbuterol",
                             "mg di", "milligramm", "pillol", "integra con una dose"]

    public static func alerts(in message: String) -> [Alert] {
        let text = message.lowercased()
        return alertPatterns.filter { _, patterns in patterns.contains { text.contains($0) } }.map(\.0)
    }

    static func disallowedOutput(in text: String) -> String? {
        let lower = text.lowercased()
        return disallowed.first { lower.contains($0) }
    }
}

/// Provider deterministico e offline: testi da template per ogni reason code. È anche il
/// fallback quando l'AI non è disponibile, non è consentita o fallisce la validazione.
public struct TemplateAIProvider: AIProvider {
    public init() {}
    public var identifier: String { "template" }

    /// Frase per reason code. I numeri compaiono solo come segnaposto dei fatti.
    static let sentences: [String: String] = [
        "checkin.nutrition.keep": "Il target calorico resta invariato: la stima del dispendio è stabile.",
        "checkin.nutrition.increase": "Aumentiamo le calorie giornaliere: il dispendio stimato è salito o il ritmo è troppo rapido.",
        "checkin.nutrition.decrease": "Riduciamo le calorie giornaliere per tornare al ritmo che hai scelto.",
        "checkin.nutrition.insufficient_data": "Per questa settimana non cambio la nutrizione: servono più giorni registrati e più pesate.",
        "checkin.nutrition.goal_reached": "Sei vicino al peso obiettivo: possiamo passare al mantenimento.",
        "checkin.nutrition.protein_change": "Aggiorniamo il target di proteine in base al peso attuale.",
        "checkin.safety.fast_loss": "Stai perdendo peso troppo in fretta: aumentiamo le calorie.",
        "checkin.safety.low_intake": "L'apporto medio è molto basso: aumentiamo le calorie.",
        "checkin.safety.underweight": "Il tuo peso è sotto la soglia di sicurezza: niente deficit calorico.",
        "checkin.safety.pregnancy": "In gravidanza o allattamento non si fa deficit calorico.",
        "checkin.training.keep": "Il programma di allenamento resta com'è.",
        "checkin.training.reduce": "Recupero e readiness sono bassi: riduciamo un po' il volume.",
        "checkin.training.increase": "Recuperi bene e progredisci: aggiungiamo un po' di volume.",
        "checkin.training.deload_mesocycle": "Fine del mesociclo: settimana di scarico.",
        "checkin.training.deload_plateau": "Molti esercizi sono fermi: una settimana di scarico aiuta a ripartire.",
        "checkin.training.deload_readiness": "La readiness è bassa da giorni: settimana di scarico.",
        "checkin.training.deload_week": "Sei in settimana di scarico: il piano non cambia.",
        "checkin.training.change_pain": "Cambiamo un esercizio che ti ha dato fastidio.",
        "checkin.training.change_plateau": "Cambiamo un esercizio fermo da settimane.",
        "today.readiness": "Ecco come stai oggi secondo i tuoi dati.",
    ]

    static let safetyReplies: [SafetyFilter.Alert: String] = [
        .chestPain: "Dolore al petto o palpitazioni vanno valutati subito da un medico. Interrompi l'allenamento e, se il dolore è forte, chiama il numero di emergenza.",
        .fainting: "Svenimenti o forti vertigini vanno valutati da un medico prima di riprendere ad allenarti.",
        .injury: "Per un possibile infortunio fermati e fatti visitare da un medico o da un fisioterapista. Possiamo escludere gli esercizi che coinvolgono la zona.",
        .eatingDisorder: "Quello che descrivi merita l'aiuto di un professionista. Puoi parlarne con il tuo medico o con un servizio dedicato ai disturbi alimentari.",
        .extremeIntake: "Ridurre drasticamente il cibo non è sicuro. Un medico o un dietista può aiutarti a impostare un piano adatto a te.",
    ]

    public func draft(for request: CoachRequest) async throws -> CoachDraft {
        Self.compose(request)
    }

    static func compose(_ request: CoachRequest) -> CoachDraft {
        if let message = request.userMessage, let alert = SafetyFilter.alerts(in: message).first {
            return CoachDraft(headline: "Prima la salute", body: Self.safetyReplies[alert] ?? "", why: [], dataUsed: [])
        }
        let lines = request.reasonCodes.compactMap { Self.sentences[$0] }
        let headline = lines.first ?? "Il tuo piano è aggiornato."
        let factLines = request.facts.prefix(4).map { "\($0.label): {{fact:\($0.id)}}" }
        return CoachDraft(
            headline: headline,
            body: lines.dropFirst().joined(separator: " "),
            why: factLines,
            dataUsed: request.facts.prefix(4).map(\.id)
        )
    }
}

/// Messaggio finale di JEV, già validato e con i valori sostituiti.
public struct CoachMessage: Sendable, Hashable, Codable {
    public var headline: String
    public var body: String
    public var why: [String]
    public var dataUsed: [CoachFact]
    /// Provider che ha scritto il testo ("template" se fallback).
    public var source: String
    public var safetyAlert: SafetyFilter.Alert?
}

/// Orchestrazione (§5.11): safety in ingresso → provider → validazione → un retry con feedback →
/// fallback al template. Il testo arriva all'utente solo se il grounding è valido.
public struct CoachService: Sendable {
    let provider: (any AIProvider)?
    let fallback = TemplateAIProvider()

    /// `provider` nil: solo template (offline o senza consenso all'AI).
    public init(provider: (any AIProvider)?) {
        self.provider = provider
    }

    public func message(for request: CoachRequest) async -> CoachMessage {
        if let text = request.userMessage, let alert = SafetyFilter.alerts(in: text).first {
            return finalize(TemplateAIProvider.compose(request), request: request, source: fallback.identifier, alert: alert)
        }
        if let provider {
            var attempt = request
            for _ in 0..<2 {
                guard let draft = try? await provider.draft(for: attempt) else { break }
                let issues = GroundingValidator.validate(draft, facts: request.facts)
                if issues.isEmpty {
                    return finalize(draft, request: request, source: provider.identifier, alert: nil)
                }
                attempt.retryFeedback = Self.feedback(issues)
            }
        }
        return finalize(TemplateAIProvider.compose(request), request: request, source: fallback.identifier, alert: nil)
    }

    static func feedback(_ issues: [GroundingIssue]) -> String {
        "La risposta precedente non è valida: usa solo i segnaposto {{fact:id}} per i numeri, nessuna cifra o numero in lettere, nessun consiglio su farmaci, digiuni o diagnosi."
            + (issues.isEmpty ? "" : " Problemi: \(issues.count).")
    }

    func finalize(_ draft: CoachDraft, request: CoachRequest, source: String, alert: SafetyFilter.Alert?) -> CoachMessage {
        let used = request.facts.filter { draft.dataUsed.contains($0.id) }
        return CoachMessage(
            headline: GroundingValidator.render(draft.headline, facts: request.facts),
            body: GroundingValidator.render(draft.body, facts: request.facts),
            why: draft.why.map { GroundingValidator.render($0, facts: request.facts) },
            dataUsed: used, source: source, safetyAlert: alert
        )
    }
}
