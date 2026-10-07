import Foundation
import ExerciseCatalog
import JevCore
import JevDomain
import Testing
@testable import WorkoutEngine

@Suite("ExerciseScore e generazione del programma (§5.5–5.6)")
struct ProgramGeneratorTests {
    let catalog: ExerciseCatalog
    let fullGym = Set(Equipment.allCases)

    init() throws {
        catalog = try ExerciseCatalog.bundled()
    }

    private func profile(
        goal: GoalType = .hypertrophy, experience: ExperienceLevel = .intermediate, days: Int = 4, minutes: Int = 75,
        equipment: Set<Equipment>? = nil, split: SplitType? = nil, priority: [MuscleGroup] = [],
        limitations: [BodyArea: Bool] = [:], excluded: Set<String> = []
    ) -> TrainingProfile {
        TrainingProfile(goal: goal, experience: experience, daysPerWeek: days, sessionMinutes: minutes,
                        equipment: equipment ?? fullGym, splitPreference: split, musclePriority: priority,
                        limitations: limitations, excludedExercises: excluded)
    }

    // MARK: ExerciseScore

    @Test("Stadio 1: attrezzatura, esclusione, controindicazione grave, dolore forte, difficoltà")
    func exclusions() throws {
        let bench = try #require(catalog["barbell_bench_press"])
        #expect(ExerciseScoring.isEligible(bench, profile: profile()))
        #expect(ExerciseScoring.exclusions(bench, profile: profile(equipment: [.dumbbell])) == [.equipmentMissing])
        #expect(ExerciseScoring.exclusions(bench, profile: profile(excluded: ["barbell_bench_press"])) == [.excludedByUser])
        #expect(ExerciseScoring.exclusions(bench, profile: profile(limitations: [.shoulder: true])) == [.contraindicated])
        #expect(ExerciseScoring.isEligible(bench, profile: profile(limitations: [.shoulder: false])), "Una limitazione lieve penalizza, non esclude")
        let pain = ScoringContext(recentPain: [.shoulder: .init(level: .strong, daysAgo: 3)])
        #expect(ExerciseScoring.exclusions(bench, profile: profile(), context: pain) == [.strongPain])
        let deadlift = try #require(catalog["conventional_deadlift"])
        #expect(ExerciseScoring.exclusions(deadlift, profile: profile(experience: .beginner)) == [.tooDifficult])
        #expect(ExerciseScoring.isEligible(deadlift, profile: profile(experience: .intermediate)))
    }

    @Test("Stadio 2: fattori in (0, 1], punteggio in [ε, 1], nessun annullamento")
    func scoreBounds() throws {
        let p = profile(priority: [.sideDelts], limitations: [.shoulder: false])
        let context = ScoringContext(recovery: [.chest: 0], readiness: 10, performance: ["barbell_bench_press": .regressing],
                                     recentPain: [.shoulder: .init(level: .mild, daysAgo: 0)],
                                     previousMesocycleExercises: ["lateral_raise"])
        for exercise in catalog.exercises {
            let f = ExerciseScoring.factors(exercise, profile: p, context: context)
            for value in [f.recovery, f.goal, f.preference, f.priority, f.variety, f.performance, f.fatigue, f.pain] {
                #expect(value > 0 && value <= 1, "\(exercise.id)")
            }
            let s = ExerciseScoring.score(exercise, profile: p, context: context)
            #expect(s >= EngineConfig.current.workout.scoreFloor && s <= 1)
        }
        let zero = ExerciseScoring.Factors(recovery: 0, goal: 0, preference: 0, priority: 0, variety: 0, performance: 0, fatigue: 0, pain: .nan)
        #expect(ExerciseScoring.score(zero) == EngineConfig.current.workout.scoreFloor)
        var broken = EngineConfig.current
        broken.workout.scoreWeights = .init(recovery: 0, goal: 0, preference: 0, priority: 0, variety: 0, performance: 0, fatigue: 0, pain: 0)
        #expect(ExerciseScoring.score(zero, config: broken) == broken.workout.scoreFloor)
    }

