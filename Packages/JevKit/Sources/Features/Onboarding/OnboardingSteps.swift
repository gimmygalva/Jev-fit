import DesignSystem
import JevCore
import JevDomain
import Persistence
import SwiftUI

// Contenuto dei singoli step (SCREEN_MAP §2). Ogni vista legge e modifica solo il modello.

struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.xl) {
            Text(verbatim: "JEV FIT")
                .font(JevFont.hero)
                .foregroundStyle(JevColor.textPrimary)
            StepTitle("Allenamento e nutrizione guidati dai tuoi dati.")
            VStack(alignment: .leading, spacing: JevSpacing.m) {
                Label("Numeri calcolati dai tuoi dati reali, non stimati a caso", systemImage: "waveform.path.ecg")
                Label("JEV, il tuo coach, ti spiega ogni decisione", systemImage: "text.bubble")
                Label("Funziona anche senza connessione", systemImage: "wifi.slash")
            }
            .font(JevFont.body)
            .foregroundStyle(JevColor.textPrimary)
            .symbolRenderingMode(.hierarchical)
            Text("JEV FIT non è un dispositivo medico e non sostituisce il parere di un medico o di un nutrizionista.")
                .font(JevFont.secondary)
                .foregroundStyle(JevColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GoalStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.m) {
            StepTitle("Qual è il tuo obiettivo?", subtitle: "Puoi cambiarlo quando vuoi.")
            let allowed = model.allowedGoals
            ForEach(GoalType.allCases, id: \.self) { goal in
                JevSelectionCard(
                    goal.title,
                    subtitle: goal.effect,
                    isSelected: model.draft.goal == goal,
                    isEnabled: allowed.contains(goal)
                ) {
                    model.selectGoal(goal)
                }
                .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
            }
        }
    }
}

struct ExperienceStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.m) {
            StepTitle("Da quanto ti alleni?", subtitle: "Serve a scegliere ripetizioni e ritmo di progressione.")
            ForEach(ExperienceLevel.allCases, id: \.self) { level in
                JevSelectionCard(level.title, subtitle: level.detail, isSelected: model.draft.experience == level) {
                    model.draft.experience = level
                }
                .accessibilityIdentifier("onboarding.experience.\(level.rawValue)")
            }
        }
    }
}

struct BodyStep: View {
    @Bindable var model: OnboardingModel
    @State private var showsSexInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.m) {
            StepTitle("I tuoi dati", subtitle: "Restano sul tuo iPhone finché non attivi la sincronizzazione.")

            Picker("Unità di peso", selection: $model.massUnitSelection) {
                Text(verbatim: "kg").tag(MassUnit.kilograms)
                Text(verbatim: "lb").tag(MassUnit.pounds)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.body.unit")

            NumberField(
                label: "Peso",
                unit: model.massUnit == .pounds ? "lb" : "kg",
                text: $model.weightText,
                identifier: "onboarding.body.weight"
            )
            NumberField(label: "Altezza", unit: "cm", text: $model.heightText, identifier: "onboarding.body.height")
            NumberField(
                label: "Età",
                unit: "anni",
                text: $model.ageText,
                identifier: "onboarding.body.age",
                keyboard: .numberPad
            )

            VStack(alignment: .leading, spacing: JevSpacing.s) {
                HStack {
                    Text("Sesso biologico (facoltativo)")
                        .font(JevFont.headline)
                        .foregroundStyle(JevColor.textPrimary)
                    Spacer()
                    Button("Perché serve?") { showsSexInfo.toggle() }
                        .font(JevFont.secondary)
                        .accessibilityIdentifier("onboarding.body.sex_info")
                }
                if showsSexInfo {
                    Text("Serve solo per stimare il metabolismo basale iniziale. Se preferisci non indicarlo usiamo una formula neutra e la stima si corregge con i tuoi dati in 2–3 settimane.")
                        .font(JevFont.secondary)
                        .foregroundStyle(JevColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("Sesso biologico", selection: $model.draft.sex) {
                    Text("Non indicato").tag(BiologicalSex?.none)
                    ForEach(BiologicalSex.allCases, id: \.self) { sex in
                        Text(sex.title).tag(BiologicalSex?.some(sex))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("onboarding.body.sex")
            }

            if model.draft.sex != .male {
                Toggle(isOn: $model.draft.pregnancyOrLactation) {
                    Text("In gravidanza o allattamento")
                        .font(JevFont.body)
                }
                .tint(JevColor.ion)
                .accessibilityIdentifier("onboarding.body.pregnancy")
            }

            NumberField(
                label: "Massa grassa (facoltativa)",
                unit: "%",
                text: $model.bodyFatText,
                identifier: "onboarding.body.body_fat"
            )

            if model.issues.contains(where: { if case .goalBlocked(_) = $0 { true } else { false } }) {
                Button("Cambia obiettivo") { model.changeGoal() }
                    .accessibilityIdentifier("onboarding.body.change_goal")
            }
        }
    }
}

struct ActivityStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.m) {
            StepTitle("Quanto ti muovi fuori dall'allenamento?")
            ForEach(ActivityLevel.allCases, id: \.self) { level in
                JevSelectionCard(level.title, subtitle: level.detail, isSelected: model.draft.activityLevel == level) {
                    model.draft.activityLevel = level
                }
                .accessibilityIdentifier("onboarding.activity.\(level.rawValue)")
            }
        }
    }
}

