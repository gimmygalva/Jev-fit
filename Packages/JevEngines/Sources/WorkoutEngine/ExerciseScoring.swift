import Foundation
import ExerciseCatalog
import JevCore
import JevDomain

/// Profilo di allenamento come lo vede l'engine (dalle preferenze dell'onboarding).
public struct TrainingProfile: Sendable, Hashable {
    public var goal: GoalType
    public var experience: ExperienceLevel
    public var daysPerWeek: Int
    public var sessionMinutes: Int
    public var equipment: Set<Equipment>
    public var splitPreference: SplitType?
    public var musclePriority: [MuscleGroup]
    /// Limitazioni dichiarate: `true` = grave (esclude), `false` = lieve (penalizza).
    public var limitations: [BodyArea: Bool]
    public var favoriteExercises: Set<String>
    public var excludedExercises: Set<String>
    public var dislikedExercises: Set<String>

    public init(
        goal: GoalType, experience: ExperienceLevel, daysPerWeek: Int, sessionMinutes: Int,
        equipment: Set<Equipment>, splitPreference: SplitType? = nil, musclePriority: [MuscleGroup] = [],
        limitations: [BodyArea: Bool] = [:], favoriteExercises: Set<String> = [],
        excludedExercises: Set<String> = [], dislikedExercises: Set<String> = []
    ) {
        self.goal = goal
        self.experience = experience
        self.daysPerWeek = daysPerWeek
        self.sessionMinutes = sessionMinutes
        self.equipment = equipment
        self.splitPreference = splitPreference
        self.musclePriority = musclePriority
        self.limitations = limitations
        self.favoriteExercises = favoriteExercises
        self.excludedExercises = excludedExercises
        self.dislikedExercises = dislikedExercises
    }
}

/// Andamento recente di un esercizio (dal trend dell'e1RM / plateau).
public enum PerformanceStatus: String, Sendable, Hashable, CaseIterable {
    case progressing
    case unknown
    case plateau
    case regressing
}

/// Stato del giorno usato dal punteggio. Il programma si genera con lo stato neutro
/// (`ScoringContext()`), così gli esercizi principali restano ancorati (§5.5).
public struct ScoringContext: Sendable, Hashable {
    /// Recupero 0–100 per muscolo (assente = 100, nessun dato).
    public var recovery: [MuscleGroup: Double]
    /// Readiness 0–100 (assente = 75).
    public var readiness: Double?
    public var performance: [String: PerformanceStatus]
    /// Dolore recente per area: livello e giorni dall'ultima segnalazione.
    public var recentPain: [BodyArea: RecentPain]
    /// Esercizi del mesociclo precedente (varietà ai confini del mesociclo).
    public var previousMesocycleExercises: Set<String>

    public struct RecentPain: Sendable, Hashable {
        public var level: PainLevel
        public var daysAgo: Double

        public init(level: PainLevel, daysAgo: Double) {
            self.level = level
            self.daysAgo = daysAgo
        }
    }

    public init(
        recovery: [MuscleGroup: Double] = [:], readiness: Double? = nil, performance: [String: PerformanceStatus] = [:],
        recentPain: [BodyArea: RecentPain] = [:], previousMesocycleExercises: Set<String> = []
    ) {
        self.recovery = recovery
        self.readiness = readiness
        self.performance = performance
        self.recentPain = recentPain
        self.previousMesocycleExercises = previousMesocycleExercises
    }
}

/// ExerciseScore (§5.6): stadio 1 vincoli duri, stadio 2 media geometrica pesata dei fattori.
public enum ExerciseScoring {
    public enum Exclusion: String, Sendable, Hashable, CaseIterable {
        case equipmentMissing = "equipment_missing"
        case excludedByUser = "excluded_by_user"
        case contraindicated
        case strongPain = "strong_pain"
        case tooDifficult = "too_difficult"
    }

    public struct Factors: Sendable, Hashable {
        public var recovery: Double
        public var goal: Double
        public var preference: Double
        public var priority: Double
        public var variety: Double
        public var performance: Double
        public var fatigue: Double
        public var pain: Double
    }

    /// Stadio 1: motivi per cui l'esercizio non può entrare (vuoto = idoneo).
    public static func exclusions(_ e: CatalogExercise, profile: TrainingProfile, context: ScoringContext = .init()) -> [Exclusion] {
        var reasons: [Exclusion] = []
        if !e.requiredEquipment.isSubset(of: profile.equipment) { reasons.append(.equipmentMissing) }
        if profile.excludedExercises.contains(e.id) { reasons.append(.excludedByUser) }
        let areas = Set(e.contraindicatedAreas)
        if areas.contains(where: { profile.limitations[$0] == true }) { reasons.append(.contraindicated) }
        if areas.contains(where: { context.recentPain[$0]?.level == .strong && (context.recentPain[$0]?.daysAgo ?? .infinity) <= 14 }) {
            reasons.append(.strongPain)
        }
        if e.difficulty > experienceRank(profile.experience) + 1 { reasons.append(.tooDifficult) }
        return reasons
    }

