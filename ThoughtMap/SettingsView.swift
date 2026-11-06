import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BackupSettings.key) private var excludeFromBackup = false
    @AppStorage("lensEnabled") private var lensEnabled = true
    @Query private var thoughts: [Thought]
    @Query private var clusters: [Cluster]

    @State private var exportURL: URL?
    @State private var sorting = false
    @State private var resorting = false
    @State private var confirmResort = false
    @State private var areas: [String] = Organizer.mainAreas()
    @State private var newArea = ""

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
                    .disabled(sorting || resorting)
                }

                Section {
                    ForEach(areas, id: \.self) { area in
                        Text(area)
                    }
                    .onDelete { offsets in
                        areas.remove(atOffsets: offsets)
                        Organizer.saveMainAreas(areas)
                    }
                    .onMove { from, to in
                        areas.move(fromOffsets: from, toOffset: to)
                        Organizer.saveMainAreas(areas)
                    }
                    HStack {
                        TextField("Add an area", text: $newArea)
                            .onSubmit(addArea)
                        Button("Add", action: addArea)
                            .disabled(newArea.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Button(resorting ? "Re-sorting… this can take a minute" : "Re-sort all thoughts") {
                        confirmResort = true
                    }
                    .disabled(resorting || sorting)
                } header: {
                    Text("Main areas")
                } footer: {
                    Text("The AI files each thought under one of these, then a theme inside it. Swipe to remove an area. Re-sorting keeps any thought you moved by hand where you put it.")
                }

                Section {
                    Toggle("Watch-style lens", isOn: $lensEnabled)
                } header: {
                    Text("Map")
                } footer: {
                    Text("Bubbles are bigger in the middle of the screen and shrink towards the edges, like the Apple Watch app grid.")
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
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: excludeFromBackup) { _, newValue in
                BackupSettings.apply(exclude: newValue)
            }
            .confirmationDialog("Re-sort all thoughts?", isPresented: $confirmResort, titleVisibility: .visible) {
                Button("Re-sort") {
                    Task {
                        resorting = true
                        await Organizer.shared.reorganizeEverything()
                        resorting = false
                    }
                }
            } message: {
                Text("The AI files every thought again using your main areas. Thoughts you placed by hand stay put.")
            }
        }
    }

    private func addArea() {
        let name = newArea.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !areas.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        areas.append(name)
        Organizer.saveMainAreas(areas)
        newArea = ""
    }
}
