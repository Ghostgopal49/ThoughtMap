import SwiftUI
import SwiftData
import UIKit

/// The bubble map. Bubbles are packed in a honeycomb and seen through a watch-style lens:
/// big in the middle of the screen, smaller towards the edges.
/// Drag the background to move around, pinch to zoom, tap a bubble to open it,
/// drag a thought onto a cluster to move it, or a cluster onto another cluster to nest it.
struct MapView: View {
    @Query private var clusters: [Cluster]
    @Query(sort: \Thought.createdAt) private var thoughts: [Thought]
    @AppStorage("lensEnabled") private var lensEnabled = true

    // Camera: the world point at the centre of the screen, and the zoom level.
    @State private var camera: CGPoint = .zero
    @State private var scale: CGFloat = 0.9
    @State private var panStartCamera: CGPoint?
    @State private var pinchStartScale: CGFloat?
    @State private var viewSize: CGSize = .zero
    @State private var didInitialFit = false

    // Dragging bubbles.
    @State private var dragging: DragItem?
    @State private var dragLocation: CGPoint?
    @State private var dropTargetID: UUID?

    // Sheets and messages.
    @State private var selectedThought: Thought?
    @State private var selectedCluster: Cluster?
    @State private var showAdd = false
    @State private var showInsights = false
    @State private var showSettings = false
    @State private var toast: String?
    @State private var sorting = false

    enum DragItem: Equatable {
        case thought(UUID)
        case cluster(UUID)
    }

    /// Where a world point ends up on screen, and how much it is shrunk by the lens.
    struct Placed {
        let point: CGPoint
        let factor: CGFloat
        let visible: Bool
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    background
                        .contentShape(Rectangle())
                        .gesture(panGesture)

                    Canvas { context, canvasSize in
                        drawLinks(in: &context, size: canvasSize)
                    }
                    .allowsHitTesting(false)

                    ForEach(thoughts) { thought in
                        thoughtBubble(thought, size: size)
                    }

                    ForEach(clusters) { cluster in
                        clusterBubble(cluster, size: size)
                    }

                    if thoughts.isEmpty && clusters.isEmpty {
                        emptyState
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(.named("map"))
                .simultaneousGesture(pinchGesture)
                .onAppear {
                    viewSize = size
                    if !didInitialFit {
                        fitAll(animated: false)
                        didInitialFit = true
                    }
                }
                .onChange(of: size) { _, newSize in
                    viewSize = newSize
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 10) {
                topBar
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                addButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showAdd) {
            AddThoughtSheet { result in
                if let thought = result.thought {
                    focus(on: thought)
                    showToast("Saved under \(result.path)")
                }
            }
        }
        .sheet(item: $selectedThought) { thought in
            ThoughtDetailView(thought: thought)
        }
        .sheet(item: $selectedCluster) { cluster in
            ClusterDetailView(cluster: cluster)
        }
        .sheet(isPresented: $showInsights) {
            InsightsView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Background and overlay controls

    private var background: some View {
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

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ThoughtMap")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                let pending = thoughts.filter(\.needsOrganizing).count
                if pending > 0 {
                    Button {
                        Task {
                            sorting = true
                            await Organizer.shared.retryAllUnsorted()
                            sorting = false
                        }
                    } label: {
                        Text(sorting ? "Sorting…" : "\(pending) unsorted · Sort now")
                            .font(.caption.weight(.semibold))
                    }
                    .disabled(sorting)
                }
            }
            Spacer()
            iconButton("chart.line.uptrend.xyaxis") { showInsights = true }
            iconButton("scope") { fitAll(animated: true) }
            iconButton("gearshape") { showSettings = true }
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var addButton: some View {
        Button {
            showAdd = true
        } label: {
            Label("New thought", systemImage: "plus")
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Your mind map is empty")
                .font(.title3.weight(.semibold))
            Text("Press your Action Button and speak, or tap New thought. Each thought finds its own bubble cluster.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
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
                DragGesture(minimumDistance: 6, coordinateSpace: .named("map"))
                    .onChanged { value in dragChanged(.thought(thought.uid), value, size: size) }
                    .onEnded { _ in dragEnded() }
            )
            .position(placed.point)
        }
    }

    @ViewBuilder
    private func clusterBubble(_ cluster: Cluster, size: CGSize) -> some View {
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
                DragGesture(minimumDistance: 6, coordinateSpace: .named("map"))
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

    /// Apple Watch–style lens: positions are pulled towards the centre and bubbles shrink
    /// the further they are from it. Turn it off in Settings for a flat map.
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

    /// The dragged bubble follows the finger, sized for wherever the finger is.
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
        let thoughtsByID = Dictionary(thoughts.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })

        // Sub-cluster to its parent: a faint line in the area's colour.
        for cluster in clusters {
            guard let parent = cluster.parent else { continue }
            let a = place(CGPoint(x: cluster.x, y: cluster.y), size: size)
            let b = place(CGPoint(x: parent.x, y: parent.y), size: size)
            guard a.visible || b.visible else { continue }
            var path = Path()
            path.move(to: a.point)
            path.addLine(to: b.point)
            context.stroke(path,
                           with: .color(Palette.color(cluster.colorIndex).opacity(0.35)),
                           style: StrokeStyle(lineWidth: max(1, 3 * scale * min(a.factor, b.factor)), lineCap: .round))
        }

        // Related thoughts across clusters (the loose web), dotted.
        for thought in thoughts {
            for id in thought.relatedIDs {
                guard let other = thoughtsByID[id], other.cluster?.uid != thought.cluster?.uid else { continue }
                let a = place(CGPoint(x: thought.x, y: thought.y), size: size)
                let b = place(CGPoint(x: other.x, y: other.y), size: size)
                guard a.visible && b.visible else { continue }
                var path = Path()
                path.move(to: a.point)
                path.addLine(to: b.point)
                context.stroke(path,
                               with: .color(Color.white.opacity(0.22)),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 6]))
            }
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

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStartScale == nil { pinchStartScale = scale }
                let start = pinchStartScale ?? scale
                scale = min(max(start * value.magnification, 0.15), 2.5)
            }
            .onEnded { _ in pinchStartScale = nil }
    }

    private func dragChanged(_ item: DragItem, _ value: DragGesture.Value, size: CGSize) {
        if dragging == nil { dragging = item }
        guard dragging == item else { return }
        dragLocation = value.location

        let target = clusters.first { cluster in
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

    private func fitAll(animated: Bool) {
        let points: [CGPoint] = clusters.map { CGPoint(x: $0.x, y: $0.y) } + thoughts.map { CGPoint(x: $0.x, y: $0.y) }
        guard !points.isEmpty, viewSize.width > 0, viewSize.height > 0 else {
            camera = .zero
            scale = 0.9
            return
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        let width = maxX - minX + 200
        let height = maxY - minY + 200
        // The lens squeezes the edges, so the map can be a bit bigger than the screen.
        let room: CGFloat = lensEnabled ? 1.5 : 1
        let fitted = min(viewSize.width * room / width, (viewSize.height - 160) * room / height)
        let apply = {
            camera = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            scale = min(max(fitted, 0.2), 1.2)
        }
        if animated {
            withAnimation(.snappy) { apply() }
        } else {
            apply()
        }
    }

    private func focus(on thought: Thought) {
        withAnimation(.snappy) {
            camera = CGPoint(x: thought.x, y: thought.y)
            scale = max(scale, 0.9)
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                if toast == message { toast = nil }
            }
        }
    }
}
