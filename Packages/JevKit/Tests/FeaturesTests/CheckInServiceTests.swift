import CheckInEngine
import CoachKit
import Foundation
import JevCore
import JevDomain
import Persistence
import Testing
@testable import Features

@Suite("Weekly check-in end-to-end (M11)")
struct CheckInServiceTests {
    let store: DataStore
    let service: CheckInService
    let utc = TimeZone(identifier: "UTC")!

    init() throws {
        store = try DataStore.inMemory()
        let facts = FactRepository(store: store)
        let training = try #require(TrainingPlanService.bundled(facts: facts))
        let dashboard = DashboardService(training: training, nutrition: NutritionPlanService(facts: facts), healthCache: nil)
        service = CheckInService(dashboard: dashboard, coach: CoachService(provider: nil))
    }

    private var today: DayKey { DayKey(date: Date(), timeZone: utc) }

    private func prepareWeek() throws {
        var draft = OnboardingDraft()
        draft.goal = .fatLoss
        draft.experience = .intermediate
        draft.weightKg = 82
        draft.heightCm = 180
        draft.ageYears = 30
        draft.sex = .male
        draft.targetRatePercentPerWeek = -0.5
        draft.daysPerWeek = 3
        try OnboardingRepository(store: store).complete(draft, timeZone: utc)
        let log = service.dashboard.nutrition.log
        for offset in 1...10 {
            let day = today.adding(days: -offset)
            let date = Date().addingTimeInterval(-Double(offset) * 86_400)
            try log.addWeight(kilograms: 82 - 0.05 * Double(10 - offset), at: date, timeZone: utc)
            if offset <= 7 {
                try log.quickAdd(energyKcal: 2100, proteinG: 150, slot: .lunch, day: day, timeZone: utc)
                try log.setDay(day, status: .complete)
            }
        }
    }

    @Test("Senza profilo nessun check-in")
    func noProfile() async throws {
        #expect(try await service.run(on: today) == nil)
    }

    @Test("Settimana completa: metriche, decisioni, spiegazione di JEV con fatti, snapshot salvato")
    func fullWeek() async throws {
        try prepareWeek()
        let metrics = try #require(try service.metrics(before: today))
        #expect(metrics.completeLoggedDays == 7)
        #expect(metrics.weighIns == 7)
        #expect(metrics.averageIntakeKcal == 2100)
        #expect(metrics.goal == .fatLoss)
        let report = try #require(try await service.run(on: today))
        #expect(!report.result.decisions.isEmpty)
        #expect(!report.result.decisions.contains { $0.type == .noAction && $0.type.area == .nutrition })
        #expect(report.message.source == "template")
        #expect(!report.message.headline.isEmpty)
        #expect(report.message.why.allSatisfy { !$0.contains("{{") })
        #expect(try service.repository.checkIns().count == 1)
        // Un secondo avvio nella stessa settimana aggiorna lo stesso snapshot.
        let again = try #require(try await service.run(on: today))
        #expect(again.checkInID == report.checkInID)
    }

    @Test("Aumento accettato: diventa il target in vigore")
    func accept() async throws {
        try prepareWeek()
        try service.repository.saveTarget(kcal: 1800, effectiveFrom: today.adding(days: -14), origin: .onboarding,
                                          engineVersion: 1)
        let report = try #require(try await service.run(on: today))
        let increase = try #require(report.result.decisions.first { $0.type == .increaseCalories })
        #expect(increase.deltaKcal == 150)
        try service.respond(to: increase, in: report, accepted: true, day: today)
        #expect(try service.dashboard.nutrition.targets(on: today)?.kcal == 1950)
        #expect(try service.repository.activeTarget(on: today)?.origin == .checkIn)
    }

    @Test("Aumento rifiutato: non riproposto finché i dati non cambiano")
    func reject() async throws {
        try prepareWeek()
        try service.repository.saveTarget(kcal: 1800, effectiveFrom: today.adding(days: -14), origin: .onboarding,
                                          engineVersion: 1)
        let report = try #require(try await service.run(on: today))
        let increase = try #require(report.result.decisions.first { $0.type == .increaseCalories })
        try service.respond(to: increase, in: report, accepted: false, day: today)
        #expect(try service.dashboard.nutrition.targets(on: today)?.kcal == 1800)
        let again = try #require(try await service.run(on: today))
        #expect(!again.result.decisions.contains { $0.type == .increaseCalories })
        #expect(again.result.suppressed == ["increase_calories:"])
    }
}
