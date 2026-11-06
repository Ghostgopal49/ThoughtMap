import Foundation
import SwiftUI
import SwiftData
import FoundationModels

/// What the on-device model returns for each new thought.
@Generable
struct Placement {
    @Guide(description: "The broad subject area of the thought. Use one of the main areas listed when it fits. Never a generic word like Projects, Tasks, Goals or To do.")
    var area: String

    @Guide(description: "A theme inside that area, 1 to 3 words, for example App ideas, Recipes to try, Languages. Reuse an existing theme when it fits.")
    var theme: String

    @Guide(description: "The thought as a short bubble label of at most 4 words.")
    var label: String
}

struct AddResult {
    let thought: Thought?
    let path: String
}

/// All the logic for adding, placing, moving and reflecting on thoughts.
/// Everything runs on the iPhone: Apple's on-device model plus local storage.
@MainActor
@Observable
final class Organizer {
    static let shared = Organizer()
    private init() {}

    private(set) var isOrganizing = false
    private var context: ModelContext { Store.shared.mainContext }

    // MARK: - Main areas (editable in Settings)

    nonisolated static let mainAreasKey = "mainAreas"
    nonisolated static let defaultMainAreas: [String] = [
        "Work", "Money", "Learning", "Health & Fitness", "Cooking", "Apps & Tech",
        "Creative", "Relationships", "Home", "Travel", "Personal"
    ]

    nonisolated static func mainAreas() -> [String] {
        let stored = UserDefaults.standard.string(forKey: mainAreasKey) ?? ""
        let list = stored
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return list.isEmpty ? defaultMainAreas : list
    }

    nonisolated static func saveMainAreas(_ areas: [String]) {
        UserDefaults.standard.set(areas.joined(separator: "\n"), forKey: mainAreasKey)
    }

    nonisolated private static let genericNames: Set<String> = [
        "projects", "project", "tasks", "task", "things to do", "to do", "todo", "to-do",
        "goals", "misc", "miscellaneous", "general", "other", "stuff", "thoughts", "notes"
    ]

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

    /// Goes up by one after every saved change, so views can rebuild their cached snapshot
    /// once per change instead of reading the database on every frame.
    private(set) var version = 0

    func save() {
        try? context.save()
        version &+= 1
    }

    // MARK: - Layout

    /// Re-packs the whole map into the honeycomb. Cheap enough to run after every change.
    func relayout(animated: Bool = true) {
        let positions = Layout.compute(clusters: allClusters(), thoughts: allThoughts())
        let apply = {
            for cluster in self.allClusters() {
                if let p = positions.clusters[cluster.uid] {
                    let x = Double(p.x), y = Double(p.y)
                    if abs(cluster.x - x) > 0.5 || abs(cluster.y - y) > 0.5 {
                        cluster.x = x
                        cluster.y = y
                    }
                }
            }
            for thought in self.allThoughts() {
                if let p = positions.thoughts[thought.uid] {
                    let x = Double(p.x), y = Double(p.y)
                    if abs(thought.x - x) > 0.5 || abs(thought.y - y) > 0.5 {
                        thought.x = x
                        thought.y = y
                    }
                }
            }
        }
        if animated {
            withAnimation(.smooth(duration: 0.5)) { apply() }
        } else {
            apply()
        }
        save()
    }

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
        relayout()

