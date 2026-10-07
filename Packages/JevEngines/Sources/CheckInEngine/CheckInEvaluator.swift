import Foundation
import JevCore
import JevDomain

/// Weekly check-in (§5.10): tabella decisionale valutata in ordine di priorità, il primo gate
/// che scatta vincola i successivi. Funzione pura: tutte le metriche arrivano già calcolate
/// dagli altri engine; le soglie sono in `EngineConfig.checkIn`.
public enum CheckInEvaluator {
    /// Metriche della settimana appena conclusa.
    public struct Metrics: Sendable, Hashable, Codable {
        // Sufficienza dati
        public var completeLoggedDays: Int
        public var weighIns: Int
        // Safety (solo giorni completi)
        /// Perdita di peso (% del peso a settimana, positivo = perdita) di questa e della scorsa settimana.
        public var lossPercentThisWeek: Double?
        public var lossPercentLastWeek: Double?
        public var averageIntakeKcal: Double?
        public var trendBMI: Double?
        public var pregnancyOrLactation: Bool
        // Nutrizione
        public var goal: GoalType
        public var currentTargetKcal: Double
        /// Nuovo target proposto dal NutritionEngine (expenditure aggiornata + ritmo target).
        public var proposedTargetKcal: Double
        public var expenditureKcal: Double
        public var floorKcal: Double
        public var expenditureConfidence: Double
        public var trendWeightKg: Double?
        public var targetWeightKg: Double?
        public var currentProteinG: Double
        public var proposedProteinG: Double
        // Allenamento
        public var isDeloadWeek: Bool
        /// Il mesociclo è arrivato al deload (dopo l'ultima settimana di programma).
        public var deloadDue: Bool
        public var readinessAverage7Days: Double?
        public var recoveryAveragePercent: Double?
        /// Sessioni fatte / pianificate (0…1).
        public var adherence: Double?
        public var progressionPositive: Bool
        /// Quota degli esercizi principali in plateau (0…1).
        public var plateauShare: Double
        public var plateauExercises: [String]
        /// Segnalazioni di dolore negli ultimi 14 giorni per esercizio.
        public var painReportsByExercise: [String: Int]

        public init(
            completeLoggedDays: Int, weighIns: Int, lossPercentThisWeek: Double? = nil, lossPercentLastWeek: Double? = nil,
            averageIntakeKcal: Double? = nil, trendBMI: Double? = nil, pregnancyOrLactation: Bool = false,
            goal: GoalType, currentTargetKcal: Double, proposedTargetKcal: Double, expenditureKcal: Double,
            floorKcal: Double, expenditureConfidence: Double = 0.5, trendWeightKg: Double? = nil,
            targetWeightKg: Double? = nil, currentProteinG: Double = 0, proposedProteinG: Double = 0,
            isDeloadWeek: Bool = false, deloadDue: Bool = false, readinessAverage7Days: Double? = nil,
            recoveryAveragePercent: Double? = nil, adherence: Double? = nil, progressionPositive: Bool = false,
            plateauShare: Double = 0, plateauExercises: [String] = [], painReportsByExercise: [String: Int] = [:]
        ) {
            self.completeLoggedDays = completeLoggedDays
            self.weighIns = weighIns
            self.lossPercentThisWeek = lossPercentThisWeek
            self.lossPercentLastWeek = lossPercentLastWeek
            self.averageIntakeKcal = averageIntakeKcal
            self.trendBMI = trendBMI
            self.pregnancyOrLactation = pregnancyOrLactation
            self.goal = goal
            self.currentTargetKcal = currentTargetKcal
            self.proposedTargetKcal = proposedTargetKcal
            self.expenditureKcal = expenditureKcal
            self.floorKcal = floorKcal
            self.expenditureConfidence = expenditureConfidence
            self.trendWeightKg = trendWeightKg
            self.targetWeightKg = targetWeightKg
            self.currentProteinG = currentProteinG
            self.proposedProteinG = proposedProteinG
            self.isDeloadWeek = isDeloadWeek
            self.deloadDue = deloadDue
            self.readinessAverage7Days = readinessAverage7Days
            self.recoveryAveragePercent = recoveryAveragePercent
            self.adherence = adherence
            self.progressionPositive = progressionPositive
            self.plateauShare = plateauShare
            self.plateauExercises = plateauExercises
            self.painReportsByExercise = painReportsByExercise
        }
    }

    public struct Decision: Sendable, Hashable, Codable {
        public var type: CheckInDecisionType
        /// Variazione delle calorie giornaliere (nutrizione).
        public var deltaKcal: Double?
        /// Variazione relativa delle serie (allenamento: −0,20 / +0,20).
        public var setsChangeFraction: Double?
        public var exerciseID: String?
        public var reasonCodes: [String]
        /// Chiavi delle metriche usate (diventano fatti per JEV).
        public var factsUsed: [String]
        public var confidence: Double

