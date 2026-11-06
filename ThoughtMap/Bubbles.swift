import SwiftUI

struct ClusterBubble: View {
    let name: String
    let color: Color
    let diameter: CGFloat
    let count: Int
    let highlighted: Bool
    let isInbox: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isInbox ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(color.gradient))
            Circle()
                .strokeBorder(highlighted ? Color.primary : Color.white.opacity(0.35),
                              lineWidth: highlighted ? 5 : 1.5)
            VStack(spacing: 2) {
                Text(name)
                    .font(.system(size: diameter > 120 ? 18 : 15, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .opacity(0.75)
                }
            }
            .foregroundStyle(isInbox ? Color.primary : Color.white)
            .padding(diameter * 0.14)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .scaleEffect(highlighted ? 1.08 : 1)
        .animation(.snappy, value: highlighted)
        .contentShape(Circle())
    }
}

struct ThoughtBubble: View {
    let label: String
    let color: Color
    let pending: Bool
    let lifted: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 170)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(pending ? Color.gray : color.opacity(0.75),
                                  style: StrokeStyle(lineWidth: 1.5, dash: pending ? [4, 3] : []))
            )
            .shadow(color: .black.opacity(lifted ? 0.25 : 0.08), radius: lifted ? 10 : 3, y: lifted ? 6 : 1)
            .scaleEffect(lifted ? 1.08 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
