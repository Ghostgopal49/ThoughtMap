import SwiftUI
import SwiftData

struct ClusterDetailView: View {
    @Bindable var cluster: Cluster

    @Environment(\.dismiss) private var dismiss
    @Query private var clusters: [Cluster]
    @Query(sort: \Thought.createdAt, order: .reverse) private var thoughts: [Thought]

    @State private var confirmDelete = false

    private var possibleParents: [Cluster] {
        clusters
            .filter { $0.uid != cluster.uid && !$0.isInbox && !$0.isDescendant(of: cluster) }
            .sorted { $0.pathString.localizedCaseInsensitiveCompare($1.pathString) == .orderedAscending }
    }

    private var thoughtsHere: [Thought] {
        thoughts.filter { $0.cluster?.uid == cluster.uid }
    }

    private var parentSelection: Binding<UUID?> {
        Binding(
            get: { cluster.parent?.uid },
            set: { newID in
                let newParent = newID.flatMap { id in clusters.first(where: { $0.uid == id }) }
                Organizer.shared.setParent(cluster, to: newParent)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if !cluster.isInbox {
                    Section("Name") {
                        TextField("Name", text: $cluster.name)
                    }

                    Section {
                        Picker("Inside", selection: parentSelection) {
                            Text("Top level").tag(UUID?.none)
                            ForEach(possibleParents) { other in
                                Text(other.pathString).tag(Optional(other.uid))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } footer: {
                        Text("Moving a cluster brings its thoughts and sub-clusters along.")
                    }
                } else {
                    Section {
                        Text("Thoughts wait here until the on-device AI can sort them. You can also drag them onto any cluster yourself.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Thoughts here (\(thoughtsHere.count))") {
                    if thoughtsHere.isEmpty {
                        Text("None yet").foregroundStyle(.secondary)
                    }
                    ForEach(thoughtsHere) { thought in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thought.label)
                            Text(thought.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !cluster.isInbox {
                    Section {
                        Button("Delete cluster", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its thoughts and sub-clusters move up one level. Nothing is lost.")
                    }
                }
            }
            .navigationTitle(cluster.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let trimmed = cluster.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { cluster.name = "Untitled" } else { cluster.name = trimmed }
                        Organizer.shared.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete \(cluster.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    let target = cluster
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        Organizer.shared.delete(target)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