        public init(type: CheckInDecisionType, deltaKcal: Double? = nil, setsChangeFraction: Double? = nil,
                    exerciseID: String? = nil, reasonCodes: [String], factsUsed: [String] = [], confidence: Double = 1) {
            self.type = type
            self.deltaKcal = deltaKcal
            self.setsChangeFraction = setsChangeFraction
            self.exerciseID = exerciseID
            self.reasonCodes = reasonCodes
            self.factsUsed = factsUsed
            self.confidence = confidence
        }

        /// Chiave per l'isteresi: stessa decisione sullo stesso oggetto.
        public var key: String { "\(type.rawValue):\(exerciseID ?? "")" }
    }

    /// Una decisione rifiutata in passato con le metriche di allora (isteresi).
    public struct Rejection: Sendable, Hashable, Codable {
        public var decisionKey: String
        public var metrics: Metrics

        public init(decisionKey: String, metrics: Metrics) {
            self.decisionKey = decisionKey
            self.metrics = metrics
        }
    }

    public struct Result: Sendable, Hashable, Codable {
        public var decisions: [Decision]
        /// Il gate di sicurezza è scattato: la UI mostra il messaggio "consulta un professionista".
        public var safetyTriggered: Bool
        /// Decisioni non riproposte perché rifiutate e con input invariati.
        public var suppressed: [String]
    }

    public static func evaluate(_ m: Metrics, rejected: [Rejection] = [], config: EngineConfig = .current) -> Result {
        let c = config.checkIn
        var decisions: [Decision] = []
        var safety = false

        // 1. Sufficienza dati (solo nutrizione).
        let enoughData = m.completeLoggedDays >= c.minimumCompleteLoggedDays && m.weighIns >= c.minimumWeighIns

        // 2. Safety gate.
        let inDeficit = m.currentTargetKcal < m.expenditureKcal - 1
        var safetyCodes: [String] = []
        if let thisWeek = m.lossPercentThisWeek, let lastWeek = m.lossPercentLastWeek,
           thisWeek > c.safetyMaxLossPercentPerWeek, lastWeek > c.safetyMaxLossPercentPerWeek {
            safetyCodes.append("checkin.safety.fast_loss")
        }
        if let intake = m.averageIntakeKcal, m.completeLoggedDays > 0, intake < c.safetyMinAverageIntakeKcal {
            safetyCodes.append("checkin.safety.low_intake")
        }
        if inDeficit, let bmi = m.trendBMI, bmi < c.underweightBMI { safetyCodes.append("checkin.safety.underweight") }
        if inDeficit, m.pregnancyOrLactation { safetyCodes.append("checkin.safety.pregnancy") }

        if !safetyCodes.isEmpty {
            safety = true
            // Verso il ritmo target o il mantenimento, mai una diminuzione; passo limitato.
            let toward = max(m.proposedTargetKcal, inDeficit ? m.expenditureKcal : m.currentTargetKcal)
            let step = min(max(toward - m.currentTargetKcal, config.nutrition.adjustmentDeadBandKcal),
                           config.nutrition.automaticAdjustmentLimitKcal)
            decisions.append(Decision(type: .increaseCalories, deltaKcal: step, reasonCodes: safetyCodes,
                                      factsUsed: ["current_target_kcal", "average_intake_kcal", "loss_percent_week"]))
        } else if !enoughData {
            decisions.append(Decision(type: .noAction, reasonCodes: ["checkin.nutrition.insufficient_data"],
                                      factsUsed: ["complete_logged_days", "weigh_ins"], confidence: 0))
        } else {
            decisions.append(contentsOf: nutritionDecisions(m, config: config))
        }

        // 3–5. Allenamento.
        decisions.append(contentsOf: trainingDecisions(m, config: config))

        // Isteresi: una decisione rifiutata non torna finché gli input rilevanti non cambiano.
        var suppressed: [String] = []
        let filtered = decisions.filter { decision in
            guard decision.type != .keep, decision.type != .noAction, !safety || decision.type.area != .nutrition else {
                return true
            }
            if let rejection = rejected.first(where: { $0.decisionKey == decision.key }),
               !inputsChanged(from: rejection.metrics, to: m, for: decision.type, config: config) {
                suppressed.append(decision.key)
                return false
            }
            return true
        }
        return Result(decisions: filtered, safetyTriggered: safety, suppressed: suppressed)
    }

