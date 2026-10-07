import DesignSystem
import ExerciseCatalog
import Foundation
import JevDomain
import Persistence
import SwiftUI
import WorkoutEngine

extension WorkoutLiveModel: Identifiable {
    public nonisolated var id: UUID { sessionID }
}

/// Tab "Allenamento" (SCR-WK-01): prossima sessione della rotazione, ripresa della sessione in
/// corso e storico.
public struct TrainingTabView: View {
    let service: TrainingPlanService
    @State private var next: TrainingPlanService.NextSession?
    @State private var activeSessionID: UUID?
    @State private var history: [WorkoutSessionRecord] = []
    @State private var live: WorkoutLiveModel?
    @State private var loaded = false

    public init(service: TrainingPlanService) {
        self.service = service
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    nextSessionContent
                } header: {
                    Text("Prossima sessione")
                }
                Section {
                    if history.isEmpty {
                        Text("Nessun allenamento completato.")
                            .foregroundStyle(JevColor.textSecondary)
                    }
                    ForEach(history, id: \.id) { session in
                        HStack {
                            Text(session.startedAt, format: .dateTime.day().month().year())
                            Spacer()
                            if let end = session.endedAt {
                                Text(verbatim: Self.duration(from: session.startedAt, to: end))
                                    .foregroundStyle(JevColor.textSecondary)
                            }
                        }
                    }
                } header: {
                    Text("Storico")
                }
            }
            .navigationTitle("Allenamento")
            .accessibilityIdentifier("tab.training")
            .task { reload() }
            .fullScreenCover(item: $live, onDismiss: reload) { model in
                WorkoutLiveView(model: model) { live = nil }
            }
        }
    }

    @ViewBuilder private var nextSessionContent: some View {
        if activeSessionID != nil {
            Button("Riprendi l'allenamento in corso") { openActive() }
                .buttonStyle(JevPrimaryButtonStyle())
                .accessibilityIdentifier("training.resume")
        } else if let next {
            VStack(alignment: .leading, spacing: JevSpacing.s) {
                Text(verbatim: next.plan.focus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                ForEach(next.exercises, id: \.exerciseKey) { exercise in
                    HStack {
                        Text(verbatim: service.catalog[exercise.exerciseKey]?.name ?? exercise.exerciseKey)
                        Spacer()
                        Text(verbatim: Self.target(exercise))
                            .foregroundStyle(JevColor.textSecondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
                if next.isDeload {
                    JevInlineNotice("Settimana di scarico: volume e carichi ridotti.")
                }
                Button("Inizia allenamento") { start() }
                    .buttonStyle(JevPrimaryButtonStyle())
                    .accessibilityIdentifier("training.start")
            }
        } else if loaded {
            Text("Completa l'onboarding per generare il programma.")
                .foregroundStyle(JevColor.textSecondary)
        }
    }

    static func target(_ exercise: WorkoutRepository.PlannedExerciseInput) -> String {
        guard let set = exercise.sets.first else { return "" }
        let count = exercise.sets.count
        if let seconds = set.targetDurationSeconds { return "\(count) × \(seconds) s" }
        let reps = set.targetReps.map(String.init) ?? "–"
        if let kg = set.targetWeightKg { return "\(count) × \(reps) · \(WorkoutFormat.kilograms(kg))" }
        return "\(count) × \(reps)"
    }

    static func duration(from start: Date, to end: Date) -> String {
        let minutes = max(Int(end.timeIntervalSince(start) / 60), 0)
        return "\(minutes) min"
    }

    private func reload() {
        activeSessionID = try? service.workouts.activeSession()?.id
        next = try? service.nextSession()
        history = (try? service.workouts.history(limit: 30)) ?? []
        loaded = true
    }

    private func start() {
        guard let id = try? service.startNextSession() else { return }
        live = WorkoutLiveModel(sessionID: id, repository: service.workouts, catalog: service.catalog)
    }

    private func openActive() {
        guard let id = activeSessionID else { return }
        live = WorkoutLiveModel(sessionID: id, repository: service.workouts, catalog: service.catalog)
    }
}

enum WorkoutFormat {
    static func kilograms(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " kg"
    }

    /// Accetta la virgola decimale italiana.
    static func parse(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}

/// Sessione in corso (SCR-WK-02).
struct WorkoutLiveView: View {
    @Bindable var model: WorkoutLiveModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let summary = model.summary {
                    WorkoutSummaryView(summary: summary, onClose: onClose)
                } else if let detail = model.detail {
                    List {
                        if let end = model.restEndsAt, end > Date() {
                            Section {
                                HStack {
                                    Text("Recupero")
                                    Spacer()
                                    Text(timerInterval: Date()...end, countsDown: true)
                                        .monospacedDigit()
                                        .font(.title3.weight(.semibold))
                                }
                                .accessibilityIdentifier("workout.rest")
                            }
                        }
                        ForEach(detail.exercises) { exercise in
                            Section {
                                if let suggestion = model.suggestedLoadKg[exercise.id] {
                                    Text(verbatim: "→ \(WorkoutFormat.kilograms(suggestion))")
                                        .foregroundStyle(JevColor.ion)
                                        .accessibilityIdentifier("workout.suggestion")
                                }
                                ForEach(exercise.sets, id: \.id) { set in
                                    SetRowView(set: set, loadType: model.loadType(exercise), suggestedKg: model.suggestedLoadKg[exercise.id]) {
                                        weight, reps, rir, duration in
                                        model.complete(setID: set.id, weightKg: weight, reps: reps, rir: rir, durationSeconds: duration)
                                    }
                                    .swipeActions {
                                        if set.completedAt == nil {
                                            Button("Elimina", role: .destructive) { model.deleteSet(set.id) }
                                        }
                                    }
                                }
                                Button("Aggiungi serie") { model.addSet(to: exercise.id) }
                            } header: {
                                Text(verbatim: model.exerciseName(exercise))
                            }
                        }
                        if model.lastError != nil {
                            JevInlineNotice("Valore non valido: controlla carico, ripetizioni e RIR.")
                        }
                    }
                    .accessibilityIdentifier("workout.live")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Allenamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.summary == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") { onClose() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Termina") { model.finish() }
                            .accessibilityIdentifier("workout.finish")
                    }
                }
            }
        }
    }
}