struct TargetStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.m) {
            StepTitle("Peso obiettivo e ritmo", subtitle: "Il peso obiettivo è facoltativo: il ritmo guida le calorie.")
            NumberField(
                label: "Peso obiettivo",
                unit: model.massUnit == .pounds ? "lb" : "kg",
                text: $model.targetWeightText,
                identifier: "onboarding.target.weight"
            )
            if let goal = model.draft.goal, let limits = GoalSafety.rateLimits(for: goal) {
                let rate = model.draft.targetRatePercentPerWeek ?? limits.defaultValue
                JevCard {
                    VStack(alignment: .leading, spacing: JevSpacing.s) {
                        HStack {
                            Text(rate < 0 ? LocalizedStringKey("Perdita a settimana") : LocalizedStringKey("Aumento a settimana"))
                                .font(JevFont.body)
                            Spacer()
                            Text(abs(rate) / 100, format: .percent.precision(.fractionLength(2)))
                                .font(JevFont.keyMetric)
                        }
                        Slider(
                            value: $model.ratePercentSelection,
                            in: limits.range,
                            step: 0.05
                        )
                        .tint(JevColor.ion)
                        .accessibilityIdentifier("onboarding.target.rate")
                        if let current = model.current.weightKg, let target = model.current.targetWeightKg,
                           let weeks = GoalSafety.weeksToTarget(currentKg: current, targetKg: target, ratePercentPerWeek: rate) {
                            Text("Arrivo stimato tra circa \(Int(weeks.rounded(.up))) settimane")
                                .font(JevFont.secondary)
                                .foregroundStyle(JevColor.textSecondary)
                        }
                    }
                }
                if GoalSafety.isAggressiveLoss(rate) {
                    JevInlineNotice("Ritmo aggressivo: più difficile preservare massa muscolare.")
                }
            }
        }
    }
}

struct AvailabilityStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.l) {
            StepTitle("Quanto tempo hai?")
            Text("Giorni a settimana")
                .font(JevFont.headline)
            ChipGrid(items: Array(2...6)) { days in
                JevChip("\(days) giorni", isSelected: model.draft.daysPerWeek == days) {
                    model.draft.daysPerWeek = days
                }
                .accessibilityIdentifier("onboarding.availability.days.\(days)")
            }
            Text("Giorni preferiti (facoltativo)")
                .font(JevFont.headline)
            ChipGrid(items: Weekday.all) { day in
                JevChip(Weekday.short(day), isSelected: model.draft.preferredWeekdays.contains(day)) {
                    model.toggleWeekday(day)
                }
            }
            Text("Minuti per sessione")
                .font(JevFont.headline)
            ChipGrid(items: [30, 45, 60, 75, 90]) { minutes in
                JevChip("\(minutes) min", isSelected: model.draft.sessionMinutes == minutes) {
                    model.draft.sessionMinutes = minutes
                }
            }
            if model.draft.experience == .beginner, (model.draft.daysPerWeek ?? 0) >= 6, model.draft.sessionMinutes >= 90 {
                JevInlineNotice("Da principiante conviene partire con meno giorni o sessioni più brevi. Puoi comunque continuare.")
            }
        }
    }
}

