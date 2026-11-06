import SwiftUI
import SwiftData
import UIKit

/// Inside one area: its themes and thoughts as watch-style glass bubbles.
/// Drag the background to move, pinch to zoom, pinch far out to go back to the eagle view.
/// Drag a thought onto a theme to move it, or a theme onto another theme to nest it.
struct AreaMapView: View {
    let rootID: UUID
    let fitRequest: Int
    @Binding var selectedThought: Thought?
    @Binding var selectedCluster: Cluster?
    var onExit: () -> Void
    var showToast: (String) -> Void

    @Query private var clusters: [Cluster]
    @Query(sort: \Thought.createdAt) private var thoughts: [Thought]
    @AppStorage("lensEnabled") private var lensEnabled = true

    @State private var camera: CGPoint = .zero
    @State private var scale: CGFloat = 0.9
    @State private var fittedScale: CGFloat = 0.9
    @State private var panStartCamera: CGPoint?
    @State private var pinchStartScale: CGFloat?
    @State private var viewSize: CGSize = .zero
    @State private var didInitialFit = false
    @State private var exiting = false

    @State private var dragging: DragItem?
    @State private var dragLocation: CGPoint?
    @State private var dropTargetID: UUID?

    enum DragItem: Equatable {
        case thought(UUID)
        case cluster(UUID)
    }

    struct Placed {
        let point: CGPoint
        let factor: CGFloat
        let visible: Bool
    }

    private var root: Cluster? { clusters.first { $0.uid == rootID } }

    private var areaClusters: [Cluster] {
        guard let root else { return [] }
        return clusters.filter { $0.uid == root.uid || $0.isDescendant(of: root) }
    }

    private var areaThoughts: [Thought] {
        let ids = Set(areaClusters.map(\.uid))
        return thoughts.filter { thought in
            guard let id = thought.cluster?.uid else { return false }
            return ids.contains(id)
        }
    }

