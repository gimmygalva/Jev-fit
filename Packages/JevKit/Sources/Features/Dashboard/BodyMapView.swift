import DesignSystem
import JevDomain
import RecoveryEngine
import SwiftUI

/// Body map (SCR-BD-01): silhouette fronte/retro con le regioni muscolari colorate per recupero.
/// Le regioni sono ellissi in coordinate normalizzate (larghezza 100, altezza 200) e si toccano
/// per vedere percentuale e ore al "pronto".
struct BodyMapView: View {
    let states: [MuscleGroup: MuscleRecovery.MuscleState]
    @Binding var selected: MuscleGroup?

    struct Region: Hashable {
        var muscle: MuscleGroup
        var rect: CGRect
    }

    /// Regioni simmetriche: una per lato quando serve.
    static func mirrored(_ muscle: MuscleGroup, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> [Region] {
        [Region(muscle: muscle, rect: CGRect(x: x, y: y, width: w, height: h)),
         Region(muscle: muscle, rect: CGRect(x: 100 - x - w, y: y, width: w, height: h))]
    }

    static let front: [Region] = {
        var regions: [Region] = []
        regions += mirrored(.frontDelts, x: 22, y: 34, w: 11, h: 10)
        regions += mirrored(.sideDelts, x: 17, y: 36, w: 7, h: 12)
        regions += mirrored(.chest, x: 33, y: 38, w: 16, h: 14)
        regions += mirrored(.biceps, x: 17, y: 50, w: 9, h: 18)
        regions += mirrored(.forearms, x: 13, y: 70, w: 9, h: 22)
        regions.append(Region(muscle: .abs, rect: CGRect(x: 40, y: 54, width: 20, height: 30)))
        regions += mirrored(.obliques, x: 32, y: 58, w: 8, h: 22)
        regions += mirrored(.quads, x: 30, y: 98, w: 17, h: 42)
        regions += mirrored(.adductors, x: 43, y: 100, w: 6, h: 24)
        regions += mirrored(.calves, x: 32, y: 150, w: 12, h: 30)
        return regions
    }()

    static let back: [Region] = {
        var regions: [Region] = []
        regions.append(Region(muscle: .upperBack, rect: CGRect(x: 35, y: 32, width: 30, height: 18)))
        regions += mirrored(.rearDelts, x: 20, y: 35, w: 12, h: 10)
        regions += mirrored(.triceps, x: 17, y: 49, w: 9, h: 19)
        regions += mirrored(.lats, x: 30, y: 50, w: 14, h: 22)
        regions += mirrored(.forearms, x: 13, y: 70, w: 9, h: 22)
        regions.append(Region(muscle: .lowerBack, rect: CGRect(x: 40, y: 72, width: 20, height: 14)))
        regions += mirrored(.glutes, x: 33, y: 86, w: 16, h: 16)
        regions += mirrored(.hamstrings, x: 31, y: 104, w: 16, h: 38)
        regions += mirrored(.calves, x: 32, y: 148, w: 12, h: 30)
        return regions
    }()

    func recovery(_ muscle: MuscleGroup) -> Double { states[muscle]?.recoveryPercent ?? 100 }

    static func color(_ recovery: Double) -> Color {
        recovery >= 90 ? JevColor.mint : recovery >= 60 ? JevColor.amber : JevColor.ember
    }

    var body: some View {
        HStack(spacing: JevSpacing.l) {
            figure(Self.front, label: "Fronte")
            figure(Self.back, label: "Retro")
        }
        .accessibilityElement(children: .contain)
    }

    private func figure(_ regions: [Region], label: LocalizedStringKey) -> some View {
        VStack(spacing: JevSpacing.xs) {
            GeometryReader { proxy in
                let scale = min(proxy.size.width / 100, proxy.size.height / 200)
                let offsetX = (proxy.size.width - 100 * scale) / 2
                ZStack(alignment: .topLeading) {
                    Silhouette()
                        .fill(JevColor.backgroundElevated)
                        .frame(width: 100 * scale, height: 200 * scale)
                        .offset(x: offsetX)
                    ForEach(Array(regions.enumerated()), id: \.offset) { item in
                        let region = item.element
                        let value = recovery(region.muscle)
                        Ellipse()
                            .fill(Self.color(value).opacity(selected == region.muscle ? 1 : 0.75))
                            .overlay(Ellipse().stroke(selected == region.muscle ? JevColor.textPrimary : .clear, lineWidth: 1.5))
                            .frame(width: region.rect.width * scale, height: region.rect.height * scale)
                            .offset(x: offsetX + region.rect.minX * scale, y: region.rect.minY * scale)
                            .onTapGesture { selected = region.muscle }
                            .accessibilityLabel(Text(verbatim: "\(MuscleNames.name(region.muscle)) \(Int(value.rounded()))%"))
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .aspectRatio(0.5, contentMode: .fit)
            Text(label).font(.caption).foregroundStyle(JevColor.textSecondary)
        }
    }
}

/// Sagoma neutra: testa, busto, braccia e gambe in coordinate 100 × 200.
struct Silhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 100, sy = rect.height / 200
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * sx, y: rect.minY + y * sy, width: w * sx, height: h * sy)
        }
        var path = Path()
        path.addEllipse(in: r(40, 4, 20, 24))
        path.addRoundedRect(in: r(30, 30, 40, 60), cornerSize: CGSize(width: 10 * sx, height: 10 * sy))
        path.addRoundedRect(in: r(15, 34, 13, 60), cornerSize: CGSize(width: 6 * sx, height: 6 * sy))
        path.addRoundedRect(in: r(72, 34, 13, 60), cornerSize: CGSize(width: 6 * sx, height: 6 * sy))
        path.addRoundedRect(in: r(30, 86, 19, 100), cornerSize: CGSize(width: 8 * sx, height: 8 * sy))
        path.addRoundedRect(in: r(51, 86, 19, 100), cornerSize: CGSize(width: 8 * sx, height: 8 * sy))
        return path
    }
}

/// Nomi dei muscoli per l'interfaccia.
enum MuscleNames {
    static func name(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: String(localized: "Petto")
        case .lats: String(localized: "Dorsali")
        case .upperBack: String(localized: "Alta schiena")
        case .frontDelts: String(localized: "Deltoidi anteriori")
        case .sideDelts: String(localized: "Deltoidi laterali")
        case .rearDelts: String(localized: "Deltoidi posteriori")
        case .biceps: String(localized: "Bicipiti")
        case .triceps: String(localized: "Tricipiti")
        case .forearms: String(localized: "Avambracci")
        case .abs: String(localized: "Addominali")
        case .obliques: String(localized: "Obliqui")
        case .lowerBack: String(localized: "Lombari")
        case .glutes: String(localized: "Glutei")
        case .quads: String(localized: "Quadricipiti")
        case .hamstrings: String(localized: "Femorali")
        case .adductors: String(localized: "Adduttori")
        case .calves: String(localized: "Polpacci")
        }
    }
}
