import Foundation
import JevCore
import JevDomain
import Testing
@testable import Persistence

@Suite("Sessioni di allenamento: salvataggio immediato, ripresa, storico (M8)")
struct WorkoutRepositoryTests {
    let store: DataStore
    let repo: WorkoutRepository
    let utc = TimeZone(identifier: "UTC")!

    init() throws {
        store = try DataStore.inMemory()
        repo = WorkoutRepository(facts: FactRepository(store: store, time: FixedTimeSource(Fixtures.start)))
    }

    private var plan: [WorkoutRepository.PlannedExerciseInput] {
        let set = WorkoutRepository.PlannedSet(targetWeightKg: 100, targetReps: 8, restSeconds: 120)
        return [
            .init(exerciseKey: "barbell_bench_press", sets: [set, set, set]),
            .init(exerciseKey: "lateral_raise", sets: [WorkoutRepository.PlannedSet(targetWeightKg: 10, targetReps: 15)]),
        ]
    }

    @Test("Avvio: sessione, esercizi e serie pianificate in ordine; una sola sessione attiva")
    func start() throws {
        let id = try repo.startSession(exercises: plan, timeZone: utc)
        let detail = try #require(try repo.detail(sessionID: id))
        #expect(detail.session.status == .inProgress)
        #expect(detail.exercises.map(\.exercise.exerciseKey) == ["barbell_bench_press", "lateral_raise"])
        #expect(detail.exercises[0].sets.map(\.setIndex) == [0, 1, 2])
        #expect(detail.exercises[0].sets.allSatisfy { $0.targetWeightKg == 100 && $0.targetReps == 8 && $0.restS == 120 })
        #expect(try repo.activeSession()?.id == id)
        #expect(throws: WorkoutRepository.WorkoutError.sessionAlreadyActive) {
            try repo.startSession(exercises: plan, timeZone: utc)
        }
    }

    @Test("Ogni serie è salvata subito: un nuovo repository sullo stesso database riprende la sessione")
    func survivesRestart() throws {
        let id = try repo.startSession(exercises: plan, timeZone: utc)
        let first = try #require(try repo.detail(sessionID: id)?.exercises[0].sets[0])
        try repo.completeSet(setID: first.id, weightKg: 100, reps: 8, rir: 2, enteredUnit: .kg)
        // "Kill" dell'app: si riparte da un repository nuovo sullo stesso store.
        let reopened = WorkoutRepository(facts: FactRepository(store: store))
        let active = try #require(try reopened.activeSession())
        #expect(active.id == id)
        let set = try #require(try reopened.detail(sessionID: id)?.exercises[0].sets[0])
        #expect(set.completedAt != nil && set.weightKg == 100 && set.reps == 8 && set.rir == 2)
        #expect(set.enteredUnit == .kg && set.enteredValue == 100)
    }

    @Test("Valori fuori dai limiti rifiutati prima del database")
    func invalidValues() throws {
        let id = try repo.startSession(exercises: plan, timeZone: utc)
        let set = try #require(try repo.detail(sessionID: id)?.exercises[0].sets[0])
        #expect(throws: WorkoutRepository.WorkoutError.invalidValue) {
            try repo.completeSet(setID: set.id, weightKg: 2000, reps: 8, rir: 2)
        }
        #expect(throws: WorkoutRepository.WorkoutError.invalidValue) {
            try repo.completeSet(setID: set.id, weightKg: 100, reps: 500, rir: 2)
        }
        #expect(throws: WorkoutRepository.WorkoutError.invalidValue) {
            try repo.completeSet(setID: set.id, weightKg: 100, reps: 8, rir: -1)
        }
        #expect(throws: WorkoutRepository.WorkoutError.setNotFound) {
            try repo.completeSet(setID: UUID(), weightKg: 100, reps: 8, rir: 2)
        }
        // Libbre: valore inserito conservato, peso canonico in kg.
        let saved = try repo.completeSet(setID: set.id, weightKg: Mass.pounds(225).kilograms, reps: 5, rir: 1, enteredUnit: .lb)
        #expect(abs((saved.enteredValue ?? 0) - 225) < 1e-9)
    }

    @Test("Aggiunta ed eliminazione di serie; nessuna modifica dopo la chiusura")
    func addDeleteFinish() throws {
        let id = try repo.startSession(exercises: plan, timeZone: utc)
        let exercise = try #require(try repo.detail(sessionID: id)?.exercises[1])
        let added = try repo.addSet(exerciseID: exercise.id)
        #expect(added.setIndex == 1 && added.targetWeightKg == 10 && added.targetReps == 15)
        try repo.deleteSet(added.id)
        #expect(try repo.detail(sessionID: id)?.exercises[1].sets.count == 1)
        let set = exercise.sets[0]
        try repo.completeSet(setID: set.id, weightKg: 10, reps: 15, rir: 1)
        let finished = try repo.finish(sessionID: id)
        #expect(finished.status == .completed && finished.endedAt != nil)
        #expect(try repo.activeSession() == nil)
        #expect(throws: WorkoutRepository.WorkoutError.sessionNotActive) { try repo.addSet(exerciseID: exercise.id) }
        #expect(throws: WorkoutRepository.WorkoutError.sessionNotActive) { try repo.finish(sessionID: id) }
        #expect(try repo.history().map(\.id) == [id])
        #expect(try repo.completedSessionCount() == 1)
    }

    @Test("Senza serie eseguite la sessione è abbandonata e non entra nello storico")
    func abandoned() throws {
        let id = try repo.startSession(exercises: plan, timeZone: utc)
        #expect(try repo.finish(sessionID: id).status == .abandoned)
        let other = try repo.startSession(exercises: plan, timeZone: utc)
        try repo.abandon(sessionID: other)
        #expect(throws: WorkoutRepository.WorkoutError.sessionNotActive) { try repo.abandon(sessionID: other) }
        #expect(try repo.history().isEmpty)
    }

    @Test("Esposizioni passate di un esercizio: solo sessioni completate e serie eseguite, dalla più vecchia")
    func exposures() throws {
        for load in [100.0, 102.5] {
            let id = try repo.startSession(exercises: plan, timeZone: utc)
            let sets = try #require(try repo.detail(sessionID: id)?.exercises[0].sets)
            try repo.completeSet(setID: sets[0].id, weightKg: load, reps: 8, rir: 2)
            try repo.finish(sessionID: id)
        }
        let exposures = try repo.exposures(exerciseKey: "barbell_bench_press")
        #expect(exposures.count == 2)
        #expect(exposures.map { $0.sets.count } == [1, 1])
        #expect(Set(exposures.compactMap { $0.sets.first?.weightKg }) == [100, 102.5])
        #expect(try repo.exposures(exerciseKey: "lateral_raise").isEmpty)
    }
}
