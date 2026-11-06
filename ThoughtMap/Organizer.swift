import Foundation
import CoreGraphics
import SwiftData
import FoundationModels

/// What the on-device model returns for each new thought.
@Generable
struct Placement {
    @Guide(description: "Cluster path from broad to specific, as separate names. Use 1 to 3 names. Reuse existing cluster names exactly when they fit.")
    var path: [String]

    @Guide(description: "The thought rewritten as a short bubble label of at most 6 words.")
    var label: String
}

struct AddResult {
    let thought: Thought?
    let path: String
}

/// All the logic for adding, placing, moving and reflecting on thoughts.
/// Everything runs on the iPhone: Apple's on-device model plus local storage.
@MainActor
final class Organizer {
    static let shared = Organizer()
    private init() {}

    private var isOrganizing = false
    private var context: ModelContext { Store.shared.mainContext }

    // MARK: - AI availability

    var isAIAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var aiStatus: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "On-device AI is ready. Your thoughts never leave this iPhone."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This iPhone can't run Apple Intelligence, so thoughts are grouped by similarity instead."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in the Settings app to let ThoughtMap sort your thoughts."
            case .modelNotReady:
                return "Apple Intelligence is still getting ready. Sorting will start once it's done."
            @unknown default:
                return "On-device AI is unavailable right now."
            }
        @unknown default:
            return "On-device AI is unavailable right now."
        }
    }

    // MARK: - Fetching

    func allClusters() -> [Cluster] { (try? context.fetch(FetchDescriptor<Cluster>())) ?? [] }
    func allThoughts() -> [Thought] { (try? context.fetch(FetchDescriptor<Thought>())) ?? [] }
    func rootClusters() -> [Cluster] { allClusters().filter { $0.parent == nil } }

    func save() { try? context.save() }

    // MARK: - Adding

    /// Saves the thought straight away (in "Unsorted"), then asks the AI where it belongs.
    /// If the AI can't run right now, it stays in "Unsorted" and is sorted next time the app opens.
    func add(text: String) async -> AddResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AddResult(thought: nil, path: "") }

        let thought = Thought(text: trimmed)
        context.insert(thought)
        thought.embedding = Embeddings.vector(for: trimmed)
        linkRelated(thought)
        move(thought, to: inbox(), manual: false)
        thought.needsOrganizing = true
        save()

        await organize(thought)
        save()
        return AddResult(thought: thought, path: thought.cluster?.pathString ?? Cluster.inboxName)
    }

    func organizePending() async {
        guard !isOrganizing else { return }
        isOrganizing = true
        defer { isOrganizing = false }

        let pending = allThoughts()
            .filter { $0.needsOrganizing && $0.organizeAttempts < 3 }
            .sorted { $0.createdAt < $1.createdAt }
        for thought in pending {
            await organize(thought)
            save()
        }
    }

    /// Lets the person retry everything in "Unsorted", e.g. after turning on Apple Intelligence.
    func retryAllUnsorted() async {
        for thought in allThoughts() where thought.needsOrganizing {
            thought.organizeAttempts = 0
        }
        await organizePending()
    }

    func reorganize(_ thought: Thought) async {
        thought.needsOrganizing = true
        thought.organizeAttempts = 0
        thought.manuallyPlaced = false
        await organize(thought)
        save()
    }

    private func organize(_ thought: Thought) async {
        thought.organizeAttempts += 1

        if isAIAvailable {
            if let placement = await askForPlacement(thought) {
                let names = placement.path
                    .map(cleanName)
                    .filter { !$0.isEmpty && $0.lowercased() != Cluster.inboxName.lowercased() }
                if !names.isEmpty {
                    let target = resolve(path: Array(names.prefix(3)))
                    let label = placement.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !label.isEmpty { thought.label = String(label.prefix(60)) }
                    thought.aiPath = target.pathString
                    move(thought, to: target, manual: false)
                    thought.needsOrganizing = false
                    removeEmptyInbox()
                    return
                }
            }
            // The AI failed (e.g. the app was in the background). Try again later before falling back.
            if thought.organizeAttempts < 3 { return }
        }

        // Fallback: join the cluster of the most similar existing thought.
        if let neighbour = nearestSortedThought(to: thought), let target = neighbour.cluster {
            move(thought, to: target, manual: false)
            thought.aiPath = target.pathString
            thought.needsOrganizing = false
        }
        removeEmptyInbox()
    }

    private static let placementInstructions = """
    You organise one person's private thoughts into a mind map.
    The map is made of clusters arranged from broad to specific, for example: Projects › App ideas › Mind map app.
    Given the existing clusters and a new thought, choose the path of clusters where the thought belongs.
    Rules:
    - Return the path as a list of separate names, broadest first. Use 1 to 3 names.
    - Reuse existing cluster names exactly, with the same spelling, whenever they fit.
    - Only invent a new cluster when nothing existing fits.
    - Top-level clusters are broad life areas, such as Work, Money, Health, Cooking, Learning, Projects, Relationships, Home, Ideas.
    - Cluster names are 1 to 3 words in Title Case.
    - The label sums up the thought in at most 6 words.
    """

    private func askForPlacement(_ thought: Thought) async -> Placement? {
        let paths = allClusters()
            .filter { !$0.isInbox }
            .map(\.pathString)
            .sorted()
            .prefix(120)

        let corrections = allThoughts()
            .filter { $0.manuallyPlaced && !$0.aiPath.isEmpty && $0.cluster?.pathString != $0.aiPath }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(6)

        var prompt = ""
        if paths.isEmpty {
            prompt += "There are no clusters yet.\n"
        } else {
            prompt += "Existing clusters (› separates levels):\n"
            prompt += paths.map { "- \($0)" }.joined(separator: "\n")
            prompt += "\n"
        }
        if !corrections.isEmpty {
            prompt += "\nThe person moved some earlier thoughts. Follow their preferences:\n"
            prompt += corrections.map { "- \"\($0.label)\": you chose \($0.aiPath), they moved it to \($0.cluster?.pathString ?? "")" }
                .joined(separator: "\n")
            prompt += "\n"
        }
        prompt += "\nNew thought: \"\(thought.text)\""

        do {
            let session = LanguageModelSession(instructions: Self.placementInstructions)
            let response = try await session.respond(to: prompt, generating: Placement.self)
            return response.content
        } catch {
            return nil
        }
    }

    private func cleanName(_ raw: String) -> String {
        let replaced = raw
            .replacingOccurrences(of: "›", with: " ")
            .replacingOccurrences(of: ">", with: " ")
            .replacingOccurrences(of: "\"", with: "")
        let words = replaced.split(whereSeparator: { $0.isWhitespace })
        let joined = words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        return String(joined.prefix(40))
    }

    /// Turns ["Projects", "App ideas"] into a cluster, reusing what exists and creating what doesn't.
    private func resolve(path names: [String]) -> Cluster {
        let lowered = names.map { $0.lowercased() }
        let clusters = allClusters().filter { !$0.isInbox }

        // An existing cluster whose path ends with exactly these names.
        let suffixMatches = clusters.filter { cluster in
            let clusterPath = cluster.path.map { $0.name.lowercased() }
            return clusterPath.count >= lowered.count && Array(clusterPath.suffix(lowered.count)) == lowered
        }
        if let best = suffixMatches.min(by: { $0.path.count < $1.path.count }) {
            return best
        }

        var parent: Cluster? = nil
        var remaining = names

        // If the first name isn't a top-level cluster but exists deeper, start from there.
        let roots = rootClusters().filter { !$0.isInbox }
        if let first = remaining.first,
           !roots.contains(where: { $0.name.lowercased() == first.lowercased() }),
           let anchor = clusters.first(where: { $0.name.lowercased() == first.lowercased() }) {
            parent = anchor
            remaining.removeFirst()
        }

        for name in remaining {
            let siblings = parent.map { p in allClusters().filter { $0.parent?.uid == p.uid } } ?? rootClusters()
            if let match = siblings.first(where: { !$0.isInbox && $0.name.lowercased() == name.lowercased() }) {
                parent = match
            } else {
                parent = createCluster(named: name, parent: parent)
            }
        }
        return parent ?? createCluster(named: names.first ?? "Ideas", parent: nil)
    }

    // MARK: - Clusters

    @discardableResult
    func createCluster(named name: String, parent: Cluster?) -> Cluster {
        let position: CGPoint
        let color: Int
        if let parent {
            let siblingCount = allClusters().filter { $0.parent?.uid == parent.uid }.count
            position = Layout.childPosition(parent: parent, index: siblingCount)
            color = parent.colorIndex
        } else {
            position = freeRootPosition()
            color = nextRootColor()
        }
        let cluster = Cluster(name: name, x: Double(position.x), y: Double(position.y), colorIndex: color)
        context.insert(cluster)
        cluster.parent = parent
        return cluster
    }

    private func freeRootPosition() -> CGPoint {
        let roots = rootClusters()
        for index in 1..<400 {
            let candidate = Layout.rootPosition(index: index)
            let isFree = roots.allSatisfy { hypot($0.x - Double(candidate.x), $0.y - Double(candidate.y)) > 420 }
            if isFree { return candidate }
        }
        return Layout.rootPosition(index: roots.count + 1)
    }

    private func nextRootColor() -> Int {
        let used = rootClusters().filter { !$0.isInbox }.map(\.colorIndex)
        for index in 0..<Palette.count where !used.contains(index) {
            return index
        }
        return used.count % Palette.count
    }

    func inbox() -> Cluster {
        if let existing = rootClusters().first(where: { $0.isInbox }) { return existing }
        let cluster = Cluster(name: Cluster.inboxName, x: 0, y: 0, colorIndex: -1)
        context.insert(cluster)
        return cluster
    }

    private func removeEmptyInbox() {
        let thoughts = allThoughts()
        for cluster in rootClusters() where cluster.isInbox {
            let hasThoughts = thoughts.contains { $0.cluster?.uid == cluster.uid }
            let hasChildren = allClusters().contains { $0.parent?.uid == cluster.uid }
            if !hasThoughts && !hasChildren { context.delete(cluster) }
        }
    }

    func subtree(of cluster: Cluster) -> [Cluster] {
        allClusters().filter { $0.uid == cluster.uid || $0.isDescendant(of: cluster) }
    }

    /// Moves a cluster together with its sub-clusters and their thoughts.
    func shift(_ cluster: Cluster, dx: Double, dy: Double) {
        let moving = subtree(of: cluster)
        let ids = Set(moving.map(\.uid))
        for c in moving {
            c.x += dx
            c.y += dy
        }
        for thought in allThoughts() {
            if let id = thought.cluster?.uid, ids.contains(id) {
                thought.x += dx
                thought.y += dy
            }
        }
        save()
    }

    func setParent(_ cluster: Cluster, to newParent: Cluster?) {
        if let newParent {
            guard newParent.uid != cluster.uid, !newParent.isDescendant(of: cluster) else { return }
        }
        guard cluster.parent?.uid != newParent?.uid else { return }

        let target: CGPoint
        if let newParent {
            let siblingCount = allClusters().filter { $0.parent?.uid == newParent.uid && $0.uid != cluster.uid }.count
            target = Layout.childPosition(parent: newParent, index: siblingCount)
        } else {
            cluster.parent = nil
            target = freeRootPosition()
        }
        cluster.parent = newParent
        let color = newParent?.colorIndex ?? nextRootColor()
        for c in subtree(of: cluster) { c.colorIndex = color }
        shift(cluster, dx: Double(target.x) - cluster.x, dy: Double(target.y) - cluster.y)
    }

    /// Deletes a cluster. Its thoughts and sub-clusters move up one level
    /// (or back to "Unsorted" if it was a top-level cluster).
    func delete(_ cluster: Cluster) {
        guard !cluster.isInbox else { return }
        let parent = cluster.parent
        for child in allClusters() where child.parent?.uid == cluster.uid {
            child.parent = parent
        }
        let orphans = allThoughts().filter { $0.cluster?.uid == cluster.uid }
        if !orphans.isEmpty {
            let destination = parent ?? inbox()
            for thought in orphans {
                move(thought, to: destination, manual: false)
                if parent == nil {
                    thought.needsOrganizing = true
                    thought.organizeAttempts = 0
                }
            }
        }
        context.delete(cluster)
        removeEmptyInbox()
        save()
    }

    // MARK: - Thoughts

    private func move(_ thought: Thought, to cluster: Cluster, manual: Bool) {
        if thought.cluster?.uid != cluster.uid {
            let index = allThoughts().filter { $0.cluster?.uid == cluster.uid && $0.uid != thought.uid }.count
            thought.cluster = cluster
            let position = Layout.thoughtPosition(around: cluster, index: index)
            thought.x = Double(position.x)
            thought.y = Double(position.y)
        }
        if manual {
            thought.manuallyPlaced = true
            thought.needsOrganizing = false
        }
    }

    func moveManually(_ thought: Thought, to cluster: Cluster) {
        move(thought, to: cluster, manual: true)
        if cluster.isInbox { thought.needsOrganizing = true }
        removeEmptyInbox()
        save()
    }

    func delete(_ thought: Thought) {
        let id = thought.uid
        for other in allThoughts() where other.relatedIDs.contains(id) {
            other.relatedIDs.removeAll { $0 == id }
        }
        context.delete(thought)
        removeEmptyInbox()
        save()
    }

    private func linkRelated(_ thought: Thought) {
        let vector = thought.embedding
        guard !vector.isEmpty else { return }
        let scored = allThoughts()
            .filter { $0.uid != thought.uid && !$0.embedding.isEmpty }
            .map { ($0.uid, Embeddings.similarity(vector, $0.embedding)) }
            .filter { $0.1 > Embeddings.relatedThreshold }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
        thought.relatedIDs = scored.map { $0.0 }
    }

    private func nearestSortedThought(to thought: Thought) -> Thought? {
        let vector = thought.embedding
        guard !vector.isEmpty else { return nil }
        var best: (Thought, Double)? = nil
        for other in allThoughts() {
            guard other.uid != thought.uid,
                  let cluster = other.cluster, !cluster.isInbox,
                  !other.embedding.isEmpty else { continue }
            let score = Embeddings.similarity(vector, other.embedding)
            if score > Embeddings.fallbackThreshold, score > (best?.1 ?? -1) {
                best = (other, score)
            }
        }
        return best?.0
    }

    // MARK: - Reflection

    private static let reflectionInstructions = """
    You help one person understand their own thinking, based on the thoughts they have jotted down.
    Write in the second person, warm but plain, in 4 to 6 sentences.
    Say where their attention is concentrated, what is rising and what is fading, and any link you notice between areas.
    Base everything only on the data given. Do not invent facts.
    End with one gentle question for them to think about.
    """

    func reflect(stats: [AreaStat], recent: [Thought]) async -> String {
        guard isAIAvailable else { return aiStatus }

        var prompt = "Areas of thought:\n"
        prompt += stats.prefix(10).map { stat in
            "- \(stat.name): \(stat.last30) thoughts in the last 30 days, \(stat.prev30) in the 30 days before, \(stat.total) overall (\(stat.trend.word))"
        }.joined(separator: "\n")
        prompt += "\n\nMost recent thoughts, newest first:\n"
        prompt += recent.prefix(40).map { thought in
            let area = thought.cluster?.pathString ?? Cluster.inboxName
            return "- [\(area)] \(thought.label)"
        }.joined(separator: "\n")

        do {
            let session = LanguageModelSession(instructions: Self.reflectionInstructions)
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            return "Couldn't write a reflection right now. Please try again in a moment."
        }
    }
}
