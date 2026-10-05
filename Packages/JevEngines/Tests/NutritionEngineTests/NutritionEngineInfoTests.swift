import Testing
import JevDomain
@testable import NutritionEngine

/// M1: verifica solo il collegamento del modulo. I test degli algoritmi arrivano con
/// la rispettiva milestone (target coverage ≥ 90%, scripts/ci/coverage-targets.txt).
@Suite("NutritionEngine — modulo")
struct NutritionEngineInfoTests {
    @Test("Il modulo usa la configurazione corrente")
    func usesCurrentConfig() {
        #expect(NutritionEngineInfo.configVersion == EngineConfig.current.version)
        #expect(NutritionEngineInfo.algorithmVersion >= 0)
    }
}
