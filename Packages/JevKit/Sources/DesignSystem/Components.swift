import SwiftUI

// Componenti di base del design system (Agent 02, M3). Le stringhe arrivano già localizzate
// dal chiamante (LocalizedStringKey), gli identificatori di accessibilità li sceglie la feature.

/// Pulsante principale a tutta larghezza, alto 56 pt (usabile in palestra, SCREEN_MAP §2).
public struct JevPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JevFont.headline)
            .frame(maxWidth: .infinity, minHeight: JevHitTarget.gym)
            .foregroundStyle(isEnabled ? JevColor.onIon : JevColor.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: JevRadius.button, style: .continuous)
                    .fill(isEnabled ? JevColor.ion : JevColor.backgroundElevated)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// Pulsante secondario testuale ("Salta", "Indietro").
public struct JevSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JevFont.body)
            .foregroundStyle(JevColor.textSecondary)
            .frame(minHeight: JevHitTarget.standard)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Contenitore "card" con il raggio e il padding del design system.
public struct JevCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(JevSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: JevRadius.card, style: .continuous)
                    .fill(JevColor.backgroundCard)
            )
    }
}

/// Opzione selezionabile a tutta larghezza (obiettivo, esperienza, livello di attività…).
/// Lo stato selezionato è comunicato da bordo, simbolo e tratto di accessibilità, non solo dal
/// colore (PS-A11Y-03).
public struct JevSelectionCard: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let isSelected: Bool
    private let isEnabled: Bool
    private let action: () -> Void

    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        isSelected: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: JevSpacing.m) {
                VStack(alignment: .leading, spacing: JevSpacing.xs) {
                    Text(title)
                        .font(JevFont.headline)
                        .foregroundStyle(JevColor.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(JevFont.secondary)
                            .foregroundStyle(JevColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: JevSpacing.s)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? JevColor.ion : JevColor.hairline)
                    .accessibilityHidden(true)
            }
            .padding(JevSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: JevRadius.card, style: .continuous)
                    .fill(JevColor.backgroundCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: JevRadius.card, style: .continuous)
                    .strokeBorder(isSelected ? JevColor.ion : JevColor.hairline, lineWidth: isSelected ? 2 : 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Chip selezionabile per scelte multiple compatte (giorni, attrezzatura, muscoli).
public struct JevChip: View {
    private let title: LocalizedStringKey
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(JevFont.secondary.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? JevColor.onIon : JevColor.textPrimary)
                .padding(.horizontal, JevSpacing.m)
                .frame(minHeight: JevHitTarget.standard)
                .background(
                    Capsule().fill(isSelected ? JevColor.ion : JevColor.backgroundCard)
                )
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : JevColor.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Barra di avanzamento a segmenti dell'onboarding.
public struct JevStepProgress: View {
    private let current: Int
    private let total: Int

    /// `current` parte da 0.
    public init(current: Int, total: Int) {
        self.current = current
        self.total = max(total, 1)
    }

    public var body: some View {
        HStack(spacing: JevSpacing.xs) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? JevColor.ion : JevColor.hairline)
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Avanzamento"))
        .accessibilityValue(Text(verbatim: "\(min(current + 1, total))/\(total)"))
    }
}

/// Messaggio inline di avviso o validazione: simbolo + testo, mai solo colore.
public struct JevInlineNotice: View {
    private let text: LocalizedStringKey

    public init(_ text: LocalizedStringKey) {
        self.text = text
    }

    public var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(JevFont.secondary)
        .foregroundStyle(JevColor.warning)
    }
}
