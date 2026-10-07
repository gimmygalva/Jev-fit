import SwiftUI
import UIKit

/// Palette semantica "Instrument" (PRODUCT_SPEC §8.2). Ogni token ha una variante dark e una
/// light e segue l'aspetto del sistema (o l'override dell'utente, PS-ST-04).
///
/// Regole d'uso (PRODUCT_SPEC §8.2):
/// - la scala Ember → Mint solo per recovery e readiness, sempre con la label di fascia;
/// - Ion solo per JEV e per le azioni primarie;
/// - i colori dei macro solo per i macro.
public enum JevColor {
    // Superfici
    public static let backgroundBase = dynamic(dark: 0x0B0C0E, light: 0xF4F3EF)
    public static let backgroundCard = dynamic(dark: 0x15171A, light: 0xFFFFFF)
    public static let backgroundElevated = dynamic(dark: 0x1D2024, light: 0xFAFAF8)
    public static let hairline = dynamic(dark: 0x2A2E33, light: 0xE3E1DC)

    // Testo
    public static let textPrimary = dynamic(dark: 0xF2F2F0, light: 0x111214)
    public static let textSecondary = dynamic(dark: 0x8E949B, light: 0x6B7077)

    // Accento: JEV e azioni primarie
    public static let ion = dynamic(dark: 0x7C8BFF, light: 0x3F4FF0)
    /// Testo/icone sopra un riempimento Ion.
    public static let onIon = dynamic(dark: 0x0B0C0E, light: 0xFFFFFF)

    // Scala recovery/readiness (fasce 1–4)
    public static let ember = dynamic(dark: 0xFF5A36, light: 0xE0401E)
    public static let amber = dynamic(dark: 0xFFAA2C, light: 0xC77A00)
    public static let citrine = dynamic(dark: 0xCFE34A, light: 0x7E8F00)
    public static let mint = dynamic(dark: 0x2ED3A0, light: 0x0E9A70)

    // Macro
    public static let protein = dynamic(dark: 0xB66DFF, light: 0x8A3FE0)
    public static let carbs = dynamic(dark: 0x33B5FF, light: 0x0A84C8)
    public static let fat = dynamic(dark: 0xFF6FA3, light: 0xD23F77)
    public static let fiber = dynamic(dark: 0x8FB996, light: 0x4F8A5A)

    // Stati
    public static let personalRecord = dynamic(dark: 0xF5C451, light: 0xA57A00)
    /// Avvisi di validazione e sicurezza (testo sempre presente, mai solo colore).
    public static let warning = amber

    static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
