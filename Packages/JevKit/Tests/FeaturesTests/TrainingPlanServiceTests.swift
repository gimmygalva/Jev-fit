import CheckInEngine
import ExerciseCatalog
import Foundation
import JevCore
import JevDomain
import Persistence
import Testing
import WorkoutEngine
@testable import Features

@Suite("Programma e overload collegati ai dati (M8)")
@MainActor
struct TrainingPlanServiceTests {
    let store: DataStore
    let facts: FactRepository
    let service: TrainingPlanService

    init() throws {
        store = try DataStore.inMemory()
        facts = FactRepository(store: store)
        service = try #require(TrainingPlanService.bundled(facts: facts))
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
        draft.sessionMinutes = 60
        draft.equipment = [.barbell, .dumbbell, .bench, .cable, .machine, .pullUpBar]
        try OnboardingRepository(store: store).complete(draft, timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test("Senza onboarding non c'è programma")
    func noProfile() throws {
        #expect(try service.profile() == nil)
        #expect(try service.nextSession() == nil)
        #expect(try service.startNextSession() == nil)
    }

    @Test("Dopo l'onboarding: profilo, prima sessione della rotazione, target senza storico")
    func firstSession() throws {
        try onboard()
        let profile = try #require(try service.profile())
        #expect(profile.goal == .hypertrophy && profile.daysPerWeek == 3)
        #expect(profile.equipment.contains(.bodyweight))
        let next = try #require(try service.nextSession())
        #expect(next.plan.index == 0)
        #expect(!next.exercises.isEmpty)
        #expect(next.exercises.allSatisfy { !$0.sets.isEmpty })
        // Nessuno storico: nessun carico inventato.
        #expect(next.exercises.allSatisfy { $0.sets.allSatisfy { $0.targetWeightKg == nil } })
    }

    @Test("Avvio, serie al massimo del range e chiusura: la volta dopo il carico sale (regola 2)")
    func overloadAcrossSessions() throws {
        try onboard()
        let first = try #require(try service.nextSession())
        let sessionID = try #require(try service.startNextSession())
        #expect(try service.startNextSession() == sessionID, "Una sessione già in corso viene ripresa")
        let detail = try #require(try service.workouts.detail(sessionID: sessionID))
        let target = try #require(detail.exercises.first { exercise in
            exercise.exercise.exerciseKey.flatMap { service.catalog[$0]?.loadType } == .external
        })
        let key = try #require(target.exercise.exerciseKey)
        let planned = try #require(first.plan.exercises.first { $0.exerciseID == key })
        for set in target.sets {
            try service.workouts.completeSet(setID: set.id, weightKg: 60, reps: planned.repRange.upperBound,
                                             rir: Double(planned.targetRIR))
        }
        try service.workouts.finish(sessionID: sessionID)
        let exercise = try #require(service.catalog[key])
        let decision = try service.prescription(for: exercise, planned: planned, isDeload: false, config: .current)
        #expect(decision.action == .increaseLoad && decision.rule == 2)
        #expect((decision.nextLoadKg ?? 0) > 60)
        #expect(decision.nextReps == planned.repRange.lowerBound)
        // La rotazione avanza.
        #expect(try service.nextSession()?.plan.index == 1)
    }

    @Test("Modello live: suggerimento dopo la prima serie, timer di recupero, riepilogo a fine sessione")
    func liveModel() throws {
        try onboard()
        let sessionID = try #require(try service.startNextSession())
        let model = WorkoutLiveModel(sessionID: sessionID, repository: service.workouts, catalog: service.catalog)
        #expect(model.isActive)
        let exercise = try #require(model.detail?.exercises.first { model.loadType($0) == .external })
        #expect(!model.exerciseName(exercise).isEmpty)
        model.complete(setID: exercise.sets[0].id, weightKg: 100, reps: 10, rir: 5)
        #expect(model.suggestedLoadKg[exercise.id] != nil, "RIR 5 contro target 2: carico da aumentare")
        #expect(model.restEndsAt != nil)
        model.complete(setID: exercise.sets[0].id, weightKg: 5000, reps: 10, rir: 2)
        #expect(model.lastError == .invalidValue)
        model.addSet(to: exercise.id)
        #expect(model.detail?.exercises.first { $0.id == exercise.id }?.sets.count == exercise.sets.count + 1)
        model.finish()
        #expect(model.summary != nil)
        #expect(!model.isActive)
        #expect((model.summary?.volumeKg ?? 0) == 1000)
    }

    private func saveCheckIn(_ decisions: [CheckInEvaluator.Decision], accepted: [String: Bool]) throws {
        let repository = CheckInRepository(facts: facts)
        let json = String(decoding: try JSONEncoder().encode(decisions), as: UTF8.self)
        let record = try repository.save(weekStart: DayKey(date: Date(), timeZone: .current).adding(days: -7),
                                         metricsJSON: "{}", decisionsJSON: json, engineVersion: 1)
        for (key, value) in accepted {
            try repository.respond(checkInID: record.id, decisionKey: key, accepted: value)
        }
    }

    @Test("Check-in: volume accettato applicato alle serie, rifiutato ignorato, deload forzato")
    func checkInAdjustments() throws {
        try onboard()
        let base = try #require(try service.nextSession())
        let increase = CheckInEvaluator.Decision(type: .increaseTrainingLoad, setsChangeFraction: 0.2, reasonCodes: [])
        try saveCheckIn([increase], accepted: [increase.key: false])
        #expect(try service.checkInAdjustment().setsFactor == 1)
        try saveCheckIn([increase], accepted: [increase.key: true])
        #expect(try service.checkInAdjustment().setsFactor == 1.2)
        let more = try #require(try service.nextSession())
        let expected = base.exercises.map { max(1, Int((Double($0.sets.count) * 1.2).rounded())) }
        #expect(more.exercises.map(\.sets.count) == expected)
        let deload = CheckInEvaluator.Decision(type: .deload, reasonCodes: [])
        try saveCheckIn([deload], accepted: [deload.key: true])
        #expect(try service.checkInAdjustment().deload)
        #expect(try service.nextSession()?.isDeload == true)
    }

    @Test("Esercizi esclusi dalle preferenze non entrano nel programma")
    func exclusions() throws {
        try onboard()
        let first = try #require(try service.nextSession()?.exercises.first?.exerciseKey)
        let now = Date()
        try facts.save(ExercisePreferenceRecord(id: UUIDv7.make(at: now), exerciseKey: first, kind: .excluded,
                                                createdAt: now, updatedAt: now))
        #expect(try service.profile()?.excludedExercises.contains(first) == true)
        #expect(try service.nextSession()?.exercises.contains { $0.exerciseKey == first } == false)
    }
}
