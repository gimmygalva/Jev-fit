import Charts
import DesignSystem
import Foundation
import JevCore
import JevDomain
import RecoveryEngine
import SwiftUI
import Sync

/// Tab "Oggi" (SCR-HM-01): JEV READINESS con confidence, prossimo allenamento, nutrizione del giorno.
public struct TodayTabView: View {
    let service: DashboardService
    let checkIn: CheckInService?
    let account: AccountService?
    let cloudSync: CloudSyncService?
    @State private var showCheckIn = false
    @State private var readiness: Readiness.Result?
    @State private var next: TrainingPlanService.NextSession?
    @State private var targets: NutritionPlanService.Targets?
    @State private var eaten: Double = 0

    public init(service: DashboardService, checkIn: CheckInService? = nil, account: AccountService? = nil,
                cloudSync: CloudSyncService? = nil) {
        self.service = service
        self.checkIn = checkIn
        self.account = account
        self.cloudSync = cloudSync
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    if let readiness {
                        VStack(alignment: .leading, spacing: JevSpacing.s) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: "\(readiness.score)")
                                    .font(.system(size: 56, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .accessibilityIdentifier("today.readiness.score")
                                Text(verbatim: Self.bandName(readiness.band))
                                    .font(.headline)
                                    .foregroundStyle(Self.bandColor(readiness.band))
                            }
                            Text(verbatim: "\(String(localized: "Affidabilità")) \(Int((readiness.confidence * 100).rounded()))%")
                                .font(.caption)
                                .foregroundStyle(JevColor.textSecondary)
                            if !readiness.missing.isEmpty {
                                Text("Alcuni dati non sono disponibili: il punteggio usa solo quelli presenti.")
                                    .font(.caption)
                                    .foregroundStyle(JevColor.textSecondary)
                            }
                        }
                    } else {
                        Text("Registra un allenamento o un check per calcolare JEV READINESS.")
                            .foregroundStyle(JevColor.textSecondary)
                    }
                    if let checkIn {
                        JevTodayCard(coach: checkIn.coach, readiness: readiness?.score)
                    }
                } header: {
                    Text("JEV READINESS")
                }
                if let checkIn {
                    Section {
                        Button("Avvia il check-in settimanale") { showCheckIn = true }
                            .accessibilityIdentifier("today.checkin")
                        NavigationLink("Chiedi a JEV") {
                            JevChatView(coach: checkIn.coach, dashboard: service)
                        }
                        .accessibilityIdentifier("today.chat")
                    }
                }
                Section {
                    if let next {
                        Text(verbatim: next.plan.focus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.headline)
                        Text(verbatim: "\(next.exercises.count) \(String(localized: "esercizi")) · \(Int((next.plan.estimatedSeconds / 60).rounded())) min")
                            .foregroundStyle(JevColor.textSecondary)
                    } else {
                        Text("Nessun programma ancora.")
                            .foregroundStyle(JevColor.textSecondary)
                    }
                } header: {
                    Text("Allenamento di oggi")
                }
                Section {
                    if let targets {
                        Text(verbatim: "\(Int(eaten.rounded())) / \(Int(targets.kcal.rounded())) kcal")
                            .monospacedDigit()
                        ProgressView(value: min(eaten / max(targets.kcal, 1), 1))
                            .tint(JevColor.ion)
                    } else {
                        Text("Registra il peso per calcolare il target calorico.")
                            .foregroundStyle(JevColor.textSecondary)
                    }
                } header: {
                    Text("Nutrizione")
                }
            }
            .navigationTitle("Oggi")
            .accessibilityIdentifier("tab.today")
            .toolbar {
                if let account, let cloudSync {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView(account: account, sync: cloudSync)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Impostazioni")
                        .accessibilityIdentifier("today.settings")
                    }
                }
            }
            .task { reload() }
            .refreshable { reload() }
            .sheet(isPresented: $showCheckIn, onDismiss: reload) {
                if let checkIn {
                    CheckInView(service: checkIn) { showCheckIn = false }
                }
            }
        }
    }

    private func reload() {
        let today = DayKey(date: Date(), timeZone: .current)
        readiness = try? service.readiness()
        next = try? service.training.nextSession()
        targets = try? service.nutrition.targets(on: today)
        eaten = (try? service.nutrition.log.totals(day: today).energyKcal) ?? 0
    }

    static func bandName(_ band: ScoreBand) -> String {
        switch band {
        case .high: String(localized: "Alto")
        case .good: String(localized: "Buono")
        case .moderate: String(localized: "Moderato")
        case .low: String(localized: "Basso")
        }
    }

    static func bandColor(_ band: ScoreBand) -> Color {
        switch band {
        case .high: JevColor.mint
        case .good: JevColor.citrine
        case .moderate: JevColor.amber
        case .low: JevColor.ember
        }
    }
}

/// Tab "Corpo" (SCR-BD-01): mappa del recupero per muscolo e ore al "pronto".
public struct BodyTabView: View {
    let service: DashboardService
    @State private var states: [MuscleGroup: MuscleRecovery.MuscleState] = [:]
    @State private var selected: MuscleGroup?

