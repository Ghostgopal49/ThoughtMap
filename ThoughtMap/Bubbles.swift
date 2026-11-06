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

/// A round, translucent glass bubble.
///
/// While the map is still, bubbles use Apple's real Liquid Glass (`liveGlass`).
/// While panning or zooming they switch to a matching "frosted glass" drawn from
/// gradients and highlights, which looks nearly the same but is far cheaper, so
/// movement stays smooth.
struct BubbleFace: View, Equatable {
    let title: String
    let subtitle: String?
    let colorIndex: Int
    let diameter: CGFloat
    let detail: BubbleDetail
    let isCluster: Bool
    let pending: Bool
    let highlighted: Bool
    var liveGlass: Bool = false

    var body: some View {
        let color = Palette.color(colorIndex)
        ZStack {
            switch detail {
            case .dot:
                Circle().fill(color.opacity(isCluster ? 0.8 : 0.5))
            case .plain, .full:
                if liveGlass {
                    Circle()
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(color.opacity(isCluster ? 0.5 : 0.3)), in: Circle())
                        .overlay(innerGlow(color))
                        .transition(.opacity)
                } else {
                    FrostedGlass(color: color, diameter: diameter, strength: isCluster ? 1 : 0.75)
                        .transition(.opacity)
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
        .background(softShadow)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.25), value: liveGlass)
    }

    /// Light gathering at the bottom of the bubble, like light refracted through glass.
    private func innerGlow(_ color: Color) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(isCluster ? 0.45 : 0.3), color.opacity(0)],
                                 center: UnitPoint(x: 0.5, y: 1.05),
                                 startRadius: 0, endRadius: diameter * 0.6))
            .allowsHitTesting(false)
    }

    /// A drawn shadow (much cheaper than `.shadow`), so bubbles float above the background.
    private var softShadow: some View {
        Circle()
            .fill(RadialGradient(colors: [Color.black.opacity(detail == .dot ? 0 : 0.32), Color.black.opacity(0)],
                                 center: .center, startRadius: diameter * 0.35, endRadius: diameter * 0.62))
            .frame(width: diameter * 1.25, height: diameter * 1.25)
            .offset(y: diameter * 0.07)
            .allowsHitTesting(false)
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

/// Frosted glass drawn with layered gradients: a milky tinted body, a bright rim along
/// the top-left edge, a soft highlight, and light pooling at the bottom.
struct FrostedGlass: View {
    let color: Color
    let diameter: CGFloat
    /// 1 for clusters (more colour), lower for thoughts (clearer glass).
    let strength: Double

    var body: some View {
        ZStack {
            // Milky, slightly tinted body.
            Circle()
                .fill(Color.white.opacity(0.08))
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.42 * strength), color.opacity(0.14 * strength)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            // Light pooling at the bottom (refraction).
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.5 * strength), color.opacity(0)],
                                     center: UnitPoint(x: 0.5, y: 1.05),
                                     startRadius: 0, endRadius: diameter * 0.6))
            // Soft sheen near the top.
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: diameter * 0.62, height: diameter * 0.34)
                .offset(y: -diameter * 0.24)
            // Bright rim on the lit side, fading round the edge.
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0.05), Color.white.opacity(0.3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.4
                )
            // A faint darker inner edge for thickness.
            Circle()
                .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.7)
                .padding(1.4)
        }
    }
}
