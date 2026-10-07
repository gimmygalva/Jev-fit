import CoachKit
import DesignSystem
import Foundation
import JevCore
import Observation
import SwiftUI

/// Chat breve con JEV (§5.11, tier routine): ogni risposta parte dai fatti di oggi calcolati
/// dagli engine; il messaggio dell'utente è un dato, mai un'istruzione. I segnali di allarme
/// ricevono una risposta di sicurezza senza passare dall'AI. Nessuna cronologia salvata.
@MainActor
@Observable
final class JevChatModel {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        var fromUser: Bool
        var text: String
        var why: [String] = []
    }

    private(set) var messages: [Message] = []
    private(set) var sending = false
    private let coach: CoachService
    private let dashboard: DashboardService

    init(coach: CoachService, dashboard: DashboardService) {
        self.coach = coach
        self.dashboard = dashboard
    }

    /// Fatti di oggi, formattati dal client.
    func facts(now: Date = Date()) -> [CoachFact] {
        var facts: [CoachFact] = []
        let today = DayKey(date: now, timeZone: .current)
        if let readiness = try? dashboard.readiness(now: now) {
            facts.append(CoachFact(id: "readiness_today", label: String(localized: "Readiness di oggi"),
                                   value: Double(readiness.score), unit: "", formatted: "\(readiness.score)"))
        }
        if let targets = try? dashboard.nutrition.targets(on: today) {
            let eaten = (try? dashboard.nutrition.log.totals(day: today).energyKcal) ?? 0
            facts.append(CoachFact(id: "target_kcal", label: String(localized: "Target calorico"), value: targets.kcal,
                                   unit: "kcal", formatted: "\(Int(targets.kcal.rounded())) kcal"))
            facts.append(CoachFact(id: "eaten_kcal", label: String(localized: "Calorie registrate oggi"), value: eaten,
                                   unit: "kcal", formatted: "\(Int(eaten.rounded())) kcal"))
            if let trend = targets.trend {
                facts.append(CoachFact(id: "weekly_change_kg", label: String(localized: "Variazione settimanale del peso"),
                                       value: trend.slopeKgPerWeek, unit: "kg",
                                       formatted: String(format: "%+.1f kg", trend.slopeKgPerWeek).replacingOccurrences(of: ".", with: ",")))
            }
        }
        if let next = try? dashboard.training.nextSession() {
            facts.append(CoachFact(id: "next_session_exercises", label: String(localized: "Esercizi della prossima sessione"),
                                   value: Double(next.exercises.count), unit: "", formatted: "\(next.exercises.count)"))
        }
        return facts
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending else { return }
        messages.append(Message(fromUser: true, text: String(trimmed.prefix(1000))))
        sending = true
        defer { sending = false }
        let request = CoachRequest(tier: .routine, purpose: "chat", facts: facts(), reasonCodes: ["chat.summary"],
                                   userMessage: String(trimmed.prefix(1000)))
        let reply = await coach.message(for: request)
        let body = [reply.headline, reply.body].filter { !$0.isEmpty }.joined(separator: "\n")
        messages.append(Message(fromUser: false, text: body, why: reply.why))
    }
}

struct JevChatView: View {
    @State private var model: JevChatModel
    @State private var draft = ""

    init(coach: CoachService, dashboard: DashboardService) {
        _model = State(initialValue: JevChatModel(coach: coach, dashboard: dashboard))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: JevSpacing.m) {
                    if model.messages.isEmpty {
                        Text("Chiedi a JEV del tuo piano di oggi: allenamento, calorie, recupero.")
                            .foregroundStyle(JevColor.textSecondary)
                    }
                    ForEach(model.messages) { message in
                        VStack(alignment: message.fromUser ? .trailing : .leading, spacing: JevSpacing.xs) {
                            Text(verbatim: message.text)
                                .padding(JevSpacing.m)
                                .background(message.fromUser ? JevColor.ion.opacity(0.15) : JevColor.backgroundCard,
                                            in: RoundedRectangle(cornerRadius: 14))
                            ForEach(message.why, id: \.self) { line in
                                Text(verbatim: line).font(.caption).foregroundStyle(JevColor.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
                    }
                    if model.sending { ProgressView() }
                }
                .padding()
            }
            HStack {
                TextField("Scrivi a JEV", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("jev.chat.field")
                Button {
                    let text = draft
                    draft = ""
                    Task { await model.send(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.sending)
                .accessibilityLabel("Invia")
                .accessibilityIdentifier("jev.chat.send")
            }
            .padding()
        }
        .navigationTitle("JEV")
        .navigationBarTitleDisplayMode(.inline)
    }
}
