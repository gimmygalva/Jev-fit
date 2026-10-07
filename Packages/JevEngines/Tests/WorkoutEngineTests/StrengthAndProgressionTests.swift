import Foundation
import JevCore
import JevDomain
import Testing
@testable import WorkoutEngine

@Suite("e1RM e carico effettivo (§5.7)")
struct StrengthEstimationTests {
    @Test("Carico effettivo per tipo di esercizio")
    func effectiveLoad() {
        #expect(StrengthEstimation.effectiveLoadKg(loadType: .external, loadKg: 100, bodyweightKg: 80, bodyweightFraction: nil) == 100)
        #expect(StrengthEstimation.effectiveLoadKg(loadType: .bodyweight, loadKg: 10, bodyweightKg: 80, bodyweightFraction: 1) == 90)
        #expect(StrengthEstimation.effectiveLoadKg(loadType: .bodyweight, loadKg: nil, bodyweightKg: 80, bodyweightFraction: 0.5) == 40)
        #expect(StrengthEstimation.effectiveLoadKg(loadType: .assisted, loadKg: 30, bodyweightKg: 80, bodyweightFraction: 1) == 50)
        #expect(StrengthEstimation.effectiveLoadKg(loadType: .assisted, loadKg: 100, bodyweightKg: 80, bodyweightFraction: 1) == 0)
        #expect(StrengthEstimation.effectiveLoadKg(loadType: .bodyweight, loadKg: 0, bodyweightKg: nil, bodyweightFraction: 1) == nil)
        #expect(StrengthEstimation.effectiveLoadKg(loadType: .timed, loadKg: 10, bodyweightKg: 80, bodyweightFraction: 1) == nil)
    }

    @Test("e1RM: una ripetizione a cedimento è il carico; 2–10 media di Epley e Brzycki; 11–12 Epley")
    func e1rmRules() throws {
        #expect(StrengthEstimation.e1RM(loadKg: 100, reps: 1, rir: 0) == 100)
        let five = try #require(StrengthEstimation.e1RM(loadKg: 100, reps: 5, rir: 0))
        let epley: Double = 100 * (1 + 5.0 / 30)
        let brzycki: Double = 100.0 * 36.0 / 32.0
        let expected: Double = (epley + brzycki) / 2
        #expect(abs(five - expected) < 1e-9)
        let eleven = try #require(StrengthEstimation.e1RM(loadKg: 100, reps: 10, rir: 1))
        #expect(abs(eleven - 100 * (1 + 11.0 / 30)) < 1e-9)
    }

    @Test("e1RM non stimato: RIR > 3, RIR mancante, oltre 12 ripetizioni, zero ripetizioni o carico nullo")
    func e1rmExclusions() {
        #expect(StrengthEstimation.e1RM(loadKg: 100, reps: 5, rir: 4) == nil)
        #expect(StrengthEstimation.e1RM(loadKg: 100, reps: 5, rir: nil) == nil)
        #expect(StrengthEstimation.e1RM(loadKg: 100, reps: 12, rir: 1) == nil)
        #expect(StrengthEstimation.e1RM(loadKg: 100, reps: 0, rir: 0) == nil)
        #expect(StrengthEstimation.e1RM(loadKg: 0, reps: 5, rir: 0) == nil)
        #expect(StrengthEstimation.e1RM(loadKg: 100, reps: 5, rir: -1) == nil)
    }

    @Test("Miglior e1RM della sessione, indice di forza e volume")
    func aggregates() throws {
        let sets = [
            PerformedSet(type: .warmup, loadKg: 60, reps: 8, rir: 4),
            PerformedSet(loadKg: 100, reps: 5, rir: 2),
            PerformedSet(loadKg: 105, reps: 3, rir: 1),
        ]
        let best = try #require(StrengthEstimation.bestE1RM(sets, loadType: .external, bodyweightKg: nil, bodyweightFraction: nil))
        #expect(best == StrengthEstimation.e1RM(loadKg: 100, reps: 5, rir: 2))
        #expect(StrengthEstimation.volumeKg(sets) == 815)
        #expect(StrengthEstimation.strengthIndex(loadKg: 50, reps: 15, rir: 2) != nil)
        #expect(StrengthEstimation.strengthIndex(loadKg: 50, reps: 25, rir: 0) == nil)
        #expect(StrengthEstimation.strengthIndex(loadKg: 0, reps: 5, rir: 0) == nil)
        #expect(StrengthEstimation.bestE1RM([PerformedSet(loadKg: 100, reps: nil)], loadType: .external,
                                            bodyweightKg: nil, bodyweightFraction: nil) == nil)
    }
}

