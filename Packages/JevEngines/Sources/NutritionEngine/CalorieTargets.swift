import Foundation
import JevCore
import JevDomain

/// Target calorico, calorie cycling e aggiustamento settimanale (§5.3).
public enum CalorieTargets {
    public struct DailyTarget: Sendable, Hashable {
        /// Media giornaliera, arrotondata a 10 kcal.
        public var kcal: Double
        /// Ritmo usato dopo i limiti dell'obiettivo (% del peso a settimana, negativo = perdita).
        public var ratePercentPerWeek: Double
        /// Il floor `max(BMR, 1.200)` ha alzato il target.
        public var floorApplied: Bool
        public var floorKcal: Double
    }

    /// Floor assoluto: `max(BMR stimato, 1.200 kcal)`.
    public static func floor(bmrKcal: Double, config: EngineConfig = .current) -> Double {
        max(bmrKcal, config.nutrition.absoluteFloorKcal)
    }

    /// `target = E + ritmo × peso × ρ / 7`, ritmo riportato nei limiti dell'obiettivo.
    /// Se il deficit non è consentito (gate di sicurezza) il target non scende sotto E.
    public static func dailyTarget(
        expenditureKcal: Double, weightKg: Double, goal: GoalType, ratePercentPerWeek: Double,
        bmrKcal: Double, deficitAllowed: Bool = true, config: EngineConfig = .current
    ) -> DailyTarget {
        var rate = GoalSafety.clampRate(ratePercentPerWeek, for: goal, config: config)
        if !deficitAllowed { rate = max(rate, 0) }
        let rateKgPerWeek = rate / 100 * weightKg
        let raw = expenditureKcal + rateKgPerWeek * config.nutrition.energyDensityKcalPerKg / 7
        let minimum = floor(bmrKcal: bmrKcal, config: config)
        let floored = max(raw, minimum)
        return DailyTarget(
            kcal: roundUp10(floored, minimum: minimum), ratePercentPerWeek: rate,
            floorApplied: raw < minimum, floorKcal: minimum
        )
    }

    // MARK: Calorie cycling

    public struct Cycle: Sendable, Hashable {
        /// Target per giorno, nell'ordine dello schema; la somma è esattamente `giorni × media`.
        public var kcal: [Double]
        /// Rapporto training/riposo effettivo dopo i limiti.
        public var effectiveRatio: Double
        /// La media non basta a tenere tutti i giorni sopra il floor.
        public var belowFloor: Bool
    }

    /// Distribuisce `average × giorni` tra giorni di allenamento e riposo con rapporto `r`
    /// (`rest = nA / (t·r + n − t)`, `training = r · rest`). Il rapporto è limitato perché nessun
    /// giorno scenda sotto il floor né si allontani più del ±15% dalla media; i valori sono
    /// arrotondati a 10 kcal e l'ultimo giorno assorbe l'errore di arrotondamento.
    public static func cycle(
        averageKcal: Double, schedule: [DayType], ratio: Double, floorKcal: Double, config: EngineConfig = .current
    ) -> Cycle {
        let n = schedule.count
        guard n > 0 else { return Cycle(kcal: [], effectiveRatio: 1, belowFloor: false) }
        let total = (averageKcal * Double(n) / 10).rounded() * 10
        let average = total / Double(n)
        let t = schedule.filter { $0 == .training }.count
        let r = effectiveRatio(average: average, days: n, trainingDays: t, ratio: ratio, floorKcal: floorKcal, config: config)
        let weightedDays: Double = Double(t) * r + Double(n - t)
        let rest: Double = Double(n) * average / weightedDays
        let training = r * rest
        let roundedTraining: Double = (training / 10).rounded() * 10
        let roundedRest: Double = (rest / 10).rounded() * 10
        var values: [Double] = schedule.map { $0 == .training ? roundedTraining : roundedRest }
        let error = total - values.reduce(0, +)
        // L'ultimo giorno assorbe l'errore, salvo che lo porti sotto il floor: allora il giorno più alto.
        var absorber = n - 1
        if values[absorber] + error < floorKcal, let highest = values.indices.max(by: { values[$0] <= values[$1] }) {
            absorber = highest
        }
        values[absorber] += error
        return Cycle(kcal: values, effectiveRatio: r, belowFloor: average < floorKcal)
    }

