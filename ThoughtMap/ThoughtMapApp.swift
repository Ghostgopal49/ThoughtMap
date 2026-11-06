import SwiftUI
import SwiftData

@main
struct ThoughtMapApp: App {
    init() {
        BackupSettings.applyStoredPreference()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Store.shared)
    }
}

/// Sorts any thoughts that were captured in the background (for example from the
/// Action Button) whenever the app comes to the foreground.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("sortingVersion") private var sortingVersion = 1

    var body: some View {
        MapView()
            .preferredColorScheme(.dark)
            .task {
                Organizer.shared.relayout(animated: false)
                // One-time re-sort when the sorting rules improve.
                if sortingVersion < 2 {
                    sortingVersion = 2
                    await Organizer.shared.reorganizeEverything()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await Organizer.shared.organizePending() }
                }
            }
    }
}
