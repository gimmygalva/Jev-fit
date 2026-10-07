import Foundation
import ExerciseCatalog
import JevCore
import JevDomain

/// Esercizio pianificato in una sessione del programma.
public struct PlannedExercise: Sendable, Hashable, Codable {
    public var exerciseID: String
    public var sets: Int
    public var repRange: ClosedRange<Int>
    public var targetRIR: Int
    public var restSeconds: Int
    /// Durata target per gli esercizi a tempo.
    public var targetDurationSeconds: Int?
}

/// Una sessione del programma (`workout_template`).
public struct SessionPlan: Sendable, Hashable, Codable {
    public enum Focus: String, Sendable, Hashable, Codable, CaseIterable {
        case fullBody = "full_body"
        case upper
        case lower
        case push
        case pull
        case legs
        case torso
        case limbs

        public var muscles: [MuscleGroup] {
            switch self {
            case .fullBody: MuscleGroup.allCases
            case .upper: [.chest, .lats, .upperBack, .frontDelts, .sideDelts, .rearDelts, .biceps, .triceps, .forearms]
            case .lower, .legs: [.quads, .hamstrings, .glutes, .adductors, .calves, .lowerBack, .abs, .obliques]
            case .push: [.chest, .frontDelts, .sideDelts, .triceps]
            case .pull: [.lats, .upperBack, .rearDelts, .biceps, .forearms]
            case .torso: [.chest, .lats, .upperBack, .frontDelts, .sideDelts, .rearDelts, .abs, .obliques]
            case .limbs: [.quads, .hamstrings, .glutes, .adductors, .calves, .biceps, .triceps, .forearms, .lowerBack]
            }
        }
    }

    public var index: Int
    public var focus: Focus
    public var exercises: [PlannedExercise]
    public var estimatedSeconds: Double
}

/// Programma generato (`training_program` + `workout_template[_exercise]`).
public struct ProgramPlan: Sendable, Hashable {
    public var split: SplitType
    public var splitReason: SplitSuggestion.Reason
    public var sessions: [SessionPlan]
    /// Serie hard settimanali pianificate per muscolo (conteggio frazionario).
    public var plannedWeeklySets: [MuscleGroup: Double]
    /// Obiettivo di serie settimanali per muscolo.
    public var targetWeeklySets: [MuscleGroup: Double]
    public var programWeek: Int
    public var isDeload: Bool
    public var engineVersion: Int
}

/// Generazione del programma (§5.5) con selezione greedy a utilità marginale (§5.6).
///
/// Deterministica: stessi input → stesso programma (pareggi risolti per id). Si genera con lo
/// stato neutro (`ScoringContext()`), così gli esercizi principali restano ancorati per tutto il
/// mesociclo; recupero e readiness del giorno intervengono nella sessione, non nel programma.
public enum ProgramGenerator {
    /// Sessioni della settimana per split e numero di giorni.
    public static func sessionFocuses(split: SplitType, days: Int) -> [SessionPlan.Focus] {
        let n = min(max(days, 1), 7)
        let cycle: [SessionPlan.Focus]
        switch split {
        case .fullBody, .custom: cycle = [.fullBody]
        case .upperLower: cycle = [.upper, .lower]
        case .torsoLimbs: cycle = [.torso, .limbs]
        case .pushPullLegs: cycle = [.push, .pull, .legs]
        case .hybrid: cycle = [.upper, .lower, .push, .pull, .legs, .upper]
        }
        return (0..<n).map { cycle[$0 % cycle.count] }
    }

