import SwiftUI

/// Tipografia (PRODUCT_SPEC §8.4). Tutti gli stili partono da uno stile di testo di sistema,
/// quindi seguono Dynamic Type (PS-A11Y-01).
public enum JevFont {
    /// H0: il numero protagonista della schermata (uno solo per schermata).
    public static let hero = Font.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
    /// H1: valori nelle card.
    public static let keyMetric = Font.system(.title, design: .rounded).weight(.semibold).monospacedDigit()
    /// Titoli di schermata e di card.
    public static let title = Font.system(.title2).weight(.semibold)
    public static let headline = Font.headline
    public static let body = Font.body
    public static let secondary = Font.subheadline
    /// Dati tabellari: set, valori nutrizionali.
    public static let data = Font.system(.body, design: .monospaced).weight(.medium)
    /// Source tag e timestamp, in maiuscolo (es. "SALUTE · 07:12").
    public static let meta = Font.system(.caption2, design: .monospaced)
}
