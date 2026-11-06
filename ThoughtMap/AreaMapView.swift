import SwiftUI
import SwiftData
import UIKit

/// A plain copy of what's needed to draw one bubble. Built once per data change,
/// so panning and zooming never touch the database.
struct BubbleItem: Identifiable {
    let id: UUID
    let isCluster: Bool
    let title: String
    let subtitle: String?
    let colorIndex: Int
    let world: CGPoint
    let diameter: CGFloat
    let pending: Bool
    // For drag-and-drop rules.
    let clusterID: UUID?        // a thought's current cluster
    let parentID: UUID?         // a cluster's parent
    let ancestorIDs: Set<UUID>  // a cluster's ancestors
    let isInbox: Bool
    let parentWorld: CGPoint?   // for the line to the parent cluster
}

/// Inside one area: its themes and thoughts as watch-style bubbles.
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
    @Query private var thoughts: [Thought]
    @AppStorage("lensEnabled") private var lensEnabled = true

    @State private var items: [BubbleItem] = []
    @State private var tintIndex: Int = -1

    @State private var camera: CGPoint = .zero
    @State private var scale: CGFloat = 0.9
    @State private var fittedScale: CGFloat = 0.9
    @State private var panStartCamera: CGPoint?
    @State private var pinchStartScale: CGFloat?
    @State private var viewSize: CGSize = .zero
    @State private var didInitialFit = false
    @State private var exiting = false

    @State private var draggingID: UUID?
    @State private var dragLocation: CGPoint?
    @State private var dropTargetID: UUID?

    struct Placed {
        let point: CGPoint
        let factor: CGFloat
        let visible: Bool
    }

    var body: some View {
        let version = Organizer.shared.version
        let tint = Palette.color(tintIndex)

        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RadialGradient(colors: [tint.opacity(0.28), tint.opacity(0.04)],
                               center: .center, startRadius: 10, endRadius: max(size.width, size.height) * 0.8)
                    .contentShape(Rectangle())
                    .gesture(panGesture)

                Canvas { context, canvasSize in
                    drawLinks(in: &context, size: canvasSize)
                }
                .allowsHitTesting(false)

                ForEach(items) { item in
                    bubble(item, size: size)
                }
            }
            .coordinateSpace(.named("area"))
            .simultaneousGesture(pinchGesture)
            .onAppear {
                viewSize = size
                rebuild()
                if !didInitialFit {
                    fit(animated: false)
                    didInitialFit = true
                }
            }
            .onChange(of: size) { _, newSize in viewSize = newSize }
            .onChange(of: fitRequest) { _, _ in fit(animated: true) }
            .onChange(of: version) { _, _ in
                withAnimation(.smooth(duration: 0.45)) { rebuild() }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Snapshot

    private func rebuild() {
        guard let root = clusters.first(where: { $0.uid == rootID }) else {
            items = []
            onExit()
            return
        }
        tintIndex = root.colorIndex
        let members = clusters.filter { $0.uid == root.uid || $0.isDescendant(of: root) }
        let memberIDs = Set(members.map(\.uid))
        var counts: [UUID: Int] = [:]
        var built: [BubbleItem] = []

        for thought in thoughts {
            guard let cluster = thought.cluster, memberIDs.contains(cluster.uid) else { continue }
            counts[cluster.uid, default: 0] += 1
            built.append(BubbleItem(
                id: thought.uid, isCluster: false, title: thought.label, subtitle: nil,
                colorIndex: cluster.colorIndex, world: CGPoint(x: thought.x, y: thought.y),
                diameter: CGFloat(Layout.thoughtDiameter), pending: thought.needsOrganizing,
                clusterID: cluster.uid, parentID: nil, ancestorIDs: [], isInbox: false, parentWorld: nil
            ))
        }
        for cluster in members {
            let path = cluster.path
            let parent = cluster.parent
            built.append(BubbleItem(
                id: cluster.uid, isCluster: true, title: cluster.name,
                subtitle: (counts[cluster.uid] ?? 0) > 0 ? "\(counts[cluster.uid] ?? 0)" : nil,
                colorIndex: cluster.colorIndex, world: CGPoint(x: cluster.x, y: cluster.y),
                diameter: CGFloat(Layout.clusterDiameter(depth: path.count - 1)), pending: false,
                clusterID: nil, parentID: parent?.uid,
                ancestorIDs: Set(path.dropLast().map(\.uid)), isInbox: cluster.isInbox,
                parentWorld: parent.flatMap { p in memberIDs.contains(p.uid) ? CGPoint(x: p.x, y: p.y) : nil }
            ))
        }
        items = built
    }

    // MARK: - Bubbles

    @ViewBuilder
    private func bubble(_ item: BubbleItem, size: CGSize) -> some View {
        let isDragged = draggingID == item.id
        let placed = isDragged ? placedAtFinger(size: size) : place(item.world, size: size)
        if placed.visible {
            let onScreen = item.diameter * scale * placed.factor
            let face = BubbleFace(
                title: item.title,
                subtitle: item.subtitle,
                colorIndex: item.colorIndex,
                diameter: item.diameter,
                detail: BubbleDetail.forSize(onScreen),
                isCluster: item.isCluster,
                pending: item.pending,
                highlighted: dropTargetID == item.id
            )
            .equatable()
            .scaleEffect(scale * placed.factor * (isDragged ? 1.1 : (dropTargetID == item.id ? 1.1 : 1)))

            Group {
                if isDragged {
                    face.shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                } else {
                    face
                }
            }
            .zIndex(isDragged ? 10 : (item.isCluster ? 1 : 0))
            .onTapGesture { open(item) }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("area"))
                    .onChanged { value in dragChanged(item, value, size: size) }
                    .onEnded { _ in dragEnded() }
            )
            .position(placed.point)
        }
    }

    private func open(_ item: BubbleItem) {
        if item.isCluster {
            selectedCluster = clusters.first { $0.uid == item.id }
        } else {
            selectedThought = thoughts.first { $0.uid == item.id }
        }
    }

    // MARK: - Camera and lens

    /// Apple Watch–style lens: bubbles are pulled towards the centre and shrink
    /// the further they are from it.
    private func place(_ world: CGPoint, size: CGSize) -> Placed {
        let raw = CGPoint(
            x: (world.x - camera.x) * scale + size.width / 2,
            y: (world.y - camera.y) * scale + size.height / 2
        )
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

    private func drawLinks(in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for item in items where item.isCluster {
            guard let parentWorld = item.parentWorld else { continue }
            let a = place(item.world, size: size)
            let b = place(parentWorld, size: size)
            guard a.visible || b.visible else { continue }
            path.move(to: a.point)
            path.addLine(to: b.point)
        }
        context.stroke(path,
                       with: .color(Palette.color(tintIndex).opacity(0.4)),
                       style: StrokeStyle(lineWidth: max(1, 2.5 * scale), lineCap: .round))
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

    private func dragChanged(_ item: BubbleItem, _ value: DragGesture.Value, size: CGSize) {
        if draggingID == nil { draggingID = item.id }
        guard draggingID == item.id else { return }
        dragLocation = value.location

        let target = items.first { candidate in
            guard candidate.isCluster, canDrop(item, on: candidate) else { return false }
            let placed = place(candidate.world, size: size)
            guard placed.visible else { return false }
            let radius = candidate.diameter / 2 * scale * placed.factor
            return hypot(placed.point.x - value.location.x, placed.point.y - value.location.y) < radius + 12
        }
        if dropTargetID != target?.id {
            dropTargetID = target?.id
            if target != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }

    private func canDrop(_ moving: BubbleItem, on target: BubbleItem) -> Bool {
        if !moving.isCluster {
            return moving.clusterID != target.id
        }
        return target.id != moving.id
            && !target.isInbox
            && !moving.isInbox
            && moving.parentID != nil
            && !target.ancestorIDs.contains(moving.id)
            && moving.parentID != target.id
    }

    private func dragEnded() {
        let movingID = draggingID
        let targetID = dropTargetID
        withAnimation(.smooth(duration: 0.3)) {
            draggingID = nil
            dragLocation = nil
            dropTargetID = nil
        }
        guard let movingID, let targetID,
              let target = clusters.first(where: { $0.uid == targetID }) else { return }

        if let thought = thoughts.first(where: { $0.uid == movingID }) {
            Organizer.shared.moveManually(thought, to: target)
            showToast("Moved to \(target.pathString)")
        } else if let moving = clusters.first(where: { $0.uid == movingID }) {
            Organizer.shared.setParent(moving, to: target)
            showToast("\(moving.name) is now inside \(target.name)")
        }
    }

    // MARK: - Camera helpers

    private func fit(animated: Bool) {
        let points = items.map(\.world)
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