    public init(service: DashboardService) {
        self.service = service
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    BodyMapView(states: states, selected: $selected)
                        .frame(maxHeight: 320)
                        .accessibilityIdentifier("body.map")
                    if let selected {
                        MuscleRow(muscle: selected, state: states[selected])
                    } else {
                        Text("Tocca un muscolo per i dettagli.")
                            .font(.caption)
                            .foregroundStyle(JevColor.textSecondary)
                    }
                }
                ForEach(MuscleSizeClass.allCases, id: \.self) { size in
                    Section {
                        ForEach(MuscleGroup.allCases.filter { $0.sizeClass == size }, id: \.self) { muscle in
                            MuscleRow(muscle: muscle, state: states[muscle])
                        }
                    } header: {
                        Text(verbatim: Self.sizeName(size))
                    }
                }
            }
            .navigationTitle("Corpo")
            .accessibilityIdentifier("tab.body")
            .task { states = (try? service.muscleStates()) ?? [:] }
            .refreshable { states = (try? service.muscleStates()) ?? [:] }
        }
    }

    static func sizeName(_ size: MuscleSizeClass) -> String {
        switch size {
        case .small: String(localized: "Muscoli piccoli")
        case .medium: String(localized: "Muscoli medi")
        case .large: String(localized: "Muscoli grandi")
        }
    }
}

struct MuscleRow: View {
    let muscle: MuscleGroup
    let state: MuscleRecovery.MuscleState?

    var body: some View {
        let recovery = state?.recoveryPercent ?? 100
        VStack(alignment: .leading, spacing: JevSpacing.xs) {
            HStack {
                Text(verbatim: MuscleNames.name(muscle))
                Spacer()
                Text(verbatim: "\(Int(recovery.rounded()))%").monospacedDigit()
            }
            ProgressView(value: recovery / 100)
                .tint(recovery >= 90 ? JevColor.mint : recovery >= 60 ? JevColor.amber : JevColor.ember)
            if let hours = state?.hoursToReady, hours > 0 {
                Text(verbatim: "\(String(localized: "Pronto tra")) \(Int(hours.rounded(.up))) h")
                    .font(.caption)
                    .foregroundStyle(JevColor.textSecondary)
            }
        }
        .accessibilityIdentifier("body.muscle.\(muscle.rawValue)")
    }
}

/// Tab "Progressi" (SCR-PR-01): 15 grafici con filtro di periodo.
public struct ProgressTabView: View {
    let service: DashboardService
    @State private var range = 28
    @State private var metric: DashboardService.Metric = .weightTrend
    @State private var points: [DashboardService.Point] = []

    public init(service: DashboardService) {
        self.service = service
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Periodo", selection: $range) {
                        Text(verbatim: "4 sett.").tag(28)
                        Text(verbatim: "12 sett.").tag(84)
                        Text(verbatim: "6 mesi").tag(182)
                        Text(verbatim: "1 anno").tag(365)
                    }
                    .pickerStyle(.segmented)
                    Picker("Grafico", selection: $metric) {
                        ForEach(DashboardService.Metric.allCases) { item in
                            Text(verbatim: Self.title(item)).tag(item)
                        }
                    }
                    .accessibilityIdentifier("progress.metric")
                }
                Section {
                    if points.isEmpty {
                        Text("Nessun dato nel periodo.")
                            .foregroundStyle(JevColor.textSecondary)
                    } else {
                        Chart(points) { point in
                            if Self.isBar(metric) {
                                BarMark(x: .value("Giorno", point.day.description), y: .value("Valore", point.value))
                                    .foregroundStyle(JevColor.ion)
                            } else {
                                LineMark(x: .value("Giorno", point.day.description), y: .value("Valore", point.value))
                                    .foregroundStyle(JevColor.ion)
                            }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 220)
                        .accessibilityIdentifier("progress.chart")
                        if let last = points.last {
                            Text(verbatim: "\(String(localized: "Ultimo valore")): \(last.value.formatted(.number.precision(.fractionLength(0...1))))")
                                .font(.caption).foregroundStyle(JevColor.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle("Progressi")
            .accessibilityIdentifier("tab.progress")
            .task(id: "\(metric.rawValue)-\(range)") {
                points = (try? service.series(metric, days: range)) ?? []
            }
        }
    }

    static func isBar(_ metric: DashboardService.Metric) -> Bool {
        [.calories, .protein, .carbs, .fat, .workouts, .volume, .hardSets, .steps, .activeEnergy].contains(metric)
    }

    static func title(_ metric: DashboardService.Metric) -> String {
        switch metric {
        case .weight: String(localized: "Peso")
        case .weightTrend: String(localized: "Trend del peso")
        case .calories: String(localized: "Calorie")
        case .protein: String(localized: "Proteine")
        case .carbs: String(localized: "Carboidrati")
        case .fat: String(localized: "Grassi")
        case .workouts: String(localized: "Allenamenti a settimana")
        case .volume: String(localized: "Volume settimanale")
        case .hardSets: String(localized: "Serie allenanti a settimana")
        case .topE1RM: String(localized: "Massimale stimato migliore")
        case .steps: String(localized: "Passi")
        case .activeEnergy: String(localized: "Energia attiva")
        case .sleep: String(localized: "Sonno")
        case .restingHeartRate: String(localized: "Frequenza a riposo")
        case .hrv: String(localized: "HRV")
        }
    }
}
