import JevDomain
import Persistence

/// Step dell'onboarding in ordine (UF-01, SCREEN_MAP §2).
///
/// Differenze dichiarate rispetto ai 17 step della spec, per M3:
/// - SCR-ONB-10 (esercizi preferiti/esclusi) arriva con il catalogo esercizi (M4);
/// - SCR-ONB-15/16 (permessi Salute e notifiche) arrivano con HealthKit (M7) e le notifiche;
/// - SCR-ONB-17 mostra il riepilogo delle scelte; calorie, macro e sessioni arrivano con
///   WorkoutEngine (M4) e NutritionEngine (M5).
public enum OnboardingStep: String, CaseIterable, Sendable {
    case welcome
    case goal
    case experience
    case body
    case activity
    case target
    case availability
    case equipment
    case split
    case limitations
    case priority
    case macro
    case units
    case summary

    /// Gli step con valori predefiniti si possono saltare (PS-ON-02).
    public var isSkippable: Bool {
        switch self {
        case .target, .split, .limitations, .priority, .macro, .units: true
        case .welcome, .goal, .experience, .body, .activity, .availability, .equipment, .summary: false
        }
    }

    /// Step visibili per la bozza corrente: il target compare solo per gli obiettivi che
    /// prevedono una variazione di peso (UF-01, decisione F).
    public static func sequence(for draft: OnboardingDraft) -> [OnboardingStep] {
        allCases.filter { step in
            step != .target || draft.goal.map { GoalSafety.rateLimits(for: $0) != nil } == true
        }
    }
}

/// Problemi che impediscono di proseguire da uno step. Il testo per l'utente lo sceglie la vista.
public enum OnboardingIssue: Equatable, Sendable {
    case missingSelection
    case invalidWeight
    case invalidHeight
    case invalidAge
    case invalidBodyFat
    /// Età sotto il minimo dell'app: non si procede.
    case appNotForMinors
    /// L'obiettivo scelto non è consentito con i dati inseriti: va cambiato.
    case goalBlocked(GoalSafety.BlockReason)
    case targetBelowHealthyWeight
    case targetIncoherent
}

/// Regole di validazione, pure e testabili.
public enum OnboardingRules {
    public static func person(_ draft: OnboardingDraft) -> GoalSafety.Person {
        GoalSafety.Person(
            ageYears: draft.ageYears,
            weightKg: draft.weightKg,
            heightCm: draft.heightCm,
            pregnancyOrLactation: draft.pregnancyOrLactation
        )
    }

    /// Problemi dello step, in ordine di importanza. Vuoto = si può proseguire.
    public static func issues(for step: OnboardingStep, in draft: OnboardingDraft, config: EngineConfig = .current) -> [OnboardingIssue] {
        let safety = config.safety
        switch step {
        case .welcome, .activity, .split, .limitations, .priority, .macro, .units, .equipment:
            return []
        case .goal:
            guard let goal = draft.goal else { return [.missingSelection] }
            if let reason = GoalSafety.block(for: goal, person: person(draft), config: config) {
                return [.goalBlocked(reason)]
            }
            return []
        case .experience:
            return draft.experience == nil ? [.missingSelection] : []
        case .body:
            var issues: [OnboardingIssue] = []
            if let age = draft.ageYears, GoalSafety.appUseBlock(ageYears: age, config: config) != nil {
                return [.appNotForMinors]
            }
            if !(draft.weightKg.map { safety.plausibleWeightKg.contains($0) } ?? false) { issues.append(.invalidWeight) }
            if !(draft.heightCm.map { safety.plausibleHeightCm.contains($0) } ?? false) { issues.append(.invalidHeight) }
            if !(draft.ageYears.map { $0 <= safety.maximumAgeYears } ?? false) { issues.append(.invalidAge) }
            if let bodyFat = draft.bodyFatPercent, !(2...70).contains(bodyFat) { issues.append(.invalidBodyFat) }
            if issues.isEmpty, let goal = draft.goal,
               let reason = GoalSafety.block(for: goal, person: person(draft), config: config) {
                issues.append(.goalBlocked(reason))
            }
            return issues
        case .target:
            guard let goal = draft.goal, let target = draft.targetWeightKg else { return [] }
            if let height = draft.heightCm, target < GoalSafety.minimumTargetWeightKg(heightCm: height, config: config) {
                return [.targetBelowHealthyWeight]
            }
            if let weight = draft.weightKg, !GoalSafety.isTargetCoherent(goal: goal, currentKg: weight, targetKg: target) {
                return [.targetIncoherent]
            }
            return []
        case .availability:
            return draft.daysPerWeek == nil ? [.missingSelection] : []
        case .summary:
            // Riepilogo: tutti gli step obbligatori devono essere validi.
            let required: [OnboardingStep] = [.goal, .experience, .body, .availability]
            return required.flatMap { issues(for: $0, in: draft, config: config) }
        }
    }
}