    static func nutritionDecisions(_ m: Metrics, config: EngineConfig) -> [Decision] {
        let c = config.checkIn
        var result: [Decision] = []
        let facts = ["current_target_kcal", "proposed_target_kcal", "expenditure_kcal"]
        if let trend = m.trendWeightKg, let target = m.targetWeightKg, m.goal != .maintenance,
           abs(trend - target) <= c.goalReachedToleranceKg {
            result.append(Decision(type: .changeMacros, reasonCodes: ["checkin.nutrition.goal_reached"],
                                   factsUsed: ["trend_weight_kg", "target_weight_kg"], confidence: m.expenditureConfidence))
        }
        let adjustment = NutritionAdjustment.step(current: m.currentTargetKcal, proposed: m.proposedTargetKcal,
                                                  floor: m.floorKcal, config: config)
        if adjustment == 0 {
            result.append(Decision(type: .keep, reasonCodes: ["checkin.nutrition.keep"], factsUsed: facts,
                                   confidence: m.expenditureConfidence))
        } else {
            result.append(Decision(
                type: adjustment > 0 ? .increaseCalories : .decreaseCalories, deltaKcal: adjustment,
                reasonCodes: [adjustment > 0 ? "checkin.nutrition.increase" : "checkin.nutrition.decrease"],
                factsUsed: facts, confidence: m.expenditureConfidence
            ))
        }
        if abs(m.proposedProteinG - m.currentProteinG) > c.proteinTargetChangeThresholdGrams,
           !result.contains(where: { $0.type == .changeMacros }) {
            result.append(Decision(type: .changeMacros, reasonCodes: ["checkin.nutrition.protein_change"],
                                   factsUsed: ["current_protein_g", "proposed_protein_g"], confidence: m.expenditureConfidence))
        }
        return result
    }

    static func trainingDecisions(_ m: Metrics, config: EngineConfig) -> [Decision] {
        let c = config.checkIn
        // 3. Deload in corso: niente decisioni di allenamento.
        if m.isDeloadWeek {
            return [Decision(type: .noAction, reasonCodes: ["checkin.training.deload_week"], confidence: 1)]
        }
        let readiness = m.readinessAverage7Days
        let recovery = m.recoveryAveragePercent
        // 5. Deload: fine mesociclo, readiness bassa o molti plateau.
        if m.deloadDue || (readiness.map { $0 < c.deloadReadinessBelow } ?? false) || m.plateauShare >= c.deloadPlateauShare {
            let code = m.deloadDue ? "checkin.training.deload_mesocycle"
                : m.plateauShare >= c.deloadPlateauShare ? "checkin.training.deload_plateau" : "checkin.training.deload_readiness"
            return [Decision(type: .deload, reasonCodes: [code], factsUsed: ["readiness_7d", "plateau_share"])]
        }
        var result: [Decision] = []
        if let readiness, let recovery, readiness < c.reduceLoadReadinessBelow, recovery < c.reduceLoadRecoveryBelow {
            result.append(Decision(type: .reduceTrainingLoad, setsChangeFraction: -c.trainingLoadSetChangeFraction,
                                   reasonCodes: ["checkin.training.reduce"], factsUsed: ["readiness_7d", "recovery_avg"]))
        } else if let readiness, let recovery, let adherence = m.adherence, readiness >= c.increaseLoadReadinessFrom,
                  adherence >= c.increaseLoadAdherenceFrom, recovery >= c.increaseLoadRecoveryFrom, m.progressionPositive {
            result.append(Decision(type: .increaseTrainingLoad, setsChangeFraction: c.trainingLoadSetChangeFraction,
                                   reasonCodes: ["checkin.training.increase"],
                                   factsUsed: ["readiness_7d", "recovery_avg", "adherence"]))
        }
        let painful = m.painReportsByExercise.filter { $0.value >= 2 }.keys.sorted()
        for exercise in Set(painful + m.plateauExercises).sorted() {
            let pain = painful.contains(exercise)
            result.append(Decision(type: .changeExercise, exerciseID: exercise,
                                   reasonCodes: [pain ? "checkin.training.change_pain" : "checkin.training.change_plateau"]))
        }
        if result.isEmpty {
            result.append(Decision(type: .keep, reasonCodes: ["checkin.training.keep"]))
        }
        return result
    }

    /// Gli input rilevanti per la decisione sono cambiati oltre la soglia?
    static func inputsChanged(from old: Metrics, to new: Metrics, for type: CheckInDecisionType, config: EngineConfig) -> Bool {
        switch type.area {
        case .nutrition:
            return abs(new.proposedTargetKcal - old.proposedTargetKcal) >= config.nutrition.adjustmentDeadBandKcal
                || abs(new.proposedProteinG - old.proposedProteinG) > config.checkIn.proteinTargetChangeThresholdGrams
                || new.goal != old.goal
        case .training:
            let readinessDelta = abs((new.readinessAverage7Days ?? 0) - (old.readinessAverage7Days ?? 0))
            let recoveryDelta = abs((new.recoveryAveragePercent ?? 0) - (old.recoveryAveragePercent ?? 0))
            return readinessDelta >= 10 || recoveryDelta >= 10 || new.deloadDue != old.deloadDue
                || new.painReportsByExercise != old.painReportsByExercise
        case .any:
            return true
        }
    }
}

/// Passo di aggiustamento delle calorie (dead band e limite automatico, mai sotto il floor).
enum NutritionAdjustment {
    static func step(current: Double, proposed: Double, floor: Double, config: EngineConfig) -> Double {
        let n = config.nutrition
        let delta = proposed - current
        guard abs(delta) >= n.adjustmentDeadBandKcal else { return 0 }
        let limited = min(max(delta, -n.automaticAdjustmentLimitKcal), n.automaticAdjustmentLimitKcal)
        let next = max(current + limited, floor)
        return ((next - current) / 10).rounded() * 10
    }
}
