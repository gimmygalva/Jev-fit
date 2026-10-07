import JevDomain

/// Scelta dello split dai giorni disponibili (ARCHITECTURE_PLAN §5.5, PS-ON-07).
///
/// Regola base: 1–3 giorni → Full Body · 4 → Upper/Lower · 5 → Hybrid · 6–7 → Push Pull Legs.
/// Se l'utente ha indicato uno split compatibile con i suoi giorni, ha la precedenza.
/// Il motivo è un codice: il testo lo produce la UI o JEV (ADR-008).
public enum SplitSuggestion {
    public enum Reason: String, Sendable, Hashable, CaseIterable {
        /// Lo split preferito dall'utente è compatibile con i giorni disponibili.
        case userPreference = "user_preference"
        /// Scelto dai giorni disponibili (nessuna preferenza o preferenza incompatibile).
        case daysPerWeek = "days_per_week"
        /// Preferenza indicata ma incompatibile con i giorni: sostituita dalla regola base.
        case preferenceIncompatible = "preference_incompatible"
    }

    public struct Result: Sendable, Hashable {
        public var split: SplitType
        public var reason: Reason
    }

    /// Giorni a settimana con cui ogni split funziona bene.
    public static func compatibleDays(for split: SplitType) -> ClosedRange<Int> {
        switch split {
        case .fullBody: 1...4
        case .upperLower: 2...4
        case .torsoLimbs: 2...4
        case .pushPullLegs: 3...7
        case .hybrid: 5...6
        case .custom: 1...7
        }
    }

    /// Split di base per un numero di giorni (riportato in 1...7).
    public static func baseSplit(daysPerWeek: Int) -> SplitType {
        switch min(max(daysPerWeek, 1), 7) {
        case ...3: .fullBody
        case 4: .upperLower
        case 5: .hybrid
        default: .pushPullLegs
        }
    }

    public static func suggest(daysPerWeek: Int, preferred: SplitType?) -> Result {
        let base = baseSplit(daysPerWeek: daysPerWeek)
        guard let preferred else { return Result(split: base, reason: .daysPerWeek) }
        if compatibleDays(for: preferred).contains(daysPerWeek) {
            return Result(split: preferred, reason: .userPreference)
        }
        return Result(split: base, reason: .preferenceIncompatible)
    }
}
