import Foundation
import JevCore
import JevDomain
import Persistence
import Testing
@testable import Features

@Suite("Onboarding — regole, navigazione tra step, bozza e completamento")
@MainActor
struct OnboardingModelTests {
    let store: DataStore
    let repository: OnboardingRepository

    init() throws {
        store = try DataStore.inMemory()
        repository = OnboardingRepository(store: store)
    }

    /// Porta il modello fino al riepilogo con le risposte minime obbligatorie.
    private func fillRequired(_ model: OnboardingModel, goal: GoalType = .hypertrophy) {
        model.next() // welcome → goal
        model.selectGoal(goal)
        model.next()
        model.draft.experience = .intermediate
        model.next()
        model.weightText = "80,5"
        model.heightText = "180"
        model.ageText = "30"
        model.next() // body → activity
        model.next() // activity → target o availability
        if model.step == .target { model.next() }
        model.draft.daysPerWeek = 4
        model.next() // availability → equipment
        model.applyEquipmentPreset(.homeGym)
        model.next() // equipment → split
        while model.step != .summary { model.skip() }
    }

    @Test("Si parte dal benvenuto e lo step target compare solo con variazione di peso")
    func sequence() {
        let model = OnboardingModel(repository: nil)
        #expect(model.step == .welcome)
        #expect(!model.canGoBack)
        #expect(!model.sequence.contains(.target))
        model.selectGoal(.fatLoss)
        #expect(model.sequence.contains(.target))
        model.selectGoal(.strength)
        #expect(!model.sequence.contains(.target))
        #expect(model.draft.targetRatePercentPerWeek == nil)
    }

    @Test("Gli step obbligatori non si superano senza risposta")
    func requiredSteps() {
        let model = OnboardingModel(repository: nil)
        model.next()
        #expect(model.step == .goal)
        #expect(!model.canContinue)
        model.next()
        #expect(model.step == .goal, "Senza obiettivo non si prosegue")
        model.skip()
        #expect(model.step == .goal, "Uno step obbligatorio non si salta")
    }

    @Test("Dati corpo: peso con la virgola, libbre convertite, valori impossibili segnalati")
    func bodyData() {
        let model = OnboardingModel(repository: nil)
        model.weightText = "82,5"
        #expect(model.current.weightKg == 82.5)
        model.setMassUnit(.pounds)
        #expect(model.weightText == "181,9")
        #expect(abs((model.current.weightKg ?? 0) - 82.5) < 0.05)
        model.setMassUnit(.kilograms)
        #expect(model.weightText == "82,5")

        model.draft.goal = .maintenance
        model.heightText = "500"
        model.ageText = "30"
        #expect(OnboardingRules.issues(for: .body, in: model.current).contains(.invalidHeight))
        model.ageText = "15"
        #expect(OnboardingRules.issues(for: .body, in: model.current) == [.appNotForMinors])
    }

    @Test("Un obiettivo non più consentito dai dati corpo blocca lo step e propone di cambiarlo")
    func goalBlockedByBodyData() {
        let model = OnboardingModel(repository: nil)
        model.selectGoal(.fatLoss)
        model.weightText = "70"
        model.heightText = "175"
        model.ageText = "17"
        #expect(OnboardingRules.issues(for: .body, in: model.current) == [.goalBlocked(.minorNoDeficit)])
        #expect(!model.allowedGoals.contains(.fatLoss))
        model.changeGoal()
        #expect(model.step == .goal)
    }

    @Test("Peso obiettivo: sotto la soglia di peso sano o nella direzione sbagliata è segnalato")
    func targetWeight() {
        let model = OnboardingModel(repository: nil)
        model.selectGoal(.fatLoss)
        model.weightText = "80"
        model.heightText = "180"
        model.targetWeightText = "55"
        #expect(OnboardingRules.issues(for: .target, in: model.current) == [.targetBelowHealthyWeight])
        model.targetWeightText = "85"
        #expect(OnboardingRules.issues(for: .target, in: model.current) == [.targetIncoherent])
        model.targetWeightText = "75"
        #expect(OnboardingRules.issues(for: .target, in: model.current).isEmpty)
        model.ratePercentSelection = -5
        #expect(model.draft.targetRatePercentPerWeek == -1.0)
        model.ratePercentSelection = -0.63
        #expect(model.draft.targetRatePercentPerWeek == -0.65)
    }

