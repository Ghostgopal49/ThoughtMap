import SwiftUI

/// How much detail a bubble shows, based on how big it is on screen.
/// Only changes when crossing a threshold, so bubbles don't redraw on every frame of a pan.
enum BubbleDetail: Equatable {
    case dot, plain, full

    static func forSize(_ onScreen: CGFloat) -> BubbleDetail {
        if onScreen < 28 { return .dot }
        if onScreen < 46 { return .plain }
        return .full
    }
}

/// A round, translucent bubble.
/// Clusters (few per screen) use Apple's real Liquid Glass. Thoughts (many) use a light
/// "glass look" made of gradients and a highlight, which looks similar but is far cheaper
/// to draw, so panning and zooming stay smooth.
struct BubbleFace: View, Equatable {
    let title: String
    let subtitle: String?
    let colorIndex: Int
    let diameter: CGFloat
    let detail: BubbleDetail
    let isCluster: Bool
    let pending: Bool
    let highlighted: Bool

    var body: some View {
        let color = Palette.color(colorIndex)
        ZStack {
            switch detail {
            case .dot:
                Circle().fill(color.opacity(isCluster ? 0.85 : 0.55))
            case .plain, .full:
                if isCluster {
                    Circle()
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(color.opacity(0.55)), in: Circle())
                } else {
                    glassLook(color)
                }
                if detail == .full {
                    label
                }
            }
            if pending {
                Circle()
                    .strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            if highlighted {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
    }

    private func glassLook(_ color: Color) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.55), color.opacity(0.18)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0)],
                                     center: UnitPoint(x: 0.32, y: 0.22),
                                     startRadius: 0, endRadius: diameter * 0.5))
            Circle()
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.06)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.2)
        }
    }

    private var label: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: isCluster ? 15 : 11.5, weight: isCluster ? .bold : .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(isCluster ? 2 : 3)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(.white)
        .padding(diameter * 0.16)
    }
}
