import Foundation
import SwiftData

/// One database for the whole app, shared by the UI and the "Add Thought" action.
/// It lives only in this app's private folder on the iPhone.
enum Store {
    @MainActor static let shared: ModelContainer = {
        let schema = Schema([Thought.self, Cluster.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the thought store: \(error)")
        }
    }()
}

/// Optionally keeps the database out of iCloud Backup.
enum BackupSettings {
    static let key = "excludeFromBackup"

    static func applyStoredPreference() {
        apply(exclude: UserDefaults.standard.bool(forKey: key))
    }

    static func apply(exclude: Bool) {
        let fileManager = FileManager.default
        guard var url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = exclude
        try? url.setResourceValues(values)
    }
}

/// Writes all thoughts to a JSON file the person can save or share.
enum Exporter {
    static func export(thoughts: [Thought]) -> URL? {
        let formatter = ISO8601DateFormatter()
        let items: [[String: Any]] = thoughts
            .sorted { $0.createdAt < $1.createdAt }
            .map { thought in
                [
                    "text": thought.text,
                    "label": thought.label,
                    "cluster": thought.cluster?.pathString ?? "",
                    "created": formatter.string(from: thought.createdAt)
                ]
            }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ThoughtMap-export.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