    @Test("Scelte multiple: priorità al massimo 3, limitazioni con intensità")
    func multipleChoices() {
        let model = OnboardingModel(repository: nil)
        for muscle in [MuscleGroup.chest, .lats, .glutes, .calves] { model.togglePriority(muscle) }
        #expect(model.draft.musclePriority == [.chest, .lats, .glutes])
        model.togglePriority(.lats)
        #expect(model.draft.musclePriority == [.chest, .glutes])

        model.toggleLimitation(.knee)
        model.setSeverity(.moderate, for: .knee)
        #expect(model.draft.limitations == [.init(area: .knee, severity: .moderate)])
        model.toggleLimitation(.knee)
        #expect(model.draft.limitations.isEmpty)

        model.toggleWeekday(3)
        model.toggleWeekday(1)
        model.toggleWeekday(3)
        #expect(model.draft.preferredWeekdays == [1])
        model.toggleEquipment(.kettlebell)
        #expect(model.draft.equipment == [.kettlebell])
    }

    @Test("Lo split consigliato segue i giorni e la preferenza compatibile")
    func splitPreview() {
        let model = OnboardingModel(repository: nil)
        #expect(model.splitSuggestion == nil)
        model.draft.daysPerWeek = 4
        #expect(model.splitSuggestion?.split == .upperLower)
        model.draft.splitPreference = .hybrid
        #expect(model.splitSuggestion?.preferenceIncompatible == true)
    }

    @Test("Chiudendo l'app a metà si riparte dallo stesso step con i valori inseriti")
    func resumeFromDraft() {
        let first = OnboardingModel(repository: repository)
        first.next()
        first.selectGoal(.hypertrophy)
        first.next()
        first.draft.experience = .advanced
        first.next()
        first.weightText = "77"
        first.back() // salva anche tornando indietro
        first.next()

        let reopened = OnboardingModel(repository: repository)
        #expect(reopened.step == .body)
        #expect(reopened.draft.goal == .hypertrophy)
        #expect(reopened.draft.experience == .advanced)
        #expect(reopened.weightText == "77")
    }

    @Test("Il percorso completo salva i record e chiama la chiusura")
    func completeFlow() throws {
        var finished = false
        let model = OnboardingModel(repository: repository) { finished = true }
        fillRequired(model)
        #expect(model.step == .summary)
        #expect(model.canContinue)
        model.next()
        #expect(finished)
        #expect(try repository.isCompleted())
        let profile = try FactRepository(store: store).fetchSingleton(UserProfileRecord.self)
        #expect(profile?.heightCm == 180)
        #expect(try FactRepository(store: store).fetchAll(WeightEntryRecord.self).first?.weightKg == 80.5)
    }

    @Test("Senza repository (anteprime) il completamento chiama comunque la chiusura")
    func previewCompletion() {
        var finished = false
        let model = OnboardingModel(repository: nil) { finished = true }
        fillRequired(model, goal: .maintenance)
        model.next()
        #expect(finished)
    }

    @Test("Parsing e formattazione dei numeri")
    func numbers() {
        #expect(OnboardingModel.parseDecimal(" 72,5 ") == 72.5)
        #expect(OnboardingModel.parseDecimal("72.5") == 72.5)
        #expect(OnboardingModel.parseDecimal("") == nil)
        #expect(OnboardingModel.parseDecimal("abc") == nil)
        #expect(OnboardingModel.format(nil) == "")
        #expect(OnboardingModel.format(80) == "80")
        #expect(OnboardingModel.format(80.04) == "80")
        #expect(OnboardingModel.format(80.25) == "80,3")
    }
}
