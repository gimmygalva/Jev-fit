import Testing
import JevDomain
@testable import RecoveryEngine

/// M1: verifica solo il collegamento del modulo. I test degli algoritmi arrivano con
/// la rispettiva milestone (target coverage ≥ 90%, scripts/ci/coverage-targets.txt).
@Suite("RecoveryEngine — modulo")
struct RecoveryEngineInfoTests {
    @Test("Il modulo usa la configurazione corrente")
    func usesCurrentConfig() {
        #expect(RecoveryEngineInfo.configVersion == EngineConfig.current.version)
        #expect(RecoveryEngineInfo.algorithmVersion >= 0)
    }
}
