import Foundation
import CoreGraphics

/// Where new bubbles go on the infinite canvas. All values are in "world" points.
enum Layout {
    static let goldenAngle = 2.399963

    /// Bubble size of a cluster. Bigger for top-level clusters and for busy ones.
    static func clusterDiameter(depth: Int, count: Int) -> Double {
        let base: Double
        switch depth {
        case 0: base = 124
        case 1: base = 100
        default: base = 84
        }
        return base + Double(min(count, 30)) * 2.5
    }

    /// Top-level clusters spiral outwards from the middle. Index 0 is the centre (used by "Unsorted").
    static func rootPosition(index: Int) -> CGPoint {
        guard index > 0 else { return .zero }
        let angle = Double(index) * goldenAngle
        let radius = 560 * Double(index).squareRoot()
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }

    /// Child clusters fan out from their parent, pointing away from the grandparent.
    static func childPosition(parent: Cluster, index: Int) -> CGPoint {
        let anchor: CGPoint
        if let grandparent = parent.parent {
            anchor = CGPoint(x: grandparent.x, y: grandparent.y)
        } else {
            anchor = .zero
        }
        var base = atan2(parent.y - anchor.y, parent.x - anchor.x)
        if abs(parent.x - anchor.x) < 1 && abs(parent.y - anchor.y) < 1 {
            base = -Double.pi / 2
        }
        let offsets: [Double] = [0, 0.8, -0.8, 1.6, -1.6, 2.4, -2.4]
        let ring = index / offsets.count
        let angle = base + offsets[index % offsets.count] + Double(ring) * 0.4
        let distance = (parent.parent == nil ? 360.0 : 310.0) + Double(ring) * 170
        return CGPoint(x: parent.x + cos(angle) * distance, y: parent.y + sin(angle) * distance)
    }

    /// Thoughts sit in a loose ring around their cluster.
    static func thoughtPosition(around cluster: Cluster, index: Int) -> CGPoint {
        let radius = clusterDiameter(depth: cluster.depth, count: index) / 2 + 72 + 30 * Double(index).squareRoot()
        let angle = Double(index) * goldenAngle + 0.6
        return CGPoint(x: cluster.x + cos(angle) * radius, y: cluster.y + sin(angle) * radius)
    }
}
