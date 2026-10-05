import Testing
import JevDomain
@testable import WorkoutEngine

/// M1: verifica solo il collegamento del modulo. I test degli algoritmi arrivano con
/// la rispettiva milestone (target coverage ≥ 90%, scripts/ci/coverage-targets.txt).
@Suite("WorkoutEngine — modulo")
struct WorkoutEngineInfoTests {
    @Test("Il modulo usa la configurazione corrente")
    func usesCurrentConfig() {
        #expect(WorkoutEngineInfo.configVersion == EngineConfig.current.version)
        #expect(WorkoutEngineInfo.algorithmVersion >= 0)
    }
}
