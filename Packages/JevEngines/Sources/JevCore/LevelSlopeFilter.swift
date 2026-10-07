import Foundation

/// Filtro di Kalman robusto a due stati (livello + pendenza) per serie irregolari nel tempo
/// (ARCHITECTURE_PLAN §5.1). Usato per il trend del peso (kg) e, in scala logaritmica, per
/// l'e1RM stabile (§5.7).
///
/// - Transizione `F = [[1, Δt], [0, 1]]` con Δt in giorni: gestisce i giorni mancanti.
/// - Rumore di processo ad accelerazione bianca: `Q = q · [[Δt³/3, Δt²/2], [Δt²/2, Δt]]`.
/// - Robustezza di Huber: se l'innovazione standardizzata supera `huberThreshold`, il rumore di
///   misura della singola osservazione viene gonfiato (la pesata anomala conta meno).
/// - Covarianza aggiornata in forma di Joseph (resta simmetrica e definita positiva).
/// - Smoother RTS all'indietro per le serie storiche dei grafici.
///
/// Le osservazioni devono avere giorni strettamente crescenti (una per giorno): chi chiama
/// le prepara (`prepare`). Valori non finiti vengono scartati.
public enum LevelSlopeFilter {
    public struct Parameters: Sendable, Hashable {
        /// Intensità del rumore di processo (unità²/giorno³): più alta = trend più reattivo.
        public var processNoise: Double
        /// Deviazione standard del rumore di misura (unità della serie).
        public var measurementSD: Double
        /// Soglia di Huber sull'innovazione standardizzata.
        public var huberThreshold: Double
        /// Incertezza iniziale della pendenza (unità/giorno).
        public var initialSlopeSD: Double

        public init(processNoise: Double, measurementSD: Double, huberThreshold: Double, initialSlopeSD: Double) {
            self.processNoise = processNoise
            self.measurementSD = measurementSD
            self.huberThreshold = huberThreshold
            self.initialSlopeSD = initialSlopeSD
        }
    }

    public struct Observation: Sendable, Hashable {
        /// Giorno dell'osservazione (es. giorni dall'epoca o dal primo dato).
        public var day: Double
        public var value: Double

        public init(day: Double, value: Double) {
            self.day = day
            self.value = value
        }
    }

    public struct Estimate: Sendable, Hashable {
        public var day: Double
        public var level: Double
        /// Pendenza per giorno.
        public var slope: Double
        public var levelSD: Double
        public var slopeSD: Double
        /// Peso di Huber usato per l'osservazione (1 = normale, < 1 = de-pesata).
        public var observationWeight: Double
    }

    /// Ordina, scarta i valori non finiti e tiene una sola osservazione per giorno (la prima
    /// dell'ordine stabile di ingresso, §5.1: "valore del giorno = prima pesata").
    public static func prepare(_ observations: [Observation]) -> [Observation] {
        let valid = observations.enumerated().filter { $0.element.day.isFinite && $0.element.value.isFinite }
        let sorted = valid.sorted { lhs, rhs in
            lhs.element.day == rhs.element.day ? lhs.offset < rhs.offset : lhs.element.day < rhs.element.day
        }
        var result: [Observation] = []
        for item in sorted where result.last?.day != item.element.day {
            result.append(item.element)
        }
        return result
    }

    /// Filtro in avanti: una stima per osservazione.
    public static func filter(_ observations: [Observation], parameters p: Parameters) -> [Estimate] {
        run(prepare(observations), parameters: p).map(\.posterior)
    }

    /// Stime lisciate (RTS): usano anche le osservazioni successive. Per i grafici.
    public static func smooth(_ observations: [Observation], parameters p: Parameters) -> [Estimate] {
        let steps = run(prepare(observations), parameters: p)
        guard steps.count > 1 else { return steps.map(\.posterior) }
        var smoothed = steps.map { (x: [$0.posterior.level, $0.posterior.slope], P: $0.posteriorCovariance) }
        for k in stride(from: steps.count - 2, through: 0, by: -1) {
            let next = steps[k + 1]
            let F = Matrix2(a: 1, b: next.dt, c: 0, d: 1)
            let Pf = steps[k].posteriorCovariance
            guard let PpInv = next.priorCovariance.inverse else { continue }
            let C = Pf * F.transposed * PpInv
            let dx = [smoothed[k + 1].x[0] - next.priorState[0], smoothed[k + 1].x[1] - next.priorState[1]]
            let x = [
                smoothed[k].x[0] + C.a * dx[0] + C.b * dx[1],
                smoothed[k].x[1] + C.c * dx[0] + C.d * dx[1],
            ]
            let P = Pf + C * (smoothed[k + 1].P - next.priorCovariance) * C.transposed
            smoothed[k] = (x, P.symmetrized)
        }
        return zip(steps, smoothed).map { step, s in
            Estimate(
                day: step.posterior.day, level: s.x[0], slope: s.x[1],
                levelSD: max(s.P.a, 0).squareRoot(), slopeSD: max(s.P.d, 0).squareRoot(),
                observationWeight: step.posterior.observationWeight
            )
        }
    }

