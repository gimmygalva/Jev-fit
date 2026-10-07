import Foundation
import JevDomain
import NutritionEngine
import Persistence

/// Numeri del riepilogo dell'onboarding (SCR-ONB-17): target calorico e macro iniziali dal
/// NutritionEngine con il prior dell'expenditure (nessuno storico ancora). `nil` se mancano dati.
enum OnboardingPlanPreview {
    struct Numbers: Equatable {
        var kcal: Double
        var proteinG: Double
        var carbsG: Double
        var fatG: Double
        var floorApplied: Bool
    }

    static func numbers(_ draft: OnboardingDraft, config: EngineConfig = .current) -> Numbers? {
        guard let goal = draft.goal, let weight = draft.weightKg, let height = draft.heightCm, let age = draft.ageYears else {
            return nil
        }
        let bmr = EnergyModel.bmr(weightKg: weight, heightCm: height, ageYears: age, sex: draft.sex,
                                  bodyFatPercent: draft.bodyFatPercent, config: config)
        let prior = EnergyModel.priorExpenditure(weightKg: weight, heightCm: height, ageYears: age, sex: draft.sex,
                                                 bodyFatPercent: draft.bodyFatPercent, activity: draft.activityLevel,
                                                 config: config)
        let person = GoalSafety.Person(ageYears: age, weightKg: weight, heightCm: height,
                                       pregnancyOrLactation: draft.pregnancyOrLactation)
        let rate = draft.targetRatePercentPerWeek ?? GoalSafety.rateLimits(for: goal, config: config)?.defaultValue ?? 0
        let target = CalorieTargets.dailyTarget(
            expenditureKcal: prior.kcal, weightKg: weight, goal: goal, ratePercentPerWeek: rate, bmrKcal: bmr,
            deficitAllowed: GoalSafety.block(for: .fatLoss, person: person, config: config) == nil, config: config
        )
        let reference = MacroPlanner.referenceWeightKg(trendWeightKg: weight, heightCm: height,
                                                       bodyFatKnown: draft.bodyFatPercent != nil, config: config)
        let macros = MacroPlanner.auto(kcal: target.kcal, goal: goal, referenceWeightKg: reference, config: config)
        return Numbers(kcal: target.kcal, proteinG: macros.proteinG, carbsG: macros.carbsG, fatG: macros.fatG,
                       floorApplied: target.floorApplied)
    }
}
