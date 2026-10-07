import CoachKit
import Foundation
import JevCore
import JevDomain
import Persistence
import Testing
@testable import Features

@Suite("Chat con JEV (post-RC)")
@MainActor
struct JevChatTests {
    let store: DataStore
    let model: JevChatModel

    init() throws {
        store = try DataStore.inMemory()
        let facts = FactRepository(store: store)
        let training = try #require(TrainingPlanService.bundled(facts: facts))
        let dashboard = DashboardService(training: training, nutrition: NutritionPlanService(facts: facts), healthCache: nil)
        model = JevChatModel(coach: CoachService(provider: nil), dashboard: dashboard)
        var draft = OnboardingDraft()
        draft.goal = .hypertrophy
        draft.experience = .intermediate
        draft.weightKg = 80
        draft.heightCm = 180
        draft.ageYears = 30
        draft.daysPerWeek = 3
        try OnboardingRepository(store: store).complete(draft, timeZone: .current)
    }

    @Test("Risposta con i fatti di oggi, nessun segnaposto non risolto")
    func reply() async {
        let facts = model.facts()
        #expect(facts.contains { $0.id == "target_kcal" })
        #expect(facts.contains { $0.id == "next_session_exercises" })
        await model.send("Come sto oggi?")
        #expect(model.messages.count == 2)
        #expect(model.messages[0].fromUser)
        let answer = model.messages[1]
        #expect(!answer.fromUser && !answer.text.isEmpty)
        #expect(answer.why.allSatisfy { !$0.contains("{{") })
        #expect(answer.why.contains { $0.contains("kcal") })
    }

    @Test("Segnali di allarme: risposta di sicurezza; messaggi vuoti ignorati")
    func safety() async {
        await model.send("   ")
        #expect(model.messages.isEmpty)
        await model.send("Ho un dolore al petto")
        #expect(model.messages.last?.text.contains("medico") == true)
    }
}