    // MARK: Implementazione

    private struct Step {
        var posterior: Estimate
        var posteriorCovariance: Matrix2
        var priorState: [Double]
        var priorCovariance: Matrix2
        var dt: Double
    }

    private static func run(_ observations: [Observation], parameters p: Parameters) -> [Step] {
        guard let first = observations.first else { return [] }
        let r = p.measurementSD * p.measurementSD
        var x = [first.value, 0.0]
        var P = Matrix2(a: r, b: 0, c: 0, d: p.initialSlopeSD * p.initialSlopeSD)
        var steps = [Step(
            posterior: Estimate(day: first.day, level: x[0], slope: x[1], levelSD: P.a.squareRoot(),
                                slopeSD: P.d.squareRoot(), observationWeight: 1),
            posteriorCovariance: P, priorState: x, priorCovariance: P, dt: 0
        )]
        var lastDay = first.day
        for obs in observations.dropFirst() {
            let dt = obs.day - lastDay
            lastDay = obs.day
            // Predizione
            let F = Matrix2(a: 1, b: dt, c: 0, d: 1)
            let q = p.processNoise
            let Q = Matrix2(a: q * dt * dt * dt / 3, b: q * dt * dt / 2, c: q * dt * dt / 2, d: q * dt)
            let xPrior = [x[0] + dt * x[1], x[1]]
            let PPrior = (F * P * F.transposed + Q).symmetrized
            // Aggiornamento robusto
            let innovation = obs.value - xPrior[0]
            let s0 = PPrior.a + r
            let z = s0 > 0 ? innovation / s0.squareRoot() : 0
            let weight = huberWeight(z, threshold: p.huberThreshold)
            let rEff = weight > 0 ? r / weight : r * 1e6
            let s = PPrior.a + rEff
            let K = [PPrior.a / s, PPrior.c / s]
            x = [xPrior[0] + K[0] * innovation, xPrior[1] + K[1] * innovation]
            // Joseph: P = (I − KH) P⁻ (I − KH)ᵀ + K R Kᵀ, con H = [1, 0]
            let A = Matrix2(a: 1 - K[0], b: 0, c: -K[1], d: 1)
            let KRK = Matrix2(a: K[0] * K[0] * rEff, b: K[0] * K[1] * rEff, c: K[1] * K[0] * rEff, d: K[1] * K[1] * rEff)
            P = (A * PPrior * A.transposed + KRK).symmetrized
            steps.append(Step(
                posterior: Estimate(day: obs.day, level: x[0], slope: x[1], levelSD: max(P.a, 0).squareRoot(),
                                    slopeSD: max(P.d, 0).squareRoot(), observationWeight: weight),
                posteriorCovariance: P, priorState: xPrior, priorCovariance: PPrior, dt: dt
            ))
        }
        return steps
    }

    private static func huberWeight(_ z: Double, threshold k: Double) -> Double {
        guard z.isFinite, k > 0 else { return 1 }
        let a = abs(z)
        return a <= k ? 1 : k / a
    }
}

/// Matrice 2×2 `[[a, b], [c, d]]` per i filtri a due stati.
struct Matrix2: Sendable, Hashable {
    var a: Double, b: Double, c: Double, d: Double

    var transposed: Matrix2 { Matrix2(a: a, b: c, c: b, d: d) }
    var symmetrized: Matrix2 {
        let off = (b + c) / 2
        return Matrix2(a: a, b: off, c: off, d: d)
    }

    var inverse: Matrix2? {
        let det = a * d - b * c
        guard det.isFinite, abs(det) > 1e-300 else { return nil }
        return Matrix2(a: d / det, b: -b / det, c: -c / det, d: a / det)
    }

    static func * (l: Matrix2, r: Matrix2) -> Matrix2 {
        Matrix2(
            a: l.a * r.a + l.b * r.c, b: l.a * r.b + l.b * r.d,
            c: l.c * r.a + l.d * r.c, d: l.c * r.b + l.d * r.d
        )
    }

    static func + (l: Matrix2, r: Matrix2) -> Matrix2 {
        Matrix2(a: l.a + r.a, b: l.b + r.b, c: l.c + r.c, d: l.d + r.d)
    }

    static func - (l: Matrix2, r: Matrix2) -> Matrix2 {
        Matrix2(a: l.a - r.a, b: l.b - r.b, c: l.c - r.c, d: l.d - r.d)
    }
}
