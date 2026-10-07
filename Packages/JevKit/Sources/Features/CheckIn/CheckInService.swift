import CheckInEngine
import CoachKit
import ExerciseCatalog
import Foundation
import JevCore
import JevDomain
import NutritionEngine
import Persistence
import WorkoutEngine

/// Weekly check-in end-to-end (M11): metriche dai dati della settimana → CheckInEngine →
/// spiegazione di JEV (gateway se disponibile e consentito, altrimenti template) → snapshot
/// salvato → risposte dell'utente (un aumento/diminuzione accettato diventa il nuovo target).
public struct CheckInService: Sendable {
    public let dashboard: DashboardService
    public let coach: CoachService
    public let repository: CheckInRepository

    public init(dashboard: DashboardService, coach: CoachService) {
        self.dashboard = dashboard
        self.coach = coach
        self.repository = CheckInRepository(facts: dashboard.training.facts)
    }

    public struct Report: Sendable, Equatable {
        public var checkInID: UUID
        public var weekStart: DayKey
        public var metrics: CheckInEvaluator.Metrics
        public var result: CheckInEvaluator.Result
        public var message: CoachMessage
    }

    var facts: FactRepository { dashboard.training.facts }

    // MARK: Metriche

    /// Metriche dei sette giorni prima di `day`; `nil` senza profilo o senza pesate.
    public func metrics(before day: DayKey, now: Date = Date(), config: EngineConfig = .current) throws -> CheckInEvaluator.Metrics? {
        let nutrition = dashboard.nutrition
        guard let targets = try nutrition.targets(on: day, config: config),
              let profile = try facts.fetchSingleton(UserProfileRecord.self) else { return nil }
        let goal = try facts.fetchAll(GoalRecord.self).filter { $0.endedAt == nil }.max { $0.startedAt < $1.startedAt }
        let weekStart = day.adding(days: -7)
        let intake = try nutrition.log.intake(from: weekStart, through: day.adding(days: -1))
        let complete = intake.filter(\.isComplete).compactMap(\.energyKcal)
        let weights = try nutrition.log.weights(from: day.adding(days: -60)).filter { $0.dayKey < day }
        let weighIns = Set(weights.filter { $0.dayKey >= weekStart }.map(\.dayKey)).count

        func lossPercent(until end: DayKey) -> Double? {
            let entries = weights.filter { $0.dayKey < end }.map { WeightTrend.Entry(dayKey: $0.dayKey, weightKg: $0.weightKg) }
            guard let trend = WeightTrend.compute(entries, config: config), let change = trend.change7DaysKg,
                  trend.trendKg > 0 else { return nil }
            return -change / trend.trendKg * 100
        }
        let meters = profile.heightCm / 100
        let trendWeight = targets.trend?.trendKg
        let reference = MacroPlanner.referenceWeightKg(trendWeightKg: targets.currentWeightKg, heightCm: profile.heightCm,
                                                       bodyFatKnown: false, config: config)
        let goalType = goal?.type ?? .maintenance
        let proposedMacros = MacroPlanner.auto(kcal: targets.engineKcal, goal: goalType, referenceWeightKg: reference, config: config)

        // Allenamento
        let next = try dashboard.training.nextSession(config: config)
        let preferences = try facts.fetchSingleton(TrainingPreferencesRecord.self)
        let weekSince = now.addingTimeInterval(-7 * 86_400)
        let sets = try dashboard.training.workouts.completedSets(since: now.addingTimeInterval(-14 * 86_400))
        let weekSets = sets.filter { $0.date >= weekSince }
        let sessions = Set(weekSets.map(\.sessionID)).count
        let adherence = preferences.map { min(Double(sessions) / Double(max($0.daysPerWeek, 1)), 1) }
        let states = try dashboard.muscleStates(now: now)
        var trainedMuscles = Set<MuscleGroup>()
        for set in weekSets {
            if let exercise = dashboard.training.catalog[set.exerciseKey] { trainedMuscles.formUnion(exercise.primaryMuscles) }
        }
        let recoveries = trainedMuscles.compactMap { states[$0]?.recoveryPercent }
        let recovery = recoveries.isEmpty ? nil : recoveries.reduce(0, +) / Double(recoveries.count)
        var pain: [String: Int] = [:]
        for set in sets where set.painLevel != .none { pain[set.exerciseKey, default: 0] += 1 }

        var plateaus: [String] = []
        let keys = Set(weekSets.map(\.exerciseKey))
        var progressing = 0
        for key in keys.sorted() {
            guard let exercise = dashboard.training.catalog[key] else { continue }
            let exposures = try dashboard.training.workouts.exposures(exerciseKey: key, limit: 12).map {
                ExerciseExposure(date: $0.date, sets: TrainingPlanService.performed($0.sets))
            }
            let plateau = PerformanceAnalysis.plateau(exposures, loadType: exercise.loadType, config: config)
            if plateau.isPlateau { plateaus.append(key) }
            if plateau.reasonCode == "plateau.progressing" || plateau.reasonCode == "plateau.rep_record" { progressing += 1 }
        }

        return CheckInEvaluator.Metrics(
            completeLoggedDays: complete.count, weighIns: weighIns,
            lossPercentThisWeek: lossPercent(until: day), lossPercentLastWeek: lossPercent(until: weekStart),
            averageIntakeKcal: complete.isEmpty ? nil : complete.reduce(0, +) / Double(complete.count),
            trendBMI: trendWeight.map { $0 / (meters * meters) },
            pregnancyOrLactation: profile.pregnancyOrLactation ?? false,
            goal: goalType, currentTargetKcal: targets.kcal, proposedTargetKcal: targets.engineKcal,
            expenditureKcal: targets.expenditureKcal, floorKcal: targets.floorKcal,
            expenditureConfidence: targets.expenditureConfidence, trendWeightKg: trendWeight,
            targetWeightKg: goal?.targetWeightKg, currentProteinG: targets.macros.proteinG,
            proposedProteinG: proposedMacros.proteinG, isDeloadWeek: next?.isDeload ?? false, deloadDue: false,
            readinessAverage7Days: (try? dashboard.readiness(now: now)).map { Double($0.score) },
            recoveryAveragePercent: recovery, adherence: adherence, progressionPositive: progressing > 0,
            plateauShare: keys.isEmpty ? 0 : Double(plateaus.count) / Double(keys.count),
            plateauExercises: plateaus, painReportsByExercise: pain
        )
    }

