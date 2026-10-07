import Foundation
import JevCore
import JevDomain
import Persistence
import RecoveryEngine
import Testing
@testable import Features

@Suite("Oggi, Corpo e Progressi dai dati (M10)")
struct DashboardServiceTests {
    let store: DataStore
    let dashboard: DashboardService
    let cache: HealthCacheStore
    let utc = TimeZone(identifier: "UTC")!

    init() throws {
        store = try DataStore.inMemory()
        let facts = FactRepository(store: store)
        cache = try HealthCacheStore.inMemory()
        let training = try #require(TrainingPlanService.bundled(facts: facts))
        dashboard = DashboardService(training: training, nutrition: NutritionPlanService(facts: facts), healthCache: cache)
    }

    private func onboard() throws {
        var draft = OnboardingDraft()
        draft.goal = .hypertrophy
        draft.experience = .intermediate
        draft.weightKg = 80
        draft.heightCm = 180
        draft.ageYears = 30
        draft.sex = .male
        draft.daysPerWeek = 3
        draft.equipment = [.barbell, .dumbbell, .bench, .cable, .machine]
        try OnboardingRepository(store: store).complete(draft, timeZone: utc)
    }

    /// Esegue la prossima sessione completando ogni serie a RIR 1.
    private func trainOnce() throws -> Set<MuscleGroup> {
        let id = try #require(try dashboard.training.startNextSession())
        let detail = try #require(try dashboard.training.workouts.detail(sessionID: id))
        var trained = Set<MuscleGroup>()
        for exercise in detail.exercises {
            if let key = exercise.exercise.exerciseKey, let item = dashboard.training.catalog[key] {
                trained.formUnion(item.primaryMuscles)
            }
            for set in exercise.sets {
                try dashboard.training.workouts.completeSet(setID: set.id, weightKg: 40, reps: 10, rir: 1)
            }
        }
        try dashboard.training.workouts.finish(sessionID: id)
        return trained
    }

    @Test("Senza dati: muscoli tutti recuperati, readiness con i soli componenti presenti")
    func empty() throws {
        let states = try dashboard.muscleStates()
        #expect(states.count == MuscleGroup.allCases.count)
        #expect(states.values.allSatisfy { $0.recoveryPercent == 100 })
        #expect(try dashboard.series(.weight, days: 28).isEmpty)
    }

    @Test("Dopo un allenamento: muscoli allenati affaticati, readiness valida solo con dati iPhone")
    func afterWorkout() throws {
        try onboard()
        let trained = try trainOnce()
        let states = try dashboard.muscleStates()
        #expect(!trained.isEmpty)
        #expect(trained.contains { (states[$0]?.recoveryPercent ?? 100) < 90 })
        #expect(states.values.contains { $0.hoursToReady > 0 })
        let readiness = try #require(try dashboard.readiness())
        #expect((0...100).contains(readiness.score))
        #expect(readiness.confidence < 1)
        #expect(readiness.missing.contains(.heartRateVariability))
        #expect(readiness.components.contains { $0.component == .consecutiveDays })
        let workouts = try dashboard.series(.workouts, days: 28)
        #expect(workouts.map(\.value).reduce(0, +) == 1)
        #expect((try dashboard.series(.volume, days: 28).first?.value ?? 0) > 0)
        #expect((try dashboard.series(.topE1RM, days: 28).first?.value ?? 0) > 40)
    }

    @Test("Serie di nutrizione, peso e Salute")
    func series() throws {
        try onboard()
        let log = dashboard.nutrition.log
        let today = DayKey(date: Date(), timeZone: .current)
        try log.quickAdd(energyKcal: 2200, proteinG: 150, slot: .lunch, day: today)
        #expect(try dashboard.series(.calories, days: 7).map(\.value) == [2200])
        #expect(try dashboard.series(.protein, days: 7).map(\.value) == [150])
        #expect(try dashboard.series(.weight, days: 7).count == 1)
        #expect(try dashboard.series(.weightTrend, days: 7).count == 1)
        try cache.upsert(HealthMetricDaily(dayKey: today, steps: 9000, sleepMinutes: 420, restingHr: 55, hrvSdnnMs: 60,
                                           updatedAt: Date()))
        #expect(try dashboard.series(.steps, days: 7).map(\.value) == [9000])
        #expect(try dashboard.series(.sleep, days: 7).map(\.value) == [7])
        #expect(try dashboard.series(.restingHeartRate, days: 7).map(\.value) == [55])
        #expect(try dashboard.series(.hrv, days: 7).map(\.value) == [60])
        #expect(try dashboard.series(.activeEnergy, days: 7).isEmpty)
        let readiness = try #require(try dashboard.readiness())
        #expect(readiness.components.contains { $0.component == .sleep })
    }
}