struct EquipmentStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.l) {
            StepTitle("Che attrezzatura hai?", subtitle: "Scegli un punto di partenza e modifica la lista.")
            ChipGrid(items: EquipmentPreset.allCases) { preset in
                JevChip(preset.title, isSelected: model.draft.equipment == preset.equipment) {
                    model.applyEquipmentPreset(preset)
                }
                .accessibilityIdentifier("onboarding.equipment.preset.\(preset.rawValue)")
            }
            Divider().overlay(JevColor.hairline)
            ChipGrid(items: Equipment.allCases) { item in
                JevChip(item.title, isSelected: model.draft.equipment.contains(item)) {
                    model.toggleEquipment(item)
                }
            }
            if model.draft.equipment.isEmpty {
                Text("Senza attrezzatura useremo esercizi a corpo libero.")
                    .font(JevFont.secondary)
                    .foregroundStyle(JevColor.textSecondary)
            }
        }
    }
}

struct SplitStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.m) {
            StepTitle("Come vuoi dividere gli allenamenti?")
            JevSelectionCard(
                "Lascia decidere a JEV",
                subtitle: suggestionText,
                isSelected: model.draft.splitPreference == nil
            ) {
                model.draft.splitPreference = nil
            }
            .accessibilityIdentifier("onboarding.split.auto")
            ForEach(SplitType.allCases, id: \.self) { split in
                JevSelectionCard(split.title, isSelected: model.draft.splitPreference == split) {
                    model.draft.splitPreference = split
                }
                .accessibilityIdentifier("onboarding.split.\(split.rawValue)")
            }
            if model.splitSuggestion?.preferenceIncompatible == true {
                JevInlineNotice("Questo split non si adatta ai giorni che hai scelto: JEV userà quello consigliato.")
            }
        }
    }

    private var suggestionText: LocalizedStringKey? {
        guard let days = model.draft.daysPerWeek else { return nil }
        let split = SplitSuggestionPreview(daysPerWeek: days, preferred: nil).split
        let text: LocalizedStringKey = "Con \(days) giorni a settimana: \(Text(split.title))"
        return text
    }
}

struct LimitationsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.l) {
            StepTitle(
                "Hai fastidi o limitazioni?",
                subtitle: "Non è una diagnosi: ci serve per evitare esercizi che potrebbero darti fastidio."
            )
            ChipGrid(items: BodyArea.allCases) { area in
                JevChip(area.title, isSelected: model.draft.limitations.contains { $0.area == area }) {
                    model.toggleLimitation(area)
                }
                .accessibilityIdentifier("onboarding.limitations.\(area.rawValue)")
            }
            ForEach($model.draft.limitations, id: \.area) { $limitation in
                JevCard {
                    VStack(alignment: .leading, spacing: JevSpacing.s) {
                        Text(limitation.area.title).font(JevFont.headline)
                        Picker("Intensità", selection: $limitation.severity) {
                            ForEach(LimitationSeverity.allCases, id: \.self) { severity in
                                Text(severity.title).tag(severity)
                            }
                        }
                        .pickerStyle(.segmented)
                        TextField("Nota (facoltativa)", text: $limitation.noteText, axis: .vertical)
                        .lineLimit(1...4)
                    }
                }
            }
        }
    }
}

struct PriorityStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.l) {
            StepTitle("Muscoli da privilegiare", subtitle: "Fino a 3 gruppi riceveranno più volume.")
            ChipGrid(items: MuscleGroup.allCases) { muscle in
                JevChip(muscle.title, isSelected: model.draft.musclePriority.contains(muscle)) {
                    model.togglePriority(muscle)
                }
                .accessibilityIdentifier("onboarding.priority.\(muscle.rawValue)")
            }
            Text("\(model.draft.musclePriority.count) di 3 selezionati")
                .font(JevFont.secondary)
                .foregroundStyle(JevColor.textSecondary)
        }
    }
}

