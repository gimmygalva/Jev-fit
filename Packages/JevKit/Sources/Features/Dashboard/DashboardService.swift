import ExerciseCatalog
import Foundation
import JevCore
import JevDomain
import NutritionEngine
import Persistence
import RecoveryEngine
import WorkoutEngine

/// Dati di Oggi, Corpo e Progressi (M10). Legge fatti e cache di Salute, delega ogni calcolo
/// agli engine (recupero, readiness, trend) e restituisce valori pronti per le viste.
public struct DashboardService: Sendable {
    public let training: TrainingPlanService
    public let nutrition: NutritionPlanService
    public let healthCache: HealthCacheStore?

    public init(training: TrainingPlanService, nutrition: NutritionPlanService, healthCache: HealthCacheStore?) {
        self.training = training
        self.nutrition = nutrition
        self.healthCache = healthCache
    }

    var facts: FactRepository { training.facts }

    // MARK: Recupero

    /// Serie eseguite negli ultimi 28 giorni come dosi di fatica per muscolo.
    func doses(now: Date) throws -> [MuscleRecovery.SetDose] {
        let since = now.addingTimeInterval(-28 * 86_400)
        return try training.workouts.completedSets(since: since).compactMap { set in
            guard let exercise = training.catalog[set.exerciseKey] else { return nil }
            return MuscleRecovery.SetDose(date: set.date, exercise: exercise, rir: set.rir, isWarmup: set.setType == .warmup)
        }
    }

    func ageYears(on day: DayKey) throws -> Int? {
        try facts.fetchSingleton(UserProfileRecord.self).map { max(day.year - $0.birthYear, 0) }
    }

    /// Stato di recupero di ogni muscolo (body map, SCR-BD-01).
    public func muscleStates(now: Date = Date(), timeZone: TimeZone = .current) throws -> [MuscleGroup: MuscleRecovery.MuscleState] {
        let day = DayKey(date: now, timeZone: timeZone)
        return MuscleRecovery.state(sets: try doses(now: now), at: now, ageYears: try ageYears(on: day))
    }

    // MARK: Readiness

    public func readiness(now: Date = Date(), timeZone: TimeZone = .current) throws -> Readiness.Result? {
        let day = DayKey(date: now, timeZone: timeZone)
        var input = Readiness.Input()

        let states = try muscleStates(now: now, timeZone: timeZone)
        if let next = try training.nextSession() {
            var muscles: [MuscleGroup: Double] = [:]
            for exercise in next.exercises {
                guard let item = training.catalog[exercise.exerciseKey] else { continue }
                for contribution in item.muscleContributions {
                    muscles[contribution.muscle, default: 0] += contribution.contribution * Double(exercise.sets.count)
                }
            }
            input.sessionRecoveryPercent = MuscleRecovery.sessionRecovery(states, muscles: muscles)
        }

        if let cache = healthCache {
            let metrics = try cache.metrics(from: day.adding(days: -28), through: day)
            let recent = metrics.filter { $0.dayKey > day.adding(days: -3) }
            if let last = metrics.last(where: { $0.dayKey == day }), let minutes = last.sleepMinutes {
                let nights = recent.compactMap(\.sleepMinutes)
                let average = nights.count >= 2 ? nights.reduce(0, +) / Double(nights.count) / 60 : nil
                input.sleep = Readiness.Sleep(lastNightHours: minutes / 60, threeNightAverageHours: average)
            }
            let hrvBaseline = metrics.compactMap { $0.hrvSdnnMs.flatMap { $0 > 0 ? log($0) : nil } }
            let hrvRecent = metrics.filter { $0.dayKey > day.adding(days: -7) }.compactMap { $0.hrvSdnnMs.flatMap { $0 > 0 ? log($0) : nil } }
            input.hrv = Readiness.Baseline(recent: hrvRecent, baseline: hrvBaseline)
            let rhrBaseline = metrics.compactMap(\.restingHr)
            input.restingHeartRate = Readiness.Baseline(recent: recent.compactMap(\.restingHr), baseline: rhrBaseline)
        }

        let sets = try training.workouts.completedSets(since: now.addingTimeInterval(-28 * 86_400))
        if let first = sets.first {
            let firstDay = first.dayKey
            let span = firstDay.days(to: day) + 1
            var loads = Array(repeating: 0.0, count: max(span, 1))
            for set in sets where set.setType != .warmup {
                let index = firstDay.days(to: set.dayKey)
                if loads.indices.contains(index) {
                    loads[index] += MuscleRecovery.intensity(rir: set.rir, isWarmup: false)
                }
            }
            input.dailyTrainingLoad = loads
        }

        let trainingDays = try training.workouts.trainingDays(since: day.adding(days: -14))
        var streak = 0
        var cursor = trainingDays.contains(day) ? day : day.adding(days: -1)
        while trainingDays.contains(cursor) {
            streak += 1
            cursor = cursor.adding(days: -1)
        }
        input.consecutiveTrainingDays = streak

        if let targets = try nutrition.targets(on: day) {
            let intake = try nutrition.log.intake(from: day.adding(days: -3), through: day.adding(days: -1))
                .filter(\.isComplete).compactMap(\.energyKcal)
            if !intake.isEmpty {
                input.energyBalance = Readiness.EnergyBalance(
                    averageIntakeKcal: intake.reduce(0, +) / Double(intake.count),
                    expenditureKcal: targets.expenditureKcal, plannedTargetKcal: targets.kcal
                )
            }
        }
        return Readiness.compute(input)
    }

