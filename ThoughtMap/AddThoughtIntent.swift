import AppIntents

/// The "Add Thought" action that shows up in the Shortcuts app.
/// Pair it with "Dictate Text" and put the shortcut on the Action Button.
struct AddThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Thought"
    static let description = IntentDescription("Saves a thought to your mind map. The on-device AI places it in the right cluster.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Thought", requestValueDialog: "What's on your mind?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await Organizer.shared.add(text: text)
        if result.thought == nil {
            return .result(dialog: "That thought was empty, so nothing was saved.")
        }
        return .result(dialog: "Saved under \(result.path).")
    }
}

struct ThoughtMapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddThoughtIntent(),
            phrases: [
                "Add a thought to \(.applicationName)",
                "New thought in \(.applicationName)",
                "Note a thought in \(.applicationName)"
            ],
            shortTitle: "Add Thought",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }
}
