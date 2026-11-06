import SwiftUI

/// A round "liquid glass" bubble, tinted with the colour of its area.
/// When it is drawn very small (zoomed out or at the edge of the lens) it switches to
/// a plain circle, which keeps scrolling smooth with many bubbles.
struct GlassBubble: View {
    let title: String
    let subtitle: String?
    let color: Color
    let diameter: CGFloat
    /// Final on-screen size factor (zoom × lens), used for level of detail.
    let displayScale: CGFloat
    let isCluster: Bool
    let pending: Bool
    let highlighted: Bool

    private var onScreen: CGFloat { diameter * displayScale }

    var body: some View {
        ZStack {
            if onScreen < 30 {
                Circle()
                    .fill(color.opacity(isCluster ? 0.85 : 0.55))
            } else {
                Circle()
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(color.opacity(isCluster ? 0.55 : 0.28)), in: Circle())
                if isCluster {
                    Circle()
                        .fill(
                            RadialGradient(colors: [color.opacity(0.45), color.opacity(0.05)],
                                           center: .topLeading, startRadius: 4, endRadius: diameter)
                        )
                        .allowsHitTesting(false)
                }
                if onScreen > 44 {
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
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .padding(diameter * 0.16)
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
}
