import Foundation
import JevCore
import JevDomain
import Observation
import Persistence
import WorkoutEngine

/// Stato e azioni dell'onboarding (ADR-002: ViewModel solo dove c'è logica di schermata).
///
/// Ogni cambio di step salva la bozza (PS-ON-01: chiudendo l'app si riparte dallo stesso step
/// con i valori inseriti). Il completamento scrive i record con `OnboardingRepository`.
@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var step: OnboardingStep
    public var draft: OnboardingDraft
    /// Errore di salvataggio da mostrare all'utente (codice, non messaggio tecnico).
    public private(set) var saveFailed = false

    // Campi di testo (dati corpo e peso obiettivo), legati direttamente ai TextField.
    // I valori numerici della bozza si ricavano da qui in `current`: una sola fonte di verità.
    public var weightText: String
    public var heightText: String
    public var ageText: String
    public var bodyFatText: String
    public var targetWeightText: String

    private let repository: OnboardingRepository?
    private let onFinished: @MainActor () -> Void

    /// - Parameters:
    ///   - repository: `nil` nelle anteprime: niente salvataggi.
    ///   - onFinished: chiamato dopo il completamento riuscito.
    public init(repository: OnboardingRepository?, onFinished: @escaping @MainActor () -> Void = {}) {
        self.repository = repository
        self.onFinished = onFinished
        let saved = (try? repository?.loadDraft()) ?? nil
        let draft = saved ?? OnboardingDraft()
        self.draft = draft
        let unit: MassUnit = draft.unitSystem == .imperial ? .pounds : .kilograms
        self.weightText = Self.format(draft.weightKg.map { Mass(kilograms: $0).value(in: unit) })
        self.heightText = Self.format(draft.heightCm)
        self.ageText = draft.ageYears.map { String($0) } ?? ""
        self.bodyFatText = Self.format(draft.bodyFatPercent)
        self.targetWeightText = Self.format(draft.targetWeightKg.map { Mass(kilograms: $0).value(in: unit) })
        let restored = draft.currentStep.flatMap(OnboardingStep.init(rawValue:)) ?? .welcome
        self.step = OnboardingStep.sequence(for: draft).contains(restored) ? restored : .welcome
    }

    // MARK: Stato derivato

    /// La bozza con i valori numerici letti dai campi di testo.
    public var current: OnboardingDraft {
        var merged = draft
        merged.weightKg = Self.weightKg(from: weightText, unit: massUnit)
        merged.heightCm = Self.parseDecimal(heightText)
        merged.ageYears = Int(ageText.trimmingCharacters(in: .whitespaces))
        merged.bodyFatPercent = Self.parseDecimal(bodyFatText)
        merged.targetWeightKg = Self.weightKg(from: targetWeightText, unit: massUnit)
        return merged
    }

    public var sequence: [OnboardingStep] { OnboardingStep.sequence(for: current) }
    public var stepIndex: Int { sequence.firstIndex(of: step) ?? 0 }
    public var issues: [OnboardingIssue] { OnboardingRules.issues(for: step, in: current) }
    public var canContinue: Bool { issues.isEmpty }
    public var canGoBack: Bool { stepIndex > 0 }

    public var massUnit: MassUnit { draft.unitSystem == .imperial ? .pounds : .kilograms }

    /// Unità di peso per i picker: cambiarla riscrive i campi nella nuova unità.
    public var massUnitSelection: MassUnit {
        get { massUnit }
        set { setMassUnit(newValue) }
    }

    /// Ritmo in % del peso a settimana per lo slider, arrotondato a 0,05 e nei limiti.
    public var ratePercentSelection: Double {
        get {
            guard let goal = draft.goal, let limits = GoalSafety.rateLimits(for: goal) else { return 0 }
            return draft.targetRatePercentPerWeek ?? limits.defaultValue
        }
        set {
            guard let goal = draft.goal else { return }
            draft.targetRatePercentPerWeek = GoalSafety.clampRate((newValue * 20).rounded() / 20, for: goal)
        }
    }

    /// Obiettivi selezionabili con i dati noti finora.
    public var allowedGoals: [GoalType] { GoalSafety.allowedGoals(for: OnboardingRules.person(current)) }

    public var splitSuggestion: SplitSuggestionPreview? {
        guard let days = draft.daysPerWeek else { return nil }
        return SplitSuggestionPreview(daysPerWeek: days, preferred: draft.splitPreference)
    }

    // MARK: Azioni

    public func next() {
        guard canContinue else { return }
        if step == .summary {
            finish()
            return
        }
        move(by: 1)
    }

    public func skip() {
        guard step.isSkippable else { return }
        move(by: 1)
    }

    public func back() {
        move(by: -1)
    }

    /// Dallo step "Dati corpo", quando l'obiettivo non è più consentito.
    public func changeGoal() {
        go(to: .goal)
    }

    public func selectGoal(_ goal: GoalType) {
        draft.goal = goal
        if let limits = GoalSafety.rateLimits(for: goal) {
            draft.targetRatePercentPerWeek = GoalSafety.clampRate(draft.targetRatePercentPerWeek ?? limits.defaultValue, for: goal)
        } else {
            draft.targetRatePercentPerWeek = nil
            targetWeightText = ""
        }
    }

    /// Cambia l'unità del peso e riscrive i campi nella nuova unità.
    public func setMassUnit(_ unit: MassUnit) {
        let weight = current.weightKg
        let target = current.targetWeightKg
        draft.unitSystem = unit == .pounds ? .imperial : .metric
        weightText = Self.format(weight.map { Mass(kilograms: $0).value(in: unit) })
        targetWeightText = Self.format(target.map { Mass(kilograms: $0).value(in: unit) })
    }

    public func toggleWeekday(_ day: Int) {
        if let index = draft.preferredWeekdays.firstIndex(of: day) {
            draft.preferredWeekdays.remove(at: index)
        } else {
            draft.preferredWeekdays.append(day)
        }
    }

    public func toggleEquipment(_ item: Equipment) {
        if let index = draft.equipment.firstIndex(of: item) {
            draft.equipment.remove(at: index)
        } else {
            draft.equipment.append(item)
        }
    }

    public func applyEquipmentPreset(_ preset: EquipmentPreset) {
        draft.equipment = preset.equipment
    }

    /// Priorità muscolari: al massimo 3 (PS-ON-09).
    public func togglePriority(_ muscle: MuscleGroup) {
        if let index = draft.musclePriority.firstIndex(of: muscle) {
            draft.musclePriority.remove(at: index)
        } else if draft.musclePriority.count < 3 {
            draft.musclePriority.append(muscle)
        }
    }

    public func toggleLimitation(_ area: BodyArea) {
        if let index = draft.limitations.firstIndex(where: { $0.area == area }) {
            draft.limitations.remove(at: index)
        } else {
            draft.limitations.append(.init(area: area, severity: .mild))
        }
    }

    public func setSeverity(_ severity: LimitationSeverity, for area: BodyArea) {
        guard let index = draft.limitations.firstIndex(where: { $0.area == area }) else { return }
        draft.limitations[index].severity = severity
    }

    // MARK: Interni

    private func move(by offset: Int) {
        let steps = sequence
        let index = (steps.firstIndex(of: step) ?? 0) + offset
        guard steps.indices.contains(index) else { return }
        go(to: steps[index])
    }

    private func go(to target: OnboardingStep) {
        draft = current
        step = target
        draft.currentStep = target.rawValue
        persist()
    }

    private func persist() {
        guard let repository else { return }
        do {
            try repository.saveDraft(draft)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    private func finish() {
        guard let repository else {
            onFinished()
            return
        }
        do {
            try repository.complete(current)
            saveFailed = false
            onFinished()
        } catch {
            saveFailed = true
        }
    }

    // MARK: Parsing

    /// Accetta virgola o punto come separatore decimale (tastiera italiana o inglese).
    static func parseDecimal(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    static func weightKg(from text: String, unit: MassUnit) -> Double? {
        parseDecimal(text).map { (Mass(value: $0, unit: unit).kilograms * 100).rounded() / 100 }
    }

    static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded).replacingOccurrences(of: ".", with: ",")
    }
}

/// Anteprima dello split con il motivo (PS-ON-07), dal WorkoutEngine.
public struct SplitSuggestionPreview: Equatable, Sendable {
    public let split: SplitType
    public let usesPreference: Bool
    public let preferenceIncompatible: Bool

    init(daysPerWeek: Int, preferred: SplitType?) {
        let result = SplitSuggestion.suggest(daysPerWeek: daysPerWeek, preferred: preferred)
        self.split = result.split
        self.usesPreference = result.reason == .userPreference
        self.preferenceIncompatible = result.reason == .preferenceIncompatible
    }
}

/// Preset di attrezzatura (PS-ON-06): ognuno precompila una checklist modificabile.
public enum EquipmentPreset: String, CaseIterable, Sendable {
    case fullGym = "full_gym"
    case homeGym = "home_gym"
    case dumbbellsOnly = "dumbbells_only"
    case bodyweight

    public var equipment: [Equipment] {
        switch self {
        case .fullGym: Equipment.allCases
        case .homeGym: [.barbell, .dumbbell, .bench, .pullUpBar, .resistanceBand, .bodyweight]
        case .dumbbellsOnly: [.dumbbell, .bench, .bodyweight]
        case .bodyweight: [.bodyweight, .pullUpBar]
        }
    }
}
