import Testing
@testable import CheckInEngine

@Suite("CheckInEngine — contratto delle decisioni")
struct CheckInDecisionTests {
    @Test("Le 9 decisioni del brief esistono con raw value stabili")
    func decisions() {
        #expect(CheckInDecisionType.allCases.count == 9)
        #expect(CheckInDecisionType.increaseCalories.rawValue == "increase_calories")
        #expect(CheckInDecisionType.noAction.rawValue == "no_action")
    }

    @Test("Ogni decisione appartiene a un'area", arguments: CheckInDecisionType.allCases)
    func areas(_ decision: CheckInDecisionType) {
        switch decision {
        case .increaseCalories, .decreaseCalories, .changeMacros:
            #expect(decision.area == .nutrition)
        case .reduceTrainingLoad, .increaseTrainingLoad, .deload, .changeExercise:
            #expect(decision.area == .training)
        case .keep, .noAction:
            #expect(decision.area == .any)
        }
    }

    @Test("Le versioni degli engine a monte sono registrate")
    func upstream() {
        #expect(Set(CheckInEngineInfo.upstreamAlgorithmVersions.keys) == ["workout", "nutrition", "recovery"])
        #expect(CheckInEngineInfo.algorithmVersion >= 0)
    }
}
