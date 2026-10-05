import Foundation
import Testing
@testable import JevCore

@Suite("UUIDv7, sorgenti di tempo e generatore deterministico")
struct IdentifiersTests {
    @Test("Bit di versione e variante corretti, timestamp recuperabile")
    func versionAndVariant() {
        var g = SeededGenerator(seed: 42)
        let ms: UInt64 = 1_791_244_800_000
        let id = UUIDv7.make(timestampMilliseconds: ms, using: &g)
        let u = id.uuid
        #expect(u.6 >> 4 == 7)
        #expect(u.8 >> 6 == 0b10)
        #expect(UUIDv7.timestampMilliseconds(of: id) == ms)
    }

    @Test("Gli ID generati in istanti successivi sono ordinati come stringa")
    func ordering() {
        var g = SeededGenerator(seed: 7)
        let ids = (0..<50).map { UUIDv7.make(timestampMilliseconds: 1_700_000_000_000 + UInt64($0), using: &g) }
        let strings = ids.map { $0.uuidString }
        #expect(strings == strings.sorted())
        #expect(Set(ids).count == ids.count)
    }

    @Test("make(at:) usa l'istante dato e un UUID non v7 non ha timestamp")
    func fromDate() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let id = UUIDv7.make(at: date)
        #expect(UUIDv7.timestampMilliseconds(of: id) == 1_000_000_000)
        #expect(UUIDv7.timestampMilliseconds(of: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!) == nil)
        // Date prima del 1970 → timestamp 0, mai un crash.
        #expect(UUIDv7.timestampMilliseconds(of: UUIDv7.make(at: Date(timeIntervalSince1970: -50))) == 0)
    }

    @Test("SeededGenerator è deterministico e seed diverse divergono")
    func seeded() {
        var a = SeededGenerator(seed: 123)
        var b = SeededGenerator(seed: 123)
        var c = SeededGenerator(seed: 124)
        let sa = (0..<10).map { _ in a.next() }
        let sb = (0..<10).map { _ in b.next() }
        let sc = (0..<10).map { _ in c.next() }
        #expect(sa == sb)
        #expect(sa != sc)
    }

    @Test("Sorgenti di tempo")
    func timeSources() {
        let fixed = Date(timeIntervalSince1970: 1234)
        #expect(FixedTimeSource(fixed).now() == fixed)
        let before = Date()
        let now = SystemTimeSource().now()
        #expect(now >= before.addingTimeInterval(-1))
    }
}
