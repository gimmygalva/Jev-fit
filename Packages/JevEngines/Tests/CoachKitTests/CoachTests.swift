import CheckInEngine
import Foundation
import JevDomain
import Testing
@testable import CoachKit

private struct ScriptedProvider: AIProvider {
    let identifier = "scripted"
    let drafts: [CoachDraft]
    let calls = Counter()

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        private var feedback: [String?] = []
        func next(_ request: CoachRequest) -> Int {
            lock.lock(); defer { lock.unlock() }
            feedback.append(request.retryFeedback)
            value += 1
            return value - 1
        }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        var feedbacks: [String?] { lock.lock(); defer { lock.unlock() }; return feedback }
    }

    func draft(for request: CoachRequest) async throws -> CoachDraft {
        let index = calls.next(request)
        guard index < drafts.count else { throw AIProviderError.unavailable }
        return drafts[index]
    }
}

@Suite("JEV: grounding dei numeri, safety, fallback (§5.11)")
struct CoachTests {
    let fact = CoachFact(id: "proposed_target_kcal", label: "Target proposto", value: 2350, unit: "kcal", formatted: "2350 kcal")

    private func request(message: String? = nil) -> CoachRequest {
        CoachRequest(tier: .analysis, purpose: "check_in_explanation", facts: [fact],
                     reasonCodes: ["checkin.nutrition.increase", "checkin.training.keep"], userMessage: message)
    }

    @Test("Validazione: cifre, numeri in lettere, segnaposto sconosciuti, contenuti vietati")
    func validation() {
        let good = CoachDraft(headline: "Nuovo target", body: "Da oggi punta a {{fact:proposed_target_kcal}}.", why: [],
                              dataUsed: ["proposed_target_kcal"])
        #expect(GroundingValidator.validate(good, facts: [fact]).isEmpty)
        let digits = CoachDraft(headline: "Target 2350", body: "", why: [], dataUsed: [])
        #expect(GroundingValidator.validate(digits, facts: [fact]) == [.literalDigits("Target 2350")])
        let words = CoachDraft(headline: "Ok", body: "Mangia duemila calorie", why: [], dataUsed: [])
        #expect(GroundingValidator.validate(words, facts: [fact]) == [.numberWord("duemila")])
        let unknown = CoachDraft(headline: "{{fact:missing}}", body: "x", why: [], dataUsed: ["ghost"])
        #expect(GroundingValidator.validate(unknown, facts: [fact]) == [.unknownFact("missing"), .unknownDataUsed("ghost")])
        let banned = CoachDraft(headline: "Ok", body: "Prova un digiuno prolungato", why: [], dataUsed: [])
        #expect(GroundingValidator.validate(banned, facts: [fact]) == [.disallowedContent("digiun")])
        #expect(GroundingValidator.validate(CoachDraft(headline: " ", body: "", why: [], dataUsed: []), facts: []) == [.empty])
        // "sei" e "una" non sono numeri nel testo normale.
        let normal = CoachDraft(headline: "Sei sulla buona strada", body: "Una settimana solida.", why: [], dataUsed: [])
        #expect(GroundingValidator.validate(normal, facts: []).isEmpty)
        #expect(GroundingValidator.render("A {{fact:proposed_target_kcal}}", facts: [fact]) == "A 2350 kcal")
    }

    @Test("Il provider valido vince; i segnaposto diventano valori")
    func providerOK() async {
        let provider = ScriptedProvider(drafts: [CoachDraft(headline: "Su", body: "Target: {{fact:proposed_target_kcal}}",
                                                            why: ["Il dispendio è salito"], dataUsed: ["proposed_target_kcal"])])
        let message = await CoachService(provider: provider).message(for: request())
        #expect(message.source == "scripted")
        #expect(message.body == "Target: 2350 kcal")
        #expect(message.dataUsed == [fact])
    }

