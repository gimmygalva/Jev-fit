import Foundation
import Testing
@testable import CoachKit

/// Provider di test che restituisce un testo con segnaposto: verifica che il contratto sia
/// implementabile da un tipo `Sendable` senza stato condiviso.
private struct EchoProvider: AIProvider {
    let identifier = "echo"
    func draft(for request: CoachRequest) async throws -> CoachDraft {
        guard let fact = request.facts.first else { throw AIProviderError.invalidResponse }
        return CoachDraft(headline: "Ok", body: "Valore: {{fact:\(fact.id)}}", why: [], dataUsed: [fact.id])
    }
}

@Suite("CoachKit — contratto AIProvider")
struct AIProviderContractTests {
    @Test("Due tier, nessun ID di modello nel client")
    func tiers() {
        #expect(CoachTier.allCases.map(\.rawValue) == ["routine", "analysis"])
    }

    @Test("Un provider restituisce segnaposto, non cifre")
    func placeholder() async throws {
        let fact = CoachFact(id: "bench_e1rm_delta_3w", label: "e1RM panca 3 sett.", value: 4.8, unit: "%", formatted: "+4,8%")
        let request = CoachRequest(tier: .routine, purpose: "today_card", facts: [fact], reasonCodes: ["overload.load_increase"])
        let draft = try await EchoProvider().draft(for: request)
        #expect(draft.body.contains("{{fact:bench_e1rm_delta_3w}}"))
        #expect(draft.dataUsed == ["bench_e1rm_delta_3w"])
        #expect(!draft.body.contains("4,8"))
    }

    @Test("Senza fatti il provider fallisce in modo tipizzato")
    func failure() async {
        let request = CoachRequest(tier: .analysis, purpose: "check_in_explanation", facts: [], reasonCodes: [])
        await #expect(throws: AIProviderError.invalidResponse) {
            try await EchoProvider().draft(for: request)
        }
    }

    @Test("Richiesta e bozza sono serializzabili (payload verso il gateway)")
    func codable() throws {
        let request = CoachRequest(tier: .routine, purpose: "chat", facts: [], reasonCodes: [], userMessage: "Perché 85 kg?")
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(CoachRequest.self, from: data) == request)
    }
}
