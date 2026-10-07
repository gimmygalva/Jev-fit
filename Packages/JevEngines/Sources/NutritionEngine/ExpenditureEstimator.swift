import Foundation
import JevCore
import JevDomain

/// Expenditure (TDEE) adattiva con un unico filtro stato-spazio (§5.2).
///
/// Stato `[M, E]`: massa di tessuto (kg) ed expenditure (kcal/giorno).
/// - `M(t+1) = M(t) + (Intake(t) − E(t)) / ρ + w` · `E(t+1) = E(t) + v`
/// - misura: peso in bilancia = M + rumore (acqua, glicogeno).
/// - Giorno non registrato o incompleto: intake ignoto → nessun termine di bilancio e incertezza
///   aumentata su M (nessun valore inventato).
/// - Intake implausibile (> 6.000 kcal o > 2,5 × E) non confermato → trattato come ignoto.
/// Il prior perde importanza da solo: è la condizione iniziale del filtro.
public enum ExpenditureEstimator {
    public struct Day: Sendable, Hashable {
        public var dayKey: DayKey
        /// Calorie registrate; `nil` se il giorno non è registrato.
        public var intakeKcal: Double?
        /// Il giorno è marcato completo (solo i giorni completi informano l'expenditure).
        public var isComplete: Bool
        /// L'utente ha confermato un intake fuori scala (QA-03).
        public var intakeConfirmed: Bool
        /// Pesata del giorno (prima del giorno), se presente.
        public var weightKg: Double?

        public init(dayKey: DayKey, intakeKcal: Double? = nil, isComplete: Bool = false,
                    intakeConfirmed: Bool = false, weightKg: Double? = nil) {
            self.dayKey = dayKey
            self.intakeKcal = intakeKcal
            self.isComplete = isComplete
            self.intakeConfirmed = intakeConfirmed
            self.weightKg = weightKg
        }
    }

    public struct Result: Sendable, Hashable {
        public var expenditureKcal: Double
        public var sdKcal: Double
        /// 0…0,99 (§5.2): `clamp(1 − σ / 400, 0, 0,99) × completezza`.
        public var confidence: Double
        public var label: ConfidenceLabel
        /// Quota di giorni completi negli ultimi 21.
        public var completeness: Double
        public var weighIns: Int
        public var lastDay: DayKey
    }

    /// Un intake è plausibile se non supera 6.000 kcal né 2,5 × l'expenditure stimata.
    public static func isPlausible(intakeKcal: Double, expenditureKcal: Double, config: EngineConfig = .current) -> Bool {
        let n = config.nutrition
        return intakeKcal >= 0 && intakeKcal <= n.implausibleDailyIntakeKcal
            && intakeKcal <= n.implausibleIntakeToExpenditureRatio * max(expenditureKcal, 1)
    }