    var body: some View {
        let members = areaClusters
        let memberThoughts = areaThoughts
        let tint = Palette.color(root?.colorIndex ?? -1)

        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ZStack {
                    MapBackground()
                    RadialGradient(colors: [tint.opacity(0.28), tint.opacity(0.04)],
                                   center: .center, startRadius: 10, endRadius: max(size.width, size.height) * 0.8)
                }
                .contentShape(Rectangle())
                .gesture(panGesture)

                Canvas { context, canvasSize in
                    drawLinks(in: &context, size: canvasSize, clusters: members)
                }
                .allowsHitTesting(false)

                ForEach(memberThoughts) { thought in
                    thoughtBubble(thought, size: size)
                }
                ForEach(members) { cluster in
                    clusterBubble(cluster, size: size, members: members)
                }
            }
            .coordinateSpace(.named("area"))
            .simultaneousGesture(pinchGesture)
            .onAppear {
                viewSize = size
                if !didInitialFit {
                    fit(animated: false)
                    didInitialFit = true
                }
            }
            .onChange(of: size) { _, newSize in viewSize = newSize }
            .onChange(of: fitRequest) { _, _ in fit(animated: true) }
            .onChange(of: root == nil) { _, gone in
                if gone { onExit() }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Bubbles

    @ViewBuilder
    private func thoughtBubble(_ thought: Thought, size: CGSize) -> some View {
        let isDragged = dragging == .thought(thought.uid)
        let placed = isDragged ? placedAtFinger(size: size) : place(CGPoint(x: thought.x, y: thought.y), size: size)
        if placed.visible {
            GlassBubble(
                title: thought.label,
                subtitle: nil,
                color: Palette.color(thought.cluster?.colorIndex ?? -1),
                diameter: CGFloat(Layout.thoughtDiameter),
                displayScale: scale * placed.factor,
                isCluster: false,
                pending: thought.needsOrganizing,
                highlighted: false
            )
            .scaleEffect(scale * placed.factor * (isDragged ? 1.12 : 1))
            .shadow(color: .black.opacity(isDragged ? 0.4 : 0), radius: 12, y: 6)
            .zIndex(isDragged ? 10 : 0)
            .onTapGesture { selectedThought = thought }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("area"))
                    .onChanged { value in dragChanged(.thought(thought.uid), value, size: size) }
                    .onEnded { _ in dragEnded() }
            )
            .position(placed.point)
        }
    }

    @ViewBuilder
    private func clusterBubble(_ cluster: Cluster, size: CGSize, members: [Cluster]) -> some View {
        let isDragged = dragging == .cluster(cluster.uid)
        let placed = isDragged ? placedAtFinger(size: size) : place(CGPoint(x: cluster.x, y: cluster.y), size: size)
        if placed.visible {
            GlassBubble(
                title: cluster.name,
                subtitle: cluster.thoughts.isEmpty ? nil : "\(cluster.thoughts.count)",
                color: Palette.color(cluster.colorIndex),
                diameter: diameter(of: cluster),
                displayScale: scale * placed.factor,
                isCluster: true,
                pending: false,
                highlighted: dropTargetID == cluster.uid
            )
            .scaleEffect(scale * placed.factor * (isDragged ? 1.08 : (dropTargetID == cluster.uid ? 1.1 : 1)))
            .animation(.snappy(duration: 0.2), value: dropTargetID)
            .zIndex(isDragged ? 10 : 1)
            .onTapGesture { selectedCluster = cluster }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("area"))
                    .onChanged { value in dragChanged(.cluster(cluster.uid), value, size: size) }
                    .onEnded { _ in dragEnded() }
            )
            .position(placed.point)
        }
    }

    private func diameter(of cluster: Cluster) -> CGFloat {
        CGFloat(Layout.clusterDiameter(depth: cluster.depth))
    }

    // MARK: - Camera and lens

    private func rawScreen(_ world: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: (world.x - camera.x) * scale + size.width / 2,
            y: (world.y - camera.y) * scale + size.height / 2
        )
    }

    /// Apple Watch–style lens: bubbles are pulled towards the centre and shrink
    /// the further they are from it.
    private func place(_ world: CGPoint, size: CGSize) -> Placed {
        let raw = rawScreen(world, size: size)
        guard lensEnabled else {
            let margin: CGFloat = 120
            let visible = raw.x > -margin && raw.x < size.width + margin && raw.y > -margin && raw.y < size.height + margin
            return Placed(point: raw, factor: 1, visible: visible)
        }
        let cx = size.width / 2, cy = size.height / 2
        let rx = max(size.width * 0.62, 1), ry = max(size.height * 0.5, 1)
        let ux = (raw.x - cx) / rx, uy = (raw.y - cy) / ry
        let d = sqrt(ux * ux + uy * uy)
        guard d > 0.0001 else { return Placed(point: raw, factor: 1, visible: true) }
        let t = tanh(d)
        let k = t / d
        let point = CGPoint(x: cx + (raw.x - cx) * k, y: cy + (raw.y - cy) * k)
        let factor = max(0.26, 1 - 0.74 * t * t)
        return Placed(point: point, factor: factor, visible: t < 0.975)
    }

    private func placedAtFinger(size: CGSize) -> Placed {
        let point = dragLocation ?? CGPoint(x: size.width / 2, y: size.height / 2)
        guard lensEnabled else { return Placed(point: point, factor: 1, visible: true) }
        let rx = max(size.width * 0.62, 1), ry = max(size.height * 0.5, 1)
        let ux = (point.x - size.width / 2) / rx, uy = (point.y - size.height / 2) / ry
        let t = min(sqrt(ux * ux + uy * uy), 1)
        return Placed(point: point, factor: max(0.26, 1 - 0.74 * t * t), visible: true)
    }

    // MARK: - Links

    private func drawLinks(in context: inout GraphicsContext, size: CGSize, clusters: [Cluster]) {
        let memberIDs = Set(clusters.map(\.uid))
        for cluster in clusters {
            guard let parent = cluster.parent, memberIDs.contains(parent.uid) else { continue }
            let a = place(CGPoint(x: cluster.x, y: cluster.y), size: size)
            let b = place(CGPoint(x: parent.x, y: parent.y), size: size)
            guard a.visible || b.visible else { continue }
            var path = Path()
            path.move(to: a.point)
            path.addLine(to: b.point)
            context.stroke(path,
                           with: .color(Palette.color(cluster.colorIndex).opacity(0.4)),
                           style: StrokeStyle(lineWidth: max(1, 3 * scale * min(a.factor, b.factor)), lineCap: .round))
        }
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if panStartCamera == nil { panStartCamera = camera }
                guard let start = panStartCamera else { return }
                camera = CGPoint(
                    x: start.x - value.translation.width / scale,
                    y: start.y - value.translation.height / scale
                )
            }
            .onEnded { _ in panStartCamera = nil }
    }

    /// Pinching far enough out leaves the area and returns to the eagle view.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStartScale == nil { pinchStartScale = scale }
                let start = pinchStartScale ?? scale
                scale = min(max(start * value.magnification, 0.1), 2.5)
                if scale < fittedScale * 0.5 { leave() }
            }
            .onEnded { _ in
                pinchStartScale = nil
                if scale < fittedScale * 0.7 {
                    leave()
                } else if scale < fittedScale {
                    withAnimation(.snappy) { scale = fittedScale }
                }
            }
    }

    private func leave() {
        guard !exiting else { return }
        exiting = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onExit()
    }

    private func dragChanged(_ item: DragItem, _ value: DragGesture.Value, size: CGSize) {
        if dragging == nil { dragging = item }
        guard dragging == item else { return }
        dragLocation = value.location

        let target = areaClusters.first { cluster in
            guard canDrop(item, on: cluster) else { return false }
            let placed = place(CGPoint(x: cluster.x, y: cluster.y), size: size)
            guard placed.visible else { return false }
            let radius = diameter(of: cluster) / 2 * scale * placed.factor
            return hypot(placed.point.x - value.location.x, placed.point.y - value.location.y) < radius + 12
        }
        if dropTargetID != target?.uid {
            dropTargetID = target?.uid
            if target != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }

    private func canDrop(_ item: DragItem, on cluster: Cluster) -> Bool {
        switch item {
        case .thought(let id):
            guard let thought = thoughts.first(where: { $0.uid == id }) else { return false }
            return thought.cluster?.uid != cluster.uid
        case .cluster(let id):
            guard let moving = clusters.first(where: { $0.uid == id }) else { return false }
            return cluster.uid != moving.uid
                && !cluster.isInbox
                && !moving.isInbox
                && moving.parent != nil
                && !cluster.isDescendant(of: moving)
                && moving.parent?.uid != cluster.uid
        }
    }

    private func dragEnded() {
        defer {
            withAnimation(.smooth(duration: 0.3)) {
                dragging = nil
                dragLocation = nil
                dropTargetID = nil
            }
        }
        guard let item = dragging,
              let targetID = dropTargetID,
              let target = clusters.first(where: { $0.uid == targetID }) else { return }

        switch item {
        case .thought(let id):
            if let thought = thoughts.first(where: { $0.uid == id }) {
                Organizer.shared.moveManually(thought, to: target)
                showToast("Moved to \(target.pathString)")
            }
        case .cluster(let id):
            if let moving = clusters.first(where: { $0.uid == id }) {
                Organizer.shared.setParent(moving, to: target)
                showToast("\(moving.name) is now inside \(target.name)")
            }
        }
    }

    // MARK: - Camera helpers

    private func fit(animated: Bool) {
        let points: [CGPoint] = areaClusters.map { CGPoint(x: $0.x, y: $0.y) } + areaThoughts.map { CGPoint(x: $0.x, y: $0.y) }
        guard !points.isEmpty, viewSize.width > 0, viewSize.height > 0 else { return }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        let width = maxX - minX + 200
        let height = maxY - minY + 200
        let room: CGFloat = lensEnabled ? 1.5 : 1
        let fitted = min(max(min(viewSize.width * room / width, (viewSize.height - 160) * room / height), 0.25), 1.2)
        let apply = {
            camera = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            scale = fitted
            fittedScale = fitted
        }
        if animated {
            withAnimation(.snappy) { apply() }
        } else {
            apply()
        }
    }
}

/// The deep, softly coloured backdrop behind everything.
struct MapBackground: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.14), Color(red: 0.10, green: 0.07, blue: 0.22), Color(red: 0.04, green: 0.10, blue: 0.18),
                Color(red: 0.08, green: 0.05, blue: 0.18), Color(red: 0.12, green: 0.10, blue: 0.26), Color(red: 0.05, green: 0.12, blue: 0.20),
                Color(red: 0.03, green: 0.05, blue: 0.10), Color(red: 0.09, green: 0.06, blue: 0.18), Color(red: 0.03, green: 0.07, blue: 0.13)
            ]
        )
    }
}