    /// Serie settimanali obiettivo per muscolo: limite inferiore del range dell'esperienza
    /// (inizio mesociclo; la rampa la applica il CheckInEngine) × obiettivo × fattore del muscolo;
    /// i prioritari +30% entro il massimo del range.
    public static func weeklyTargets(profile: TrainingProfile, config: EngineConfig = .current) -> [MuscleGroup: Double] {
        let w = config.workout
        let range = w.weeklyHardSets[profile.experience] ?? 10...16
        let goal = w.goalVolumeMultiplier[profile.goal] ?? 1
        var targets: [MuscleGroup: Double] = [:]
        for muscle in MuscleGroup.allCases {
            let factor = w.muscleVolumeFactor[muscle] ?? 1
            var target = range.lowerBound * goal * factor
            if profile.musclePriority.contains(muscle) {
                target = min(target * (1 + w.priorityVolumeBoost), range.upperBound * goal * factor)
            }
            targets[muscle] = target
        }
        return targets
    }

    /// Rep range per obiettivo e meccanica.
    public static func repRange(goal: GoalType, mechanics: Mechanics) -> ClosedRange<Int> {
        switch (goal, mechanics) {
        case (.strength, .compound): 3...6
        case (.strength, .isolation): 8...12
        case (.hypertrophy, .compound), (.recomposition, .compound), (.fatLoss, .compound): 6...10
        case (.maintenance, .compound), (.generalFitness, .compound): 6...12
        case (_, .isolation): 10...15
        }
    }

    public static func restSeconds(goal: GoalType, mechanics: Mechanics, config: EngineConfig = .current) -> Double {
        let w = config.workout
        switch mechanics {
        case .compound: return goal == .strength ? w.restSecondsStrengthCompound : w.restSecondsCompound
        case .isolation: return w.restSecondsIsolation
        }
    }

    /// RIR target della settimana di programma (0-based) e deload dopo l'ultima.
    public static func weekParameters(programWeek: Int, config: EngineConfig = .current) -> (rir: Int, isDeload: Bool) {
        let schedule = config.workout.rirByProgramWeek
        guard !schedule.isEmpty else { return (2, false) }
        let position = programWeek % (schedule.count + 1)
        return position < schedule.count ? (schedule[position], false) : (3, true)
    }

