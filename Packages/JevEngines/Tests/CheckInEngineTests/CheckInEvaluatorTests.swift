import JevDomain
import Testing
@testable import CheckInEngine

@Suite("Weekly check-in: priorità, safety, isteresi (§5.10)")
struct CheckInEvaluatorTests {
    private func metrics(
        days: Int = 6, weighIns: Int = 5, current: Double = 2200, proposed: Double = 2200, expenditure: Double = 2600,
        goal: GoalType = .fatLoss
    ) -> CheckInEvaluator.Metrics {
        CheckInEvaluator.Metrics(
            completeLoggedDays: days, weighIns: weighIns, lossPercentThisWeek: 0.5, lossPercentLastWeek: 0.5,
            averageIntakeKcal: 2150, trendBMI: 24, goal: goal, currentTargetKcal: current, proposedTargetKcal: proposed,
            expenditureKcal: expenditure, floorKcal: 1700, expenditureConfidence: 0.7, currentProteinG: 160,
            proposedProteinG: 162, readinessAverage7Days: 70, recoveryAveragePercent: 80, adherence: 0.9
        )
    }

    private func types(_ result: CheckInEvaluator.Result) -> [CheckInDecisionType] { result.decisions.map(\.type) }

    @Test("Dati insufficienti: nutrizione NO ACTION, l'allenamento si valuta comunque")
    func insufficient() {
        let result = CheckInEvaluator.evaluate(metrics(days: 3))
        #expect(types(result) == [.noAction, .keep])
        #expect(result.decisions[0].reasonCodes == ["checkin.nutrition.insufficient_data"])
        #expect(CheckInEvaluator.evaluate(metrics(weighIns: 2)).decisions[0].type == .noAction)
    }

    @Test("Nutrizione: dead band, aumento e diminuzione limitati a ±150, mai sotto il floor")
    func nutrition() {
        #expect(types(CheckInEvaluator.evaluate(metrics(proposed: 2230))).first == .keep)
        let up = CheckInEvaluator.evaluate(metrics(proposed: 2500))
        #expect(up.decisions[0].type == .increaseCalories && up.decisions[0].deltaKcal == 150)
        let down = CheckInEvaluator.evaluate(metrics(proposed: 2100))
        #expect(down.decisions[0].type == .decreaseCalories && down.decisions[0].deltaKcal == -100)
        let floored = CheckInEvaluator.evaluate(metrics(current: 1750, proposed: 1500))
        #expect(floored.decisions[0].deltaKcal == -50)
    }

    @Test("Safety: perdita rapida per due settimane o intake molto basso → solo aumento")
    func safety() {
        var fast = metrics(proposed: 1900)
        fast.lossPercentThisWeek = 1.8
        fast.lossPercentLastWeek = 1.6
        let result = CheckInEvaluator.evaluate(fast)
        #expect(result.safetyTriggered)
        #expect(result.decisions[0].type == .increaseCalories)
        #expect((result.decisions[0].deltaKcal ?? 0) > 0)
        #expect(!types(result).contains(.decreaseCalories))
        var low = metrics()
        low.averageIntakeKcal = 800
        #expect(CheckInEvaluator.evaluate(low).decisions[0].reasonCodes.contains("checkin.safety.low_intake"))
        var thin = metrics()
        thin.trendBMI = 18
        thin.pregnancyOrLactation = true
        let codes = CheckInEvaluator.evaluate(thin).decisions[0].reasonCodes
        #expect(codes.contains("checkin.safety.underweight") && codes.contains("checkin.safety.pregnancy"))
        // Un calo forte di una sola settimana non basta.
        var once = metrics()
        once.lossPercentThisWeek = 2
        #expect(!CheckInEvaluator.evaluate(once).safetyTriggered)
    }

    @Test("Obiettivo raggiunto e cambio del target proteico → CHANGE MACROS")
    func macros() {
        var reached = metrics()
        reached.trendWeightKg = 75.3
        reached.targetWeightKg = 75
        #expect(types(CheckInEvaluator.evaluate(reached)).contains(.changeMacros))
        var protein = metrics()
        protein.proposedProteinG = 190
        let result = CheckInEvaluator.evaluate(protein)
        #expect(result.decisions.contains { $0.type == .changeMacros && $0.reasonCodes == ["checkin.nutrition.protein_change"] })
    }