@Suite("Progressive overload — tabella delle regole (§5.7)")
struct ProgressionTests {
    let barbell = Progression.Prescription(loadType: .external, incrementKg: 2.5, repRange: 6...10, targetRIR: 2)

    private func sets(_ reps: [Int], rir: [Double?], load: Double = 100) -> [PerformedSet] {
        zip(reps, rir).map { PerformedSet(loadKg: load, reps: $0, rir: $1) }
    }

    @Test("Regola 0: dolore non letto o deload bloccano gli aumenti")
    func rule0() {
        let top = sets([10, 10, 10], rir: [3, 3, 3])
        let pain = Progression.decide(lastExposure: top, prescription: barbell, context: .init(painBlocksIncrease: true))
        #expect(pain.action == .keep && pain.rule == 0 && pain.reasonCode == "overload.keep_pain")
        #expect(pain.nextLoadKg == 100)
        let deload = Progression.decide(lastExposure: top, prescription: barbell, context: .init(isDeload: true))
        #expect(deload.rule == 0 && deload.reasonCode == "overload.keep_deload")
    }

    @Test("Regola 1: senza RIR solo progressione per ripetizioni")
    func rule1() {
        let atTop = Progression.decide(lastExposure: sets([10, 10, 10], rir: [nil, nil, nil]), prescription: barbell)
        #expect(atTop.action == .increaseLoad && atTop.rule == 1)
        #expect(atTop.nextLoadKg == 102.5 && atTop.nextReps == 6)
        let below = Progression.decide(lastExposure: sets([8, 7, 7], rir: [nil, nil, nil]), prescription: barbell)
        #expect(below.action == .increaseReps && below.rule == 1 && below.nextReps == 9)
    }

    @Test("Regola 2: tutte le serie al massimo con RIR ≥ target → carico + Δ; RIR molto alto → + 2Δ")
    func rule2() {
        let single = Progression.decide(lastExposure: sets([10, 10, 10], rir: [2, 2, 3]), prescription: barbell)
        #expect(single.action == .increaseLoad && single.rule == 2 && single.nextLoadKg == 102.5 && single.nextReps == 6)
        let double = Progression.decide(lastExposure: sets([10, 10, 10], rir: [4, 3, 3]), prescription: barbell)
        #expect(double.nextLoadKg == 105 && double.reasonCode == "overload.load_increase_double")
        // Con carichi alti il passo è il 2,5% arrotondato a Δ se maggiore di Δ.
        let heavy = Progression.decide(lastExposure: sets([10, 10, 10], rir: [2, 2, 2], load: 200), prescription: barbell)
        #expect(heavy.nextLoadKg == 205)
    }

    @Test("Regole 3 e 4: sotto il target la prima volta si mantiene, la seconda si regredisce di almeno Δ")
    func rules3and4() {
        let under = sets([5, 4, 6], rir: [0, 0, 1])
        let first = Progression.decide(lastExposure: under, prescription: barbell)
        #expect(first.action == .keep && first.rule == 4 && first.underperformed)
        let second = Progression.decide(lastExposure: under, prescription: barbell,
                                        context: .init(previousExposureUnderperformed: true))
        #expect(second.action == .regress && second.rule == 3 && second.nextLoadKg == 95)
        // −5% di 10 kg con Δ = 2 arrotonderebbe a 0: il passo minimo è Δ.
        let light = Progression.Prescription(loadType: .external, incrementKg: 2, repRange: 10...15, targetRIR: 2)
        let tiny = Progression.decide(lastExposure: sets([5, 5], rir: [0, 0], load: 10), prescription: light,
                                      context: .init(previousExposureUnderperformed: true))
        #expect(tiny.nextLoadKg == 8)
    }

    @Test("Regola 5: double progression; regola 6: mantieni")
    func rules5and6() {
        let inRange = Progression.decide(lastExposure: sets([8, 8, 7], rir: [2, 2, 1]), prescription: barbell)
        #expect(inRange.action == .increaseReps && inRange.rule == 5 && inRange.nextReps == 8 && inRange.nextLoadKg == 100)
        let mixed = Progression.decide(lastExposure: sets([12, 12, 9], rir: [1, 1, 1]), prescription: barbell)
        #expect(mixed.action == .keep && mixed.rule == 6)
        let empty = Progression.decide(lastExposure: [PerformedSet(type: .warmup, loadKg: 40, reps: 10)], prescription: barbell)
        #expect(empty.action == .keep && empty.reasonCode == "overload.keep_no_data")
    }