    public static func isEligible(_ e: CatalogExercise, profile: TrainingProfile, context: ScoringContext = .init()) -> Bool {
        exclusions(e, profile: profile, context: context).isEmpty
    }

    static func experienceRank(_ level: ExperienceLevel) -> Int {
        switch level {
        case .beginner: 1
        case .intermediate: 2
        case .advanced: 3
        }
    }

    /// Stadio 2: fattori in (0, 1].
    public static func factors(_ e: CatalogExercise, profile: TrainingProfile, context: ScoringContext = .init(),
                               config: EngineConfig = .current) -> Factors {
        let w = config.workout
        // Recupero: media pesata dai contributi, sigmoide centrata al 55%.
        let contributions = e.muscleContributions
        let totalContribution = contributions.reduce(0) { $0 + $1.contribution }
        let weightedRecovery = contributions.reduce(0) { sum, item in
            sum + item.contribution * (context.recovery[item.muscle] ?? 100)
        } / max(totalContribution, 1e-9)
        let recovery = 1 / (1 + exp(-(weightedRecovery - w.recoverySigmoidCenter) / w.recoverySigmoidWidth))

        // Compatibilità con l'obiettivo: meccanica × qualità dello stimolo.
        let base: Double
        switch (profile.goal, e.mechanics) {
        case (.strength, .compound): base = 1.0
        case (.strength, .isolation): base = 0.6
        case (.hypertrophy, _), (.recomposition, _), (.fatLoss, _): base = e.mechanics == .compound ? 0.95 : 0.9
        case (.maintenance, .compound), (.generalFitness, .compound): base = 0.9
        case (.maintenance, .isolation), (.generalFitness, .isolation): base = 0.75
        }
        let goal = min(base * e.stimulusScore, 1)

        let preference: Double = profile.favoriteExercises.contains(e.id) ? 1.0
            : profile.dislikedExercises.contains(e.id) ? 0.35 : 0.75

        let priority: Double = profile.musclePriority.isEmpty || !Set(profile.musclePriority).isDisjoint(with: e.primaryMuscles) ? 1.0 : 0.8

        let variety: Double = context.previousMesocycleExercises.contains(e.id) && e.mechanics == .isolation ? 0.7 : 1.0

        let performance: Double
        switch context.performance[e.id] ?? .unknown {
        case .progressing: performance = 1.0
        case .unknown: performance = 0.8
        case .plateau: performance = 0.6
        case .regressing: performance = 0.5
        }

        let readiness = RobustStatistics.clamp(context.readiness ?? 75, 0...100)
        let fatigueNorm = RobustStatistics.clamp((e.fatigueScore - 0.3) / 1.0, 0...1)
        let fatigue = 1 - 0.6 * fatigueNorm * (1 - readiness / 100)

        // Dolore lieve recente o limitazione lieve sull'area: 1 − 0,6 · e^(−giorni/14).
        var pain = 1.0
        for area in e.contraindicatedAreas {
            if let recent = context.recentPain[area], recent.level == .mild {
                pain = min(pain, 1 - 0.6 * exp(-max(recent.daysAgo, 0) / w.painDecayDays))
            }
            if profile.limitations[area] == false {
                pain = min(pain, 0.4)
            }
        }
        return Factors(recovery: recovery, goal: goal, preference: preference, priority: priority,
                       variety: variety, performance: performance, fatigue: fatigue, pain: pain)
    }

    /// `S = exp(Σ wᵢ · ln max(fᵢ, ε))` in `[ε, 1]`.
    public static func score(_ f: Factors, config: EngineConfig = .current) -> Double {
        let w = config.workout.scoreWeights
        let eps = config.workout.scoreFloor
        let pairs: [(Double, Double)] = [
            (w.recovery, f.recovery), (w.goal, f.goal), (w.preference, f.preference), (w.priority, f.priority),
            (w.variety, f.variety), (w.performance, f.performance), (w.fatigue, f.fatigue), (w.pain, f.pain),
        ]
        let total = pairs.reduce(0) { $0 + $1.0 }
        guard total > 0 else { return eps }
        let logSum = pairs.reduce(0) { sum, pair in
            let value = pair.1.isFinite ? pair.1 : eps
            return sum + pair.0 / total * log(RobustStatistics.clamp(value, eps...1))
        }
        return RobustStatistics.clamp(exp(logSum), eps...1)
    }

    public static func score(_ e: CatalogExercise, profile: TrainingProfile, context: ScoringContext = .init(),
                             config: EngineConfig = .current) -> Double {
        score(factors(e, profile: profile, context: context, config: config), config: config)
    }
}
