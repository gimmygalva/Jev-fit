import Foundation
import ExerciseCatalog
import JevCore
import JevDomain
import Testing
@testable import RecoveryEngine

@Suite("Recupero muscolare (§5.8)")
struct MuscleRecoveryTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// Configurazione con tolleranza neutra (k = 1) per verificare la calibrazione.
    private var neutral: EngineConfig {
        var config = EngineConfig.current
        config.recovery.toleranceRange = 1...1
        return config
    }

    private func chestSets(_ count: Int, rir: Double?, at date: Date) -> [MuscleRecovery.SetDose] {
        (0..<count).map { _ in MuscleRecovery.SetDose(date: date, contributions: [.chest: 1], rir: rir) }
    }

    @Test("Intensità per RIR, RIR mancante e riscaldamento")
    func intensity() {
        #expect(MuscleRecovery.intensity(rir: 0, isWarmup: false) == 1)
        #expect(MuscleRecovery.intensity(rir: 1, isWarmup: false) == 0.9)
        #expect(MuscleRecovery.intensity(rir: 2, isWarmup: false) == 0.8)
        #expect(MuscleRecovery.intensity(rir: 3, isWarmup: false) == 0.65)
        #expect(MuscleRecovery.intensity(rir: 4, isWarmup: false) == 0.5)
        #expect(MuscleRecovery.intensity(rir: 8, isWarmup: false) == 0.5)
        #expect(MuscleRecovery.intensity(rir: -1, isWarmup: false) == 1)
        #expect(MuscleRecovery.intensity(rir: nil, isWarmup: false) == 0.8)
        #expect(MuscleRecovery.intensity(rir: .nan, isWarmup: false) == 0.8)
        #expect(MuscleRecovery.intensity(rir: 0, isWarmup: true) == 0.1)
    }

    @Test("Tolleranza cronica: 10 serie/settimana → 1, poche serie → di più, tante → minimo 0,7")
    func tolerance() {
        #expect(abs(MuscleRecovery.tolerance(weeklyHardSets: 10) - 1) < 1e-12)
        let low: Double = pow(2.0, 0.3)
        #expect(abs(MuscleRecovery.tolerance(weeklyHardSets: 0) - low) < 1e-12)
        #expect(abs(MuscleRecovery.tolerance(weeklyHardSets: .nan) - low) < 1e-12)
        #expect(MuscleRecovery.tolerance(weeklyHardSets: 40) == 0.7)
    }

    @Test("τ per taglia, età e moltiplicatore personale limitato")
    func tau() {
        #expect(MuscleRecovery.tauHours(for: .quads, ageYears: 30) == 38)
        #expect(abs(MuscleRecovery.tauHours(for: .quads, ageYears: 50) - 41.8) < 1e-9)
        #expect(MuscleRecovery.tauHours(for: .sideDelts, ageYears: nil) == 24)
        #expect(MuscleRecovery.tauHours(for: .biceps, ageYears: 25, userMultiplier: 3) == 45)
        #expect(MuscleRecovery.tauHours(for: .biceps, ageYears: 25, userMultiplier: .nan) == 30)
    }

    @Test("Calibrazione: 6 serie a RIR 1 → 35%, di nuovo al 90% in circa 69 ore")
    func calibration() throws {
        let sets = chestSets(6, rir: 1, at: t0)
        let now = try #require(MuscleRecovery.state(sets: sets, at: t0, ageYears: 30, config: neutral)[.chest])
        #expect(abs(now.fatigue - 5.4) < 1e-9)
        #expect(abs(now.recoveryPercent - 35) < 1e-9)
        #expect(abs(now.hoursToReady - 69) < 0.5)
        #expect(!now.isReady)
        let later = try #require(MuscleRecovery.state(sets: sets, at: t0.addingTimeInterval(69 * 3600), ageYears: 30,
                                                      config: neutral)[.chest])
        #expect(abs(later.recoveryPercent - 90) < 0.2)
        let rested = try #require(MuscleRecovery.state(sets: sets, at: t0.addingTimeInterval(96 * 3600), ageYears: 30,
                                                       config: neutral)[.chest])
        #expect(rested.isReady && rested.hoursToReady == 0)
        // Un muscolo non allenato è pronto.
        let quads = try #require(MuscleRecovery.state(sets: sets, at: t0, ageYears: 30, config: neutral)[.quads])
        #expect(quads.recoveryPercent == 100 && quads.hoursToReady == 0)
    }

    @Test("Più serie e più vicine al cedimento affaticano di più; le serie future sono ignorate")
    func monotonic() throws {
        let light = try #require(MuscleRecovery.state(sets: chestSets(3, rir: 3, at: t0), at: t0, ageYears: 30)[.chest])
        let hard = try #require(MuscleRecovery.state(sets: chestSets(6, rir: 0, at: t0), at: t0, ageYears: 30)[.chest])
        #expect(hard.recoveryPercent < light.recoveryPercent)
        let future = chestSets(6, rir: 0, at: t0.addingTimeInterval(3600))
        let before = try #require(MuscleRecovery.state(sets: future, at: t0, ageYears: 30)[.chest])
        #expect(before.recoveryPercent == 100)
    }

    @Test("Guard su ln(0) e valori non finiti")
    func guards() {
        #expect(MuscleRecovery.hoursToReady(fatigue: 0, tauHours: 30) == 0)
        #expect(MuscleRecovery.hoursToReady(fatigue: .infinity, tauHours: 30) == 0)
        #expect(MuscleRecovery.hoursToReady(fatigue: .nan, tauHours: 30) == 0)
        #expect(MuscleRecovery.hoursToReady(fatigue: 5, tauHours: 0) == 0)
        #expect(MuscleRecovery.hoursToReady(fatigue: 0.1, tauHours: 30) == 0)
        #expect(MuscleRecovery.recoveryPercent(fatigue: 0) == 100)
        #expect(MuscleRecovery.recoveryPercent(fatigue: .nan) == 100)
    }

    @Test("Volume settimanale su 4 settimane, riscaldamenti e serie vecchie esclusi")
    func weeklyVolume() {
        var sets = (0..<8).map { i in
            MuscleRecovery.SetDose(date: t0.addingTimeInterval(-Double(i) * 3 * 86_400), contributions: [.chest: 1, .triceps: 0.5], rir: 2)
        }
        sets.append(MuscleRecovery.SetDose(date: t0, contributions: [.chest: 1], rir: nil, isWarmup: true))
        sets.append(MuscleRecovery.SetDose(date: t0.addingTimeInterval(-40 * 86_400), contributions: [.chest: 1], rir: 2))
        let volume = MuscleRecovery.weeklyHardSets(sets, at: t0)
        #expect(volume[.chest] == 2)
        #expect(volume[.triceps] == 1)
    }

    @Test("Dose dal catalogo: contributi primari e secondari, fatigue score dell'esercizio")
    func catalogDose() throws {
        let catalog = try ExerciseCatalog.bundled()
        let bench = try #require(catalog["barbell_bench_press"])
        let dose = MuscleRecovery.SetDose(date: t0, exercise: bench, rir: 1)
        for muscle in bench.primaryMuscles {
            #expect(dose.contributions[muscle] == 1)
        }
        #expect(dose.exerciseFatigue == bench.fatigueScore)
    }

    @Test("Recupero della sessione pesato sui muscoli coinvolti")
    func session() throws {
        let states = MuscleRecovery.state(sets: chestSets(6, rir: 1, at: t0), at: t0, ageYears: 30, config: neutral)
        let mixed = try #require(MuscleRecovery.sessionRecovery(states, muscles: [.chest: 1, .quads: 1]))
        #expect(abs(mixed - 67.5) < 1e-9)
        #expect(MuscleRecovery.sessionRecovery(states, muscles: [:]) == nil)
        #expect(MuscleRecovery.sessionRecovery([:], muscles: [.chest: 1]) == nil)
    }

    @Test("Adattamento di u: solo con ≥ 6 esposizioni, passi da 0,05, entro il range")
    func adaptation() {
        let few = Array(repeating: MuscleRecovery.Exposure(estimatedRecoveryPercent: 95, performanceResidual: -0.1), count: 5)
        #expect(MuscleRecovery.adapt(multiplier: 1, exposures: few).reasonCode == "recovery.adapt_insufficient_data")
        let slow = Array(repeating: MuscleRecovery.Exposure(estimatedRecoveryPercent: 95, performanceResidual: -0.05), count: 6)
        let slower = MuscleRecovery.adapt(multiplier: 1, exposures: slow)
        #expect(abs(slower.multiplier - 1.05) < 1e-12 && slower.reasonCode == "recovery.adapt_slower")
        let fast = Array(repeating: MuscleRecovery.Exposure(estimatedRecoveryPercent: 60, performanceResidual: 0.05), count: 6)
        let faster = MuscleRecovery.adapt(multiplier: 1, exposures: fast)
        #expect(abs(faster.multiplier - 0.95) < 1e-12 && faster.reasonCode == "recovery.adapt_faster")
        let neutralResiduals = Array(repeating: MuscleRecovery.Exposure(estimatedRecoveryPercent: 95, performanceResidual: 0), count: 6)
        #expect(MuscleRecovery.adapt(multiplier: 1, exposures: neutralResiduals).reasonCode == "recovery.adapt_keep")
        #expect(MuscleRecovery.adapt(multiplier: 1.5, exposures: slow).multiplier == 1.5)
        #expect(MuscleRecovery.adapt(multiplier: .nan, exposures: few).multiplier == 1)
    }
}
