import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BackupSettings.key) private var excludeFromBackup = false
    @Query private var thoughts: [Thought]
    @Query private var clusters: [Cluster]

    @State private var exportURL: URL?
    @State private var sorting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("On-device AI") {
                    Label(Organizer.shared.aiStatus,
                          systemImage: Organizer.shared.isAIAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    Button(sorting ? "Sorting…" : "Sort unsorted thoughts now") {
                        Task {
                            sorting = true
                            await Organizer.shared.retryAllUnsorted()
                            sorting = false
                        }
                    }
                    .disabled(sorting)
                }

                Section {
                    Toggle("Keep out of iCloud Backup", isOn: $excludeFromBackup)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Your thoughts are stored only on this iPhone and never sent anywhere. Turning this on also leaves them out of iCloud backups, so they can't be restored if you lose your phone. If you turn it on, export now and then.")
                }

                Section("Your data") {
                    LabeledContent("Thoughts", value: "\(thoughts.count)")
                    LabeledContent("Clusters", value: "\(clusters.count)")
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Save or share export", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("Prepare export file") {
                            exportURL = Exporter.export(thoughts: thoughts)
                        }
                    }
                }

                Section("Action Button setup") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Open the Shortcuts app and tap +.")
                        Text("2. Add the action \"Dictate Text\".")
                        Text("3. Add the action \"Add Thought\" (from ThoughtMap). It uses the dictated text automatically.")
                        Text("4. Name the shortcut \"Capture thought\".")
                        Text("5. In Settings › Action Button, choose Shortcut › Capture thought.")
                    }
                    .font(.subheadline)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: excludeFromBackup) { _, newValue in
                BackupSettings.apply(exclude: newValue)
            }
        }
    }
}