    /// Stima dalla serie di giorni (anche non contigui: i giorni mancanti sono ignoti).
    public static func estimate(
        days input: [Day], prior: (kcal: Double, sd: Double), config: EngineConfig = .current
    ) -> Result? {
        let n = config.nutrition
        let days = Dictionary(input.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
        guard let start = days.keys.min(), let end = days.keys.max() else { return nil }
        let rho = n.energyDensityKcalPerKg
        var mass: Double?
        var expenditure = prior.kcal
        var covariance = Matrix(a: 0, b: 0, c: 0, d: prior.sd * prior.sd)
        var weighIns = 0
        var recentIntakes: [Double?] = []
        var noisyUntil: DayKey?

        var day = start
        var previous: Day?
        while day <= end {
            let today = days[day]
            if let m = mass {
                // Predizione dal giorno precedente con l'intake di ieri.
                let intake = previous.flatMap { usableIntake($0, expenditure: expenditure, config: config) }
                let q = covariance
                let qm = n.tissueProcessNoiseKg * n.tissueProcessNoiseKg
                let qe = n.expenditureDriftKcalPerDay * n.expenditureDriftKcalPerDay
                if let intake {
                    mass = m + (intake - expenditure) / rho
                    let f = -1 / rho
                    covariance = Matrix(
                        a: q.a + f * (q.b + q.c) + f * f * q.d + qm, b: q.b + f * q.d,
                        c: q.c + f * q.d, d: q.d + qe
                    )
                } else {
                    let unknown = n.unknownIntakeSDKcal / rho
                    covariance = Matrix(a: q.a + qm + unknown * unknown, b: q.b, c: q.c, d: q.d + qe)
                }
                recentIntakes.append(intake)
                if intakeShift(recentIntakes, threshold: n.intakeChangeThresholdKcal) {
                    noisyUntil = day.adding(days: 14)
                }
            }
            if let weight = today?.weightKg, config.safety.plausibleWeightKg.contains(weight) {
                weighIns += 1
                if let m = mass {
                    let noise = (noisyUntil.map { day <= $0 } ?? false) ? n.intakeChangeScaleNoiseKg : n.scaleNoiseKg
                    let r = noise * noise
                    let s = covariance.a + r
                    let k = (covariance.a / s, covariance.c / s)
                    let innovation = weight - m
                    mass = m + k.0 * innovation
                    expenditure += k.1 * innovation
                    // Joseph con H = [1, 0]
                    let a = Matrix(a: 1 - k.0, b: 0, c: -k.1, d: 1)
                    let krk = Matrix(a: k.0 * k.0 * r, b: k.0 * k.1 * r, c: k.1 * k.0 * r, d: k.1 * k.1 * r)
                    covariance = (a * covariance * a.transposed + krk).symmetrized
                } else {
                    mass = weight
                    covariance.a = n.scaleNoiseKg * n.scaleNoiseKg
                }
            }
            previous = today ?? Day(dayKey: day)
            day = day.adding(days: 1)
        }

        let sd = max(covariance.d, 0).squareRoot()
        let windowStart = end.adding(days: -(n.completenessWindowDays - 1))
        let window = max(min(n.completenessWindowDays, start.days(to: end) + 1), 1)
        let complete = days.values.filter { $0.dayKey >= windowStart && $0.isComplete && $0.intakeKcal != nil }.count
        let completeness = min(Double(complete) / Double(window), 1)
        let raw = RobustStatistics.clamp(1 - sd / n.expenditureConfidenceReferenceKcal, 0...0.99)
        let confidence = weighIns >= 2 ? raw * completeness : 0
        return Result(
            expenditureKcal: expenditure, sdKcal: sd, confidence: confidence,
            label: config.confidence.label(for: confidence), completeness: completeness,
            weighIns: weighIns, lastDay: end
        )
    }

    /// Intake utilizzabile: giorno completo, registrato, plausibile o confermato.
    static func usableIntake(_ day: Day, expenditure: Double, config: EngineConfig) -> Double? {
        guard day.isComplete, let intake = day.intakeKcal, intake.isFinite, intake >= 0 else { return nil }
        guard day.intakeConfirmed || isPlausible(intakeKcal: intake, expenditureKcal: expenditure, config: config) else {
            return nil
        }
        return intake
    }

    /// La media degli ultimi 7 intake noti differisce di oltre la soglia dalla media dei 7 precedenti.
    static func intakeShift(_ intakes: [Double?], threshold: Double) -> Bool {
        guard intakes.count >= 14 else { return false }
        let recent = intakes.suffix(7).compactMap { $0 }
        let before = intakes.dropLast(7).suffix(7).compactMap { $0 }
        guard recent.count >= 4, before.count >= 4 else { return false }
        let a = recent.reduce(0, +) / Double(recent.count)
        let b = before.reduce(0, +) / Double(before.count)
        return abs(a - b) > threshold
    }

    struct Matrix {
        var a: Double, b: Double, c: Double, d: Double
        var transposed: Matrix { Matrix(a: a, b: c, c: b, d: d) }
        var symmetrized: Matrix {
            let off = (b + c) / 2
            return Matrix(a: a, b: off, c: off, d: d)
        }

        static func * (l: Matrix, r: Matrix) -> Matrix {
            Matrix(a: l.a * r.a + l.b * r.c, b: l.a * r.b + l.b * r.d, c: l.c * r.a + l.d * r.c, d: l.c * r.b + l.d * r.d)
        }

        static func + (l: Matrix, r: Matrix) -> Matrix {
            Matrix(a: l.a + r.a, b: l.b + r.b, c: l.c + r.c, d: l.d + r.d)
        }
    }
}
