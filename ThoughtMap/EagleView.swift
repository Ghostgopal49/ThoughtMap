import SwiftUI

/// One area in the eagle view.
struct AreaSlice: Identifiable {
    let id: UUID
    let name: String
    let colorIndex: Int
    let symbol: String
    let count: Int
    /// Biggest themes inside the area, shown as small bubbles in the wedge.
    let themeSizes: [Int]
}

/// The eagle's-eye view: the screen is split into wedges around a centre point,
/// one wedge per area. Bigger wedges are areas you think about more.
/// Tap a wedge to dive into that area.
struct EagleView: View {
    let slices: [AreaSlice]
    let unsortedCount: Int
    var onOpen: (UUID, UnitPoint) -> Void
    var onOpenUnsorted: () -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let centre = CGPoint(x: size.width / 2, y: size.height * 0.52)
            let angles = wedgeAngles()

            ZStack {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    let start = angles[index].start
                    let end = angles[index].end
                    wedge(slice, start: start, end: end, centre: centre, size: size)
                }

                // Lines between the wedges, like spokes.
                Canvas { context, _ in
                    guard slices.count > 1 else { return }
                    for range in angles {
                        let edge = rayLength(from: centre, angle: range.start.radians, in: size)
                        var path = Path()
                        path.move(to: centre)
                        path.addLine(to: point(from: centre, angle: range.start.radians, distance: edge + 2))
                        context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 1.5)
                    }
                }
                .allowsHitTesting(false)

                hub
                    .position(centre)
            }
        }
    }

    // MARK: - Wedges

    private func wedgeAngles() -> [(start: Angle, end: Angle)] {
        guard !slices.isEmpty else { return [] }
        let total = Double(max(slices.map(\.count).reduce(0, +), 1))
        let even = 1.0 / Double(slices.count)
        // Mix of "equal share" and "share of thoughts", so busy areas get bigger
        // wedges but quiet ones never disappear.
        let shares = slices.map { 0.45 * even + 0.55 * (Double($0.count) / total) }
        let sum = shares.reduce(0, +)
        var cursor = -90.0
        return shares.map { share in
            let width = 360 * share / sum
            defer { cursor += width }
            return (Angle(degrees: cursor), Angle(degrees: cursor + width))
        }
    }

    @ViewBuilder
    private func wedge(_ slice: AreaSlice, start: Angle, end: Angle, centre: CGPoint, size: CGSize) -> some View {
        let color = Palette.color(slice.colorIndex)
        let shape = Wedge(centre: centre, start: start, end: end)
        let mid = (start.radians + end.radians) / 2
        let span = end.radians - start.radians
        let reach = rayLength(from: centre, angle: mid, in: size)
        let labelDistance = max(min(reach * 0.5, reach - 70), 80)
        let labelPoint = point(from: centre, angle: mid, distance: labelDistance)
        // Shrink the label in narrow wedges so it stays inside.
        let room = labelDistance * min(span, .pi)
        let labelScale = min(1, max(0.55, room / 130))

        ZStack {
            shape
                .fill(
                    RadialGradient(colors: [color.opacity(0.10), color.opacity(0.42)],
                                   center: UnitPoint(x: centre.x / max(size.width, 1), y: centre.y / max(size.height, 1)),
                                   startRadius: 30, endRadius: max(size.width, size.height) * 0.7)
                )

            themeBubbles(slice, start: start.radians, span: span, centre: centre, size: size, color: color)

            VStack(spacing: 4) {
                Image(systemName: slice.symbol)
                    .font(.system(size: 26, weight: .semibold))
                Text(slice.name)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(slice.count == 1 ? "1 thought" : "\(slice.count) thoughts")
                    .font(.caption.weight(.medium))
                    .opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(color.opacity(0.35)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .frame(maxWidth: 150)
            .scaleEffect(labelScale)
            .position(labelPoint)
            .allowsHitTesting(false)
        }
        .contentShape(shape)
        .onTapGesture {
            let anchor = UnitPoint(x: labelPoint.x / max(size.width, 1), y: labelPoint.y / max(size.height, 1))
            onOpen(slice.id, anchor)
        }
    }

    /// A few small glass bubbles in the outer part of the wedge, one per big theme.
    @ViewBuilder
    private func themeBubbles(_ slice: AreaSlice, start: Double, span: Double, centre: CGPoint, size: CGSize, color: Color) -> some View {
        let themes = Array(slice.themeSizes.prefix(4))
        ForEach(Array(themes.enumerated()), id: \.offset) { index, count in
            let angle = start + span * Double(index + 1) / Double(themes.count + 1)
            let reach = rayLength(from: centre, angle: angle, in: size)
            let distance = max(reach * 0.8, reach - 60)
            let diameter = CGFloat(22 + min(count, 12) * 3)
            Circle()
                .fill(Color.clear)
                .frame(width: diameter, height: diameter)
                .glassEffect(.regular.tint(color.opacity(0.4)), in: Circle())
                .position(point(from: centre, angle: angle, distance: distance))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Centre hub

    private var hub: some View {
        Button(action: onOpenUnsorted) {
            VStack(spacing: 2) {
                Image(systemName: unsortedCount > 0 ? "tray.full" : "circle.hexagongrid")
                    .font(.system(size: 20, weight: .semibold))
                if unsortedCount > 0 {
                    Text("\(unsortedCount)")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 66, height: 66)
            .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(unsortedCount == 0)
    }

    // MARK: - Geometry

    private func point(from centre: CGPoint, angle: Double, distance: Double) -> CGPoint {
        CGPoint(x: centre.x + cos(angle) * distance, y: centre.y + sin(angle) * distance)
    }

    /// How far a ray from the centre travels before leaving the screen.
    private func rayLength(from centre: CGPoint, angle: Double, in size: CGSize) -> Double {
        let dx = cos(angle), dy = sin(angle)
        var best = Double.greatestFiniteMagnitude
        if dx > 0.0001 { best = min(best, (Double(size.width) - Double(centre.x)) / dx) }
        if dx < -0.0001 { best = min(best, -Double(centre.x) / dx) }
        if dy > 0.0001 { best = min(best, (Double(size.height) - Double(centre.y)) / dy) }
        if dy < -0.0001 { best = min(best, -Double(centre.y) / dy) }
        return best == .greatestFiniteMagnitude ? 200 : best
    }
}

/// A pie slice that reaches past the screen edges, so the screen is fully tiled.
struct Wedge: Shape {
    let centre: CGPoint
    let start: Angle
    let end: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = hypot(rect.width, rect.height) * 1.5
        path.move(to: centre)
        path.addArc(center: centre, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        path.closeSubpath()
        return path
    }
}
