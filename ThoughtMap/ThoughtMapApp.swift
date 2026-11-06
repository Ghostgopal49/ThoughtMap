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

    var body: some View {
        MapView()
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    Task { await Organizer.shared.organizePending() }
                }
            }
    }
}
