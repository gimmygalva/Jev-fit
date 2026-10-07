import Testing
import JevDomain
@testable import WorkoutEngine

@Suite("SplitSuggestion — split dai giorni disponibili (§5.5)")
struct SplitSuggestionTests {
    @Test("Regola base per giorni", arguments: [
        (1, SplitType.fullBody), (2, .fullBody), (3, .fullBody), (4, .upperLower),
        (5, .hybrid), (6, .pushPullLegs), (7, .pushPullLegs), (0, .fullBody), (12, .pushPullLegs),
    ] as [(Int, SplitType)])
    func base(days: Int, expected: SplitType) {
        #expect(SplitSuggestion.baseSplit(daysPerWeek: days) == expected)
        let result = SplitSuggestion.suggest(daysPerWeek: days, preferred: nil)
        #expect(result.split == expected)
        #expect(result.reason == .daysPerWeek)
    }

    @Test("Una preferenza compatibile ha la precedenza")
    func compatiblePreference() {
        let result = SplitSuggestion.suggest(daysPerWeek: 4, preferred: .torsoLimbs)
        #expect(result == .init(split: .torsoLimbs, reason: .userPreference))
        #expect(SplitSuggestion.suggest(daysPerWeek: 3, preferred: .custom).split == .custom)
    }

    @Test("Una preferenza incompatibile viene sostituita, con il motivo")
    func incompatiblePreference() {
        let result = SplitSuggestion.suggest(daysPerWeek: 2, preferred: .hybrid)
        #expect(result == .init(split: .fullBody, reason: .preferenceIncompatible))
    }

    @Test("Lo split di base è sempre compatibile con i suoi giorni")
    func baseIsCompatible() {
        for days in 1...7 {
            let split = SplitSuggestion.baseSplit(daysPerWeek: days)
            #expect(SplitSuggestion.compatibleDays(for: split).contains(days), "\(days) giorni → \(split)")
        }
        for split in SplitType.allCases {
            #expect(!SplitSuggestion.compatibleDays(for: split).isEmpty)
        }
    }
}