    @Test("Il punteggio cresce con il recupero, con la preferenza e con la performance")
    func monotonicity() throws {
        let row = try #require(catalog["barbell_row"])
        var previous = 0.0
        for recovery in stride(from: 0.0, through: 100, by: 10) {
            let s = ExerciseScoring.score(row, profile: profile(), context: .init(recovery: [.upperBack: recovery, .lats: recovery]))
            #expect(s >= previous)
            previous = s
        }
        var favorite = profile()
        favorite.favoriteExercises = ["barbell_row"]
        var disliked = profile()
        disliked.dislikedExercises = ["barbell_row"]
        #expect(ExerciseScoring.score(row, profile: favorite) > ExerciseScoring.score(row, profile: profile()))
        #expect(ExerciseScoring.score(row, profile: disliked) < ExerciseScoring.score(row, profile: profile()))
        let statuses: [PerformanceStatus] = [.progressing, .unknown, .plateau, .regressing]
        let byStatus = statuses.map { ExerciseScoring.score(row, profile: profile(), context: .init(performance: ["barbell_row": $0])) }
        #expect(byStatus == byStatus.sorted(by: >))
        #expect(ExerciseScoring.experienceRank(.advanced) == 3)
        for goal in GoalType.allCases {
            #expect(ExerciseScoring.score(row, profile: profile(goal: goal)) > 0)
        }
    }

    // MARK: Programma

