import ExerciseCatalog
import Foundation
import JevCore
import JevDomain
import Persistence
import WorkoutEngine

/// Collega profilo, programma e progressive overload (M8): quale sessione fare oggi e con quali
/// carichi. Tutta la logica numerica resta negli engine; qui si leggono i dati e si traducono.
public struct TrainingPlanService: Sendable {
    public let facts: FactRepository
    public let workouts: WorkoutRepository
    public let catalog: ExerciseCatalog

    public init(facts: FactRepository, catalog: ExerciseCatalog) {
        self.facts = facts
        self.workouts = WorkoutRepository(facts: facts)
        self.catalog = catalog
    }

    /// La prossima sessione della rotazione con i target di ogni serie.
    public struct NextSession: Sendable, Equatable {
        public var plan: SessionPlan
        public var programWeek: Int
        public var isDeload: Bool
        public var split: SplitType
        public var exercises: [WorkoutRepository.PlannedExerciseInput]
        /// Decisione di overload per esercizio (reason code e regola), per la UI e per JEV.
        public var decisions: [String: Progression.Decision]
    }

    /// Con il catalogo incluso nell'app; `nil` se il catalogo non si carica (risorsa danneggiata).
    public static func bundled(facts: FactRepository) -> TrainingPlanService? {
        (try? ExerciseCatalog.bundled()).map { TrainingPlanService(facts: facts, catalog: $0) }
    }

    // MARK: Profilo

    /// Profilo di allenamento dai fatti salvati dall'onboarding; `nil` se l'onboarding manca.
    public func profile() throws -> TrainingProfile? {
        guard let user = try facts.fetchSingleton(UserProfileRecord.self),
              let preferences = try facts.fetchSingleton(TrainingPreferencesRecord.self) else { return nil }
        let goal = try facts.fetchAll(GoalRecord.self)
            .filter { $0.endedAt == nil }
            .max { $0.startedAt < $1.startedAt }
        var limitations: [BodyArea: Bool] = [:]
        for limitation in try facts.fetchAll(LimitationRecord.self) where limitation.active {
            limitations[limitation.bodyArea] = limitation.severity == .moderate
        }
        var equipment = Set(preferences.equipment)
        equipment.insert(.bodyweight)
        return TrainingProfile(
            goal: goal?.type ?? .generalFitness, experience: user.experience, daysPerWeek: preferences.daysPerWeek,
            sessionMinutes: preferences.sessionMinutes, equipment: equipment, splitPreference: preferences.splitPreference,
            musclePriority: preferences.musclePriority, limitations: limitations
        )
    }

    // MARK: Prossima sessione

    public func nextSession(config: EngineConfig = .current) throws -> NextSession? {
        guard let profile = try profile() else { return nil }
        let completed = try workouts.completedSessionCount()
        let sessionsPerWeek = max(profile.daysPerWeek, 1)
        let mesocycle = config.workout.rirByProgramWeek.count + 1
        let programWeek = (completed / sessionsPerWeek) % mesocycle
        let program = ProgramGenerator.generate(profile: profile, catalog: catalog, programWeek: programWeek, config: config)
        guard !program.sessions.isEmpty else { return nil }
        let plan = program.sessions[completed % program.sessions.count]
        var inputs: [WorkoutRepository.PlannedExerciseInput] = []
        var decisions: [String: Progression.Decision] = [:]
        for planned in plan.exercises {
            guard let exercise = catalog[planned.exerciseID] else { continue }
            let decision = try prescription(for: exercise, planned: planned, isDeload: program.isDeload, config: config)
            decisions[exercise.id] = decision
            inputs.append(input(exercise: exercise, planned: planned, decision: decision, isDeload: program.isDeload, config: config))
        }
        return NextSession(plan: plan, programWeek: programWeek, isDeload: program.isDeload, split: program.split,
                           exercises: inputs, decisions: decisions)
    }

    /// Decisione di overload dalle ultime due esposizioni (la penultima serve alla regola 3).
    func prescription(
        for exercise: CatalogExercise, planned: PlannedExercise, isDeload: Bool, config: EngineConfig
    ) throws -> Progression.Decision {
        let prescription = Progression.Prescription(
            loadType: exercise.loadType, incrementKg: exercise.loadIncrementKg, repRange: planned.repRange,
            targetRIR: planned.targetRIR, targetDurationSeconds: planned.targetDurationSeconds
        )
        let exposures = try workouts.exposures(exerciseKey: exercise.id, limit: 2)
        let now = facts.time.now()
        let painWindow = Double(config.progression.painLookbackDays) * 86_400
        let recentPain = exposures.contains { exposure in
            now.timeIntervalSince(exposure.date) <= painWindow && exposure.sets.contains { $0.painLevel != .none }
        }
        var previousUnderperformed = false
        if exposures.count == 2 {
            previousUnderperformed = Progression.decide(
                lastExposure: Self.performed(exposures[0].sets), prescription: prescription
            ).underperformed
        }
        let context = Progression.Context(
            painBlocksIncrease: recentPain, isDeload: isDeload, previousExposureUnderperformed: previousUnderperformed
        )
        return Progression.decide(lastExposure: Self.performed(exposures.last?.sets ?? []),
                                  prescription: prescription, context: context)
    }

    static func performed(_ sets: [WorkoutSetRecord]) -> [PerformedSet] {
        sets.map {
            PerformedSet(type: $0.setType, loadKg: $0.weightKg, reps: $0.reps, rir: $0.rir,
                         durationSeconds: $0.durationS, pain: $0.painLevel)
        }
    }

    func input(
        exercise: CatalogExercise, planned: PlannedExercise, decision: Progression.Decision, isDeload: Bool,
        config: EngineConfig
    ) -> WorkoutRepository.PlannedExerciseInput {
        var load = decision.nextLoadKg
        if isDeload, let current = load, exercise.loadIncrementKg > 0, exercise.loadType == .external {
            let reduced = current * (1 - config.progression.deloadLoadReduction)
            load = (reduced / exercise.loadIncrementKg).rounded() * exercise.loadIncrementKg
        }
        let timed = exercise.loadType == .timed
        let set = WorkoutRepository.PlannedSet(
            type: .working, targetWeightKg: timed ? nil : load, targetReps: timed ? nil : decision.nextReps,
            targetDurationSeconds: timed ? (decision.nextDurationSeconds ?? planned.targetDurationSeconds) : nil,
            restSeconds: planned.restSeconds
        )
        return WorkoutRepository.PlannedExerciseInput(
            exerciseKey: exercise.id, sets: Array(repeating: set, count: max(planned.sets, 1))
        )
    }

    /// Avvia la prossima sessione (o restituisce quella già in corso).
    public func startNextSession() throws -> UUID? {
        if let active = try workouts.activeSession() { return active.id }
        guard let next = try nextSession() else { return nil }
        return try workouts.startSession(exercises: next.exercises)
    }
}
