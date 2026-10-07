import CheckInEngine
import Foundation
import JevDomain

/// Fatti e richiesta per JEV a partire dal check-in: i numeri vengono dalle metriche degli
/// engine e sono formattati qui (unità metriche, separatore decimale italiano).
public enum CheckInCoach {
    static func format(_ value: Double, decimals: Int, unit: String) -> String {
        let text = String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",")
        return unit.isEmpty ? text : "\(text) \(unit)"
    }

    public static func facts(_ m: CheckInEvaluator.Metrics, result: CheckInEvaluator.Result) -> [CoachFact] {
        var facts: [CoachFact] = [
            CoachFact(id: "current_target_kcal", label: "Target attuale", value: m.currentTargetKcal, unit: "kcal",
                      formatted: format(m.currentTargetKcal, decimals: 0, unit: "kcal")),
            CoachFact(id: "proposed_target_kcal", label: "Target proposto", value: m.proposedTargetKcal, unit: "kcal",
                      formatted: format(m.proposedTargetKcal, decimals: 0, unit: "kcal")),
            CoachFact(id: "expenditure_kcal", label: "Dispendio stimato", value: m.expenditureKcal, unit: "kcal",
                      formatted: format(m.expenditureKcal, decimals: 0, unit: "kcal")),
            CoachFact(id: "complete_logged_days", label: "Giorni registrati completi", value: Double(m.completeLoggedDays),
                      unit: "", formatted: format(Double(m.completeLoggedDays), decimals: 0, unit: "")),
            CoachFact(id: "weigh_ins", label: "Pesate", value: Double(m.weighIns), unit: "",
                      formatted: format(Double(m.weighIns), decimals: 0, unit: "")),
        ]
        if let intake = m.averageIntakeKcal {
            facts.append(CoachFact(id: "average_intake_kcal", label: "Apporto medio", value: intake, unit: "kcal",
                                   formatted: format(intake, decimals: 0, unit: "kcal")))
        }
        if let loss = m.lossPercentThisWeek {
            facts.append(CoachFact(id: "loss_percent_week", label: "Variazione settimanale", value: -loss, unit: "%",
                                   formatted: format(-loss, decimals: 1, unit: "%")))
        }
        if let trend = m.trendWeightKg {
            facts.append(CoachFact(id: "trend_weight_kg", label: "Peso (trend)", value: trend, unit: "kg",
                                   formatted: format(trend, decimals: 1, unit: "kg")))
        }
        if let readiness = m.readinessAverage7Days {
            facts.append(CoachFact(id: "readiness_7d", label: "Readiness media", value: readiness, unit: "",
                                   formatted: format(readiness, decimals: 0, unit: "")))
        }
        if let recovery = m.recoveryAveragePercent {
            facts.append(CoachFact(id: "recovery_avg", label: "Recupero medio", value: recovery, unit: "%",
                                   formatted: format(recovery, decimals: 0, unit: "%")))
        }
        for decision in result.decisions {
            if let delta = decision.deltaKcal {
                facts.append(CoachFact(id: "delta_kcal", label: "Variazione calorie", value: delta, unit: "kcal",
                                       formatted: (delta > 0 ? "+" : "") + format(delta, decimals: 0, unit: "kcal")))
            }
        }
        return facts
    }

    /// Richiesta per la narrazione del check-in (tier analysis).
    public static func request(_ m: CheckInEvaluator.Metrics, result: CheckInEvaluator.Result) -> CoachRequest {
        CoachRequest(tier: .analysis, purpose: "check_in_explanation", facts: facts(m, result: result),
                     reasonCodes: result.decisions.flatMap(\.reasonCodes))
    }
}
