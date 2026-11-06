import Foundation
import SwiftData

/// A bubble that groups thoughts, e.g. "Projects" or "Projects › App ideas".
@Model
final class Cluster {
    var uid: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var x: Double = 0
    var y: Double = 0
    /// Index into `Palette`. -1 means grey (used for "Unsorted").
    var colorIndex: Int = 0

    var parent: Cluster?

    @Relationship(deleteRule: .nullify, inverse: \Cluster.parent)
    var children: [Cluster] = []

    @Relationship(deleteRule: .nullify, inverse: \Thought.cluster)
    var thoughts: [Thought] = []

    init(name: String, x: Double, y: Double, colorIndex: Int) {
        self.uid = UUID()
        self.name = name
        self.createdAt = Date()
        self.x = x
        self.y = y
        self.colorIndex = colorIndex
    }

    static let inboxName = "Unsorted"

    var isInbox: Bool { parent == nil && name == Cluster.inboxName }

    /// From the top-level cluster down to this one.
    var path: [Cluster] {
        var result: [Cluster] = []
        var current: Cluster? = self
        var steps = 0
        while let node = current, steps < 12 {
            result.insert(node, at: 0)
            current = node.parent
            steps += 1
        }
        return result
    }

    var pathString: String { path.map(\.name).joined(separator: " › ") }
    var root: Cluster { path.first ?? self }
    var depth: Int { max(path.count - 1, 0) }

    func isDescendant(of other: Cluster) -> Bool {
        var current = parent
        var steps = 0
        while let node = current, steps < 12 {
            if node.uid == other.uid { return true }
            current = node.parent
            steps += 1
        }
        return false
    }
}

/// One captured thought.
@Model
final class Thought {
    var uid: UUID = UUID()
    /// Exactly what was said or typed.
    var text: String = ""
    /// Short version shown inside the bubble.
    var label: String = ""
    var createdAt: Date = Date()
    var x: Double = 0
    var y: Double = 0

    var cluster: Cluster?

    /// True until the AI (or the fallback) has found a home for it.
    var needsOrganizing: Bool = true
    var organizeAttempts: Int = 0
    /// True once the person has moved it themselves.
    var manuallyPlaced: Bool = false
    /// Where the AI first put it. Compared with where it ends up, to learn from corrections.
    var aiPath: String = ""
    /// On-device sentence embedding, used to find related thoughts.
    var embedding: [Double] = []
    var relatedIDs: [UUID] = []

    init(text: String) {
        self.uid = UUID()
        self.text = text
        self.label = Thought.shortLabel(for: text)
        self.createdAt = Date()
    }

    static func shortLabel(for text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        if words.count <= 7 { return text }
        return words.prefix(7).joined(separator: " ") + "…"
    }
}
