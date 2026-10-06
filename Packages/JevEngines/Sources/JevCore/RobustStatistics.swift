import Foundation

/// Statistiche robuste di base usate da più engine (trend peso, e1RM, baseline readiness).
/// Tutte le funzioni ignorano valori non finiti e restituiscono nil su input vuoti invece di
/// produrre NaN: un NaN che entra in un engine si propaga fino alla UI.
public enum RobustStatistics {
    /// Valori finiti dell'input, nello stesso ordine.
    public static func finite(_ values: [Double]) -> [Double] {
        values.filter { $0.isFinite }
    }

    public static func mean(_ values: [Double]) -> Double? {
        let v = finite(values)
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }

    public static func median(_ values: [Double]) -> Double? {
        let v = finite(values).sorted()
        guard !v.isEmpty else { return nil }
        let mid = v.count / 2
        return v.count.isMultiple(of: 2) ? (v[mid - 1] + v[mid]) / 2 : v[mid]
    }

    /// Median absolute deviation (non scalata).
    public static func medianAbsoluteDeviation(_ values: [Double]) -> Double? {
        guard let m = median(values) else { return nil }
        return median(finite(values).map { abs($0 - m) })
    }

    /// MAD scalata come stimatore consistente della deviazione standard per dati normali
    /// (fattore 1,4826).
    public static func robustStandardDeviation(_ values: [Double]) -> Double? {
        medianAbsoluteDeviation(values).map { $0 * 1.4826 }
    }

    /// Deviazione standard campionaria (n − 1). Nil con meno di 2 valori.
    public static func sampleStandardDeviation(_ values: [Double]) -> Double? {
        let v = finite(values)
        guard v.count >= 2, let m = mean(v) else { return nil }
        let ss = v.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (ss / Double(v.count - 1)).squareRoot()
    }

    /// Peso di Huber per un residuo standardizzato `z`: 1 se |z| ≤ k, altrimenti k/|z|.
    /// Usato per de-pesare le osservazioni anomale nei filtri robusti.
    public static func huberWeight(standardizedResidual z: Double, threshold k: Double) -> Double {
        guard z.isFinite, k > 0 else { return 0 }
        let a = abs(z)
        return a <= k ? 1 : k / a
    }

    /// Limita `value` all'intervallo chiuso.
    public static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
