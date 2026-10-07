import Foundation
import JevCore
import JevDomain
import Testing
@testable import NutritionEngine

@Suite("BMR, prior dell'expenditure e trend del peso (§5.1–5.2)")
struct EnergyModelTests {
    let day0 = DayKey(year: 2026, month: 1, day: 5)!

    @Test("Mifflin–St Jeor per sesso, costante neutra senza sesso, Katch–McArdle con % grasso")
    func bmr() {
        #expect(EnergyModel.bmr(weightKg: 80, heightCm: 180, ageYears: 30, sex: .male) == 1780)
        #expect(EnergyModel.bmr(weightKg: 80, heightCm: 180, ageYears: 30, sex: .female) == 1614)
        #expect(EnergyModel.bmr(weightKg: 80, heightCm: 180, ageYears: 30, sex: nil) == 1697)
        let katch = EnergyModel.bmr(weightKg: 80, heightCm: 180, ageYears: 30, sex: .male, bodyFatPercent: 20)
        #expect(abs(katch - 1752.4) < 1e-9)
        // % grasso non plausibile: ignorata.
        #expect(EnergyModel.bmr(weightKg: 80, heightCm: 180, ageYears: 30, sex: .male, bodyFatPercent: 80) == 1780)
    }

    @Test("Prior = BMR × attività, deviazione standard 15% (18% senza sesso)")
    func prior() {
        #expect(EnergyModel.activityFactor(.moderate) == 1.55)
        let male = EnergyModel.priorExpenditure(weightKg: 80, heightCm: 180, ageYears: 30, sex: .male, activity: .moderate)
        #expect(abs(male.kcal - 2759) < 1e-9)
        let expectedSD: Double = 2759.0 * 0.15
        #expect(abs(male.sd - expectedSD) < 1e-9)
        let neutral = EnergyModel.priorExpenditure(weightKg: 80, heightCm: 180, ageYears: 30, sex: nil, activity: .moderate)
        #expect(abs(neutral.sd / neutral.kcal - 0.18) < 1e-12)
        var config = EngineConfig.current
        config.nutrition.activityFactors = [:]
        #expect(EnergyModel.activityFactor(.high, config: config) == 1.4)
    }

    @Test("Trend costante: livello fermo, pendenza nulla")
    func flatTrend() throws {
        let entries = (0..<30).map { WeightTrend.Entry(dayKey: day0.adding(days: $0), weightKg: 80) }
        let result = try #require(WeightTrend.compute(entries))
        #expect(abs(result.trendKg - 80) < 1e-6)
        #expect(abs(result.slopeKgPerWeek) < 1e-6)
        #expect(abs(result.change7DaysKg ?? 1) < 1e-6)
        #expect(abs(result.change21DaysKg ?? 1) < 1e-6)
        #expect(result.smoothed.count == 30)
        #expect(result.entriesUsed == 30)
        #expect(result.lastDay == day0.adding(days: 29))
        #expect(result.trendSDKg > 0 && result.slopeSDKgPerWeek > 0)
    }

    @Test("Perdita di 0,5 kg a settimana: pendenza e variazione a 7 giorni")
    func losingTrend() throws {
        let entries = (0..<60).map { i in
            let weight: Double = 90.0 - 0.5 * Double(i) / 7.0
            return WeightTrend.Entry(dayKey: day0.adding(days: i), weightKg: weight)
        }
        let result = try #require(WeightTrend.compute(entries))
        #expect(abs(result.slopeKgPerWeek + 0.5) < 0.1)
        #expect(abs((result.change7DaysKg ?? 0) + 0.5) < 0.15)
    }

    @Test("Pesate non plausibili rifiutate, una sola per giorno, storico corto senza variazioni")
    func filtering() throws {
        #expect(WeightTrend.compute([]) == nil)
        #expect(WeightTrend.compute([WeightTrend.Entry(dayKey: day0, weightKg: 5)]) == nil)
        let entries = [
            WeightTrend.Entry(dayKey: day0.adding(days: 2), weightKg: 80),
            WeightTrend.Entry(dayKey: day0, weightKg: 80),
            WeightTrend.Entry(dayKey: day0, weightKg: 95),
            WeightTrend.Entry(dayKey: day0.adding(days: 1), weightKg: 500),
        ]
        let result = try #require(WeightTrend.compute(entries))
        #expect(result.entriesUsed == 2)
        #expect(abs(result.trendKg - 80) < 1e-6)
        #expect(result.change7DaysKg == nil)
        #expect(result.change21DaysKg == nil)
        #expect(result.smoothed.map(\.dayKey) == [day0, day0.adding(days: 2)])
    }
}
