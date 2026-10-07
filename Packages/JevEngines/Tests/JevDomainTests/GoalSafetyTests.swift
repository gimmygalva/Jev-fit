import Foundation
import Testing
@testable import JevDomain

@Suite("GoalSafety — gate sull'obiettivo e ritmo (QA-14, PS-ON-03/05)")
struct GoalSafetyTests {
    let adult = GoalSafety.Person(ageYears: 30, weightKg: 80, heightCm: 180)

    @Test("Un adulto normopeso può scegliere qualsiasi obiettivo")
    func adultAllGoals() {
        #expect(GoalSafety.allowedGoals(for: adult) == GoalType.allCases)
        #expect(GoalSafety.block(for: .fatLoss, person: adult) == nil)
    }

    @Test("Sotto i 16 anni l'app non procede, con qualsiasi obiettivo")
    func belowMinimumAge() {
        let kid = GoalSafety.Person(ageYears: 15)
        #expect(GoalSafety.appUseBlock(ageYears: 15) == .belowMinimumAppAge)
        #expect(GoalSafety.appUseBlock(ageYears: 16) == nil)
        #expect(GoalSafety.appUseBlock(ageYears: nil) == nil)
        for goal in GoalType.allCases {
            #expect(GoalSafety.block(for: goal, person: kid) == .belowMinimumAppAge)
        }
        #expect(GoalSafety.allowedGoals(for: kid).isEmpty)
    }

    @Test("Minorenni: nessun deficit, gli altri obiettivi restano")
    func minor() {
        let minor = GoalSafety.Person(ageYears: 17, weightKg: 70, heightCm: 175)
        #expect(GoalSafety.block(for: .fatLoss, person: minor) == .minorNoDeficit)
        #expect(GoalSafety.block(for: .hypertrophy, person: minor) == nil)
        #expect(!GoalSafety.allowedGoals(for: minor).contains(.fatLoss))
        #expect(GoalSafety.block(for: .fatLoss, person: .init(ageYears: 18, weightKg: 70, heightCm: 175)) == nil)
    }

    @Test("Gravidanza o allattamento: nessun deficit")
    func pregnancy() {
        var person = adult
        person.pregnancyOrLactation = true
        #expect(GoalSafety.block(for: .fatLoss, person: person) == .pregnancyNoDeficit)
        #expect(GoalSafety.block(for: .maintenance, person: person) == nil)
    }

    @Test("BMI sotto 18,5: niente dimagrimento")
    func underweight() {
        let thin = GoalSafety.Person(ageYears: 30, weightKg: 55, heightCm: 180) // BMI ≈ 17,0
        #expect(GoalSafety.block(for: .fatLoss, person: thin) == .underweightNoLoss)
        #expect(GoalSafety.block(for: .hypertrophy, person: thin) == nil)
    }

    @Test("I dati mancanti non bloccano: il controllo si ripete quando arrivano")
    func missingData() {
        #expect(GoalSafety.block(for: .fatLoss, person: .init()) == nil)
        #expect(GoalSafety.block(for: .fatLoss, person: .init(weightKg: 55)) == nil)
    }

    @Test("Solo il dimagrimento richiede un deficit")
    func deficitGoals() {
        #expect(GoalType.allCases.filter(GoalSafety.requiresDeficit) == [.fatLoss])
    }

    @Test("BMI e peso minimo selezionabile")
    func bmi() throws {
        let value = try #require(GoalSafety.bmi(weightKg: 80, heightCm: 200))
        #expect(abs(value - 20) < 1e-9)
        #expect(GoalSafety.bmi(weightKg: nil, heightCm: 180) == nil)
        #expect(GoalSafety.bmi(weightKg: 80, heightCm: 0) == nil)
        #expect(GoalSafety.bmi(weightKg: .nan, heightCm: 180) == nil)
        #expect(abs(GoalSafety.minimumTargetWeightKg(heightCm: 200) - 74) < 1e-9)
    }

