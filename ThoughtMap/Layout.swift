import Foundation
import CoreGraphics

/// Packs every bubble into a tight honeycomb, like the Apple Watch app grid.
/// Positions are recalculated from the structure (which thought is in which cluster),
/// so the map always stays neat. All values are in "world" points.
enum Layout {
    static let thoughtDiameter = 80.0
    static let gap = 6.0

    static func clusterDiameter(depth: Int) -> Double {
        switch depth {
        case 0: return 138
        case 1: return 112
        default: return 96
        }
    }

    struct Positions {
        var clusters: [UUID: CGPoint] = [:]
        var thoughts: [UUID: CGPoint] = [:]
    }

    /// A cluster with its thoughts and sub-clusters, laid out around its own centre.
    private struct Group {
        var radius: Double
        var clusters: [UUID: CGPoint]
        var thoughts: [UUID: CGPoint]
    }

    static func compute(clusters: [Cluster], thoughts: [Thought]) -> Positions {
        var thoughtsByCluster: [UUID: [Thought]] = [:]
        for thought in thoughts {
            if let cluster = thought.cluster {
                thoughtsByCluster[cluster.uid, default: []].append(thought)
            }
        }
        var childrenByCluster: [UUID: [Cluster]] = [:]
        for cluster in clusters {
            if let parent = cluster.parent {
                childrenByCluster[parent.uid, default: []].append(cluster)
            }
        }

        func layoutGroup(_ cluster: Cluster, depth: Int) -> Group {
            var group = Group(radius: 0, clusters: [cluster.uid: .zero], thoughts: [:])
            let core = clusterDiameter(depth: depth) / 2
            let step = thoughtDiameter + gap

            // Thoughts in rings around the cluster, each ring staggered like a honeycomb.
            let own = (thoughtsByCluster[cluster.uid] ?? []).sorted { $0.createdAt < $1.createdAt }
            var extent = core
            var ring = 1
            var radius = core + gap + thoughtDiameter / 2
            var slots = max(6, Int((2 * Double.pi * radius / step).rounded(.down)))
            var slot = 0
            for thought in own {
                if slot == slots {
                    ring += 1
                    slot = 0
                    radius += step * 0.9
                    slots = max(6, Int((2 * Double.pi * radius / step).rounded(.down)))
                }
                let angle = 2 * Double.pi * Double(slot) / Double(slots) + Double(ring) * 0.5 - Double.pi / 2
                group.thoughts[thought.uid] = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                extent = radius + thoughtDiameter / 2
                slot += 1
            }

            // Sub-clusters fan outwards, beyond this cluster's thoughts.
            let children = (childrenByCluster[cluster.uid] ?? []).sorted { $0.createdAt < $1.createdAt }
            var outer = extent
            if !children.isEmpty, depth < 10 {
                let childGroups = children.map { layoutGroup($0, depth: depth + 1) }
                let maxArc = depth == 0 ? 2 * Double.pi : 1.5 * Double.pi
                var base = extent + 14
                var distances: [Double] = []
                var widths: [Double] = []
                for _ in 0..<80 {
                    distances = childGroups.map { base + $0.radius }
                    widths = zip(childGroups, distances).map { group, distance in
                        2 * asin(min(1, (group.radius + 8) / distance))
                    }
                    if widths.reduce(0, +) <= maxArc { break }
                    base += 40
                }
                let total = widths.reduce(0, +)
                var cursor = depth == 0 ? -Double.pi / 2 : -total / 2
                for (index, child) in childGroups.enumerated() {
                    let angle = cursor + widths[index] / 2
                    cursor += widths[index]
                    let distance = distances[index]
                    let centre = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
                    for (id, point) in child.clusters {
                        group.clusters[id] = add(rotate(point, by: angle), centre)
                    }
                    for (id, point) in child.thoughts {
                        group.thoughts[id] = add(rotate(point, by: angle), centre)
                    }
                    outer = max(outer, distance + child.radius)
                }
            }
            group.radius = outer
            return group
        }

        // Top-level clusters: oldest first, packed as close to the middle as they fit.
        // "Unsorted" always goes last so it never pushes the others around.
        let roots = clusters
            .filter { $0.parent == nil }
            .sorted { a, b in
                if a.isInbox != b.isInbox { return !a.isInbox }
                return a.createdAt < b.createdAt
            }

        var result = Positions()
        var placed: [(centre: CGPoint, radius: Double)] = []
        for root in roots {
            let group = layoutGroup(root, depth: 0)
            let centre = findSpot(radius: group.radius, placed: placed)
            placed.append((centre, group.radius))
            for (id, point) in group.clusters { result.clusters[id] = add(point, centre) }
            for (id, point) in group.thoughts { result.thoughts[id] = add(point, centre) }
        }
        return result
    }

    /// Walks outwards along a spiral from the middle until the group fits without overlapping.
    private static func findSpot(radius: Double, placed: [(centre: CGPoint, radius: Double)]) -> CGPoint {
        if placed.isEmpty { return .zero }
        for i in 0..<60_000 {
            let theta = Double(i) * 0.12
            let r = 9.0 * theta
            let candidate = CGPoint(x: cos(theta) * r, y: sin(theta) * r)
            let fits = placed.allSatisfy { other in
                hypot(Double(candidate.x - other.centre.x), Double(candidate.y - other.centre.y)) >= radius + other.radius + 20
            }
            if fits { return candidate }
        }
        let far = placed.map { Double($0.centre.x) + $0.radius }.max() ?? 0
        return CGPoint(x: far + radius + 40, y: 0)
    }

    private static func rotate(_ p: CGPoint, by angle: Double) -> CGPoint {
        let x = Double(p.x), y = Double(p.y)
        return CGPoint(x: x * cos(angle) - y * sin(angle), y: x * sin(angle) + y * cos(angle))
    }

    private static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: a.x + b.x, y: a.y + b.y)
    }
}