    @Test("Una risposta non valida: un retry con feedback, poi fallback al template")
    func retryAndFallback() async {
        let bad = CoachDraft(headline: "Mangia 2500 kcal", body: "", why: [], dataUsed: [])
        let fixed = CoachDraft(headline: "Ok", body: "{{fact:proposed_target_kcal}}", why: [], dataUsed: [])
        let recovering = ScriptedProvider(drafts: [bad, fixed])
        let second = await CoachService(provider: recovering).message(for: request())
        #expect(second.source == "scripted" && second.body == "2350 kcal")
        #expect(recovering.calls.feedbacks.first == .some(nil))
        #expect(recovering.calls.feedbacks.last??.isEmpty == false)
        let stubborn = ScriptedProvider(drafts: [bad, bad])
        let fallback = await CoachService(provider: stubborn).message(for: request())
        #expect(fallback.source == "template")
        #expect(stubborn.calls.count == 2)
        #expect(!fallback.headline.isEmpty)
        let offline = await CoachService(provider: ScriptedProvider(drafts: [])).message(for: request())
        #expect(offline.source == "template")
        let noAI = await CoachService(provider: nil).message(for: request())
        #expect(noAI.why.first == "Target proposto: 2350 kcal")
    }

    @Test("Segnali di allarme: risposta di sicurezza senza chiamare l'AI", arguments: [
        ("Ho un dolore al petto quando corro", SafetyFilter.Alert.chestPain),
        ("Ieri sono svenuto in palestra", .fainting),
        ("Credo di avere uno strappo", .injury),
        ("Dopo cena mi faccio vomitare", .eatingDisorder),
        ("Voglio mangiare zero per una settimana", .extremeIntake),
    ])
    func alerts(_ text: String, _ alert: SafetyFilter.Alert) async {
        let provider = ScriptedProvider(drafts: [])
        let message = await CoachService(provider: provider).message(for: request(message: text))
        #expect(message.safetyAlert == alert)
        #expect(provider.calls.count == 0)
        #expect(message.headline == "Prima la salute")
        #expect(GroundingValidator.validate(CoachDraft(headline: message.headline, body: message.body, why: [], dataUsed: []),
                                            facts: []).isEmpty)
    }

    @Test("Template: ogni frase rispetta il grounding")
    func templates() {
        for sentence in TemplateAIProvider.sentences.values {
            let draft = CoachDraft(headline: sentence, body: "", why: [], dataUsed: [])
            #expect(GroundingValidator.validate(draft, facts: []).isEmpty, "\(sentence)")
        }
        for reply in TemplateAIProvider.safetyReplies.values {
            #expect(GroundingValidator.validate(CoachDraft(headline: reply, body: "", why: [], dataUsed: []), facts: []).isEmpty)
        }
        let empty = TemplateAIProvider.compose(CoachRequest(tier: .routine, purpose: "x", facts: [], reasonCodes: []))
        #expect(empty.headline == "Il tuo piano è aggiornato.")
    }

    @Test("Fatti del check-in formattati in italiano e richiesta di analisi")
    func checkInFacts() {
        var metrics = CheckInEvaluator.Metrics(
            completeLoggedDays: 6, weighIns: 5, lossPercentThisWeek: 0.4, goal: .fatLoss, currentTargetKcal: 2200,
            proposedTargetKcal: 2500, expenditureKcal: 2600, floorKcal: 1700, trendWeightKg: 80.25,
            readinessAverage7Days: 71, recoveryAveragePercent: 82
        )
        metrics.averageIntakeKcal = 2190
        let result = CheckInEvaluator.evaluate(metrics)
        let request = CheckInCoach.request(metrics, result: result)
        #expect(request.tier == .analysis)
        let byID = Dictionary(uniqueKeysWithValues: request.facts.map { ($0.id, $0.formatted) })
        #expect(byID["proposed_target_kcal"] == "2500 kcal")
        #expect(byID["trend_weight_kg"] == "80,3 kg" || byID["trend_weight_kg"] == "80,2 kg")
        #expect(byID["loss_percent_week"] == "-0,4 %")
        #expect(byID["delta_kcal"] == "+150 kcal")
        #expect(byID["readiness_7d"] == "71")
        #expect(request.reasonCodes.contains("checkin.nutrition.increase"))
    }
}