    @Test("Allenamento: deload in corso, deload dovuto, riduzione, aumento, cambio esercizio")
    func training() {
        var deloadWeek = metrics()
        deloadWeek.isDeloadWeek = true
        #expect(CheckInEvaluator.evaluate(deloadWeek).decisions.last?.reasonCodes == ["checkin.training.deload_week"])
        var due = metrics()
        due.deloadDue = true
        #expect(types(CheckInEvaluator.evaluate(due)).contains(.deload))
        var plateau = metrics()
        plateau.plateauShare = 0.6
        #expect(CheckInEvaluator.evaluate(plateau).decisions.last?.reasonCodes == ["checkin.training.deload_plateau"])
        var tired = metrics()
        tired.readinessAverage7Days = 45
        tired.recoveryAveragePercent = 55
        let tiredResult = CheckInEvaluator.evaluate(tired)
        #expect(tiredResult.decisions.contains { $0.type == .deload || $0.type == .reduceTrainingLoad })
        var lowRecovery = metrics()
        lowRecovery.readinessAverage7Days = 48
        lowRecovery.recoveryAveragePercent = 50
        var config = EngineConfig.current
        config.checkIn.deloadReadinessBelow = 30
        let reduce = CheckInEvaluator.evaluate(lowRecovery, config: config)
        #expect(reduce.decisions.contains { $0.type == .reduceTrainingLoad && $0.setsChangeFraction == -0.2 })
        var good = metrics()
        good.progressionPositive = true
        #expect(CheckInEvaluator.evaluate(good).decisions.contains { $0.type == .increaseTrainingLoad && $0.setsChangeFraction == 0.2 })
        var pain = metrics()
        pain.painReportsByExercise = ["barbell_back_squat": 2, "lateral_raise": 1]
        pain.plateauExercises = ["barbell_bench_press"]
        let changes = CheckInEvaluator.evaluate(pain).decisions.filter { $0.type == .changeExercise }
        #expect(changes.map(\.exerciseID) == ["barbell_back_squat", "barbell_bench_press"])
        #expect(changes[0].reasonCodes == ["checkin.training.change_pain"])
    }

    @Test("Isteresi: decisione rifiutata non riproposta finché gli input non cambiano")
    func hysteresis() {
        let base = metrics(proposed: 2500)
        let first = CheckInEvaluator.evaluate(base)
        let decision = first.decisions[0]
        let rejection = CheckInEvaluator.Rejection(decisionKey: decision.key, metrics: base)
        let again = CheckInEvaluator.evaluate(base, rejected: [rejection])
        #expect(!types(again).contains(.increaseCalories))
        #expect(again.suppressed == [decision.key])
        let changed = CheckInEvaluator.evaluate(metrics(proposed: 2600), rejected: [rejection])
        #expect(types(changed).contains(.increaseCalories))
        var good = metrics()
        good.progressionPositive = true
        let training = CheckInEvaluator.Rejection(decisionKey: "increase_training_load:", metrics: good)
        #expect(!types(CheckInEvaluator.evaluate(good, rejected: [training])).contains(.increaseTrainingLoad))
        var better = good
        better.readinessAverage7Days = 85
        #expect(types(CheckInEvaluator.evaluate(better, rejected: [training])).contains(.increaseTrainingLoad))
        // La safety ignora l'isteresi.
        var fast = base
        fast.lossPercentThisWeek = 2
        fast.lossPercentLastWeek = 2
        let safety = CheckInEvaluator.Rejection(decisionKey: "increase_calories:", metrics: fast)
        #expect(types(CheckInEvaluator.evaluate(fast, rejected: [safety])).first == .increaseCalories)
        #expect(CheckInEvaluator.inputsChanged(from: base, to: base, for: .keep, config: .current))
    }
}
