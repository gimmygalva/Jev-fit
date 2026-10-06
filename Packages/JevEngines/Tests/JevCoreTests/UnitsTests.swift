import Foundation
import Testing
@testable import JevCore

@Suite("Unità canoniche")
struct UnitsTests {
    @Test("1 lb = 0,45359237 kg esatti e il round-trip kg → lb → kg è stabile")
    func massConversion() {
        #expect(Mass.pounds(1).kilograms == 0.453_592_37)
        let original = Mass.kilograms(82.5)
        let roundTrip = Mass(value: original.value(in: .pounds), unit: .pounds)
        #expect(abs(roundTrip.kilograms - 82.5) < 1e-9)
        #expect(abs(Mass.kilograms(100).pounds - 220.462_262_185) < 1e-6)
    }

    @Test("1 kcal = 4,184 kJ e il round-trip è stabile")
    func energyConversion() {
        #expect(Energy.kilocalories(1).kilojoules == 4.184)
        #expect(abs(Energy.kilojoules(4184).kilocalories - 1000) < 1e-9)
        let e = Energy(value: 2740, unit: .kilocalories)
        #expect(abs(Energy(value: e.value(in: .kilojoules), unit: .kilojoules).kilocalories - 2740) < 1e-9)
    }

    @Test("Operatori aritmetici e confronto")
    func arithmetic() {
        #expect(Mass.kilograms(80) + Mass.kilograms(2.5) == Mass.kilograms(82.5))
        #expect(Mass.kilograms(80) - Mass.kilograms(5) == Mass.kilograms(75))
        #expect(Mass.kilograms(10) * 2 == Mass.kilograms(20))
        #expect(Mass.kilograms(1) < Mass.kilograms(2))
        #expect(Energy.kilocalories(100) + Energy.kilocalories(50) == Energy.kilocalories(150))
        #expect(Energy.kilocalories(100) - Energy.kilocalories(50) == Energy.kilocalories(50))
        #expect(Energy.kilocalories(100) * 1.5 == Energy.kilocalories(150))
        #expect(Energy.zero < Energy.kilocalories(1))
        #expect(Mass.zero.kilograms == 0)
        #expect(Mass(value: 3, unit: .kilograms).value(in: .kilograms) == 3)
        #expect(Energy(value: 3, unit: .kilocalories).value(in: .kilocalories) == 3)
    }

    @Test("Codable preserva i valori")
    func codable() throws {
        let data = try JSONEncoder().encode(Mass.kilograms(70.4))
        #expect(try JSONDecoder().decode(Mass.self, from: data) == Mass.kilograms(70.4))
    }
}