    // MARK: Progressi

    public struct Point: Sendable, Hashable, Identifiable {
        public var day: DayKey
        public var value: Double
        public var id: DayKey { day }
    }

    public enum Metric: String, Sendable, CaseIterable, Identifiable {
        case weight
        case weightTrend = "weight_trend"
        case calories
        case protein
        case carbs
        case fat
        case workouts
        case volume
        case hardSets = "hard_sets"
        case topE1RM = "top_e1rm"
        case steps
        case activeEnergy = "active_energy"
        case sleep
        case restingHeartRate = "resting_hr"
        case hrv

        public var id: String { rawValue }
    }

    /// Serie giornaliera (o settimanale per allenamenti, volume e serie) del periodo richiesto.
    public func series(_ metric: Metric, days: Int, now: Date = Date(), timeZone: TimeZone = .current) throws -> [Point] {
        let today = DayKey(date: now, timeZone: timeZone)
        let start = today.adding(days: -(days - 1))
        switch metric {
        case .weight:
            return try nutrition.log.weights(from: start).map { Point(day: $0.dayKey, value: $0.weightKg) }
        case .weightTrend:
            let weights = try nutrition.log.weights(from: start.adding(days: -60))
            let entries = weights.map { WeightTrend.Entry(dayKey: $0.dayKey, weightKg: $0.weightKg) }
            return (WeightTrend.compute(entries)?.smoothed ?? []).filter { $0.dayKey >= start }
                .map { Point(day: $0.dayKey, value: $0.trendKg) }
        case .calories, .protein, .carbs, .fat:
            return try nutritionSeries(metric, from: start, through: today)
        case .workouts, .volume, .hardSets, .topE1RM:
            return try trainingSeries(metric, from: start, through: today, now: now)
        case .steps, .activeEnergy, .sleep, .restingHeartRate, .hrv:
            guard let cache = healthCache else { return [] }
            return try cache.metrics(from: start, through: today).compactMap { row in
                let value: Double? = switch metric {
                case .steps: row.steps.map(Double.init)
                case .activeEnergy: row.activeKcal
                case .sleep: row.sleepMinutes.map { $0 / 60 }
                case .restingHeartRate: row.restingHr
                default: row.hrvSdnnMs
                }
                return value.map { Point(day: row.dayKey, value: $0) }
            }
        }
    }

    func nutritionSeries(_ metric: Metric, from start: DayKey, through end: DayKey) throws -> [Point] {
        var points: [Point] = []
        var day = start
        while day <= end {
            let entries = try nutrition.log.entries(day: day)
            if !entries.isEmpty {
                let totals = try nutrition.log.totals(day: day)
                let value: Double = switch metric {
                case .protein: totals.proteinG
                case .carbs: totals.carbsG
                case .fat: totals.fatG
                default: totals.energyKcal
                }
                points.append(Point(day: day, value: value))
            }
            day = day.adding(days: 1)
        }
        return points
    }

    /// Valori settimanali (punto sul lunedì... sul primo giorno della settimana del periodo).
    func trainingSeries(_ metric: Metric, from start: DayKey, through end: DayKey, now: Date) throws -> [Point] {
        let since = now.addingTimeInterval(-Double(start.days(to: end) + 2) * 86_400)
        let sets = try training.workouts.completedSets(since: since).filter { $0.dayKey >= start && $0.dayKey <= end }
        var buckets: [Int: [WorkoutRepository.CompletedSet]] = [:]
        for set in sets {
            buckets[start.days(to: set.dayKey) / 7, default: []].append(set)
        }
        return buckets.keys.sorted().compactMap { week in
            guard let items = buckets[week] else { return nil }
            let day = start.adding(days: week * 7)
            let working = items.filter { $0.setType != .warmup }
            let value: Double
            switch metric {
            case .workouts:
                value = Double(Set(items.map(\.sessionID)).count)
            case .volume:
                value = working.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
            case .hardSets:
                value = Double(working.filter { ($0.rir ?? 0) <= 4 }.count)
            default:
                value = working.compactMap { set in
                    set.weightKg.flatMap { StrengthEstimation.e1RM(loadKg: $0, reps: set.reps ?? 0, rir: set.rir) }
                }.max() ?? 0
            }
            return Point(day: day, value: value)
        }
    }
}
