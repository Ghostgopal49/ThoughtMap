import SwiftUI
import SwiftData

struct ThoughtDetailView: View {
    @Bindable var thought: Thought

    @Environment(\.dismiss) private var dismiss
    @Query private var clusters: [Cluster]
    @Query private var thoughts: [Thought]

    @State private var newClusterName = ""
    @State private var confirmDelete = false
    @State private var working = false

    private var sortedClusters: [Cluster] {
        clusters.sorted { $0.pathString.localizedCaseInsensitiveCompare($1.pathString) == .orderedAscending }
    }

    private var related: [Thought] {
        thoughts.filter { thought.relatedIDs.contains($0.uid) }
    }

    private var clusterSelection: Binding<UUID?> {
        Binding(
            get: { thought.cluster?.uid },
            set: { newID in
                guard let newID, let cluster = clusters.first(where: { $0.uid == newID }) else { return }
                Organizer.shared.moveManually(thought, to: cluster)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thought") {
                    TextField("Thought", text: $thought.text, axis: .vertical)
                        .lineLimit(2...8)
                    TextField("Bubble label", text: $thought.label)
                    LabeledContent("Added", value: thought.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                Section {
                    Picker("Cluster", selection: clusterSelection) {
                        ForEach(sortedClusters) { cluster in
                            Text(cluster.pathString).tag(Optional(cluster.uid))
                        }
                    }
                    .pickerStyle(.navigationLink)

                    HStack {
                        TextField("New cluster name", text: $newClusterName)
                        Button("Create") { createClusterAndMove() }
                            .disabled(newClusterName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Where it lives")
                } footer: {
                    Text("A new cluster is created inside the current one. When you move thoughts, the AI learns where you like things to go.")
                }

                Section {
                    Button {
                        Task {
                            working = true
                            await Organizer.shared.reorganize(thought)
                            working = false
                        }
                    } label: {
                        Label(working ? "Thinking…" : "Ask AI to place it again", systemImage: "sparkles")
                    }
                    .disabled(working)
                }

                if !related.isEmpty {
                    Section("Related thoughts") {
                        ForEach(related) { other in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other.label)
                                Text(other.cluster?.pathString ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Delete thought", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(thought.cluster?.name ?? "Thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Organizer.shared.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete this thought?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    let target = thought
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        Organizer.shared.delete(target)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func createClusterAndMove() {
        let name = newClusterName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let parent = (thought.cluster?.isInbox ?? true) ? nil : thought.cluster
        let cluster = Organizer.shared.createCluster(named: name, parent: parent)
        Organizer.shared.moveManually(thought, to: cluster)
        newClusterName = ""
    }
}