        await organize(thought)
        relayout()
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
            relayout()
        }
    }

    /// Lets the person retry everything in "Unsorted", e.g. after turning on Apple Intelligence.
    func retryAllUnsorted() async {
        for thought in allThoughts() where thought.needsOrganizing {
            thought.organizeAttempts = 0
        }
        await organizePending()
    }

    /// Sorts every thought again from scratch, keeping the ones the person placed by hand.
    func reorganizeEverything() async {
        guard !isOrganizing else { return }
        let box = inbox()
        for thought in allThoughts() where !thought.manuallyPlaced {
            thought.cluster = box
            thought.needsOrganizing = true
            thought.organizeAttempts = 0
            thought.aiPath = ""
        }
        save()
        pruneAllEmptyClusters()
        relayout()
        await organizePending()
    }

    func reorganize(_ thought: Thought) async {
        thought.needsOrganizing = true
        thought.organizeAttempts = 0
        thought.manuallyPlaced = false
        await organize(thought)
        relayout()
    }

    private func organize(_ thought: Thought) async {
        thought.organizeAttempts += 1

        if isAIAvailable {
            if let placement = await askForPlacement(thought) {
                if let target = resolve(area: placement.area, theme: placement.theme) {
                    let label = placement.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !label.isEmpty { thought.label = String(label.prefix(50)) }
                    thought.aiPath = target.pathString
                    move(thought, to: target, manual: false)
                    thought.needsOrganizing = false
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
    }

    private static let placementInstructions = """
    You organise one person's private thoughts into a mind map.
    Each thought goes into an AREA (its broad subject) and a THEME inside that area.
    Rules:
    - The area is about WHAT the thought is about, never about what kind of thing it is. Wanting to do something, a plan, a goal or a task is not an area.
    - Never use generic areas like Projects, Tasks, Goals, Things to do, Ideas or Misc.
    - Pick the most specific subject. Learning to cook belongs in Cooking, not Learning. Learning to code an app belongs in Apps & Tech.
    - Use Learning only for studying, courses, languages, books and skills with no better area.
    - Prefer the person's main areas. Create a new area only when none fits at all.
    - Reuse existing themes with the exact same spelling when they fit.
    - Names are 1 to 3 words in Title Case. The label sums up the thought in at most 4 words.
    Examples:
    - "I want to create a mind map app for my iPhone" → area: Apps & Tech, theme: App Ideas, label: Mind map iPhone app
    - "learn to make proper biryani" → area: Cooking, theme: Recipes to Try, label: Make biryani
    - "start learning Spanish" → area: Learning, theme: Languages, label: Learn Spanish
    - "put 10% of salary into index funds" → area: Money, theme: Investing, label: Invest 10% monthly
    - "ask my manager about the promotion" → area: Work, theme: Career Growth, label: Ask about promotion
    - "go for a run three times a week" → area: Health & Fitness, theme: Running, label: Run 3x weekly
    """

    private func askForPlacement(_ thought: Thought) async -> Placement? {
        let roots = rootClusters().filter { !$0.isInbox }.sorted { $0.name < $1.name }
        let clusters = allClusters()

        var prompt = "Main areas: " + Self.mainAreas().joined(separator: ", ") + "\n"
        let themeLines = roots.prefix(30).compactMap { root -> String? in
            let themes = clusters
                .filter { $0.parent?.uid == root.uid }
                .map(\.name)
                .sorted()
                .prefix(12)
            return themes.isEmpty ? "- \(root.name): (no themes yet)" : "- \(root.name): " + themes.joined(separator: ", ")
        }
        if !themeLines.isEmpty {
            prompt += "\nExisting areas and their themes:\n" + themeLines.joined(separator: "\n") + "\n"
        }

        let corrections = allThoughts()
            .filter { $0.manuallyPlaced && !$0.aiPath.isEmpty && $0.cluster?.pathString != $0.aiPath }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(6)
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

    private func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Finds the best existing area name, or one of the main areas, for what the model said.
    private func matchArea(_ raw: String, theme: String) -> String {
        var name = cleanName(raw)
        let mains = Self.mainAreas()
        let existing = rootClusters().filter { !$0.isInbox }.map(\.name)
        let candidates = existing + mains.filter { m in !existing.contains(where: { same($0, m) }) }

        let isGeneric = Self.genericNames.contains(name.lowercased()) && !mains.contains(where: { same($0, name) })
        if name.isEmpty || isGeneric {
            // The model fell back to a generic word: try the theme, else Personal.
            let themeName = cleanName(theme)
            if let hit = candidates.first(where: { same($0, themeName) }) { return hit }
            name = mains.first(where: { same($0, "Personal") }) ?? "Personal"
        }
        if let exact = candidates.first(where: { same($0, name) }) { return exact }
        let lower = name.lowercased()
        if lower.count >= 3, let close = candidates.first(where: { candidate in
            let c = candidate.lowercased()
            return c.count >= 3 && (c.contains(lower) || lower.contains(c))
        }) {
            return close
        }
        return name
    }

    /// Turns (area, theme) into a cluster, reusing what exists and creating what doesn't.
    private func resolve(area rawArea: String, theme rawTheme: String) -> Cluster? {
        let areaName = matchArea(rawArea, theme: rawTheme)
        guard !areaName.isEmpty, !same(areaName, Cluster.inboxName) else { return nil }

        let root = rootClusters().first(where: { !$0.isInbox && same($0.name, areaName) })
            ?? createCluster(named: areaName, parent: nil)

        let themeName = cleanName(rawTheme)
        if themeName.isEmpty || same(themeName, areaName) || Self.genericNames.contains(themeName.lowercased()) {
            return root
        }
        let inArea = allClusters().filter { $0.isDescendant(of: root) }
        if let direct = inArea.first(where: { $0.parent?.uid == root.uid && same($0.name, themeName) }) {
            return direct
        }
        if let deeper = inArea.first(where: { same($0.name, themeName) }) {
            return deeper
        }
        return createCluster(named: themeName, parent: root)
    }

    // MARK: - Clusters

    @discardableResult
    func createCluster(named name: String, parent: Cluster?) -> Cluster {
        let color = parent?.colorIndex ?? AreaStyle.guess(for: name)?.colorIndex ?? nextRootColor()
        let cluster = Cluster(name: name, x: parent?.x ?? 0, y: parent?.y ?? 0, colorIndex: color)
        context.insert(cluster)
        cluster.parent = parent
        return cluster
    }

    private func nextRootColor() -> Int {
        let used = rootClusters().filter { !$0.isInbox }.map(\.colorIndex)
        for index in 0..<Palette.count where !used.contains(index) {
            return index
        }
        return used.count % Palette.count
    }

    /// Changes an area's colour (for it and everything inside) and its icon.
    func setStyle(of cluster: Cluster, colorIndex: Int? = nil, symbol: String? = nil) {
        let area = cluster.root
        if let colorIndex {
            for c in subtree(of: area) { c.colorIndex = colorIndex }
        }
        if let symbol { area.symbol = symbol }
        save()
    }

    func inbox() -> Cluster {
        if let existing = rootClusters().first(where: { $0.isInbox }) { return existing }
        let cluster = Cluster(name: Cluster.inboxName, x: 0, y: 0, colorIndex: -1)
        context.insert(cluster)
        return cluster
    }

    private func isEmpty(_ cluster: Cluster) -> Bool {
        let hasThoughts = allThoughts().contains { $0.cluster?.uid == cluster.uid }
        let hasChildren = allClusters().contains { $0.parent?.uid == cluster.uid }
        return !hasThoughts && !hasChildren
    }

    /// Removes a cluster once it has nothing left in it, and then its parent if that is now empty too.
    private func pruneIfEmpty(_ cluster: Cluster?) {
        var current = cluster
        var steps = 0
        while let node = current, steps < 12, isEmpty(node) {
            let parent = node.parent
            context.delete(node)
            save()
            current = parent
            steps += 1
        }
    }

    private func pruneAllEmptyClusters() {
        var changed = true
        var rounds = 0
        while changed && rounds < 12 {
            changed = false
            rounds += 1
            for cluster in allClusters() where isEmpty(cluster) {
                context.delete(cluster)
                changed = true
            }
            save()
        }
    }

    func subtree(of cluster: Cluster) -> [Cluster] {
        allClusters().filter { $0.uid == cluster.uid || $0.isDescendant(of: cluster) }
    }

    func setParent(_ cluster: Cluster, to newParent: Cluster?) {
        if let newParent {
            guard newParent.uid != cluster.uid, !newParent.isDescendant(of: cluster), !newParent.isInbox else { return }
        }
        guard !cluster.isInbox, cluster.parent?.uid != newParent?.uid else { return }
        let oldParent = cluster.parent
        cluster.parent = newParent
        let color = newParent?.colorIndex ?? nextRootColor()
        for c in subtree(of: cluster) { c.colorIndex = color }
        pruneIfEmpty(oldParent)
        relayout()
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
                thought.cluster = destination
                if parent == nil {
                    thought.needsOrganizing = true
                    thought.organizeAttempts = 0
                }
            }
        }
        context.delete(cluster)
        save()
        relayout()
    }

    // MARK: - Thoughts

    private func move(_ thought: Thought, to cluster: Cluster, manual: Bool) {
        let previous = thought.cluster
        if previous?.uid != cluster.uid {
            thought.cluster = cluster
            save()
            pruneIfEmpty(previous)
        }
        if manual {
            thought.manuallyPlaced = true
            thought.needsOrganizing = false
        }
    }

    func moveManually(_ thought: Thought, to cluster: Cluster) {
        move(thought, to: cluster, manual: true)
        if cluster.isInbox { thought.needsOrganizing = true }
        relayout()
    }

    func delete(_ thought: Thought) {
        let id = thought.uid
        let previous = thought.cluster
        for other in allThoughts() where other.relatedIDs.contains(id) {
            other.relatedIDs.removeAll { $0 == id }
        }
        context.delete(thought)
        save()
        pruneIfEmpty(previous)
        relayout()
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
