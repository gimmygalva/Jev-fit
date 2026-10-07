import Foundation
import GRDB
import JevCore
import JevDomain
import Testing
@testable import Persistence

@Suite("OnboardingRepository — bozza a ogni step e scrittura finale (UF-01)")
struct OnboardingRepositoryTests {
    let store: DataStore
    let repo: OnboardingRepository
    let rome = TimeZone(identifier: "Europe/Rome")!

    init() throws {
        store = try DataStore.inMemory()
        repo = OnboardingRepository(store: store, time: FixedTimeSource(Fixtures.start))
    }

    static func completeDraft() -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.goal = .fatLoss
        draft.experience = .intermediate
        draft.weightKg = 84.2
        draft.heightCm = 181
        draft.ageYears = 34
        draft.sex = .male
        draft.bodyFatPercent = 21
        draft.targetWeightKg = 78
        draft.targetRatePercentPerWeek = -3 // fuori limite: va riportato a -1,0
        draft.daysPerWeek = 4
        draft.preferredWeekdays = [5, 1, 3]
        draft.sessionMinutes = 75
        draft.equipment = [.barbell, .dumbbell, .bench]
        draft.splitPreference = .upperLower
        draft.limitations = [.init(area: .knee, severity: .mild, note: "  fastidio sulle scale  ")]
        draft.musclePriority = [.sideDelts]
        draft.macroMode = .assisted
        draft.checkInWeekday = 7
        return draft
    }

    @Test("Senza bozza né profilo l'onboarding non è completato")
    func initialState() throws {
        #expect(try repo.isCompleted() == false)
        #expect(try repo.loadDraft() == nil)
    }

    @Test("La bozza sopravvive alla riapertura del database, step compreso")
    func draftRoundTrip() throws {
        var draft = OnboardingDraft()
        draft.currentStep = "body"
        draft.goal = .hypertrophy
        draft.weightKg = 70.5
        try repo.saveDraft(draft)
        draft.experience = .beginner
        try repo.saveDraft(draft)

        let reopened = OnboardingRepository(store: try DataStore(writer: store.writer))
        #expect(try reopened.loadDraft() == draft)
        #expect(try reopened.isCompleted() == false)
    }

    @Test("Una bozza illeggibile o di un formato diverso viene ignorata")
    func invalidDraft() throws {
        try store.writer.write { db in
            try db.execute(sql: "INSERT INTO schema_meta (key, value) VALUES ('onboarding_draft', 'non è json')")
        }
        #expect(try repo.loadDraft() == nil)
        var old = OnboardingDraft()
        old.formatVersion = 0
        try repo.saveDraft(old)
        #expect(try repo.loadDraft() == nil)
    }

    @Test("Il completamento scrive tutti i record in una transazione e chiude la bozza")
    func complete() throws {
        try repo.saveDraft(Self.completeDraft())
        try repo.complete(Self.completeDraft(), timeZone: rome)

        #expect(try repo.isCompleted())
        #expect(try repo.loadDraft() == nil)
        let facts = FactRepository(store: store)
        let profile = try #require(try facts.fetchSingleton(UserProfileRecord.self))
        #expect(profile.birthYear == 2026 - 34)
        #expect(profile.heightCm == 181)
        #expect(profile.experience == .intermediate)
        #expect(profile.pregnancyOrLactation == nil, "Per il sesso maschile la domanda non si pone")

        let goal = try #require(try facts.fetchAll(GoalRecord.self).first)
        #expect(goal.type == .fatLoss)
        #expect(goal.targetRatePctWeek == -1.0)
        #expect(goal.targetWeightKg == 78)

        let settings = try #require(try facts.fetchSingleton(AppSettingsRecord.self))
        #expect(settings.macroMode == .assisted)
        #expect(settings.checkInWeekday == 7)

        let prefs = try #require(try facts.fetchSingleton(TrainingPreferencesRecord.self))
        #expect(prefs.preferredWeekdays == [1, 3, 5])
        #expect(prefs.equipment == [.barbell, .dumbbell, .bench])
        #expect(prefs.splitPreference == .upperLower)

        let limitation = try #require(try facts.fetchAll(LimitationRecord.self).first)
        #expect(limitation.bodyArea == .knee)
        #expect(limitation.note == "fastidio sulle scale")

        let weight = try #require(try facts.fetchAll(WeightEntryRecord.self).first)
        #expect(weight.weightKg == 84.2)
        #expect(weight.tz == "Europe/Rome")
        #expect(weight.source == .manual)
        #expect(try facts.fetchAll(BodyMeasurementRecord.self).first?.value == 21)

        // Tutto è in coda per la sync.
        #expect(try OutboxRepository(store: store).count() == 7)
    }

    @Test("Obiettivi senza variazione di peso non salvano un ritmo; nessuna attrezzatura → corpo libero")
    func defaults() throws {
        var draft = Self.completeDraft()
        draft.goal = .strength
        draft.equipment = []
        draft.limitations = []
        draft.bodyFatPercent = nil
        try repo.complete(draft, timeZone: rome)
        let facts = FactRepository(store: store)
        #expect(try facts.fetchAll(GoalRecord.self).first?.targetRatePctWeek == nil)
        #expect(try facts.fetchSingleton(TrainingPreferencesRecord.self)?.equipment == [.bodyweight])
        #expect(try facts.fetchAll(BodyMeasurementRecord.self).isEmpty)
    }

    @Test("Dati obbligatori mancanti: errore e nessun record scritto")
    func missingData() throws {
        var draft = Self.completeDraft()
        draft.heightCm = nil
        #expect(throws: OnboardingError.missing("height")) { try repo.complete(draft) }
        #expect(try repo.isCompleted() == false)
        #expect(try OutboxRepository(store: store).count() == 0)
    }

    @Test("Un obiettivo non consentito non viene salvato (gate di sicurezza)")
    func unsafeGoal() throws {
        var draft = Self.completeDraft()
        draft.ageYears = 17
        #expect(throws: OnboardingError.goalNotAllowed(.minorNoDeficit)) { try repo.complete(draft) }
        draft.ageYears = 30
        draft.sex = .female
        draft.pregnancyOrLactation = true
        #expect(throws: OnboardingError.goalNotAllowed(.pregnancyNoDeficit)) { try repo.complete(draft) }
        #expect(try repo.isCompleted() == false)
    }

    @Test("Un valore fuori dai vincoli del database annulla tutto il completamento")
    func constraintViolationRollsBack() throws {
        var draft = Self.completeDraft()
        draft.bodyFatPercent = 95 // CHECK: 2–70 %
        #expect(throws: DatabaseError.self) { try repo.complete(draft, timeZone: rome) }
        #expect(try repo.isCompleted() == false)
        #expect(try FactRepository(store: store).fetchAll(UserProfileRecord.self).isEmpty)
    }
}
