import SwiftUI
import SwiftData
import UIKit

/// The infinite canvas: drag the background to pan, pinch to zoom,
/// drag a thought onto a cluster to move it, drag a cluster to rearrange.
struct MapView: View {
    @Query private var clusters: [Cluster]
    @Query(sort: \Thought.createdAt) private var thoughts: [Thought]

    // Camera: the world point at the centre of the screen, and the zoom level.
    @State private var camera: CGPoint = .zero
    @State private var scale: CGFloat = 0.7
    @State private var panStartCamera: CGPoint?
    @State private var pinchStartScale: CGFloat?
    @State private var viewSize: CGSize = .zero
    @State private var didInitialFit = false

    // Dragging bubbles.
    @State private var dragging: DragItem?
    @State private var dragDelta: CGSize = .zero
    @State private var movingClusterIDs: Set<UUID> = []
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

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    Color(.systemGroupedBackground)
                        .contentShape(Rectangle())
                        .gesture(panGesture)

                    Canvas { context, canvasSize in
                        drawBackground(in: &context, size: canvasSize)
                    }
                    .allowsHitTesting(false)

                    ForEach(thoughts) { thought in
                        if dragging == .thought(thought.uid) || isVisible(position(of: thought), size: size) {
                            thoughtView(thought, size: size)
                        }
                    }

                    ForEach(clusters) { cluster in
                        if movingClusterIDs.contains(cluster.uid) || isVisible(position(of: cluster), size: size, margin: 300) {
                            clusterView(cluster, size: size)
                        }
                    }