/// Riga di una serie: target precompilati, conferma con un tocco.
struct SetRowView: View {
    let set: WorkoutSetRecord
    let loadType: LoadType
    let suggestedKg: Double?
    let onComplete: (Double?, Int?, Double?, Int?) -> Void

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var rirText = ""

    var body: some View {
        HStack(spacing: JevSpacing.s) {
            Text(verbatim: "\(set.setIndex + 1)")
                .font(.caption.weight(.semibold))
                .frame(width: 20)
                .foregroundStyle(JevColor.textSecondary)
            if set.completedAt != nil {
                Text(verbatim: Self.summary(set, loadType: loadType))
                    .monospacedDigit()
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(JevColor.mint)
            } else {
                if loadType != .timed {
                    TextField("kg", text: $weightText)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 70)
                }
                TextField(loadType == .timed ? "sec" : "rip", text: $repsText)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 50)
                if loadType != .timed {
                    TextField("RIR", text: $rirText)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 50)
                }
                Spacer()
                Button {
                    complete()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Completa serie")
                .accessibilityIdentifier("workout.set.complete")
            }
        }
        .textFieldStyle(.roundedBorder)
        .onAppear(perform: prefill)
        .onChange(of: suggestedKg) { _, _ in prefill() }
    }

    private func prefill() {
        guard set.completedAt == nil else { return }
        if let kg = suggestedKg ?? set.targetWeightKg {
            weightText = kg.formatted(.number.precision(.fractionLength(0...2)))
        }
        if let reps = set.targetReps, repsText.isEmpty { repsText = String(reps) }
    }

    private func complete() {
        let value = Int(repsText.trimmingCharacters(in: .whitespaces))
        if loadType == .timed {
            onComplete(nil, 1, nil, value)
        } else {
            onComplete(WorkoutFormat.parse(weightText), value, WorkoutFormat.parse(rirText), nil)
        }
    }

    static func summary(_ set: WorkoutSetRecord, loadType: LoadType) -> String {
        if loadType == .timed { return "\(set.durationS ?? 0) s" }
        let reps = set.reps.map(String.init) ?? "–"
        let weight = set.weightKg.map(WorkoutFormat.kilograms) ?? "–"
        let rir = set.rir.map { " · RIR \($0.formatted(.number.precision(.fractionLength(0...1))))" } ?? ""
        return "\(weight) × \(reps)\(rir)"
    }
}

/// Riepilogo a fine sessione (SCR-WK-03): volume, serie hard per muscolo, record.
struct WorkoutSummaryView: View {
    let summary: PerformanceAnalysis.SessionSummary
    let onClose: () -> Void

    private var muscleRows: [(muscle: MuscleGroup, sets: Double)] {
        summary.hardSetsByMuscle
            .map { (muscle: $0.key, sets: $0.value) }
            .sorted { $0.muscle.rawValue < $1.muscle.rawValue }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text(verbatim: WorkoutFormat.kilograms(summary.volumeKg)).monospacedDigit()
                }
                HStack {
                    Text("Serie di lavoro")
                    Spacer()
                    Text(verbatim: "\(summary.workingSets)").monospacedDigit()
                }
            }
            if !summary.records.isEmpty {
                Section {
                    ForEach(Array(summary.records.enumerated()), id: \.offset) { item in
                        let record = item.element
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(JevColor.personalRecord)
                            Text(verbatim: record.exerciseID.replacingOccurrences(of: "_", with: " ").capitalized)
                            Spacer()
                            Text(verbatim: record.value.formatted(.number.precision(.fractionLength(0...1))))
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Record personali")
                }
            }
            Section {
                ForEach(muscleRows, id: \.muscle) { row in
                    HStack {
                        Text(verbatim: row.muscle.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        Spacer()
                        Text(verbatim: row.sets.formatted(.number.precision(.fractionLength(0...1)))).monospacedDigit()
                    }
                }
            } header: {
                Text("Serie per muscolo")
            }
            Section {
                Button("Fine") { onClose() }
                    .buttonStyle(JevPrimaryButtonStyle())
                    .accessibilityIdentifier("workout.summary.done")
            }
        }
        .accessibilityIdentifier("workout.summary")
    }
}