    /// `r_eff = min(r, ((nA / floor) − n + t) / t, r tale che nessun giorno esca dal ±15%)`, mai < 1.
    static func effectiveRatio(
        average: Double, days n: Int, trainingDays t: Int, ratio: Double, floorKcal: Double, config: EngineConfig
    ) -> Double {
        guard t > 0, t < n, ratio > 1, average > 0 else { return 1 }
        let nd = Double(n), td = Double(t)
        let dev = config.nutrition.calorieCyclingMaxDeviation
        var bound = ratio
        if floorKcal > 0 { bound = min(bound, (nd * average / floorKcal - nd + td) / td) }
        // Giorno di riposo ≥ (1 − dev) · media.
        bound = min(bound, (nd / (1 - dev) - nd + td) / td)
        // Giorno di allenamento ≤ (1 + dev) · media.
        let denominator = nd - (1 + dev) * td
        if denominator > 0 { bound = min(bound, (1 + dev) * (nd - td) / denominator) }
        return max(bound, 1)
    }

    /// Ribilanciamento a metà settimana (§5.3): i giorni già passati restano com'erano, i
    /// rimanenti si dividono il residuo della settimana senza scendere sotto il floor.
    public static func rebalance(
        weeklyTotalKcal: Double, pastDaysKcal: [Double], remaining: [DayType], ratio: Double, floorKcal: Double,
        config: EngineConfig = .current
    ) -> Cycle {
        guard !remaining.isEmpty else { return Cycle(kcal: [], effectiveRatio: 1, belowFloor: false) }
        let residual = weeklyTotalKcal - pastDaysKcal.reduce(0, +)
        let average = residual / Double(remaining.count)
        if average < floorKcal {
            let atFloor = roundUp10(floorKcal, minimum: floorKcal)
            return Cycle(kcal: remaining.map { _ in atFloor }, effectiveRatio: 1, belowFloor: true)
        }
        return cycle(averageKcal: average, schedule: remaining, ratio: ratio, floorKcal: floorKcal, config: config)
    }

    // MARK: Aggiustamento settimanale

    public struct Adjustment: Sendable, Hashable {
        public var kcal: Double
        public var deltaKcal: Double
        public var reasonCode: String
    }

    /// Variazione dal target attuale verso quello proposto: sotto la dead band (±50) nulla cambia;
    /// il passo è limitato a ±150 kcal (automatico) o ±250 (modifica manuale); mai sotto il floor.
    public static func adjust(
        currentKcal: Double, proposedKcal: Double, floorKcal: Double, manual: Bool = false,
        config: EngineConfig = .current
    ) -> Adjustment {
        let n = config.nutrition
        let delta = proposedKcal - currentKcal
        guard abs(delta) >= n.adjustmentDeadBandKcal else {
            return Adjustment(kcal: currentKcal, deltaKcal: 0, reasonCode: "target.dead_band")
        }
        let limit = manual ? n.manualAdjustmentLimitKcal : n.automaticAdjustmentLimitKcal
        let step = RobustStatistics.clamp(delta, -limit...limit)
        var next = ((currentKcal + step) / 10).rounded() * 10
        var code = abs(delta) > limit ? "target.limited" : "target.adjusted"
        if next < floorKcal {
            next = roundUp10(floorKcal, minimum: floorKcal)
            code = "target.floor"
        }
        return Adjustment(kcal: next, deltaKcal: next - currentKcal, reasonCode: code)
    }

    /// Arrotonda a 10 kcal senza scendere sotto `minimum`.
    static func roundUp10(_ value: Double, minimum: Double) -> Double {
        let rounded = (value / 10).rounded() * 10
        return rounded >= minimum ? rounded : (minimum / 10).rounded(.up) * 10
    }
}