    public static func generate(
        profile: TrainingProfile, catalog: ExerciseCatalog, programWeek: Int = 0,
        context: ScoringContext = .init(), config: EngineConfig = .current
    ) -> ProgramPlan {
        let w = config.workout
        let suggestion = SplitSuggestion.suggest(daysPerWeek: profile.daysPerWeek, preferred: profile.splitPreference)
        let focuses = sessionFocuses(split: suggestion.split, days: profile.daysPerWeek)
        let targets = weeklyTargets(profile: profile, config: config)
        var frequency: [MuscleGroup: Int] = [:]
        for focus in focuses {
            for muscle in focus.muscles { frequency[muscle, default: 0] += 1 }
        }
        let week = weekParameters(programWeek: programWeek, config: config)
        let budget = Double(max(profile.sessionMinutes, 15)) * 60
        let candidates = catalog.exercises.filter { ExerciseScoring.isEligible($0, profile: profile, context: context) }
        let scores = Dictionary(uniqueKeysWithValues: candidates.map {
            ($0.id, ExerciseScoring.score($0, profile: profile, context: context, config: config))
        })

        var planned: [MuscleGroup: Double] = [:]
        var usedThisWeek = Set<String>()
        var sessions: [SessionPlan] = []

        for (index, focus) in focuses.enumerated() {
            let focusSet = Set(focus.muscles)
            var need: [MuscleGroup: Double] = [:]
            for muscle in focus.muscles {
                let f = Double(max(frequency[muscle] ?? 1, 1))
                need[muscle] = min((targets[muscle] ?? 0) / f, w.maxHardSetsPerMuscleSession)
            }
            var time = w.warmupSeconds
            var chosen: [(exercise: CatalogExercise, sets: Int)] = []
            var patternCount: [MovementPattern: Int] = [:]
            var skipped = Set<String>()

            while true {
                var best: (utility: Double, exercise: CatalogExercise, sets: Int)?
                for e in candidates where !skipped.contains(e.id) && !chosen.contains(where: { $0.exercise.id == e.id }) {
                    guard (patternCount[e.pattern] ?? 0) < 2 else { continue }
                    let primaryNeed = e.primaryMuscles.filter(focusSet.contains).map { need[$0] ?? 0 }.max() ?? 0
                    guard primaryNeed >= 1 else { continue }
                    let sets = setsFor(primaryNeed: primaryNeed, config: config)
                    let cover = e.muscleContributions.reduce(0.0) { sum, item in
                        guard focusSet.contains(item.muscle) else { return sum }
                        return sum + min(need[item.muscle] ?? 0, item.contribution * Double(sets))
                    }
                    guard cover > 0 else { continue }
                    let reuse = usedThisWeek.contains(e.id) ? w.weeklyReusePenalty : 1
                    let utility = (scores[e.id] ?? 0) * reuse * cover / Double(sets) - w.fatigueUtilityPenalty * e.fatigueScore
                    guard utility > 0 else { continue }
                    if let current = best {
                        if utility > current.utility + 1e-12 || (abs(utility - current.utility) <= 1e-12 && e.id < current.exercise.id) {
                            best = (utility, e, sets)
                        }
                    } else {
                        best = (utility, e, sets)
                    }
                }
                guard var pick = best else { break }
                let perSet = w.setDurationSeconds + restSeconds(goal: profile.goal, mechanics: pick.exercise.mechanics, config: config)
                if time + Double(pick.sets) * perSet > budget {
                    // Prova con il minimo di serie; altrimenti l'esercizio non entra in questa sessione.
                    let minimum = w.minSetsPerExercise
                    if time + Double(minimum) * perSet > budget {
                        skipped.insert(pick.exercise.id)
                        if time + Double(minimum) * (w.setDurationSeconds + w.restSecondsIsolation) > budget { break }
                        continue
                    }
                    pick.sets = minimum
                }
                time += Double(pick.sets) * perSet
                chosen.append((pick.exercise, pick.sets))
                usedThisWeek.insert(pick.exercise.id)
                patternCount[pick.exercise.pattern, default: 0] += 1
                for item in pick.exercise.muscleContributions {
                    if let current = need[item.muscle] {
                        need[item.muscle] = max(0, current - item.contribution * Double(pick.sets))
                    }
                    planned[item.muscle, default: 0] += item.contribution * Double(pick.sets)
                }
            }

            // Ordine in sessione: multiarticolari prima, poi per fatica decrescente.
            let ordered = chosen.sorted { lhs, rhs in
                if lhs.exercise.mechanics != rhs.exercise.mechanics { return lhs.exercise.mechanics == .compound }
                if lhs.exercise.fatigueScore != rhs.exercise.fatigueScore { return lhs.exercise.fatigueScore > rhs.exercise.fatigueScore }
                return lhs.exercise.id < rhs.exercise.id
            }
            let exercises = ordered.map { item -> PlannedExercise in
                let sets = week.isDeload ? max(1, Int((Double(item.sets) * (1 - w.deloadSetReduction)).rounded())) : item.sets
                return PlannedExercise(
                    exerciseID: item.exercise.id,
                    sets: sets,
                    repRange: repRange(goal: profile.goal, mechanics: item.exercise.mechanics),
                    targetRIR: week.rir,
                    restSeconds: Int(restSeconds(goal: profile.goal, mechanics: item.exercise.mechanics, config: config)),
                    targetDurationSeconds: item.exercise.loadType == .timed ? 30 : nil
                )
            }
            sessions.append(SessionPlan(index: index, focus: focus, exercises: exercises, estimatedSeconds: time))
        }

        return ProgramPlan(
            split: suggestion.split, splitReason: suggestion.reason, sessions: sessions,
            plannedWeeklySets: planned, targetWeeklySets: targets, programWeek: programWeek,
            isDeload: week.isDeload, engineVersion: WorkoutEngineInfo.algorithmVersion
        )
    }

    static func setsFor(primaryNeed: Double, config: EngineConfig) -> Int {
        let w = config.workout
        let raw = Int((primaryNeed - 1e-9).rounded(.up))
        return min(max(raw, w.minSetsPerExercise), w.maxSetsPerExercise)
    }
}
