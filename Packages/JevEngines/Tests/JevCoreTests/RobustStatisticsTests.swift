import Foundation
import Testing
@testable import JevCore

@Suite("Statistiche robuste")
struct RobustStatisticsTests {
    typealias S = RobustStatistics

    @Test("Input vuoti o non finiti non producono NaN")
    func emptyAndNonFinite() {
        #expect(S.mean([]) == nil)
        #expect(S.median([.nan, .infinity]) == nil)
        #expect(S.medianAbsoluteDeviation([]) == nil)
        #expect(S.sampleStandardDeviation([1]) == nil)
        #expect(S.robustStandardDeviation([]) == nil)
        #expect(S.finite([1, .nan, 2, -.infinity]) == [1, 2])
    }

    @Test("Media, mediana pari e dispari")
    func centralTendency() {
        #expect(S.mean([1, 2, 3, .nan]) == 2)
        #expect(S.median([5, 1, 3]) == 3)
        #expect(S.median([4, 1, 3, 2]) == 2.5)
    }

    @Test("MAD resiste a un outlier, la deviazione standard no")
    func robustness() {
        let data: [Double] = [80.0, 80.2, 79.9, 80.1, 80.0, 95.0]
        let mad = S.robustStandardDeviation(data)!
        let sd = S.sampleStandardDeviation(data)!
        #expect(mad < 0.3)
        #expect(sd > 5)
        #expect(S.medianAbsoluteDeviation([1, 1, 1]) == 0)
    }

    @Test("Peso di Huber")
    func huber() {
        #expect(S.huberWeight(standardizedResidual: 1, threshold: 2.5) == 1)
        #expect(S.huberWeight(standardizedResidual: -2.5, threshold: 2.5) == 1)
        #expect(S.huberWeight(standardizedResidual: 5, threshold: 2.5) == 0.5)
        #expect(S.huberWeight(standardizedResidual: .nan, threshold: 2.5) == 0)
        #expect(S.huberWeight(standardizedResidual: 1, threshold: 0) == 0)
    }

    @Test("Clamp")
    func clamp() {
        #expect(S.clamp(5, 0...3) == 3)
        #expect(S.clamp(-1, 0...3) == 0)
        #expect(S.clamp(2, 0...3) == 2)
    }
}
