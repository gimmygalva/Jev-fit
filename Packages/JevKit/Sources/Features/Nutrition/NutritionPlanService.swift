import Foundation
import JevCore
import JevDomain
import NutritionEngine
import Persistence

/// Target del giorno dai dati reali (M9): profilo, trend del peso, expenditure adattiva dai
/// giorni completi, target calorico e macro AUTO. Tutti i numeri vengono dal NutritionEngine.
public struct NutritionPlanService: Sendable {
    public let log: NutritionLogRepository

    public init(facts: FactRepository) {
        self.log = NutritionLogRepository(facts: facts)
    }

    public struct Targets: Sendable, Equatable {
        public var kcal: Double
        public var macros: MacroPlanner.Macros
        public var expenditureKcal: Double
        public var expenditureConfidence: Double
        public var confidenceLabel: ConfidenceLabel
        public var bmrKcal: Double
        public var ratePercentPerWeek: Double
        public var floorApplied: Bool
        public var trend: WeightTrend.Result?
        public var currentWeightKg: Double
    }

    /// Finestra di storico usata per trend ed expenditure.
    static let historyDays = 120

    public func targets(on day: DayKey, config: EngineConfig = .current) throws -> Targets? {
        let facts = log.facts
        guard let profile = try facts.fetchSingleton(UserProfileRecord.self) else { return nil }
        let goal = try facts.fetchAll(GoalRecord.self).filter { $0.endedAt == nil }.max { $0.startedAt < $1.startedAt }
        let start = day.adding(days: -Self.historyDays)
        let weights = try log.weights(from: start).filter { $0.dayKey <= day }
        guard let lastWeight = weights.last?.weightKg else { return nil }

        let trend = WeightTrend.compute(weights.map { WeightTrend.Entry(dayKey: $0.dayKey, weightKg: $0.weightKg) }, config: config)
        let weight = trend?.trendKg ?? lastWeight
        let age = max(day.year - profile.birthYear, 0)
        let bmr = EnergyModel.bmr(weightKg: weight, heightCm: profile.heightCm, ageYears: age, sex: profile.sex, config: config)
        let prior = EnergyModel.priorExpenditure(weightKg: weight, heightCm: profile.heightCm, ageYears: age, sex: profile.sex,
                                                 activity: profile.activityLevel, config: config)

        // Giorni fino a ieri: oggi è ancora aperto.
        let intake = try log.intake(from: start, through: day.adding(days: -1))
        var days: [DayKey: ExpenditureEstimator.Day] = [:]
        for item in intake {
            days[item.day] = ExpenditureEstimator.Day(dayKey: item.day, intakeKcal: item.energyKcal, isComplete: item.isComplete)
        }
        var seenWeightDays = Set<DayKey>()
        for entry in weights where seenWeightDays.insert(entry.dayKey).inserted {
            days[entry.dayKey, default: ExpenditureEstimator.Day(dayKey: entry.dayKey)].weightKg = entry.weightKg
        }
        let estimate = ExpenditureEstimator.estimate(days: Array(days.values), prior: prior, config: config)
        let expenditure = estimate?.expenditureKcal ?? prior.kcal

        let goalType = goal?.type ?? .maintenance
        let person = GoalSafety.Person(ageYears: age, weightKg: weight, heightCm: profile.heightCm,
                                       pregnancyOrLactation: profile.pregnancyOrLactation ?? false)
        let deficitAllowed = GoalSafety.block(for: .fatLoss, person: person, config: config) == nil
        let rate = goal?.targetRatePctWeek ?? GoalSafety.rateLimits(for: goalType, config: config)?.defaultValue ?? 0
        let target = CalorieTargets.dailyTarget(
            expenditureKcal: expenditure, weightKg: weight, goal: goalType, ratePercentPerWeek: rate, bmrKcal: bmr,
            deficitAllowed: deficitAllowed, config: config
        )
        let reference = MacroPlanner.referenceWeightKg(trendWeightKg: weight, heightCm: profile.heightCm,
                                                       bodyFatKnown: false, config: config)
        let macros = MacroPlanner.auto(kcal: target.kcal, goal: goalType, referenceWeightKg: reference, config: config)
        let confidence = estimate?.confidence ?? 0
        return Targets(
            kcal: target.kcal, macros: macros, expenditureKcal: expenditure, expenditureConfidence: confidence,
            confidenceLabel: estimate?.label ?? config.confidence.label(for: confidence), bmrKcal: bmr,
            ratePercentPerWeek: target.ratePercentPerWeek, floorApplied: target.floorApplied, trend: trend,
            currentWeightKg: weight
        )
    }
}