                    if thoughts.isEmpty && clusters.isEmpty {
                        emptyState
                            .allowsHitTesting(false)
                    }
                }
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
                        .background(.regularMaterial, in: Capsule())
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

    // MARK: - Overlay controls

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
            Text("Press your Action Button and speak, or tap New thought. Each thought finds its own cluster.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
    }

    // MARK: - Bubbles

    @ViewBuilder
    private func thoughtView(_ thought: Thought, size: CGSize) -> some View {
        ThoughtBubble(
            label: thought.label,
            color: Palette.color(thought.cluster?.colorIndex ?? -1),
            pending: thought.needsOrganizing,
            lifted: dragging == .thought(thought.uid)
        )
        .scaleEffect(scale)
        .onTapGesture { selectedThought = thought }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in thoughtDragChanged(thought, value) }
                .onEnded { _ in thoughtDragEnded(thought) }
        )
        .position(toScreen(position(of: thought), size: size))
    }

    @ViewBuilder
    private func clusterView(_ cluster: Cluster, size: CGSize) -> some View {
        ClusterBubble(
            name: cluster.name,
            color: Palette.color(cluster.colorIndex),
            diameter: diameter(of: cluster),
            count: cluster.thoughts.count,
            highlighted: dropTargetID == cluster.uid,
            isInbox: cluster.isInbox
        )
        .scaleEffect(scale)
        .onTapGesture { selectedCluster = cluster }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in clusterDragChanged(cluster, value) }
                .onEnded { _ in clusterDragEnded(cluster) }
        )
        .position(toScreen(position(of: cluster), size: size))
    }

    private func diameter(of cluster: Cluster) -> CGFloat {
        CGFloat(Layout.clusterDiameter(depth: cluster.depth, count: cluster.thoughts.count))
    }

    // MARK: - Geometry

    private func toScreen(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - camera.x) * scale + size.width / 2,
            y: (point.y - camera.y) * scale + size.height / 2
        )
    }

    private func isVisible(_ point: CGPoint, size: CGSize, margin: CGFloat = 160) -> Bool {
        let p = toScreen(point, size: size)
        return p.x > -margin && p.x < size.width + margin && p.y > -margin && p.y < size.height + margin
    }

    private func position(of thought: Thought) -> CGPoint {
        var offset = CGSize.zero
        if dragging == .thought(thought.uid) {
            offset = dragDelta
        } else if let id = thought.cluster?.uid, movingClusterIDs.contains(id) {
            offset = dragDelta
        }
        return CGPoint(x: CGFloat(thought.x) + offset.width, y: CGFloat(thought.y) + offset.height)
    }

    private func position(of cluster: Cluster) -> CGPoint {
        let offset = movingClusterIDs.contains(cluster.uid) ? dragDelta : .zero
        return CGPoint(x: CGFloat(cluster.x) + offset.width, y: CGFloat(cluster.y) + offset.height)
    }

    // MARK: - Drawing links and the dot grid

    private func drawBackground(in context: inout GraphicsContext, size: CGSize) {
        // Dot grid, so panning feels like moving over paper.
        let spacing: CGFloat = scale < 0.35 ? 240 : 60
        let halfWidth = size.width / 2 / scale
        let halfHeight = size.height / 2 / scale
        let startX = floor((camera.x - halfWidth) / spacing) * spacing
        let startY = floor((camera.y - halfHeight) / spacing) * spacing
        let columns = Int((halfWidth * 2) / spacing) + 2
        let rows = Int((halfHeight * 2) / spacing) + 2
        if columns * rows < 3000 {
            var dots = Path()
            for column in 0..<columns {
                for row in 0..<rows {
                    let world = CGPoint(x: startX + CGFloat(column) * spacing, y: startY + CGFloat(row) * spacing)
                    let p = toScreen(world, size: size)
                    dots.addEllipse(in: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4))
                }
            }
            context.fill(dots, with: .color(Color.gray.opacity(0.22)))
        }

        let thoughtsByID = Dictionary(thoughts.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })

        // Cluster to parent cluster.
        for cluster in clusters {
            guard let parent = cluster.parent else { continue }
            var path = Path()
            path.move(to: toScreen(position(of: cluster), size: size))
            path.addLine(to: toScreen(position(of: parent), size: size))
            context.stroke(path,
                           with: .color(Palette.color(cluster.colorIndex).opacity(0.55)),
                           style: StrokeStyle(lineWidth: max(1, 4 * scale), lineCap: .round))
        }

        // Thought to its cluster.
        for thought in thoughts {
            guard let cluster = thought.cluster else { continue }
            var path = Path()
            path.move(to: toScreen(position(of: thought), size: size))
            path.addLine(to: toScreen(position(of: cluster), size: size))
            context.stroke(path,
                           with: .color(Palette.color(cluster.colorIndex).opacity(0.35)),
                           style: StrokeStyle(lineWidth: max(0.6, 1.5 * scale), lineCap: .round))
        }

        // Related thoughts (the loose web), dotted.
        for thought in thoughts {
            for id in thought.relatedIDs {
                guard let other = thoughtsByID[id] else { continue }
                var path = Path()
                path.move(to: toScreen(position(of: thought), size: size))
                path.addLine(to: toScreen(position(of: other), size: size))
                context.stroke(path,
                               with: .color(Color.secondary.opacity(0.45)),
                               style: StrokeStyle(lineWidth: max(0.6, 1.2 * scale), lineCap: .round, dash: [3, 6]))
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
                scale = min(max(start * value.magnification, 0.12), 3.0)
            }
            .onEnded { _ in pinchStartScale = nil }
    }

    private func thoughtDragChanged(_ thought: Thought, _ value: DragGesture.Value) {
        if dragging == nil { dragging = .thought(thought.uid) }
        guard dragging == .thought(thought.uid) else { return }
        dragDelta = CGSize(width: value.translation.width / scale, height: value.translation.height / scale)

        let point = position(of: thought)
        let target = clusters.first { cluster in
            cluster.uid != thought.cluster?.uid &&
            hypot(CGFloat(cluster.x) - point.x, CGFloat(cluster.y) - point.y) < diameter(of: cluster) / 2 + 12
        }
        if dropTargetID != target?.uid {
            dropTargetID = target?.uid
            if target != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }

    private func thoughtDragEnded(_ thought: Thought) {
        if dragging == .thought(thought.uid) {
            if let id = dropTargetID, let target = clusters.first(where: { $0.uid == id }) {
                Organizer.shared.moveManually(thought, to: target)
                showToast("Moved to \(target.pathString)")
            } else {
                thought.x += Double(dragDelta.width)
                thought.y += Double(dragDelta.height)
                Organizer.shared.save()
            }
        }
        resetDrag()
    }

    private func clusterDragChanged(_ cluster: Cluster, _ value: DragGesture.Value) {
        if dragging == nil {
            dragging = .cluster(cluster.uid)
            movingClusterIDs = Set(clusters.filter { $0.uid == cluster.uid || $0.isDescendant(of: cluster) }.map(\.uid))
        }
        guard dragging == .cluster(cluster.uid) else { return }
        dragDelta = CGSize(width: value.translation.width / scale, height: value.translation.height / scale)
    }

    private func clusterDragEnded(_ cluster: Cluster) {
        if dragging == .cluster(cluster.uid) {
            Organizer.shared.shift(cluster, dx: Double(dragDelta.width), dy: Double(dragDelta.height))
        }
        resetDrag()
    }

    private func resetDrag() {
        dragging = nil
        dragDelta = .zero
        movingClusterIDs = []
        dropTargetID = nil
    }

    // MARK: - Camera helpers

    private func fitAll(animated: Bool) {
        let points: [CGPoint] = clusters.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) } + thoughts.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        guard !points.isEmpty, viewSize.width > 0, viewSize.height > 0 else {
            camera = .zero
            scale = 0.7
            return
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        let width = maxX - minX + 340
        let height = maxY - minY + 340
        let fitted = min(viewSize.width / width, (viewSize.height - 180) / height)
        let apply = {
            camera = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            scale = min(max(fitted, 0.15), 1.1)
        }
        if animated {
            withAnimation(.snappy) { apply() }
        } else {
            apply()
        }
    }

    private func focus(on thought: Thought) {
        withAnimation(.snappy) {
            camera = CGPoint(x: CGFloat(thought.x), y: CGFloat(thought.y))
            scale = max(scale, 0.8)
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
