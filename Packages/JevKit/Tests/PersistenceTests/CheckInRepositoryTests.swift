import Foundation
import JevCore
import JevDomain
import Testing
@testable import Persistence

@Suite("Check-in salvati e target accettati (M11)")
struct CheckInRepositoryTests {
    let repo: CheckInRepository
    let week = DayKey("2026-09-28")!

    init() throws {
        repo = CheckInRepository(facts: FactRepository(store: try DataStore.inMemory(), time: FixedTimeSource(Fixtures.start)))
    }

    @Test("Un check-in per settimana, aggiornato; risposte come JSON")
    func checkIns() throws {
        let first = try repo.save(weekStart: week, metricsJSON: #"{"a":1}"#, decisionsJSON: "[]", engineVersion: 1)
        let second = try repo.save(weekStart: week, metricsJSON: #"{"a":2}"#, decisionsJSON: #"[{"type":"keep"}]"#, engineVersion: 0)
        #expect(first.id == second.id && second.metrics == #"{"a":2}"# && second.engineVersion == 1)
        let answered = try repo.respond(checkInID: first.id, decisionKey: "increase_calories:", accepted: false)
        #expect(answered.responses == #"{"increase_calories:":false}"#)
        #expect(answered.completedAt != nil)
        #expect(try repo.checkIns().count == 1)
        #expect(throws: FactRepositoryError.notFound) { try repo.respond(checkInID: UUID(), decisionKey: "x", accepted: true) }
    }

    @Test("Target in vigore: l'ultimo con data di inizio non futura, limiti del database")
    func targets() throws {
        #expect(try repo.activeTarget(on: week) == nil)
        try repo.saveTarget(kcal: 2200, effectiveFrom: week, origin: .onboarding, engineVersion: 1)
        try repo.saveTarget(kcal: 2050.4, effectiveFrom: week.adding(days: 7), origin: .checkIn, engineVersion: 1)
        #expect(try repo.activeTarget(on: week.adding(days: 3))?.weeklyAvgKcal == 2200)
        #expect(try repo.activeTarget(on: week.adding(days: 7))?.weeklyAvgKcal == 2050)
        let tiny = try repo.saveTarget(kcal: 300, effectiveFrom: week.adding(days: 30), origin: .manual, engineVersion: 0)
        #expect(tiny.weeklyAvgKcal == 800 && tiny.engineVersion == 1)
    }
}