    // MARK: Esecuzione

    /// Decisioni rifiutate nei check-in precedenti, con le metriche di allora (isteresi).
    func rejections() throws -> [CheckInEvaluator.Rejection] {
        var result: [CheckInEvaluator.Rejection] = []
        for record in try repository.checkIns(limit: 8) {
            guard let responses = try? JSONDecoder().decode([String: Bool].self, from: Data(record.responses.utf8)),
                  let metrics = try? JSONDecoder().decode(CheckInEvaluator.Metrics.self, from: Data(record.metrics.utf8)) else { continue }
            for (key, accepted) in responses where !accepted {
                result.append(CheckInEvaluator.Rejection(decisionKey: key, metrics: metrics))
            }
        }
        return result
    }

    public func run(on day: DayKey, now: Date = Date(), config: EngineConfig = .current) async throws -> Report? {
        guard let metrics = try metrics(before: day, now: now, config: config) else { return nil }
        let result = CheckInEvaluator.evaluate(metrics, rejected: try rejections(), config: config)
        let message = await coach.message(for: CheckInCoach.request(metrics, result: result))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let record = try repository.save(
            weekStart: day.adding(days: -7),
            metricsJSON: String(decoding: try encoder.encode(metrics), as: UTF8.self),
            decisionsJSON: String(decoding: try encoder.encode(result.decisions), as: UTF8.self),
            engineVersion: CheckInEngineInfo.algorithmVersion
        )
        return Report(checkInID: record.id, weekStart: record.weekStart, metrics: metrics, result: result, message: message)
    }

    /// Risposta a una decisione. Un cambio di calorie accettato diventa il target in vigore da `day`.
    public func respond(to decision: CheckInEvaluator.Decision, in report: Report, accepted: Bool, day: DayKey) throws {
        try repository.respond(checkInID: report.checkInID, decisionKey: decision.key, accepted: accepted)
        if accepted, decision.type == .changeExercise, let exercise = decision.exerciseID {
            // L'esercizio esce dal programma; il generatore sceglie un'alternativa.
            let now = facts.time.now()
            try facts.save(ExercisePreferenceRecord(id: UUIDv7.make(at: now), exerciseKey: exercise, kind: .excluded,
                                                    createdAt: now, updatedAt: now))
            return
        }
        guard accepted, let delta = decision.deltaKcal,
              decision.type == .increaseCalories || decision.type == .decreaseCalories else { return }
        let kcal = max(report.metrics.currentTargetKcal + delta, report.metrics.floorKcal)
        try repository.saveTarget(kcal: kcal, effectiveFrom: day, origin: .checkIn, checkInID: report.checkInID,
                                  engineVersion: NutritionEngineInfo.algorithmVersion)
    }
}
