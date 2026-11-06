import SwiftUI
import SwiftData

/// The home screen. Shows the eagle view of all areas; tapping a wedge dives into
/// that area's bubble map, and pinching out comes back up.
struct MapView: View {
    @Query private var clusters: [Cluster]
    @Query(sort: \Thought.createdAt) private var thoughts: [Thought]

    @State private var focusedArea: UUID?
    @State private var zoomAnchor: UnitPoint = .center
    @State private var fitRequest = 0

    @State private var selectedThought: Thought?
    @State private var selectedCluster: Cluster?
    @State private var showAdd = false
    @State private var showInsights = false
    @State private var showSettings = false
    @State private var toast: String?
    @State private var sorting = false

    var body: some View {
        let slices = self.slices
        let unsortedCount = self.unsortedCount
        ZStack {
            MapBackground()
                .ignoresSafeArea()

            if let id = focusedArea {
                AreaMapView(
                    rootID: id,
                    fitRequest: fitRequest,
                    selectedThought: $selectedThought,
                    selectedCluster: $selectedCluster,
                    onExit: { goToEagleView() },
                    showToast: { showToast($0) }
                )
                .id(id)
                .transition(.scale(scale: 0.3, anchor: zoomAnchor).combined(with: .opacity))
                .zIndex(1)
            } else if slices.isEmpty && unsortedCount == 0 {
                emptyState
                    .transition(.opacity)
            } else {
                EagleView(
                    slices: slices,
                    unsortedCount: unsortedCount,
                    onOpen: { id, anchor in open(id, anchor: anchor) },
                    onOpenUnsorted: {
                        if let inbox = clusters.first(where: { $0.isInbox }) {
                            open(inbox.uid, anchor: .center)
                        }
                    }
                )
                .ignoresSafeArea()
                .transition(.scale(scale: 2.4, anchor: zoomAnchor).combined(with: .opacity))
                .zIndex(0)
            }

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
            .zIndex(2)
        }
        .sheet(isPresented: $showAdd) {
            AddThoughtSheet { result in
                if result.thought != nil {
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

    // MARK: - Areas for the eagle view

    private var slices: [AreaSlice] {
        let roots = clusters
            .filter { $0.parent == nil && !$0.isInbox }
            .sorted { $0.createdAt < $1.createdAt }
        var totals: [UUID: Int] = [:]
        var themeTotals: [UUID: [UUID: Int]] = [:]
        for thought in thoughts {
            guard let cluster = thought.cluster else { continue }
            let path = cluster.path
            guard let area = path.first, !area.isInbox else { continue }
            totals[area.uid, default: 0] += 1
            if path.count > 1 {
                themeTotals[area.uid, default: [:]][path[1].uid, default: 0] += 1
            }
        }
        return roots.map { root in
            AreaSlice(
                id: root.uid,
                name: root.name,
                colorIndex: root.colorIndex,
                symbol: root.displaySymbol,
                count: totals[root.uid] ?? 0,
                themeSizes: (themeTotals[root.uid] ?? [:]).values.sorted(by: >)
            )
        }
    }

    private var unsortedCount: Int {
        thoughts.filter { $0.cluster?.isInbox ?? true }.count
    }

    private var focusedCluster: Cluster? {
        guard let focusedArea else { return nil }
        return clusters.first { $0.uid == focusedArea }
    }

    private func open(_ id: UUID, anchor: UnitPoint) {
        zoomAnchor = anchor
        withAnimation(.smooth(duration: 0.5)) { focusedArea = id }
    }

    private func goToEagleView() {
        withAnimation(.smooth(duration: 0.5)) { focusedArea = nil }
    }

    // MARK: - Controls

    private var topBar: some View {
        HStack(spacing: 10) {
            if let area = focusedCluster {
                Button {
                    goToEagleView()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Image(systemName: area.displaySymbol)
                        Text(area.name)
                            .lineLimit(1)
                    }
                    .font(.system(.headline, design: .rounded))
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.glass)
            } else {
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
            }
            Spacer()
            iconButton("chart.line.uptrend.xyaxis") { showInsights = true }
            if focusedArea != nil {
                iconButton("scope") { fitRequest += 1 }
            }
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
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Your mind map is empty")
                .font(.title3.weight(.semibold))
            Text("Press your Action Button and speak, or tap New thought. Each thought finds its own area.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
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
