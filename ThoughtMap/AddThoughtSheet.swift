import SwiftUI

struct AddThoughtSheet: View {
    var onSaved: (AddResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("What's on your mind?", text: $text, axis: .vertical)
                    .font(.title3)
                    .lineLimit(3...10)
                    .focused($focused)
                    .disabled(saving)
                Text("Tip: tap the microphone on the keyboard to speak instead of typing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("New thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(trimmed.isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(saving)
    }

    private func save() {
        saving = true
        let input = trimmed
        Task {
            let result = await Organizer.shared.add(text: input)
            saving = false
            dismiss()
            onSaved(result)
        }
    }
}
