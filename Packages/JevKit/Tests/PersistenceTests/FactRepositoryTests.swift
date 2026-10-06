import Foundation
import GRDB
import JevCore
import JevDomain
import Testing
@testable import Persistence

/// Orologio controllabile dai test (le scritture leggono l'istante da `TimeSource`).
final class TestClock: TimeSource, @unchecked Sendable {
    // Accesso solo dal thread del test: i test di questo file non scrivono in parallelo.
    private var current: Date
    init(_ start: Date) { current = start }
    func now() -> Date { current }
    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
    func set(_ date: Date) { current = date }
}

enum Fixtures {
    static let start = Date(timeIntervalSince1970: 1_791_000_000) // 2026-10-03
    static let rome = "Europe/Rome"
    static let day = DayKey("2026-10-06")!

    static func profile(at date: Date = start) -> UserProfileRecord {
        UserProfileRecord(
            id: UUIDv7.make(at: date), birthYear: 1990, heightCm: 180,
            experience: .intermediate, activityLevel: .moderate,
            createdAt: date, updatedAt: date
        )
    }

    static func weight(_ kg: Double, hk: UUID? = nil, at date: Date = start) -> WeightEntryRecord {
        WeightEntryRecord(
            id: UUIDv7.make(at: date), measuredAt: date, dayKey: day, tz: rome, weightKg: kg,
            source: hk == nil ? .manual : .healthkit, hkUuid: hk,
            createdAt: date, updatedAt: date
        )
    }
}

@Suite("FactRepository — scritture, tombstone, letture")
struct FactRepositoryTests {
    let store: DataStore
    let clock: TestClock
    let repo: FactRepository

    init() throws {
        store = try DataStore.inMemory()
        clock = TestClock(Fixtures.start)
        repo = FactRepository(store: store, time: clock)
    }

    @Test("Il salvataggio imposta timestamp, dispositivo e stato pending; il record torna identico")
    func saveAndRoundTrip() throws {
        let saved = try repo.save(Fixtures.profile())
        #expect(saved.syncState == .pending)
        #expect(saved.originDeviceId == store.deviceID)
        #expect(saved.updatedAt == Fixtures.start)
        let loaded = try #require(try repo.fetch(UserProfileRecord.self, id: saved.id))
        #expect(loaded == saved)
        #expect(loaded.unitSystem == .metric)
        #expect(loaded.energyUnit == .kcal)
    }

    @Test("Enum, liste JSON, DayKey e UUID opzionali sopravvivono al database")
    func richTypesRoundTrip() throws {
        let prefs = TrainingPreferencesRecord(
            id: UUIDv7.make(at: Fixtures.start), daysPerWeek: 4, preferredWeekdays: [1, 3, 5, 6],
            sessionMinutes: 75, splitPreference: .upperLower, equipment: [.barbell, .dumbbell, .pullUpBar],
            musclePriority: [.sideDelts, .glutes], createdAt: Fixtures.start, updatedAt: Fixtures.start
        )
        let savedPrefs = try repo.save(prefs)
        #expect(try repo.fetch(TrainingPreferencesRecord.self, id: prefs.id) == savedPrefs)

        let hk = UUID()
        let weight = try repo.save(Fixtures.weight(81.4, hk: hk))
        let loaded = try #require(try repo.fetch(WeightEntryRecord.self, id: weight.id))
        #expect(loaded.dayKey == Fixtures.day)
        #expect(loaded.hkUuid == hk)
        #expect(loaded.source == .healthkit)

        // Il JSON nel database è leggibile anche fuori da Swift (sync, export).
        let rawEquipment = try store.writer.read { db in
            try String.fetchOne(db, sql: "SELECT equipment FROM training_preferences")
        }
        #expect(rawEquipment == #"["barbell","dumbbell","pull_up_bar"]"#)
        let rawDay = try store.writer.read { db in try String.fetchOne(db, sql: "SELECT day_key FROM weight_entry") }
        #expect(rawDay == "2026-10-06")
    }

    @Test("Un aggiornamento conserva createdAt e fa avanzare updatedAt anche se l'orologio torna indietro")
    func updateKeepsCreatedAtAndMonotonicUpdatedAt() throws {
        var profile = try repo.save(Fixtures.profile())
        clock.advance(-3600) // orologio spostato indietro di un'ora
        profile.heightCm = 181
        let updated = try repo.save(profile)
        #expect(updated.createdAt == Fixtures.start)
        #expect(updated.updatedAt > Fixtures.start)
        #expect(try repo.fetch(UserProfileRecord.self, id: profile.id)?.heightCm == 181)
    }