    @Test("Limiti del ritmo: perdita 0,25–1,0%, aumento 0,1–0,5%, default 0,5 e 0,25")
    func rateLimits() throws {
        let loss = try #require(GoalSafety.rateLimits(for: .fatLoss))
        #expect(loss.range == -1.0 ... -0.25)
        #expect(loss.defaultValue == -0.5)
        let gain = try #require(GoalSafety.rateLimits(for: .hypertrophy))
        #expect(gain.range == 0.1...0.5)
        #expect(gain.defaultValue == 0.25)
        for goal in [GoalType.strength, .maintenance, .recomposition, .generalFitness] {
            #expect(GoalSafety.rateLimits(for: goal) == nil)
        }
    }

    @Test("Il ritmo viene riportato nei limiti")
    func clampRate() {
        #expect(GoalSafety.clampRate(-3, for: .fatLoss) == -1.0)
        #expect(GoalSafety.clampRate(0, for: .fatLoss) == -0.25)
        #expect(GoalSafety.clampRate(-0.6, for: .fatLoss) == -0.6)
        #expect(GoalSafety.clampRate(.nan, for: .fatLoss) == -0.5)
        #expect(GoalSafety.clampRate(2, for: .hypertrophy) == 0.5)
        #expect(GoalSafety.clampRate(-1, for: .maintenance) == 0)
    }

    @Test("Ritmo aggressivo oltre 0,75% di perdita a settimana")
    func aggressive() {
        #expect(GoalSafety.isAggressiveLoss(-0.8))
        #expect(!GoalSafety.isAggressiveLoss(-0.75))
        #expect(!GoalSafety.isAggressiveLoss(0.5))
    }

    @Test("Settimane per arrivare all'obiettivo")
    func weeksToTarget() throws {
        // 80 kg, -0,5%/sett = -0,4 kg/sett, 4 kg da perdere → 10 settimane.
        let weeks = try #require(GoalSafety.weeksToTarget(currentKg: 80, targetKg: 76, ratePercentPerWeek: -0.5))
        #expect(abs(weeks - 10) < 1e-9)
        #expect(GoalSafety.weeksToTarget(currentKg: 80, targetKg: 80, ratePercentPerWeek: -0.5) == 0)
        #expect(GoalSafety.weeksToTarget(currentKg: 80, targetKg: 84, ratePercentPerWeek: -0.5) == nil)
        #expect(GoalSafety.weeksToTarget(currentKg: 80, targetKg: 76, ratePercentPerWeek: 0) == nil)
        #expect(GoalSafety.weeksToTarget(currentKg: 0, targetKg: 76, ratePercentPerWeek: -0.5) == nil)
        #expect(GoalSafety.weeksToTarget(currentKg: 80, targetKg: .infinity, ratePercentPerWeek: -0.5) == nil)
    }

    @Test("Coerenza del peso obiettivo con l'obiettivo")
    func coherence() {
        #expect(GoalSafety.isTargetCoherent(goal: .fatLoss, currentKg: 80, targetKg: 75))
        #expect(!GoalSafety.isTargetCoherent(goal: .fatLoss, currentKg: 80, targetKg: 85))
        #expect(GoalSafety.isTargetCoherent(goal: .hypertrophy, currentKg: 80, targetKg: 85))
        #expect(!GoalSafety.isTargetCoherent(goal: .hypertrophy, currentKg: 80, targetKg: 75))
        #expect(GoalSafety.isTargetCoherent(goal: .maintenance, currentKg: 80, targetKg: 60))
    }

    @Test("Le soglie di sicurezza sono coerenti con il database e con la spec")
    func safetyConfig() {
        let s = EngineConfig.v1.safety
        #expect(s.minimumAppAgeYears == 16)
        #expect(s.minimumDeficitAgeYears == 18)
        #expect(s.minimumAppAgeYears < s.minimumDeficitAgeYears)
        #expect(s.minimumDeficitAgeYears < s.maximumAgeYears)
        #expect(s.plausibleWeightKg == 20...400)
        #expect(s.plausibleHeightCm == 100...250)
        #expect(EngineConfig.v1.nutrition.minLossPercentPerWeek < s.aggressiveLossPercentPerWeek)
        #expect(s.aggressiveLossPercentPerWeek < EngineConfig.v1.nutrition.maxLossPercentPerWeek)
    }
}