struct MacroStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.m) {
            StepTitle("Come vuoi gestire calorie e macro?")
            ForEach(MacroMode.allCases, id: \.self) { mode in
                JevSelectionCard(mode.title, subtitle: mode.detail, isSelected: model.draft.macroMode == mode) {
                    model.draft.macroMode = mode
                }
                .accessibilityIdentifier("onboarding.macro.\(mode.rawValue)")
            }
        }
    }
}

struct UnitsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.l) {
            StepTitle("Unità e check-in settimanale")
            JevCard {
                VStack(alignment: .leading, spacing: JevSpacing.m) {
                    Picker("Energia", selection: $model.draft.energyUnit) {
                        Text(verbatim: "kcal").tag(EnergyUnitPreference.kcal)
                        Text(verbatim: "kJ").tag(EnergyUnitPreference.kj)
                    }
                    .pickerStyle(.segmented)
                    Picker("Peso", selection: $model.massUnitSelection) {
                        Text(verbatim: "kg").tag(MassUnit.kilograms)
                        Text(verbatim: "lb").tag(MassUnit.pounds)
                    }
                    .pickerStyle(.segmented)
                }
            }
            Text("Giorno del check-in")
                .font(JevFont.headline)
            Text("Una volta a settimana JEV rivede allenamento e nutrizione con te.")
                .font(JevFont.secondary)
                .foregroundStyle(JevColor.textSecondary)
            ChipGrid(items: Weekday.all) { day in
                JevChip(Weekday.long(day), isSelected: model.draft.checkInWeekday == day) {
                    model.draft.checkInWeekday = day
                }
            }
        }
    }
}

struct SummaryStep: View {
    let model: OnboardingModel

    var body: some View {
        let draft = model.current
        VStack(alignment: .leading, spacing: JevSpacing.m) {
            StepTitle("Il tuo punto di partenza", subtitle: "Controlla le scelte: potrai cambiarle nelle impostazioni.")
            JevCard {
                VStack(alignment: .leading, spacing: JevSpacing.s) {
                    if let goal = draft.goal { SummaryRow(label: "Obiettivo", value: Text(goal.title)) }
                    if let experience = draft.experience { SummaryRow(label: "Esperienza", value: Text(experience.title)) }
                    if let weight = draft.weightKg {
                        SummaryRow(label: "Peso", value: Text(weightText(weight)))
                    }
                    if let days = draft.daysPerWeek {
                        SummaryRow(label: "Allenamenti", value: Text("\(days) × \(draft.sessionMinutes) min"))
                    }
                    if let suggestion = model.splitSuggestion {
                        SummaryRow(label: "Split", value: Text(suggestion.split.title))
                    }
                    SummaryRow(label: "Calorie e macro", value: Text(draft.macroMode.title))
                }
            }
            Text("Calorie, macro e sessioni del programma vengono calcolati dai motori di JEV FIT a partire da queste scelte.")
                .font(JevFont.secondary)
                .foregroundStyle(JevColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func weightText(_ kg: Double) -> String {
        let unit = model.massUnit
        let value = Mass(kilograms: kg).value(in: unit)
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        return unit == .pounds ? "\(number) lb" : "\(number) kg"
    }
}

extension OnboardingDraft.Limitation {
    /// Nota come testo non opzionale per il TextField; vuota = nessuna nota. Massimo 1000
    /// caratteri, come il vincolo del database (SEC-DB-08).
    var noteText: String {
        get { note ?? "" }
        set { note = newValue.isEmpty ? nil : String(newValue.prefix(1000)) }
    }
}

private struct SummaryRow: View {
    let label: LocalizedStringKey
    let value: Text

    var body: some View {
        HStack {
            Text(label).foregroundStyle(JevColor.textSecondary)
            Spacer()
            value.foregroundStyle(JevColor.textPrimary)
        }
        .font(JevFont.body)
        .accessibilityElement(children: .combine)
    }
}
