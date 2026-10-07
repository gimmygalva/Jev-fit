import CheckInEngine
import CoachKit
import DesignSystem
import Foundation
import JevCore
import SwiftUI

/// Weekly check-in (SCR-CI-01): spiegazione di JEV con WHY / DATA USED / fonte, decisioni da
/// accettare o rifiutare. KEEP = "valutato, il piano resta"; NO ACTION = "non valutabile ora".
struct CheckInView: View {
    let service: CheckInService
    let onClose: () -> Void
    @State private var report: CheckInService.Report?
    @State private var loading = true
    @State private var answered: [String: Bool] = [:]

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    ProgressView()
                } else if let report {
                    Section {
                        Text(verbatim: report.message.headline).font(.headline)
                        if !report.message.body.isEmpty { Text(verbatim: report.message.body) }
                        if let _ = report.message.safetyAlert {
                            JevInlineNotice("Se hai dubbi sulla tua salute, consulta un medico.")
                        }
                    } header: {
                        Text("JEV")
                    }
                    if !report.message.why.isEmpty {
                        Section {
                            ForEach(report.message.why, id: \.self) { line in Text(verbatim: line) }
                        } header: {
                            Text("Perché")
                        }
                    }
                    Section {
                        ForEach(Array(report.result.decisions.enumerated()), id: \.offset) { item in
                            DecisionRow(decision: item.element, answer: answered[item.element.key]) { accepted in
                                try? service.respond(to: item.element, in: report, accepted: accepted,
                                                     day: DayKey(date: Date(), timeZone: .current))
                                answered[item.element.key] = accepted
                            }
                        }
                    } header: {
                        Text("Decisioni")
                    }
                    if report.result.safetyTriggered {
                        Section {
                            JevInlineNotice("Abbiamo rilevato un segnale di sicurezza: il piano è stato reso più prudente. Se qualcosa non ti torna, parlane con un professionista.")
                        }
                    }
                    Section {
                        Text(verbatim: "\(String(localized: "Fonte")): \(report.message.source == "template" ? String(localized: "testi locali") : "JEV AI")")
                            .font(.caption)
                            .foregroundStyle(JevColor.textSecondary)
                    }
                } else {
                    Text("Servono il profilo e almeno una pesata per il check-in.")
                        .foregroundStyle(JevColor.textSecondary)
                }
            }
            .navigationTitle("Check-in settimanale")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("checkin.view")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { onClose() }
                }
            }
            .task {
                report = try? await service.run(on: DayKey(date: Date(), timeZone: .current))
                loading = false
            }
        }
    }
}

struct DecisionRow: View {
    let decision: CheckInEvaluator.Decision
    let answer: Bool?
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.s) {
            Text(verbatim: Self.title(decision)).font(.headline)
            if let delta = decision.deltaKcal {
                Text(verbatim: "\(delta > 0 ? "+" : "")\(Int(delta.rounded())) kcal").monospacedDigit()
            }
            if let fraction = decision.setsChangeFraction {
                Text(verbatim: "\(fraction > 0 ? "+" : "")\(Int((fraction * 100).rounded()))% \(String(localized: "serie"))")
                    .monospacedDigit()
            }
            if let exercise = decision.exerciseID {
                Text(verbatim: exercise.replacingOccurrences(of: "_", with: " ").capitalized)
                    .foregroundStyle(JevColor.textSecondary)
            }
            if Self.needsAnswer(decision.type) {
                if let answer {
                    Text(verbatim: answer ? String(localized: "Accettata") : String(localized: "Rifiutata"))
                        .font(.caption)
                        .foregroundStyle(answer ? JevColor.mint : JevColor.textSecondary)
                } else {
                    HStack {
                        Button("Accetta") { onAnswer(true) }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("checkin.accept")
                        Button("Rifiuta") { onAnswer(false) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    static func needsAnswer(_ type: CheckInDecisionType) -> Bool {
        type != .keep && type != .noAction
    }

    static func title(_ decision: CheckInEvaluator.Decision) -> String {
        switch decision.type {
        case .keep: String(localized: "Mantieni: valutato, il piano resta")
        case .noAction: String(localized: "Nessuna azione: non valutabile ora")
        case .increaseCalories: String(localized: "Aumenta le calorie")
        case .decreaseCalories: String(localized: "Riduci le calorie")
        case .changeMacros: String(localized: "Aggiorna i macro")
        case .reduceTrainingLoad: String(localized: "Riduci il volume di allenamento")
        case .increaseTrainingLoad: String(localized: "Aumenta il volume di allenamento")
        case .deload: String(localized: "Settimana di scarico")
        case .changeExercise: String(localized: "Cambia esercizio")
        }
    }
}

/// Card di JEV su Oggi: spiega la readiness con i fatti dell'engine (template offline o gateway).
struct JevTodayCard: View {
    let coach: CoachService
    let readiness: Int?
    @State private var message: CoachMessage?

    var body: some View {
        Group {
            if let message {
                VStack(alignment: .leading, spacing: JevSpacing.xs) {
                    Text(verbatim: message.headline).font(.subheadline.weight(.semibold))
                    ForEach(message.why, id: \.self) { line in
                        Text(verbatim: line).font(.caption).foregroundStyle(JevColor.textSecondary)
                    }
                }
                .accessibilityIdentifier("today.jev")
            }
        }
        .task(id: readiness) {
            guard let readiness else { return }
            let fact = CoachFact(id: "readiness_today", label: String(localized: "Readiness di oggi"),
                                 value: Double(readiness), unit: "", formatted: "\(readiness)")
            message = await coach.message(for: CoachRequest(tier: .routine, purpose: "today_card", facts: [fact],
                                                            reasonCodes: ["today.readiness"]))
        }
    }
}