    @Test("La cancellazione è un tombstone: il record sparisce dalle letture ma resta per la sync")
    func tombstone() throws {
        let weight = try repo.save(Fixtures.weight(80))
        clock.advance(60)
        try repo.delete(WeightEntryRecord.self, id: weight.id)
        #expect(try repo.fetch(WeightEntryRecord.self, id: weight.id) == nil)
        #expect(try repo.fetchAll(WeightEntryRecord.self).isEmpty)
        let raw = try store.writer.read { db in try WeightEntryRecord.fetchOne(db, key: weight.id) }
        #expect(raw?.deletedAt != nil)
        #expect(raw?.syncState == .pending)

        // Idempotente, e un record cancellato non si modifica più (il tombstone vince).
        try repo.delete(WeightEntryRecord.self, id: weight.id)
        #expect(throws: FactRepositoryError.recordDeleted) { try repo.save(weight) }
        #expect(throws: FactRepositoryError.notFound) { try repo.delete(WeightEntryRecord.self, id: UUID()) }
    }

    @Test("Profilo, impostazioni e preferenze: un solo record vivo")
    func singletons() throws {
        let first = try repo.save(Fixtures.profile())
        #expect(throws: DatabaseError.self) { try repo.save(Fixtures.profile(at: Fixtures.start.addingTimeInterval(1))) }
        try repo.delete(UserProfileRecord.self, id: first.id)
        let second = try repo.save(Fixtures.profile(at: Fixtures.start.addingTimeInterval(2)))
        #expect(try repo.fetchSingleton(UserProfileRecord.self)?.id == second.id)
    }

    @Test("La stessa pesata di Salute non si importa due volte (hk_uuid unico)")
    func healthKitDedup() throws {
        let hk = UUID()
        try repo.save(Fixtures.weight(80, hk: hk))
        #expect(throws: DatabaseError.self) { try repo.save(Fixtures.weight(80, hk: hk, at: Fixtures.start.addingTimeInterval(1))) }
    }

    @Test("I vincoli di dominio rifiutano valori impossibili")
    func domainChecks() throws {
        #expect(throws: DatabaseError.self) { try repo.save(Fixtures.weight(10)) }
        var set = WorkoutSetRecord(
            id: UUID(), workoutExerciseId: UUID(), setIndex: 0, setType: .working,
            createdAt: Fixtures.start, updatedAt: Fixtures.start
        )
        set.reps = 500
        #expect(throws: DatabaseError.self) { try repo.save(set) }
    }

    @Test("Una sessione completa (sessione → esercizio → serie) si salva in una transazione")
    func workoutGraph() throws {
        let t = Fixtures.start
        let session = WorkoutSessionRecord(
            id: UUIDv7.make(at: t), startedAt: t, status: .inProgress, dayKey: Fixtures.day, tz: Fixtures.rome,
            createdAt: t, updatedAt: t
        )
        let exercise = WorkoutExerciseRecord(
            id: UUIDv7.make(at: t), sessionId: session.id, exerciseKey: "bench_press", position: 0,
            createdAt: t, updatedAt: t
        )
        let set = WorkoutSetRecord(
            id: UUIDv7.make(at: t), workoutExerciseId: exercise.id, setIndex: 0, setType: .working,
            weightKg: 100, enteredValue: 220.5, enteredUnit: .lb, reps: 5, rir: 2,
            createdAt: t, updatedAt: t
        )
        try store.writer.write { db in
            // Ordine "sbagliato" voluto: le FK sono differite al commit.
            try repo.save(set, in: db)
            try repo.save(exercise, in: db)
            try repo.save(session, in: db)
        }
        #expect(try repo.fetch(WorkoutSetRecord.self, id: set.id)?.enteredUnit == .lb)

        // Una serie che punta a un esercizio inesistente fa fallire la transazione.
        let orphan = WorkoutSetRecord(
            id: UUID(), workoutExerciseId: UUID(), setIndex: 1, setType: .working,
            createdAt: t, updatedAt: t
        )
        #expect(throws: DatabaseError.self) { try repo.save(orphan) }
        #expect(try repo.fetch(WorkoutSetRecord.self, id: orphan.id) == nil)

        // Un solo workout in corso alla volta (ripresa dopo la chiusura dell'app).
        let another = WorkoutSessionRecord(
            id: UUID(), startedAt: t, status: .inProgress, dayKey: Fixtures.day, tz: Fixtures.rome,
            createdAt: t, updatedAt: t
        )
        #expect(throws: DatabaseError.self) { try repo.save(another) }
    }

    @Test("Voce di diario quick add e voce con alimento")
    func foodLog() throws {
        let t = Fixtures.start
        let quick = FoodLogEntryRecord(
            id: UUID(), dayKey: Fixtures.day, tz: Fixtures.rome, mealSlot: .snack, loggedAt: t,
            foodSource: .quickAdd, energyKcal: 250, proteinG: 10, carbsG: 30, fatG: 9,
            createdAt: t, updatedAt: t
        )
        try repo.save(quick)
        var incomplete = quick
        incomplete.id = UUID()
        incomplete.foodSource = .openFoodFacts // un alimento richiede id, nome e grammi
        #expect(throws: DatabaseError.self) { try repo.save(incomplete) }
        incomplete.foodSourceId = "8001505005707"
        incomplete.foodName = "Biscotti"
        incomplete.grams = 40
        try repo.save(incomplete)
        #expect(try repo.fetchAll(FoodLogEntryRecord.self).count == 2)
    }
}
