import DesignSystem
import JevCore
import JevDomain
import Persistence
import SwiftUI

/// Onboarding a schermo intero (SCREEN_MAP §2, UF-01).
///
/// Struttura comune: barra di avanzamento, contenuto dello step, `[Continua]` in basso (56 pt),
/// `[Salta]` solo negli step opzionali, `[Indietro]` sempre tranne al primo step.
/// Identificatori di accessibilità: `onboarding.step.<step>`, `onboarding.continue`,
/// `onboarding.skip`, `onboarding.back` e quelli dei singoli controlli.
public struct OnboardingView: View {
    private let model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: JevSpacing.l) {
                    stepContent
                    ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
                        if shouldShow(issue) {
                            JevInlineNotice(issue.message)
                        }
                    }
                    if model.saveFailed {
                        JevInlineNotice("Non è stato possibile salvare. Riprova.")
                    }
                }
                .padding(.horizontal, JevSpacing.l)
                .padding(.vertical, JevSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(JevColor.backgroundBase.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.\(model.step.rawValue)")
    }

    // MARK: Struttura

    private var header: some View {
        HStack(spacing: JevSpacing.m) {
            if model.canGoBack {
                Button {
                    model.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: JevHitTarget.standard, height: JevHitTarget.standard)
                }
                .accessibilityLabel(Text("Indietro"))
                .accessibilityIdentifier("onboarding.back")
                .foregroundStyle(JevColor.textPrimary)
            }
            JevStepProgress(current: model.stepIndex, total: model.sequence.count)
        }
        .padding(.horizontal, JevSpacing.l)
        .padding(.top, JevSpacing.s)
        .frame(minHeight: JevHitTarget.standard)
    }

    private var footer: some View {
        VStack(spacing: JevSpacing.s) {
            Button {
                model.next()
            } label: {
                Text(primaryTitle)
            }
            .buttonStyle(JevPrimaryButtonStyle())
            .disabled(!model.canContinue)
            .accessibilityIdentifier("onboarding.continue")

            if model.step.isSkippable {
                Button("Salta") { model.skip() }
                    .buttonStyle(JevSecondaryButtonStyle())
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
        .padding(.horizontal, JevSpacing.l)
        .padding(.vertical, JevSpacing.m)
        .background(JevColor.backgroundBase)
    }

    private var primaryTitle: LocalizedStringKey {
        switch model.step {
        case .welcome: "Inizia"
        case .summary: "Inizia ad allenarti"
        default: "Continua"
        }
    }

    /// "Scegli un'opzione" non serve come messaggio: il pulsante disattivato basta. Gli altri
    /// problemi si mostrano solo quando l'utente ha già scritto qualcosa.
    private func shouldShow(_ issue: OnboardingIssue) -> Bool {
        switch issue {
        case .missingSelection: false
        case .invalidWeight: !model.weightText.isEmpty
        case .invalidHeight: !model.heightText.isEmpty
        case .invalidAge: !model.ageText.isEmpty
        default: true
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .goal: GoalStep(model: model)
        case .experience: ExperienceStep(model: model)
        case .body: BodyStep(model: model)
        case .activity: ActivityStep(model: model)
        case .target: TargetStep(model: model)
        case .availability: AvailabilityStep(model: model)
        case .equipment: EquipmentStep(model: model)
        case .split: SplitStep(model: model)
        case .limitations: LimitationsStep(model: model)
        case .priority: PriorityStep(model: model)
        case .macro: MacroStep(model: model)
        case .units: UnitsStep(model: model)
        case .summary: SummaryStep(model: model)
        }
    }
}

// MARK: - Componenti comuni agli step

struct StepTitle: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JevSpacing.s) {
            Text(title)
                .font(JevFont.title)
                .foregroundStyle(JevColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(JevFont.body)
                    .foregroundStyle(JevColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Riga etichetta + campo numerico con unità ("82,5 kg"), unità al 60% (PRODUCT_SPEC §8.1).
struct NumberField: View {
    let label: LocalizedStringKey
    let unit: LocalizedStringKey
    @Binding var text: String
    let identifier: String
    var keyboard: UIKeyboardType = .decimalPad

    var body: some View {
        JevCard {
            HStack(spacing: JevSpacing.m) {
                Text(label)
                    .font(JevFont.body)
                    .foregroundStyle(JevColor.textPrimary)
                Spacer()
                TextField("", text: $text, prompt: Text(verbatim: "—"))
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .font(JevFont.keyMetric)
                    .foregroundStyle(JevColor.textPrimary)
                    .frame(maxWidth: 140)
                    .accessibilityLabel(Text(label))
                    .accessibilityIdentifier(identifier)
                Text(unit)
                    .font(JevFont.secondary)
                    .foregroundStyle(JevColor.textSecondary)
            }
        }
    }
}

/// Griglia di chip che va a capo.
struct ChipGrid<Item: Hashable, Cell: View>: View {
    let items: [Item]
    let label: (Item) -> Cell

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: JevSpacing.s)], alignment: .leading, spacing: JevSpacing.s) {
            ForEach(items, id: \.self) { item in
                label(item)
            }
        }
    }
}