    @Test("Corpo libero e assistiti: la zavorra cresce, l'assistenza cala o cresce in regressione")
    func bodyweightAndAssisted() {
        let bw = Progression.Prescription(loadType: .bodyweight, incrementKg: 2.5, repRange: 6...10, targetRIR: 2)
        let noLoad = [PerformedSet(reps: 10, rir: 2), PerformedSet(reps: 10, rir: 2)]
        #expect(Progression.decide(lastExposure: noLoad, prescription: bw).nextLoadKg == 2.5)
        let assisted = Progression.Prescription(loadType: .assisted, incrementKg: 5, repRange: 6...10, targetRIR: 2)
        let helped = [PerformedSet(loadKg: 30, reps: 10, rir: 2), PerformedSet(loadKg: 30, reps: 10, rir: 2)]
        #expect(Progression.decide(lastExposure: helped, prescription: assisted).nextLoadKg == 25)
        let struggling = [PerformedSet(loadKg: 30, reps: 3, rir: 0), PerformedSet(loadKg: 30, reps: 3, rir: 0)]
        #expect(Progression.decide(lastExposure: struggling, prescription: assisted,
                                   context: .init(previousExposureUnderperformed: true)).nextLoadKg == 35)
        #expect(Progression.increased(10, steps: 1, .init(loadType: .timed, incrementKg: 0, repRange: 1...1, targetRIR: 2)) == nil)
        #expect(Progression.regressed(10, .init(loadType: .timed, incrementKg: 0, repRange: 1...1, targetRIR: 2)) == nil)
        #expect(Progression.regressed(nil, bw) == nil)
    }

    @Test("Esercizi a tempo: la durata cresce, cala dopo due esposizioni corte, altrimenti resta")
    func timed() {
        let plank = Progression.Prescription(loadType: .timed, incrementKg: 0, repRange: 1...1, targetRIR: 2, targetDurationSeconds: 40)
        let full = [PerformedSet(durationSeconds: 40), PerformedSet(durationSeconds: 45)]
        let up = Progression.decide(lastExposure: full, prescription: plank)
        #expect(up.action == .increaseDuration && up.nextDurationSeconds == 45 && up.rule == 7)
        let short = [PerformedSet(durationSeconds: 20), PerformedSet(durationSeconds: 25)]
        #expect(Progression.decide(lastExposure: short, prescription: plank).action == .keep)
        let down = Progression.decide(lastExposure: short, prescription: plank, context: .init(previousExposureUnderperformed: true))
        #expect(down.action == .decreaseDuration && down.nextDurationSeconds == 35)
        #expect(Progression.decide(lastExposure: full, prescription: plank, context: .init(isDeload: true)).rule == 0)
        let noTarget = Progression.Prescription(loadType: .timed, incrementKg: 0, repRange: 1...1, targetRIR: 2)
        #expect(Progression.decide(lastExposure: [PerformedSet(durationSeconds: 30)], prescription: noTarget).nextDurationSeconds == 35)
    }

    @Test("Aggiustamento live: ±2,5% o ±5% arrotondati al passo, di almeno un passo")
    func live() {
        #expect(Progression.liveAdjustedLoad(firstSetLoadKg: 100, firstSetRIR: 4, prescription: barbell) == 102.5)
        #expect(Progression.liveAdjustedLoad(firstSetLoadKg: 100, firstSetRIR: 5, prescription: barbell) == 105)
        #expect(Progression.liveAdjustedLoad(firstSetLoadKg: 100, firstSetRIR: 0, prescription: barbell) == 97.5)
        #expect(Progression.liveAdjustedLoad(firstSetLoadKg: 100, firstSetRIR: 3, prescription: barbell) == 100)
        #expect(Progression.liveAdjustedLoad(firstSetLoadKg: 20, firstSetRIR: 5, prescription: barbell) == 22.5)
    }

    @Test("Proprietà: ogni input cade in esattamente una regola e i target restano validi")
    func property() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<2_000 {
            let count = Int.random(in: 0...5, using: &generator)
            let exposure = (0..<count).map { _ in
                PerformedSet(
                    type: Bool.random(using: &generator) ? .working : .top,
                    loadKg: Double(Int.random(in: 0...80, using: &generator)) * 2.5,
                    reps: Int.random(in: 0...15, using: &generator),
                    rir: Bool.random(using: &generator) ? Double(Int.random(in: 0...5, using: &generator)) : nil
                )
            }
            let context = Progression.Context(
                painBlocksIncrease: Int.random(in: 0...9, using: &generator) == 0,
                isDeload: Int.random(in: 0...9, using: &generator) == 0,
                previousExposureUnderperformed: Bool.random(using: &generator)
            )
            let d = Progression.decide(lastExposure: exposure, prescription: barbell, context: context)
            #expect((0...6).contains(d.rule))
            #expect(barbell.repRange.contains(d.nextReps))
            #expect((d.nextLoadKg ?? 0) >= 0)
            #expect(d.reasonCode.hasPrefix("overload."))
        }
    }
}