    @Test("Sessioni per split e giorni")
    func focuses() {
        #expect(ProgramGenerator.sessionFocuses(split: .upperLower, days: 4) == [.upper, .lower, .upper, .lower])
        #expect(ProgramGenerator.sessionFocuses(split: .pushPullLegs, days: 6) == [.push, .pull, .legs, .push, .pull, .legs])
        #expect(ProgramGenerator.sessionFocuses(split: .hybrid, days: 5) == [.upper, .lower, .push, .pull, .legs])
        #expect(ProgramGenerator.sessionFocuses(split: .torsoLimbs, days: 2) == [.torso, .limbs])
        #expect(ProgramGenerator.sessionFocuses(split: .custom, days: 3) == [.fullBody, .fullBody, .fullBody])
        #expect(ProgramGenerator.sessionFocuses(split: .fullBody, days: 0).count == 1)
        for focus in SessionPlan.Focus.allCases { #expect(!focus.muscles.isEmpty) }
    }

    @Test("Obiettivi di volume: range dell'esperienza, obiettivo, priorità entro il massimo")
    func targets() {
        let base = ProgramGenerator.weeklyTargets(profile: profile())
        #expect(base[.chest] == 10)
        #expect(base[.forearms] == 4)
        let prioritized = ProgramGenerator.weeklyTargets(profile: profile(priority: [.chest]))
        #expect(prioritized[.chest] == 13)
        let strength = ProgramGenerator.weeklyTargets(profile: profile(goal: .strength))
        #expect(strength[.chest] == 7)
        let beginner = ProgramGenerator.weeklyTargets(profile: profile(experience: .beginner, priority: [.chest]))
        #expect(beginner[.chest] == 10, "La priorità non supera il massimo del range")
    }

    @Test("Rep range, recuperi e settimane del mesociclo con deload")
    func parameters() {
        #expect(ProgramGenerator.repRange(goal: .strength, mechanics: .compound) == 3...6)
        #expect(ProgramGenerator.repRange(goal: .strength, mechanics: .isolation) == 8...12)
        #expect(ProgramGenerator.repRange(goal: .hypertrophy, mechanics: .compound) == 6...10)
        #expect(ProgramGenerator.repRange(goal: .generalFitness, mechanics: .compound) == 6...12)
        #expect(ProgramGenerator.repRange(goal: .fatLoss, mechanics: .isolation) == 10...15)
        #expect(ProgramGenerator.restSeconds(goal: .strength, mechanics: .compound) == 180)
        #expect(ProgramGenerator.restSeconds(goal: .hypertrophy, mechanics: .compound) == 120)
        #expect(ProgramGenerator.restSeconds(goal: .hypertrophy, mechanics: .isolation) == 75)
        #expect(ProgramGenerator.weekParameters(programWeek: 0) == (3, false))
        #expect(ProgramGenerator.weekParameters(programWeek: 3) == (1, false))
        #expect(ProgramGenerator.weekParameters(programWeek: 4) == (3, true))
        #expect(ProgramGenerator.weekParameters(programWeek: 5) == (3, false))
        var empty = EngineConfig.current
        empty.workout.rirByProgramWeek = []
        #expect(ProgramGenerator.weekParameters(programWeek: 2, config: empty) == (2, false))
        #expect(ProgramGenerator.setsFor(primaryNeed: 0.5, config: .current) == 2)
        #expect(ProgramGenerator.setsFor(primaryNeed: 9, config: .current) == 4)
    }

    @Test("Proprietà su molti profili: deterministico, nel tempo, solo esercizi idonei, serie valide")
    func properties() {
        let equipmentSets: [Set<Equipment>] = [
            fullGym, [.dumbbell, .bench], [.bodyweight], [.barbell, .bench, .pullUpBar, .dumbbell], [],
        ]
        for goal in GoalType.allCases {
            for experience in ExperienceLevel.allCases {
                for days in [2, 3, 4, 5, 6] {
                    for equipment in equipmentSets {
                        let p = profile(goal: goal, experience: experience, days: days, minutes: 60, equipment: equipment,
                                        limitations: [.knee: true])
                        let plan = ProgramGenerator.generate(profile: p, catalog: catalog)
                        #expect(plan == ProgramGenerator.generate(profile: p, catalog: catalog), "Non deterministico")
                        #expect(plan.sessions.count == days)
                        for session in plan.sessions {
                            #expect(session.estimatedSeconds <= 60 * 60 + 1e-6)
                            let ids = session.exercises.map(\.exerciseID)
                            #expect(Set(ids).count == ids.count, "Esercizio ripetuto nella stessa sessione")
                            var seenIsolation = false
                            for planned in session.exercises {
                                guard let exercise = catalog[planned.exerciseID] else {
                                    Issue.record("Esercizio sconosciuto \(planned.exerciseID)")
                                    continue
                                }
                                #expect(ExerciseScoring.isEligible(exercise, profile: p))
                                #expect(!exercise.contraindicatedAreas.contains(.knee))
                                #expect((1...4).contains(planned.sets))
                                #expect(planned.repRange == ProgramGenerator.repRange(goal: goal, mechanics: exercise.mechanics))
                                if exercise.mechanics == .isolation { seenIsolation = true }
                                if exercise.mechanics == .compound { #expect(!seenIsolation, "Multiarticolari prima degli isolamenti") }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Palestra completa, ipertrofia, 4 giorni: i muscoli principali raggiungono il volume obiettivo")
    func coverage() {
        let plan = ProgramGenerator.generate(profile: profile(), catalog: catalog)
        #expect(plan.split == .upperLower)
        #expect(plan.splitReason == .daysPerWeek)
        for muscle in [MuscleGroup.chest, .lats, .upperBack, .quads, .hamstrings, .glutes, .biceps, .triceps] {
            let planned = plan.plannedWeeklySets[muscle] ?? 0
            let target = plan.targetWeeklySets[muscle] ?? 0
            #expect(planned >= target * 0.8, "\(muscle): \(planned) su \(target)")
        }
        #expect(plan.sessions.allSatisfy { !$0.exercises.isEmpty })
        #expect(plan.engineVersion == WorkoutEngineInfo.algorithmVersion)
    }

    @Test("Settimana di deload: serie ridotte e RIR 3")
    func deload() {
        let normal = ProgramGenerator.generate(profile: profile(), catalog: catalog, programWeek: 0)
        let deload = ProgramGenerator.generate(profile: profile(), catalog: catalog, programWeek: 4)
        #expect(deload.isDeload)
        let normalSets = normal.sessions.flatMap(\.exercises).map(\.sets).reduce(0, +)
        let deloadSets = deload.sessions.flatMap(\.exercises).map(\.sets).reduce(0, +)
        #expect(deloadSets < normalSets)
        #expect(deload.sessions.flatMap(\.exercises).allSatisfy { $0.targetRIR == 3 })
    }

    @Test("Esercizi a tempo ricevono una durata target; sessioni brevissime restano nel budget")
    func timedAndShort() {
        let plan = ProgramGenerator.generate(profile: profile(goal: .generalFitness, days: 3, minutes: 15, equipment: [.bodyweight]),
                                             catalog: catalog)
        for session in plan.sessions {
            #expect(session.estimatedSeconds <= 15 * 60 + 1e-6)
        }
        let core = ProgramGenerator.generate(profile: profile(days: 2, minutes: 90, equipment: [.bodyweight]), catalog: catalog)
        let timed = core.sessions.flatMap(\.exercises).filter { catalog[$0.exerciseID]?.loadType == .timed }
        #expect(timed.allSatisfy { $0.targetDurationSeconds == 30 })
    }
}
