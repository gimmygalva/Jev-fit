import Foundation
import JevCore
import JevDomain
import NutritionEngine
import Persistence
import Testing
@testable import Features

@Suite("Target nutrizionali dai dati reali (M9)")
struct NutritionPlanServiceTests {
    let store: DataStore
    let service: NutritionPlanService
    let utc = TimeZone(identifier: "UTC")!

    init() throws {
        store = try DataStore.inMemory()
        service = NutritionPlanService(facts: FactRepository(store: store))
    }

    private func onboard(goal: GoalType, rate: Double? = nil) throws {
        var draft = OnboardingDraft()
        draft.goal = goal
        draft.experience = .intermediate
        draft.weightKg = 80
        draft.heightCm = 180
        draft.ageYears = 30
        draft.sex = .male
        draft.activityLevel = .moderate
        draft.targetRatePercentPerWeek = rate
        draft.daysPerWeek = 3
        try OnboardingRepository(store: store).complete(draft, timeZone: utc)
    }

    private var today: DayKey { DayKey(date: Date(), timeZone: utc) }

    @Test("Senza profilo o senza pesate nessun target")
    func missing() throws {
        #expect(try service.targets(on: today) == nil)
    }

    @Test("Dimagrimento: target sotto l'expenditure del prior, macro coerenti, confidence iniziale")
    func fatLoss() throws {
        try onboard(goal: .fatLoss, rate: -0.5)
        let targets = try #require(try service.targets(on: today))
        let prior = EnergyModel.priorExpenditure(weightKg: 80, heightCm: 180, ageYears: 30,
                                                 sex: .male, activity: .moderate)
        #expect(abs(targets.expenditureKcal - prior.kcal) < 1)
        #expect(targets.kcal < targets.expenditureKcal)
        #expect(targets.ratePercentPerWeek == -0.5)
        #expect(targets.confidenceLabel == .initialEstimate)
        #expect(abs(targets.macros.kcal - targets.kcal) <= targets.kcal * 0.01)
        #expect(targets.macros.proteinG == (2.2 * 80).rounded())
        #expect(targets.currentWeightKg == 80)
    }

    @Test("Mantenimento: target uguale all'expenditure arrotondata; giorni registrati entrano nella stima")
    func maintenance() throws {
        try onboard(goal: .maintenance)
        let log = service.log
        for offset in 1...14 {
            let day = today.adding(days: -offset)
            try log.quickAdd(energyKcal: 2600, slot: .lunch, day: day)
            try log.setDay(day, status: .complete)
        }
        let targets = try #require(try service.targets(on: today))
        #expect(targets.ratePercentPerWeek == 0)
        #expect(abs(targets.kcal - targets.expenditureKcal) <= 5)
    }
}
